import 'dart:convert';
import 'dart:io';
import 'package:core_contracts/core_contracts.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:supermarket_server/core/domain_failure.dart';
import 'package:supermarket_server/features/catalog/data/postgres_catalog_repository.dart';
import 'package:supermarket_server/features/auth_users/data/postgres_user_repository.dart';
import 'fixtures.dart';

void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  group(
    'PostgreSQL transactions',
    () {
      late Pool pool;
      late PostgresCatalogRepository catalog;
      setUpAll(() async {
        pool = Pool.withUrl(url!);
        catalog = PostgresCatalogRepository(pool);
        // This suite requires a dedicated migrated test database, never production.
        await pool.execute(
          Sql.named(
            'INSERT INTO branches(id,name) VALUES(@id,@name) ON CONFLICT(id) DO NOTHING',
          ),
          parameters: {'id': branch, 'name': 'فرع اختبارات'},
        );
        await pool.execute(
          Sql.named(
            "INSERT INTO users(id,firebase_uid,display_name,branch_id,role_id) SELECT @id,@uid,'اختبار',@branch,id FROM roles WHERE code='ADMIN' ON CONFLICT(id) DO NOTHING",
          ),
          parameters: {
            'id': actor.userId,
            'uid': actor.firebaseUid,
            'branch': branch,
          },
        );
      });
      tearDownAll(() async => pool.close());
      test('provisioned session resolves actual role permissions', () async {
        final session = await PostgresUserRepository(
          pool,
        ).findByFirebaseUid(actor.firebaseUid);
        expect(session?.branchId, branch);
        expect(session?.permissions, contains('catalog.write'));
      });
      test(
        'ten concurrent duplicate requests create one row and one audit',
        () async {
          final p = product();
          final key = const Uuid().v4();
          final results = await Future.wait(
            List.generate(
              10,
              (_) => catalog.upsert(p, actor, key, 'identical'),
            ),
          );
          expect(results.map((p) => p.revision).toSet(), {1});
          final count = await pool.execute(
            Sql.named('SELECT count(*) FROM audit_logs WHERE entity_id=@id'),
            parameters: {'id': p.id},
          );
          expect(count.first[0], 1);
          await expectLater(
            catalog.upsert(p, actor, key, 'different'),
            throwsA(
              isA<DomainFailure>().having(
                (e) => e.code,
                'code',
                'IDEMPOTENCY_CONFLICT',
              ),
            ),
          );
        },
      );
      test(
        'duplicate barcode rolls back product, key and audit together',
        () async {
          final barcode = '${DateTime.now().microsecondsSinceEpoch}'.substring(
            0,
            13,
          );
          await catalog.upsert(
            product(barcode: barcode),
            actor,
            const Uuid().v4(),
            'first',
          );
          final second = product(barcode: barcode);
          final key = const Uuid().v4();
          await expectLater(
            catalog.upsert(second, actor, key, 'second'),
            throwsA(
              isA<DomainFailure>().having((e) => e.code, 'code', 'DUPLICATE'),
            ),
          );
          final productRows = await pool.execute(
            Sql.named('SELECT id FROM products WHERE id=@id'),
            parameters: {'id': second.id},
          );
          expect(productRows, isEmpty);
          final operations = await pool.execute(
            Sql.named(
              'SELECT id FROM idempotency_keys WHERE operation_key=@key',
            ),
            parameters: {'key': key},
          );
          expect(operations, isEmpty);
          final audit = await pool.execute(
            Sql.named('SELECT id FROM audit_logs WHERE entity_id=@id'),
            parameters: {'id': second.id},
          );
          expect(audit, isEmpty);
        },
      );
      test(
        'stock is preserved, stale revisions rejected, exact lookup works',
        () async {
          final barcode = '${DateTime.now().microsecondsSinceEpoch}'.substring(
            1,
            14,
          );
          final p = product(barcode: barcode);
          final first = await catalog.upsert(
            p,
            actor,
            const Uuid().v4(),
            'first',
          );
          await pool.execute(
            Sql.named('UPDATE products SET stock_base_qty=24 WHERE id=@id'),
            parameters: {'id': p.id},
          );
          final input = ProductDto.fromJson({
            ...first.toJson(),
            'stockBaseQty': 999,
            'name': 'اسم جديد',
          });
          final updated = await catalog.upsert(
            input,
            actor,
            const Uuid().v4(),
            'update',
          );
          expect(updated.stockBaseQty, 24);
          expect(updated.revision, 2);
          expect(updated.name, 'اسم جديد');
          await expectLater(
            catalog.upsert(p, actor, const Uuid().v4(), 'stale'),
            throwsA(
              isA<DomainFailure>().having(
                (e) => e.code,
                'code',
                'REVISION_CONFLICT',
              ),
            ),
          );
          expect((await catalog.lookup(branch, barcode))?.id, p.id);
          expect(await catalog.lookup(otherBranch, barcode), isNull);
          expect(
            (await catalog.list(
              branch,
              search: 'اسم جديد',
            )).any((p) => p.id == updated.id),
            isTrue,
          );
          expect(await catalog.list(otherBranch), isEmpty);
          final roundTrip = ProductDto.fromJson(
            jsonDecode(jsonEncode(updated.toJson())) as Map<String, dynamic>,
          );
          expect(roundTrip.units.first.retailPrice, '150.00');
        },
      );
    },
    skip: url == null
        ? 'TEST_DATABASE_URL is required for a dedicated migrated PostgreSQL test database'
        : false,
  );
}
