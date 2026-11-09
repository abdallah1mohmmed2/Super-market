import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import '../core/http_responses.dart';

/// Assigns correlation before any component can fail; validates client IDs.
Middleware requestContextMiddleware() =>
    (inner) => (request) async {
      final supplied = request.headers['x-request-id'];
      final valid =
          supplied != null &&
          RegExp(r'^[A-Za-z0-9._:-]{1,100}$').hasMatch(supplied);
      final r = request.change(
        context: {'requestId': valid ? supplied : const Uuid().v4()},
      );
      if (supplied != null && !valid)
        return failure(r, 400, 'INVALID_REQUEST_ID', 'معرّف الطلب غير صالح');
      if (supplied == null &&
          request.method != 'OPTIONS' &&
          request.url.path != 'health' &&
          request.url.path != 'v1/app-config') {
        return failure(
          r,
          400,
          'REQUEST_ID_REQUIRED',
          'ترويسة X-Request-Id مطلوبة',
        );
      }
      return (await inner(r)).change(headers: {'x-request-id': requestIdOf(r)});
    };
