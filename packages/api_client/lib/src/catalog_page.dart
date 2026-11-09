import 'package:core_contracts/core_contracts.dart';

/// A conditionally fetched catalog page and its validator.
class CatalogPage {
  final ApiResponse<List<ProductDto>>? response;
  final String? etag;
  final bool notModified;

  /// Carries a complete page or an explicit 304 result.
  const CatalogPage({this.response, this.etag, this.notModified = false});
}
