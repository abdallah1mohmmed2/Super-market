import 'package:core_contracts/core_contracts.dart';
import 'package:shelf/shelf.dart';
import '../core/domain_failure.dart';
import '../features/auth_users/domain/auth_verifier.dart';
import '../features/auth_users/application/create_session_use_case.dart';

/// Verifies identity before resolving current branch and role permissions.
Middleware firebaseAuthMiddleware(
  AuthVerifier verifier,
  CreateSessionUseCase session,
) =>
    (inner) => (request) async {
      if (request.url.path == 'health' || request.url.path == 'v1/app-config')
        return inner(request);
      final match = RegExp(
        r'^Bearer ([^\s]+)$',
        caseSensitive: false,
      ).firstMatch(request.headers['authorization'] ?? '');
      if (match == null)
        throw const DomainFailure('UNAUTHENTICATED', 'تسجيل الدخول مطلوب');
      final uid = await verifier.verify(match.group(1)!);
      final actor = await session(uid);
      return inner(request.change(context: {'actor': actor}));
    };

/// Returns the immutable authorization context established by middleware.
UserSessionDto actorOf(Request request) =>
    request.context['actor']! as UserSessionDto;
