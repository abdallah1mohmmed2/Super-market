/// Pagination and correlation metadata returned on every JSON success.
class PageMeta {
  final int page;
  final int limit;
  final String? nextCursor;
  final String requestId;

  /// Creates correlation metadata with a maximum page size of thirty.
  const PageMeta({
    this.page = 1,
    this.limit = 30,
    this.nextCursor,
    required this.requestId,
  });

  /// Decodes metadata from the wire.
  factory PageMeta.fromJson(Map<String, dynamic> json) => PageMeta(
    page: json['page'] as int,
    limit: json['limit'] as int,
    nextCursor: json['nextCursor'] as String?,
    requestId: json['requestId'] as String,
  );

  /// Serializes all metadata fields, including a terminal null cursor.
  Map<String, dynamic> toJson() => {
    'page': page,
    'limit': limit,
    'nextCursor': nextCursor,
    'requestId': requestId,
  };
}
