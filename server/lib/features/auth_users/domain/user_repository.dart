import 'package:core_contracts/core_contracts.dart';

/// Resolves explicitly provisioned users and their live permissions.
abstract interface class UserRepository {
  /// Reads the enabled user bound to the verified external identity.
  Future<UserSessionDto?> findByFirebaseUid(String uid);
}
