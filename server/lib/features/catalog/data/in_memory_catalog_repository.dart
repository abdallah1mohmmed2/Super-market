import 'package:core_contracts/core_contracts.dart';
import '../../../core/domain_failure.dart';
import '../domain/catalog_repository.dart';

/// An explicit, non-persistent development adapter implementing production rules.
class InMemoryCatalogRepository implements CatalogRepository {
  final Map<String, ProductDto> _products = {};
  final Map<String, ({String hash, ProductDto product})> _operations = {};

  /// Applies a complete mutation synchronously within the isolate.
  @override
  Future<ProductDto> upsert(
    ProductDto p,
    UserSessionDto actor,
    String key,
    String fingerprint,
  ) async {
    final scope = '${actor.userId}/${actor.branchId}/$key';
    final previous = _operations[scope];
    if (previous != null) {
      if (previous.hash != fingerprint)
        throw const DomainFailure(
          'IDEMPOTENCY_CONFLICT',
          'مفتاح العملية مستخدم بمحتوى مختلف',
        );
      return previous.product;
    }
    final old = _products[p.id];
    if (old != null && old.branchId != actor.branchId)
      throw const DomainFailure('FORBIDDEN', 'الصنف خارج الفرع النشط');
    if ((old?.revision ?? 0) != p.revision)
      throw const DomainFailure(
        'REVISION_CONFLICT',
        'تغير الصنف على جهاز آخر؛ حدّث البيانات',
      );
    for (final other in _products.values.where(
      (e) => e.branchId == actor.branchId && e.id != p.id,
    )) {
      if (other.code == p.code ||
          p.scalePluCode != null && other.scalePluCode == p.scalePluCode)
        throw const DomainFailure('DUPLICATE', 'الكود أو PLU مستخدم مسبقاً');
      for (final u in p.units) {
        if (u.barcode != null && other.units.any((o) => o.barcode == u.barcode))
          throw const DomainFailure('DUPLICATE', 'الباركود مستخدم لصنف آخر');
      }
    }
    for (final other in _products.values.where((e) => e.id != p.id)) {
      if (p.units.any((u) => other.units.any((o) => o.id == u.id))) {
        throw const DomainFailure('DUPLICATE', 'معرّف الوحدة مستخدم لصنف آخر');
      }
    }
    if (p.categoryId != null) {
      throw const DomainFailure(
        'VALIDATION',
        'التصنيف غير موجود في مخزن التطوير',
      );
    }
    final result = p.acknowledged(
      p.revision + 1,
      DateTime.now().toUtc(),
      stock: old?.stockBaseQty ?? 0,
    );
    _products[p.id] = result;
    _operations[scope] = (hash: fingerprint, product: result);
    return result;
  }

  /// Reads sorted UUID pages, optionally matching identity text.
  @override
  Future<List<ProductDto>> list(
    String branchId, {
    String? after,
    String search = '',
    int limit = 30,
  }) async {
    final q = search.toLowerCase();
    final rows =
        _products.values
            .where(
              (p) =>
                  p.branchId == branchId &&
                  (after == null || p.id.compareTo(after) > 0) &&
                  (q.isEmpty ||
                      p.name.toLowerCase().contains(q) ||
                      p.code.toLowerCase().contains(q) ||
                      p.units.any((u) => u.barcode?.contains(q) ?? false)),
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return rows.take(limit).toList();
  }

  /// Resolves an exact barcode or PLU in one branch.
  @override
  Future<ProductDto?> lookup(String branchId, String code) async {
    for (final p in _products.values) {
      if (p.branchId == branchId &&
          (p.scalePluCode == code || p.units.any((u) => u.barcode == code)))
        return p;
    }
    return null;
  }
}
