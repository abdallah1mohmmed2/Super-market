import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:supermarket_server/core/application.dart';
import 'package:supermarket_server/features/auth_users/data/in_memory_user_repository.dart';
import 'package:supermarket_server/features/catalog/data/in_memory_catalog_repository.dart';
import 'fixtures.dart';

void main() {
  test(
    'exports actual success, null, failure and conditional HTTP responses',
    () async {
      final app = createApplication(
        verifier: FixtureVerifier(),
        users: InMemoryUserRepository([actor]),
        catalog: InMemoryCatalogRepository(),
      );
      final samples = <Map<String, dynamic>>[];
      Future<Map<String, String>> capture(
        String method,
        String path, {
        Object? body,
        String? key,
        Map<String, String> headers = const {},
      }) async {
        final r = await app(
          request(method, path, body: body, key: key, headers: headers),
        );
        final raw = await r.readAsString();
        samples.add({
          'path': Uri.parse(path).path,
          'method': method,
          'status': r.statusCode,
          'body': raw.isEmpty ? '' : jsonDecode(raw),
        });
        return r.headers;
      }

      await capture('GET', '/health');
      await capture('GET', '/v1/app-config');
      await capture(
        'POST',
        '/v1/auth/session',
        body: {},
        key: const Uuid().v4(),
      );
      await capture('GET', '/v1/catalog/lookup?code=12345678');
      final p = product(barcode: '12345678');
      await capture(
        'POST',
        '/v1/catalog/products',
        body: p.toJson(),
        key: const Uuid().v4(),
      );
      await capture('GET', '/v1/catalog/lookup?code=12345678');
      final h = await capture('GET', '/v1/catalog/products');
      await capture(
        'GET',
        '/v1/catalog/products',
        headers: {'if-none-match': h['etag']!},
      );
      await capture(
        'GET',
        '/v1/catalog/products',
        headers: {'authorization': 'Bearer invalid'},
      );
      await capture('POST', '/v1/catalog/products', body: p.toJson());
      await capture(
        'POST',
        '/v1/catalog/products',
        body: p.toJson(),
        key: const Uuid().v4(),
      );
      expect(
        samples.map((s) => s['status']),
        containsAll([200, 304, 400, 401, 409]),
      );
      final out = File('build/contract_samples.json');
      await out.parent.create(recursive: true);
      await out.writeAsString(jsonEncode(samples));
    },
  );
}
