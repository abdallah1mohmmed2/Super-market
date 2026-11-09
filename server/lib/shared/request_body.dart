import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../core/domain_failure.dart';

/// Reads bounded JSON with a hard streaming limit to avoid unbounded allocation.
Future<Map<String, dynamic>> readObject(
  Request request, {
  int maxBytes = 262144,
}) async {
  if ((request.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase() !=
      'application/json') {
    throw const DomainFailure(
      'VALIDATION',
      'Content-Type يجب أن يكون application/json',
    );
  }
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    if (bytes.length + chunk.length > maxBytes)
      throw const DomainFailure(
        'PAYLOAD_TOO_LARGE',
        'حجم الطلب أكبر من الحد المسموح',
      );
    bytes.addAll(chunk);
  }
  final object = jsonDecode(utf8.decode(bytes));
  if (object is! Map<String, dynamic>) throw const FormatException();
  return object;
}

/// Requires a version-four operation key so client retries retain their identity.
String operationKey(Request request) {
  final key = request.headers['idempotency-key'] ?? '';
  if (!RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-4[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$',
  ).hasMatch(key)) {
    throw const DomainFailure(
      'IDEMPOTENCY_KEY_REQUIRED',
      'مفتاح عملية UUID v4 مطلوب',
    );
  }
  return key.toLowerCase();
}

/// Normalizes JSON object ordering for stable mutation fingerprints.
Object? canonicalJson(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: canonicalJson(value[key])};
  }
  if (value is List) return value.map(canonicalJson).toList();
  return value;
}
