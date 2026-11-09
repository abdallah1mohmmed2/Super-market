import 'dart:convert';
import 'package:core_contracts/core_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'package:supermarket_server/core/domain_failure.dart';
import 'package:supermarket_server/features/auth_users/domain/auth_verifier.dart';

const branch = '20000000-0000-4000-8000-000000000001';
const otherBranch = '20000000-0000-4000-8000-000000000002';
final actor = UserSessionDto(
  userId: '10000000-0000-4000-8000-000000000001',
  firebaseUid: 'fixture-uid',
  displayName: 'اختبار',
  branchId: branch,
  branchName: 'اختبار',
  role: 'ADMIN',
  permissions: ['catalog.read', 'catalog.write'],
);

/// Injected verifier for isolated transport tests, unavailable to production wiring.
class FixtureVerifier implements AuthVerifier {
  @override
  Future<String> verify(String token) async {
    if (token != 'test-token')
      throw const DomainFailure('UNAUTHENTICATED', 'رمز غير صالح');
    return 'fixture-uid';
  }
}

/// Builds a complete product without any production seed data.
ProductDto product({
  String? id,
  String? code,
  String? barcode,
  int revision = 0,
  String branchId = branch,
}) => ProductDto(
  id: id ?? const Uuid().v4(),
  branchId: branchId,
  code: code ?? const Uuid().v4(),
  name: 'أرز',
  baseUnit: 'حبة',
  revision: revision,
  units: [
    ProductUnitBarcodeDto(
      id: const Uuid().v4(),
      unitName: 'حبة',
      conversionFactor: 1,
      barcode: barcode,
      retailPrice: '150.00',
      wholesalePrice: '120.00',
    ),
  ],
);

/// Builds correlated authenticated HTTP requests to exercise the complete pipeline.
Request request(
  String method,
  String path, {
  Object? body,
  String? key,
  Map<String, String> headers = const {},
}) => Request(
  method,
  Uri.parse('http://localhost$path'),
  headers: {
    'x-request-id': 'fixture-request',
    'authorization': 'Bearer test-token',
    if (body != null) 'content-type': 'application/json',
    if (key != null) 'idempotency-key': key,
    ...headers,
  },
  body: body == null ? null : jsonEncode(body),
);

/// Decodes an actual HTTP response body.
Future<Map<String, dynamic>> responseJson(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;
