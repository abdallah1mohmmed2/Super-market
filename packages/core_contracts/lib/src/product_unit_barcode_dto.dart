/// A product unit, its exact money strings and optional barcode.
class ProductUnitBarcodeDto {
  final String id;
  final String unitName;
  final double conversionFactor;
  final String? barcode;
  final String retailPrice;
  final String wholesalePrice;
  final String costPrice;

  /// Constructs one unit. Conversion is measured in base units.
  const ProductUnitBarcodeDto({
    required this.id,
    required this.unitName,
    required this.conversionFactor,
    this.barcode,
    this.retailPrice = '0.00',
    this.wholesalePrice = '0.00',
    this.costPrice = '0.00',
  });

  /// Decodes a product unit.
  factory ProductUnitBarcodeDto.fromJson(Map<String, dynamic> j) =>
      ProductUnitBarcodeDto(
        id: j['id'] as String,
        unitName: j['unitName'] as String,
        conversionFactor: (j['conversionFactor'] as num).toDouble(),
        barcode: j['barcode'] as String?,
        retailPrice: j['retailPrice'] as String,
        wholesalePrice: j['wholesalePrice'] as String,
        costPrice: j['costPrice'] as String,
      );

  /// Serializes the complete unit.
  Map<String, dynamic> toJson() => {
    'id': id,
    'unitName': unitName,
    'conversionFactor': conversionFactor,
    'barcode': barcode,
    'retailPrice': retailPrice,
    'wholesalePrice': wholesalePrice,
    'costPrice': costPrice,
  };
}
