/// Boundary for optional device notifications; database commits never depend on it.
abstract interface class PushNotifier {
  /// Sends one data notification to an explicitly registered device token.
  Future<void> send(String token, Map<String, String> data);
}
