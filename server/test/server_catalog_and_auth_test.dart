import 'dart:convert';
import 'package:core_contracts/core_contracts.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:shelf/shelf.dart';
import 'package:supermarket_server/core/application.dart';
import 'package:supermarket_server/features/auth_users/data/in_memory_user_repository.dart';
import 'package:supermarket_server/features/catalog/data/in_memory_catalog_repository.dart';
import 'package:supermarket_server/shared/rate_limiter.dart';
import 'fixtures.dart';

void main() {
  late Handler app;
  setUp(
    () => app = createApplication(
      verifier: FixtureVerifier(),
      users: InMemoryUserRepository([actor]),
      catalog: InMemoryCatalogRepository(),
      corsOrigins: {'https://shop.test'},
      rateLimiter: RateLimiter(maxRequests: 1000),
    ),
  );
  test('health, config and session have success envelopes', () async {
    for (final path in ['/health', '/v1/app-config']) {
      final r = await app(Request('GET', Uri.parse('http://localhost$path')));
      expect(r.statusCode, 200);
      final j = await responseJson(r);
      expect(j.keys, containsAll(['data', 'meta']));
      expect((j['meta'] as Map)['requestId'], isNotEmpty);
    }
    final r = await app(
      request('POST', '/v1/auth/session', body: {}, key: const Uuid().v4()),
    );
    expect(r.statusCode, 200);
    expect((await responseJson(r))['data']['branchId'], branch);
  });
  test(
    'missing identity, invalid token and unprovisioned identity fail',
    () async {
      final invalid = await app(
        request(
          'GET',
          '/v1/catalog/products',
          headers: {'authorization': 'Bearer invalid'},
        ),
      );
      expect(invalid.statusCode, 401);
      expect(
        (await responseJson(invalid))['error']['requestId'],
        'fixture-request',
      );
      final missing = await app(
        Request(
          'GET',
          Uri.parse('http://localhost/v1/catalog/products'),
          headers: {'x-request-id': 'test'},
        ),
      );
      expect(missing.statusCode, 401);
      final unprovisioned = createApplication(
        verifier: FixtureVerifier(),
        users: const InMemoryUserRepository(),
        catalog: InMemoryCatalogRepository(),
      );
      expect(
        (await unprovisioned(
          request('GET', '/v1/catalog/products'),
        )).statusCode,
        403,
      );
    },
  );
  test(
    'same operation is replayed once and changed payload returns 409',
    () async {
      final p = product();
      final key = const Uuid().v4();
      final responses = await Future.wait(
        List.generate(
          10,
          (_) async => await app(
            request('POST', '/v1/catalog/products', body: p.toJson(), key: key),
          ),
        ),
      );
      for (final r in responses) {
        expect(r.statusCode, 200);
        expect((await responseJson(r))['data']['revision'], 1);
      }
      final changed = p.toJson()..['name'] = 'قيمة مختلفة';
      expect(
        (await app(
          request('POST', '/v1/catalog/products', body: changed, key: key),
        )).statusCode,
        409,
      );
      final list = await responseJson(
        await app(request('GET', '/v1/catalog/products')),
      );
      expect(list['data'], hasLength(1));
    },
  );
  test(
    'duplicate barcode, stale revision and cross-branch writes are rejected',
    () async {
      final p = product(barcode: '1234567890123');
      expect(
        (await app(
          request(
            'POST',
            '/v1/catalog/products',
            body: p.toJson(),
            key: const Uuid().v4(),
          ),
        )).statusCode,
        200,
      );
      expect(
        (await app(
          request(
            'POST',
            '/v1/catalog/products',
            body: product(barcode: '1234567890123').toJson(),
            key: const Uuid().v4(),
          ),
        )).statusCode,
        409,
      );
      expect(
        (await app(
          request(
            'POST',
            '/v1/catalog/products',
            body: p.toJson(),
            key: const Uuid().v4(),
          ),
        )).statusCode,
        409,
      );
      expect(
        (await app(
          request(
            'POST',
            '/v1/catalog/products',
            body: product(branchId: otherBranch).toJson(),
            key: const Uuid().v4(),
          ),
        )).statusCode,
        403,
      );
    },
  );
  test('stock cannot be created by catalog input', () async {
    final input = product().toJson()..['stockBaseQty'] = 500;
    final r = await app(
      request(
        'POST',
        '/v1/catalog/products',
        body: input,
        key: const Uuid().v4(),
      ),
    );
    expect(r.statusCode, 200);
    expect((await responseJson(r))['data']['stockBaseQty'], 0);
  });
  test(
    'pagination is capped, ETag is stable, lookup and search are scoped',
    () async {
      for (var i = 0; i < 31; i++) {
        final r = await app(
          request(
            'POST',
            '/v1/catalog/products',
            body: product(code: 'P$i', barcode: '${10000000 + i}').toJson(),
            key: const Uuid().v4(),
          ),
        );
        expect(r.statusCode, 200);
      }
      final first = await app(request('GET', '/v1/catalog/products?limit=100'));
      final etag = first.headers['etag'];
      final j = await responseJson(first);
      expect(j['data'], hasLength(30));
      expect(j['meta']['limit'], 30);
      final cursor = Uri.encodeQueryComponent(
        j['meta']['nextCursor'] as String,
      );
      final last = await responseJson(
        await app(request('GET', '/v1/catalog/products?cursor=$cursor')),
      );
      expect(last['data'], hasLength(1));
      expect(last['meta']['nextCursor'], isNull);
      final unchanged = await app(
        request(
          'GET',
          '/v1/catalog/products?limit=100',
          headers: {'if-none-match': etag!},
        ),
      );
      expect(unchanged.statusCode, 304);
      expect(await unchanged.readAsString(), '');
      final lookup = await responseJson(
        await app(request('GET', '/v1/catalog/lookup?code=10000000')),
      );
      expect(lookup['data']['code'], 'P0');
      final found = await responseJson(
        await app(request('GET', '/v1/catalog/products?q=P30')),
      );
      expect(found['data'], hasLength(1));
      final forged = base64Url.encode(
        utf8.encode('$otherBranch||20000000-0000-4000-8000-000000000001'),
      );
      expect(
        (await app(
          request('GET', '/v1/catalog/products?cursor=$forged'),
        )).statusCode,
        400,
      );
    },
  );
  test('CORS preflight, rejected origins and error envelopes', () async {
    final pre = await app(
      Request(
        'OPTIONS',
        Uri.parse('http://localhost/v1/catalog/products'),
        headers: {'origin': 'https://shop.test'},
      ),
    );
    expect(pre.statusCode, 204);
    expect(pre.headers['access-control-allow-origin'], 'https://shop.test');
    expect(
      (await app(
        request('GET', '/health', headers: {'origin': 'https://evil.test'}),
      )).statusCode,
      403,
    );
    final bad = await app(
      request(
        'POST',
        '/v1/catalog/products',
        body: {},
        key: const Uuid().v4(),
        headers: {'origin': 'https://shop.test'},
      ),
    );
    expect(bad.statusCode, 400);
    expect(bad.headers['access-control-allow-origin'], 'https://shop.test');
    expect((await responseJson(bad))['error']['code'], 'VALIDATION');
    expect((await app(request('GET', '/missing'))).statusCode, 404);
  });
  test(
    'missing operation key, malformed cursor and oversize body fail safely',
    () async {
      expect(
        (await app(
          request('POST', '/v1/catalog/products', body: product().toJson()),
        )).statusCode,
        400,
      );
      expect(
        (await app(
          request('GET', '/v1/catalog/products?cursor=bad'),
        )).statusCode,
        400,
      );
      expect(
        (await app(
          request(
            'POST',
            '/v1/catalog/products',
            body: {'x': 'a' * 262145},
            key: const Uuid().v4(),
          ),
        )).statusCode,
        413,
      );
    },
  );
  test('rate limit uses correlated error and retry header', () async {
    final limited = createApplication(
      verifier: FixtureVerifier(),
      users: InMemoryUserRepository([actor]),
      catalog: InMemoryCatalogRepository(),
      rateLimiter: RateLimiter(maxRequests: 1),
    );
    expect((await limited(request('GET', '/health'))).statusCode, 200);
    final r = await limited(request('GET', '/health'));
    expect(r.statusCode, 429);
    expect(r.headers['retry-after'], '60');
  });
  test(
    'nested unknown fields and non-JSON content types are rejected',
    () async {
      final body = product().toJson();
      (body['units'] as List).first['unknown'] = true;
      expect(
        (await app(
          request(
            'POST',
            '/v1/catalog/products',
            body: body,
            key: const Uuid().v4(),
          ),
        )).statusCode,
        400,
      );
      expect(
        (await app(
          request(
            'POST',
            '/v1/catalog/products',
            body: product().toJson(),
            key: const Uuid().v4(),
            headers: {'content-type': 'application/jsonp'},
          ),
        )).statusCode,
        400,
      );
    },
  );

  test('read-only roles cannot mutate products', () async {
    final reader = UserSessionDto.fromJson({
      ...actor.toJson(),
      'permissions': ['catalog.read'],
    });
    final readOnly = createApplication(
      verifier: FixtureVerifier(),
      users: InMemoryUserRepository([reader]),
      catalog: InMemoryCatalogRepository(),
    );
    expect(
      (await readOnly(request('GET', '/v1/catalog/products'))).statusCode,
      200,
    );
    expect(
      (await readOnly(
        request(
          'POST',
          '/v1/catalog/products',
          body: product().toJson(),
          key: const Uuid().v4(),
        ),
      )).statusCode,
      403,
    );
  });
}
