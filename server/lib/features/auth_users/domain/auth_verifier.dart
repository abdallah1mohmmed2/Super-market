/// Verifies an external identity without granting application permissions.
abstract interface class AuthVerifier {
  /// Returns a verified Firebase UID or throws a business authentication failure.
  Future<String> verify(String token);
}
