import 'dart:async';
import 'dart:convert';
import 'package:api_client/api_client.dart';
import 'package:core_contracts/core_contracts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// An injected credential provider used solely by isolated transport tests.
class Tokens implements TokenProvider {
  @override
  Future<String?> getToken() async => 'firebase-token';
}

void main() {
  final p = ProductDto(
    id: '30000000-0000-4000-8000-000000000001',
    branchId: '20000000-0000-4000-8000-000000000001',
    code: 'P1',
    name: 'أرز',
    baseUnit: 'حبة',
    units: [
      const ProductUnitBarcodeDto(
        id: '40000000-0000-4000-8000-000000000001',
        unitName: 'حبة',
        conversionFactor: 1,
      ),
    ],
  );
  const key = '50000000-0000-4000-8000-000000000001';
  test(
    'mutation retry keeps the same key, body, token and request ID',
    () async {
      final requests = <http.Request>[];
      final client = ErpApiClient(
        baseUrl: Uri.parse('https://erp.test'),
        tokens: Tokens(),
        retryDelay: Duration.zero,
        client: MockClient((request) async {
          requests.add(request);
          if (requests.length == 1)
            throw http.ClientException('connection lost');
          if (requests.length == 2)
            return http.Response('temporary failure', 503);
          return http.Response(
            jsonEncode({
              'data': p.toJson(),
              'meta': {
                'page': 1,
                'limit': 30,
                'nextCursor': null,
                'requestId': request.headers['X-Request-Id'],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final result = await client.upsertProduct(p, idempotencyKey: key);
      expect(result.id, p.id);
      expect(requests, hasLength(3));
      expect(requests.map((r) => r.headers['Idempotency-Key']).toSet(), {key});
      expect(
        requests.map((r) => r.headers['X-Request-Id']).toSet(),
        hasLength(1),
      );
      expect(requests.map((r) => r.headers['Authorization']).toSet(), {
        'Bearer firebase-token',
      });
      expect(requests.map((r) => r.body).toSet(), hasLength(1));
      client.close();
    },
  );
  test('business conflicts are not retried', () async {
    var calls = 0;
    final client = ErpApiClient(
      baseUrl: Uri.parse('https://erp.test'),
      tokens: Tokens(),
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'DUPLICATE',
              'message': 'الباركود مكرر',
              'requestId': 'r1',
            },
          }),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await expectLater(
      client.upsertProduct(p, idempotencyKey: key),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 409)),
    );
    expect(calls, 1);
    client.close();
  });
  test(
    'conditional pages preserve the validator and cap requested size',
    () async {
      final client = ErpApiClient(
        baseUrl: Uri.parse('https://erp.test'),
        tokens: Tokens(),
        client: MockClient((r) async {
          expect(r.url.queryParameters['limit'], '30');
          expect(r.headers['If-None-Match'], '"etag"');
          return http.Response('', 304, headers: {'etag': '"etag"'});
        }),
      );
      final page = await client.listProducts(limit: 100, etag: '"etag"');
      expect(page.notModified, isTrue);
      expect(page.response, isNull);
      expect(page.etag, '"etag"');
      client.close();
    },
  );
  test('timeouts retry with a bounded budget', () async {
    var calls = 0;
    final client = ErpApiClient(
      baseUrl: Uri.parse('https://erp.test'),
      tokens: Tokens(),
      retryDelay: Duration.zero,
      client: MockClient((_) async {
        calls++;
        throw TimeoutException('timeout');
      }),
    );
    await expectLater(client.listProducts(), throwsA(isA<TimeoutException>()));
    expect(calls, 3);
    client.close();
  });
}
