import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../../core/domain_failure.dart';
import '../../../core/http_responses.dart';
import '../../../shared/firebase_auth_middleware.dart';
import '../../../shared/request_body.dart';

/// Exposes the currently verified session without mutating role assignments.
Router authRoutes() {
  final r = Router();
  r.post('/v1/auth/session', (Request request) async {
    operationKey(request);
    final body = await readObject(request);
    if (body.isNotEmpty)
      throw const DomainFailure(
        'VALIDATION',
        'لا يقبل طلب الجلسة حقولاً إضافية',
      );
    return success(request, actorOf(request).toJson());
  });
  return r;
}
