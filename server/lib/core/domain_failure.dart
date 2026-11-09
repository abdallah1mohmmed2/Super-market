/// A business rejection that the HTTP boundary translates into an API error.
class DomainFailure implements Exception {
  final String code;
  final String message;

  /// Creates a safe public business failure.
  const DomainFailure(this.code, this.message);
}
