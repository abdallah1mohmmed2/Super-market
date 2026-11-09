import 'package:core_contracts/core_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../../../core/http_responses.dart';

/// Provides public process health and deployment configuration.
Router healthRoutes(AppConfigDto config) {
  final r = Router();
  r.get(
    '/health',
    (Request request) => success(request, {'status': 'ok', 'version': '0.1.0'}),
  );
  r.get(
    '/v1/app-config',
    (Request request) => success(request, config.toJson()),
  );
  return r;
}
