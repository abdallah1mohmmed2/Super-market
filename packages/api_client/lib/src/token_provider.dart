/// Supplies a refreshed Firebase ID token through an infrastructure adapter.
abstract interface class TokenProvider {
  /// Returns null when no online credential exists.
  Future<String?> getToken();
}
