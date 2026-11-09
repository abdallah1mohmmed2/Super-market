import 'dart:convert';
import 'package:core_contracts/core_contracts.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../../core/domain_failure.dart';
import '../../../core/http_responses.dart';
import '../../../shared/firebase_auth_middleware.dart';
import '../../../shared/request_body.dart';
import '../application/upsert_product_use_case.dart';
import '../application/list_products_cursor_use_case.dart';
import '../application/lookup_barcode_or_scale_use_case.dart';

/// HTTP-only adaptation of the catalog's use cases.
class CatalogRoutes {
  final UpsertProductUseCase upsert;
  final ListProductsCursorUseCase list;
  final LookupBarcodeOrScaleUseCase lookup;

  /// Injects application cases without importing persistence adapters.
  const CatalogRoutes(this.upsert, this.list, this.lookup);

  /// Registers the version-one product and exact-lookup routes.
  Router get router {
    final r = Router();
    r.post('/v1/catalog/products', (Request request) async {
      final key = operationKey(request);
      final json = await readObject(request);
      const keys = {
        'id',
        'branchId',
        'code',
        'name',
        'baseUnit',
        'isWeighted',
        'scalePluCode',
        'categoryId',
        'units',
        'stockBaseQty',
        'revision',
        'updatedAt',
      };
      if (json.keys.any((k) => !keys.contains(k)))
        throw const DomainFailure(
          'VALIDATION',
          'يتضمن الطلب حقولاً غير معروفة',
        );
      const unitKeys = {
        'id',
        'unitName',
        'conversionFactor',
        'barcode',
        'retailPrice',
        'wholesalePrice',
        'costPrice',
      };
      if (json['units'] is List) {
        for (final unit in json['units'] as List) {
          if (unit is Map && unit.keys.any((k) => !unitKeys.contains(k))) {
            throw const DomainFailure(
              'VALIDATION',
              'تتضمن الوحدة حقولاً غير معروفة',
            );
          }
        }
      }
      final product = ProductDto.fromJson(json);
      final hash = sha256
          .convert(utf8.encode(jsonEncode(canonicalJson(product.toJson()))))
          .toString();
      final result = await upsert(product, actorOf(request), key, hash);
      return success(request, result.toJson());
    });
    r.get('/v1/catalog/products', (Request request) async {
      final params = request.url.queryParameters;
      final limit = int.tryParse(params['limit'] ?? '30');
      if (limit == null || limit < 1)
        throw const DomainFailure('VALIDATION', 'حجم الصفحة غير صالح');
      final q = params['q'] ?? '';
      if (q.length > 160 || q.contains('|'))
        throw const DomainFailure('VALIDATION', 'نص البحث غير صالح');
      final page = await list(
        actorOf(request),
        cursor: params['cursor'],
        search: q,
        limit: limit,
      );
      final data = page.products.map((p) => p.toJson()).toList();
      final hash = sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'branch': actorOf(request).branchId,
                'data': data,
                'next': page.nextCursor,
                'limit': page.limit,
              }),
            ),
          )
          .toString();
      final etag = '"$hash"';
      if (request.headers['if-none-match'] == etag)
        return Response(
          304,
          headers: {'etag': etag, 'cache-control': 'private, no-cache'},
        );
      return success(
        request,
        data,
        nextCursor: page.nextCursor,
        limit: page.limit,
        headers: {'etag': etag, 'cache-control': 'private, no-cache'},
      );
    });
    r.get(
      '/v1/catalog/lookup',
      (Request request) async => success(
        request,
        (await lookup(
          actorOf(request),
          request.url.queryParameters['code'] ?? '',
        ))?.toJson(),
      ),
    );
    return r;
  }
}
