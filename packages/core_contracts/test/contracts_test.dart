import 'dart:convert';

import 'package:core_contracts/core_contracts.dart';
import 'package:test/test.dart';

void main() {
  test(
    'exact price strings survive transport and product collections are immutable',
    () {
      final p = ProductDto(
        id: '30000000-0000-4000-8000-000000000001',
        branchId: '20000000-0000-4000-8000-000000000001',
        code: 'P1',
        name: 'أرز',
        baseUnit: 'حبة',
        units: [
          const ProductUnitBarcodeDto(
            id: '40000000-0000-4000-8000-000000000001',
            unitName: 'حبة',
            conversionFactor: 1,
            retailPrice: '9999999999999.99',
          ),
        ],
      );
      final decoded = ProductDto.fromJson(
        jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.units.first.retailPrice, '9999999999999.99');
      expect(() => decoded.units.clear(), throwsUnsupportedError);
      final ack = decoded.acknowledged(1, DateTime.utc(2026), stock: 24);
      expect(ack.revision, 1);
      expect(ack.stockBaseQty, 24);
      expect(decoded.revision, 0);
    },
  );
  test('response and error envelopes retain their correlation', () {
    final response = ApiResponse<String>(
      data: 'ok',
      meta: const PageMeta(requestId: 'request-1'),
    );
    final decoded = ApiResponse<String>.fromJson(
      response.toJson((v) => v),
      (v) => v as String,
    );
    expect(decoded.meta.requestId, 'request-1');
    expect(decoded.meta.nextCursor, isNull);
    final error = ApiError.fromJson({
      'code': 'CONFLICT',
      'message': 'تعارض',
      'requestId': 'request-2',
    }, status: 409);
    expect(error.toJson()['requestId'], 'request-2');
    expect(error.status, 409);
  });
}
