import 'package:core_contracts/core_contracts.dart';
import '../../../core/domain_failure.dart';
import '../domain/user_repository.dart';

/// Creates no accounts implicitly; permissions come from the authoritative store.
class CreateSessionUseCase {
  final UserRepository users;

  /// Injects the user persistence port.
  const CreateSessionUseCase(this.users);

  /// Resolves an active, branch-scoped session for a verified UID.
  Future<UserSessionDto> call(String uid) async =>
      await users.findByFirebaseUid(uid) ??
      (throw const DomainFailure(
        'USER_NOT_PROVISIONED',
        'لم يُمنح هذا الحساب صلاحية الدخول',
      ));
}
