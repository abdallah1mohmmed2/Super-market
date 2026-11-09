import 'package:core_contracts/core_contracts.dart';
import '../../../core/domain_failure.dart';

/// Enforces product identity, numeric units and decimal money invariants.
class Product {
  final ProductDto value;

  /// Creates a validated product aggregate from immutable shared value contracts.
  Product(this.value) {
    final p = value;
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final money = RegExp(r'^(0|[1-9][0-9]{0,12})\.[0-9]{2}$');
    void require(bool valid, String message) {
      if (!valid) throw DomainFailure('VALIDATION', message);
    }

    require(
      uuid.hasMatch(p.id) && uuid.hasMatch(p.branchId),
      'معرّف الصنف أو الفرع غير صالح',
    );
    require(
      p.code.trim().isNotEmpty &&
          p.code == p.code.trim() &&
          p.code.length <= 40,
      'كود الصنف مطلوب وبحد أقصى40 حرفاً',
    );
    require(
      p.name.trim().isNotEmpty && p.name.length <= 160,
      'اسم الصنف مطلوب وبحد أقصى160 حرفاً',
    );
    require(
      p.baseUnit.trim().isNotEmpty &&
          p.baseUnit == p.baseUnit.trim() &&
          p.baseUnit.length <= 30,
      'وحدة الأساس مطلوبة',
    );
    require(p.revision >= 0, 'إصدار الصنف غير صالح');
    require(p.stockBaseQty.isFinite && p.stockBaseQty >= 0, 'الكمية غير صالحة');
    require(
      p.units.isNotEmpty && p.units.length <= 30,
      'أضف وحدة واحدة وحتى30 وحدة',
    );
    require(
      p.units.any((u) => u.conversionFactor == 1 && u.unitName == p.baseUnit),
      'يلزم تعريف وحدة الأساس بمعامل1',
    );
    require(
      p.scalePluCode == null ||
          (p.isWeighted && RegExp(r'^\d{4}$').hasMatch(p.scalePluCode!)),
      'كود PLU يجب أن يكون4 أرقام لصنف موزون',
    );
    require(
      p.categoryId == null || uuid.hasMatch(p.categoryId!),
      'التصنيف غير صالح',
    );
    final ids = <String>{};
    final names = <String>{};
    final barcodes = <String>{};
    for (final u in p.units) {
      require(
        uuid.hasMatch(u.id) && ids.add(u.id),
        'معرّف وحدة مكرر أو غير صالح',
      );
      require(
        u.unitName.trim().isNotEmpty &&
            u.unitName == u.unitName.trim() &&
            u.unitName.length <= 30 &&
            names.add(u.unitName),
        'اسم وحدة مكرر أو غير صالح',
      );
      require(
        u.conversionFactor.isFinite &&
            u.conversionFactor > 0 &&
            u.conversionFactor <= 1000000 &&
            double.parse(u.conversionFactor.toStringAsFixed(6)) ==
                u.conversionFactor,
        'معامل التحويل يجب أن يكون موجباً',
      );
      require(
        p.isWeighted ||
            u.conversionFactor == u.conversionFactor.roundToDouble(),
        'الصنف العددي يحتاج معامل تحويل صحيحاً',
      );
      require(
        money.hasMatch(u.retailPrice) &&
            money.hasMatch(u.wholesalePrice) &&
            money.hasMatch(u.costPrice),
        'السعر غير صالح؛ استخدم منزلتين عشريتين',
      );
      require(
        u.barcode == null ||
            (RegExp(r'^\d{8,14}$').hasMatch(u.barcode!) &&
                barcodes.add(u.barcode!)),
        'الباركود مكرر أو ليس8–14 رقماً',
      );
    }
  }
}
