import 'dart:async';
import 'package:shelf/shelf.dart';
import '../core/domain_failure.dart';
import '../core/http_responses.dart';

/// Converts all business, transport and decoding errors into the same envelope.
Middleware errorMiddleware({void Function(String)? log}) =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on DomainFailure catch (e) {
        final status = switch (e.code) {
          'UNAUTHENTICATED' => 401,
          'FORBIDDEN' || 'USER_NOT_PROVISIONED' => 403,
          'DUPLICATE' || 'REVISION_CONFLICT' || 'IDEMPOTENCY_CONFLICT' => 409,
          'AUTH_UNAVAILABLE' => 503,
          'PAYLOAD_TOO_LARGE' => 413,
          _ => 400,
        };
        return failure(request, status, e.code, e.message);
      } on FormatException {
        return failure(request, 400, 'VALIDATION', 'صيغة الطلب غير صالحة');
      } on TypeError {
        return failure(request, 400, 'VALIDATION', 'حقول الطلب غير صالحة');
      } on TimeoutException {
        return failure(
          request,
          503,
          'SERVICE_UNAVAILABLE',
          'الخدمة غير متاحة مؤقتاً',
        );
      } catch (e) {
        log?.call('requestId=${requestIdOf(request)} failure=${e.runtimeType}');
        return failure(request, 500, 'INTERNAL_ERROR', 'تعذر إكمال العملية');
      }
    };
