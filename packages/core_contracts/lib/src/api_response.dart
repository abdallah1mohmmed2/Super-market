import 'page_meta.dart';

/// A successful typed API envelope.
class ApiResponse<T> {
  final T data;
  final PageMeta meta;

  /// Creates a typed response with its correlation metadata.
  const ApiResponse({required this.data, required this.meta});

  /// Decodes data using the caller's concrete type decoder.
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object?) decode,
  ) => ApiResponse(
    data: decode(json['data']),
    meta: PageMeta.fromJson(json['meta'] as Map<String, dynamic>),
  );

  /// Serializes data with the caller's concrete type encoder.
  Map<String, dynamic> toJson(Object? Function(T) encode) => {
    'data': encode(data),
    'meta': meta.toJson(),
  };
}
