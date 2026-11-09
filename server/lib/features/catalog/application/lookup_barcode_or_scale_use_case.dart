import 'package:core_contracts/core_contracts.dart';
import '../../../core/domain_failure.dart';
import '../domain/catalog_repository.dart';

/// Resolves exact barcode identities; weighted-label parsing belongs to the POS.
class LookupBarcodeOrScaleUseCase {
  final CatalogRepository repository;

  /// Injects a branch-scoped catalog lookup.
  const LookupBarcodeOrScaleUseCase(this.repository);

  /// Reads an exact four-digit PLU or an eight-to-fourteen-digit barcode.
  Future<ProductDto?> call(UserSessionDto actor, String code) {
    if (!actor.permissions.contains('catalog.read'))
      throw const DomainFailure('FORBIDDEN', 'لا تملك صلاحية عرض الأصناف');
    if (!RegExp(r'^(\d{4}|\d{8,14})$').hasMatch(code))
      throw const DomainFailure('VALIDATION', 'الباركود أو PLU غير صالح');
    return repository.lookup(actor.branchId, code);
  }
}
