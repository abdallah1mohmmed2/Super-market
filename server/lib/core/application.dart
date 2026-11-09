import 'package:core_contracts/core_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../features/auth_users/domain/auth_verifier.dart';
import '../features/auth_users/domain/user_repository.dart';
import '../features/auth_users/application/create_session_use_case.dart';
import '../features/auth_users/presentation/auth_routes.dart';
import '../features/catalog/domain/catalog_repository.dart';
import '../features/catalog/application/upsert_product_use_case.dart';
import '../features/catalog/application/list_products_cursor_use_case.dart';
import '../features/catalog/application/lookup_barcode_or_scale_use_case.dart';
import '../features/catalog/presentation/catalog_routes.dart';
import '../features/health_config/presentation/health_routes.dart';
import '../shared/request_context_middleware.dart';
import '../shared/cors_middleware.dart';
import '../shared/error_middleware.dart';
import '../shared/request_logger.dart';
import '../shared/rate_limiter.dart';
import '../shared/firebase_auth_middleware.dart';
import 'http_responses.dart';

/// Composes ports and use cases; tests inject real or in-memory adapters here.
Handler createApplication({
  required AuthVerifier verifier,
  required UserRepository users,
  required CatalogRepository catalog,
  AppConfigDto config = const AppConfigDto(),
  Set<String> corsOrigins = const {},
  void Function(String)? logger,
  RateLimiter? rateLimiter,
}) {
  final routes =
      Router(
          notFoundHandler: (r) =>
              failure(r, 404, 'NOT_FOUND', 'المسار غير موجود'),
        )
        ..get('/health', healthRoutes(config).call)
        ..get('/v1/app-config', healthRoutes(config).call)
        ..post('/v1/auth/session', authRoutes().call);
  final catalogRoutes = CatalogRoutes(
    UpsertProductUseCase(catalog),
    ListProductsCursorUseCase(catalog),
    LookupBarcodeOrScaleUseCase(catalog),
  ).router;
  routes
    ..get('/v1/catalog/products', catalogRoutes.call)
    ..post('/v1/catalog/products', catalogRoutes.call)
    ..get('/v1/catalog/lookup', catalogRoutes.call);
  return Pipeline()
      .addMiddleware(requestContextMiddleware())
      .addMiddleware(requestLogger(logger ?? (_) {}))
      .addMiddleware(corsMiddleware(corsOrigins))
      .addMiddleware(errorMiddleware(log: logger))
      .addMiddleware((rateLimiter ?? RateLimiter()).middleware)
      .addMiddleware(
        firebaseAuthMiddleware(verifier, CreateSessionUseCase(users)),
      )
      .addHandler(routes.call);
}
