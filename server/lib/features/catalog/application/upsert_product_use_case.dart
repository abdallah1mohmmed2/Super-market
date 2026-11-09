import 'package:core_contracts/core_contracts.dart';
import '../../../core/domain_failure.dart';
import '../domain/catalog_repository.dart';
import '../domain/product.dart';

/// Authorizes and validates a catalog definition before persistence.
class UpsertProductUseCase {
  final CatalogRepository repository;

  /// Injects transactional persistence.
  const UpsertProductUseCase(this.repository);

  /// Executes a branch-isolated command with a stable operation identity.
  Future<ProductDto> call(
    ProductDto dto,
    UserSessionDto actor,
    String key,
    String fingerprint,
  ) {
    if (!actor.permissions.contains('catalog.write'))
      throw const DomainFailure('FORBIDDEN', 'لا تملك صلاحية تعديل الأصناف');
    if (dto.branchId != actor.branchId)
      throw const DomainFailure('FORBIDDEN', 'الصنف لا ينتمي إلى الفرع النشط');
    return repository.upsert(Product(dto).value, actor, key, fingerprint);
  }
}
