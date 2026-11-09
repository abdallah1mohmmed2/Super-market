import 'package:core_contracts/core_contracts.dart';
import '../domain/user_repository.dart';

/// Explicit development provisioning; never creates a user during login.
class InMemoryUserRepository implements UserRepository {
  final List<UserSessionDto> users;

  /// Creates an empty or explicitly configured development store.
  const InMemoryUserRepository([this.users = const []]);

  /// Finds the configured verified identity.
  @override
  Future<UserSessionDto?> findByFirebaseUid(String uid) async {
    for (final user in users) {
      if (user.firebaseUid == uid) return user;
    }
    return null;
  }
}
