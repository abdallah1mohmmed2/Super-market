import 'product_unit_barcode_dto.dart';

/// A branch-scoped product definition with server-owned stock and revision.
class ProductDto {
  final String id;
  final String branchId;
  final String code;
  final String name;
  final String baseUnit;
  final bool isWeighted;
  final String? scalePluCode;
  final String? categoryId;
  final List<ProductUnitBarcodeDto> units;
  final double stockBaseQty;
  final int revision;
  final DateTime? updatedAt;

  /// Constructs a product. New products always start with zero stock.
  ProductDto({
    required this.id,
    required this.branchId,
    required this.code,
    required this.name,
    required this.baseUnit,
    required List<ProductUnitBarcodeDto> units,
    this.isWeighted = false,
    this.scalePluCode,
    this.categoryId,
    this.stockBaseQty = 0,
    this.revision = 0,
    this.updatedAt,
  }) : units = List.unmodifiable(units);

  /// Decodes a product and its full unit list.
  factory ProductDto.fromJson(Map<String, dynamic> j) => ProductDto(
    id: j['id'] as String,
    branchId: j['branchId'] as String,
    code: j['code'] as String,
    name: j['name'] as String,
    baseUnit: j['baseUnit'] as String,
    isWeighted: j['isWeighted'] as bool,
    scalePluCode: j['scalePluCode'] as String?,
    categoryId: j['categoryId'] as String?,
    units: (j['units'] as List)
        .map(
          (v) => ProductUnitBarcodeDto.fromJson(
            Map<String, dynamic>.from(v as Map),
          ),
        )
        .toList(),
    stockBaseQty: (j['stockBaseQty'] as num).toDouble(),
    revision: j['revision'] as int,
    updatedAt: j['updatedAt'] == null
        ? null
        : DateTime.parse(j['updatedAt'] as String),
  );

  /// Copies server acknowledgement fields without losing local definitions.
  ProductDto acknowledged(int newRevision, DateTime time, {double? stock}) =>
      ProductDto(
        id: id,
        branchId: branchId,
        code: code,
        name: name,
        baseUnit: baseUnit,
        units: units,
        isWeighted: isWeighted,
        scalePluCode: scalePluCode,
        categoryId: categoryId,
        stockBaseQty: stock ?? stockBaseQty,
        revision: newRevision,
        updatedAt: time,
      );

  /// Serializes the complete product contract.
  Map<String, dynamic> toJson() => {
    'id': id,
    'branchId': branchId,
    'code': code,
    'name': name,
    'baseUnit': baseUnit,
    'isWeighted': isWeighted,
    'scalePluCode': scalePluCode,
    'categoryId': categoryId,
    'units': units.map((u) => u.toJson()).toList(),
    'stockBaseQty': stockBaseQty,
    'revision': revision,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };
}
