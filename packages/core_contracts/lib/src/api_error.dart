/// A stable API failure that never exposes internal SQL or credentials.
class ApiError implements Exception {
  final String code;
  final String message;
  final String requestId;
  final int status;

  /// Constructs a public error envelope payload.
  const ApiError({
    required this.code,
    required this.message,
    required this.requestId,
    this.status = 400,
  });

  /// Decodes the inner error object.
  factory ApiError.fromJson(Map<String, dynamic> json, {int status = 400}) =>
      ApiError(
        code: json['code'] as String,
        message: json['message'] as String,
        requestId: json['requestId'] as String,
        status: status,
      );

  /// Encodes the inner error object.
  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    'requestId': requestId,
  };

  @override
  String toString() => message;
}
