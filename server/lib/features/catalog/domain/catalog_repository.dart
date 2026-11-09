import 'package:core_contracts/core_contracts.dart';

/// Branch-scoped catalog persistence with transactional deduplication.
abstract interface class CatalogRepository {
  /// Saves a definition atomically with audit and operation identity.
  Future<ProductDto> upsert(
    ProductDto product,
    UserSessionDto actor,
    String key,
    String fingerprint,
  );

  /// Reads at most limit+1 rows after a stable UUID cursor.
  Future<List<ProductDto>> list(
    String branchId, {
    String? after,
    String search = '',
    int limit = 30,
  });

  /// Resolves a barcode or PLU inside the authorized branch only.
  Future<ProductDto?> lookup(String branchId, String code);
}
