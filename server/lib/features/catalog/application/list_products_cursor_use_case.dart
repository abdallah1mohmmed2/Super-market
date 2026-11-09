import 'dart:convert';
import 'package:core_contracts/core_contracts.dart';
import '../../../core/domain_failure.dart';
import '../domain/catalog_repository.dart';

/// Lists a stable branch-scoped page without offset scans.
class ListProductsCursorUseCase {
  final CatalogRepository repository;

  /// Injects catalog reads.
  const ListProductsCursorUseCase(this.repository);

  /// Validates a scoped cursor and clamps page size to thirty.
  Future<({List<ProductDto> products, String? nextCursor, int limit})> call(
    UserSessionDto actor, {
    String? cursor,
    String search = '',
    int limit = 30,
  }) async {
    if (!actor.permissions.contains('catalog.read'))
      throw const DomainFailure('FORBIDDEN', 'لا تملك صلاحية عرض الأصناف');
    String? after;
    if (cursor != null) {
      try {
        final parts = utf8
            .decode(base64Url.decode(base64Url.normalize(cursor)))
            .split('|');
        if (parts.length != 3 ||
            parts[0] != actor.branchId ||
            parts[1] != search ||
            !RegExp(
              r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
            ).hasMatch(parts[2]))
          throw const FormatException();
        after = parts[2];
      } catch (_) {
        throw const DomainFailure('VALIDATION', 'مؤشر الصفحة غير صالح');
      }
    }
    final size = limit.clamp(1, 30);
    final rows = await repository.list(
      actor.branchId,
      after: after,
      search: search,
      limit: size + 1,
    );
    final more = rows.length > size;
    final products = rows.take(size).toList();
    return (
      products: products,
      nextCursor: more
          ? base64Url.encode(
              utf8.encode('${actor.branchId}|$search|${products.last.id}'),
            )
          : null,
      limit: size,
    );
  }
}
