import 'dart:convert';
import 'package:core_contracts/core_contracts.dart';
import 'package:postgres/postgres.dart';
import '../../../core/domain_failure.dart';
import '../domain/catalog_repository.dart';

/// PostgreSQL catalog adapter; all writes, audit and deduplication share one transaction.
class PostgresCatalogRepository implements CatalogRepository {
  final Pool pool;

  /// Injects the bounded database connection pool.
  const PostgresCatalogRepository(this.pool);
  static const _projection = r'''
 SELECT json_build_object('id',p.id::text,'branchId',p.branch_id::text,
 'code',p.code,'name',p.name,'baseUnit',p.base_unit,'isWeighted',p.is_weighted,
 'categoryId',p.category_id::text,'scalePluCode',p.scale_plu_code,
 'stockBaseQty',p.stock_base_qty,'revision',p.revision,'updatedAt',p.updated_at,
 'units',COALESCE((SELECT json_agg(json_build_object('id',u.id::text,
 'unitName',u.unit_name,'conversionFactor',u.conversion_factor,'barcode',u.barcode,
 'retailPrice',u.retail_price::text,'wholesalePrice',u.wholesale_price::text,
 'costPrice',u.cost_price::text) ORDER BY u.conversion_factor,u.id)
 FROM product_units_barcodes u WHERE u.product_id=p.id AND u.deleted_at IS NULL),'[]'::json))
 FROM products p WHERE p.deleted_at IS NULL AND p.branch_id=@branch
 ''';
  ProductDto _decode(Object? object) =>
      ProductDto.fromJson(Map<String, dynamic>.from(object as Map));

  /// Applies a command once and preserves stock when editing definitions.
  @override
  Future<ProductDto> upsert(
    ProductDto p,
    UserSessionDto actor,
    String key,
    String fingerprint,
  ) async {
    try {
      return await pool.runTx((tx) async {
        final scope = 'catalog/${actor.branchId}';
        await tx.execute(
          Sql.named('SELECT pg_advisory_xact_lock(hashtextextended(@scope,0))'),
          parameters: {'scope': scope},
        );
        final identity = {
          'user': actor.userId,
          'branch': actor.branchId,
          'key': key,
          'route': '/v1/catalog/products',
        };
        final saved = await tx.execute(
          Sql.named(
            'SELECT payload_hash,response FROM idempotency_keys WHERE user_id=@user AND branch_id=@branch AND route=@route AND operation_key=@key',
          ),
          parameters: identity,
        );
        if (saved.isNotEmpty) {
          if (saved.first[0] != fingerprint)
            throw const DomainFailure(
              'IDEMPOTENCY_CONFLICT',
              'مفتاح العملية مستخدم بمحتوى مختلف',
            );
          return _decode(saved.first[1]);
        }
        final oldRows = await tx.execute(
          Sql.named(
            'SELECT branch_id::text,revision,stock_base_qty::text FROM products WHERE id=@id FOR UPDATE',
          ),
          parameters: {'id': p.id},
        );
        if (oldRows.isNotEmpty && oldRows.first[0] != actor.branchId)
          throw const DomainFailure('FORBIDDEN', 'الصنف خارج الفرع النشط');
        final oldRevision = oldRows.isEmpty ? 0 : oldRows.first[1] as int;
        if (oldRevision != p.revision)
          throw const DomainFailure(
            'REVISION_CONFLICT',
            'تغير الصنف على جهاز آخر؛ حدّث البيانات',
          );
        final old = await tx.execute(
          Sql.named('$_projection AND p.id=@id'),
          parameters: {'branch': actor.branchId, 'id': p.id},
        );
        await tx.execute(
          Sql.named(
            '''INSERT INTO products(id,branch_id,category_id,code,name,base_unit,is_weighted,scale_plu_code,revision)
 VALUES(@id,@branch,@category,@code,@name,@base,@weighted,@plu,1)
 ON CONFLICT(id) DO UPDATE SET category_id=EXCLUDED.category_id,code=EXCLUDED.code,name=EXCLUDED.name,
 base_unit=EXCLUDED.base_unit,is_weighted=EXCLUDED.is_weighted,scale_plu_code=EXCLUDED.scale_plu_code,revision=products.revision+1''',
          ),
          parameters: {
            'id': p.id,
            'branch': p.branchId,
            'category': p.categoryId,
            'code': p.code,
            'name': p.name,
            'base': p.baseUnit,
            'weighted': p.isWeighted,
            'plu': p.scalePluCode,
          },
        );
        await tx.execute(
          Sql.named(
            'UPDATE product_units_barcodes SET deleted_at=now() WHERE product_id=@id AND branch_id=@branch',
          ),
          parameters: {'id': p.id, 'branch': actor.branchId},
        );
        for (final u in p.units) {
          final owned = await tx.execute(
            Sql.named(
              'SELECT product_id::text FROM product_units_barcodes WHERE id=@id',
            ),
            parameters: {'id': u.id},
          );
          if (owned.isNotEmpty && owned.first[0] != p.id)
            throw const DomainFailure(
              'DUPLICATE',
              'معرّف الوحدة مستخدم لصنف آخر',
            );
          await tx.execute(
            Sql.named(
              '''INSERT INTO product_units_barcodes(id,product_id,branch_id,unit_name,conversion_factor,barcode,retail_price,wholesale_price,cost_price)
 VALUES(@id,@product,@branch,@name,@factor,@barcode,@retail,@wholesale,@cost)
 ON CONFLICT(id) DO UPDATE SET unit_name=EXCLUDED.unit_name,conversion_factor=EXCLUDED.conversion_factor,
 barcode=EXCLUDED.barcode,retail_price=EXCLUDED.retail_price,wholesale_price=EXCLUDED.wholesale_price,
 cost_price=EXCLUDED.cost_price,deleted_at=NULL''',
            ),
            parameters: {
              'id': u.id,
              'product': p.id,
              'branch': p.branchId,
              'name': u.unitName,
              'factor': u.conversionFactor,
              'barcode': u.barcode,
              'retail': u.retailPrice,
              'wholesale': u.wholesalePrice,
              'cost': u.costPrice,
            },
          );
        }
        final rows = await tx.execute(
          Sql.named('$_projection AND p.id=@id'),
          parameters: {'branch': p.branchId, 'id': p.id},
        );
        final result = _decode(rows.first[0]);
        await tx.execute(
          Sql.named(
            '''INSERT INTO idempotency_keys(user_id,branch_id,route,operation_key,payload_hash,response)
 VALUES(@user,@branch,@route,@key,@hash,CAST(@response AS jsonb))''',
          ),
          parameters: {
            ...identity,
            'hash': fingerprint,
            'response': jsonEncode(result.toJson()),
          },
        );
        await tx.execute(
          Sql.named(
            '''INSERT INTO audit_logs(branch_id,user_id,action,entity_type,entity_id,old_values,new_values)
 VALUES(@branch,@user,'CATALOG_UPSERT','product',@id,CAST(@old AS jsonb),CAST(@new AS jsonb))''',
          ),
          parameters: {
            'branch': p.branchId,
            'user': actor.userId,
            'id': p.id,
            'old': old.isEmpty ? null : jsonEncode(old.first[0]),
            'new': jsonEncode(result.toJson()),
          },
        );
        return result;
      });
    } on ServerException catch (e) {
      if (e.code == '23505')
        throw const DomainFailure(
          'DUPLICATE',
          'الكود أو الباركود أو PLU مستخدم مسبقاً',
        );
      if (e.code == '23503' || e.code == '23514')
        throw const DomainFailure(
          'VALIDATION',
          'بيانات الصنف أو الوحدة غير متوافقة',
        );
      rethrow;
    }
  }

  /// Reads one indexed UUID page with safe bound search parameters.
  @override
  Future<List<ProductDto>> list(
    String branchId, {
    String? after,
    String search = '',
    int limit = 30,
  }) async {
    final rows = await pool.execute(
      Sql.named('''$_projection
 AND (@after::uuid IS NULL OR p.id>@after::uuid)
 AND (@search='' OR position(lower(@search) in lower(p.name))>0 OR position(lower(@search) in lower(p.code))>0
 OR EXISTS(SELECT 1 FROM product_units_barcodes u WHERE u.product_id=p.id AND u.deleted_at IS NULL AND position(@search in u.barcode)>0))
 ORDER BY p.id LIMIT @limit'''),
      parameters: {
        'branch': branchId,
        'after': after,
        'search': search,
        'limit': limit,
      },
    );
    return rows.map((r) => _decode(r[0])).toList();
  }

  /// Resolves the exact scoped identity without trusting client branch selection.
  @override
  Future<ProductDto?> lookup(String branchId, String code) async {
    final rows = await pool.execute(
      Sql.named(
        '''$_projection AND (p.scale_plu_code=@code OR EXISTS
 (SELECT 1 FROM product_units_barcodes u WHERE u.product_id=p.id AND u.deleted_at IS NULL AND u.barcode=@code)) LIMIT 1''',
      ),
      parameters: {'branch': branchId, 'code': code},
    );
    return rows.isEmpty ? null : _decode(rows.first[0]);
  }
}
