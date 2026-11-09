import 'dart:async';
import 'dart:convert';

import 'package:core_contracts/core_contracts.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'catalog_page.dart';
import 'token_provider.dart';

/// Adds tokens, request correlation and bounded retries preserving mutation keys.
class ErpApiClient {
  final Uri baseUrl;
  final TokenProvider tokens;
  final http.Client _http;
  final Duration retryDelay;

  /// Creates a client pointing to a build-time configured deployment URL.
  ErpApiClient({
    required this.baseUrl,
    required this.tokens,
    http.Client? client,
    this.retryDelay = const Duration(milliseconds: 250),
  }) : _http = client ?? http.Client() {
    if (!['http', 'https'].contains(baseUrl.scheme) || baseUrl.host.isEmpty) {
      throw ArgumentError('A valid API_BASE_URL is required');
    }
  }
  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? key,
    String? etag,
    bool authenticated = true,
  }) async {
    final requestId = const Uuid().v4();
    final token = authenticated ? await tokens.getToken() : null;
    if (authenticated && (token == null || token.isEmpty)) {
      throw ApiError(
        code: 'AUTH_REQUIRED',
        message: 'يلزم تسجيل الدخول للاتصال بالخادم',
        requestId: requestId,
        status: 401,
      );
    }
    final headers = <String, String>{
      'X-Request-Id': requestId,
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (key != null) 'Idempotency-Key': key,
      if (etag != null) 'If-None-Match': etag,
    };
    final encoded = body == null ? null : jsonEncode(body);
    final uri = baseUrl.resolve(path).replace(queryParameters: query);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final request = http.Request(method, uri)..headers.addAll(headers);
        if (encoded != null) request.body = encoded;
        final r = await _http
            .send(request)
            .then(http.Response.fromStream)
            .timeout(const Duration(seconds: 15));
        if ((r.statusCode == 429 || r.statusCode >= 500) && attempt < 2) {
          await Future<void>.delayed(retryDelay * (1 << attempt));
          continue;
        }
        if (r.statusCode >= 400) {
          final Object? decoded;
          try {
            decoded = jsonDecode(utf8.decode(r.bodyBytes));
          } on FormatException {
            throw ApiError(
              code: 'INVALID_RESPONSE',
              message: 'تعذر قراءة رد الخادم',
              requestId: requestId,
              status: r.statusCode,
            );
          }
          if (decoded is! Map<String, dynamic> ||
              decoded['error'] is! Map<String, dynamic>) {
            throw ApiError(
              code: 'INVALID_RESPONSE',
              message: 'تعذر قراءة رد الخادم',
              requestId: requestId,
              status: r.statusCode,
            );
          }
          throw ApiError.fromJson(
            decoded['error'] as Map<String, dynamic>,
            status: r.statusCode,
          );
        }
        return r;
      } on http.ClientException {
        if (attempt == 2) rethrow;
        await Future<void>.delayed(retryDelay * (1 << attempt));
      } on TimeoutException {
        if (attempt == 2) rethrow;
        await Future<void>.delayed(retryDelay * (1 << attempt));
      }
    }
    throw StateError('Retry budget exhausted');
  }

  Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

  /// Exchanges the Firebase token for provisioned branch permissions.
  Future<UserSessionDto> createSession({
    required String idempotencyKey,
  }) async => ApiResponse<UserSessionDto>.fromJson(
    _json(
      await _request(
        'POST',
        '/v1/auth/session',
        body: const {},
        key: idempotencyKey,
      ),
    ),
    (v) => UserSessionDto.fromJson(v as Map<String, dynamic>),
  ).data;

  /// Fetches public deployment configuration.
  Future<AppConfigDto> getAppConfig() async =>
      ApiResponse<AppConfigDto>.fromJson(
        _json(await _request('GET', '/v1/app-config', authenticated: false)),
        (v) => AppConfigDto.fromJson(v as Map<String, dynamic>),
      ).data;

  /// Saves a definition using a durable caller-assigned operation UUID.
  Future<ProductDto> upsertProduct(
    ProductDto product, {
    required String idempotencyKey,
  }) async => ApiResponse<ProductDto>.fromJson(
    _json(
      await _request(
        'POST',
        '/v1/catalog/products',
        body: product.toJson(),
        key: idempotencyKey,
      ),
    ),
    (v) => ProductDto.fromJson(v as Map<String, dynamic>),
  ).data;

  /// Retrieves at most thirty products and supports conditional ETags.
  Future<CatalogPage> listProducts({
    String? cursor,
    String search = '',
    int limit = 30,
    String? etag,
  }) async {
    final r = await _request(
      'GET',
      '/v1/catalog/products',
      query: {
        'limit': '${limit.clamp(1, 30)}',
        if (cursor != null) 'cursor': cursor,
        if (search.isNotEmpty) 'q': search,
      },
      etag: etag,
    );
    return CatalogPage(
      etag: r.headers['etag'],
      notModified: r.statusCode == 304,
      response: r.statusCode == 304
          ? null
          : ApiResponse<List<ProductDto>>.fromJson(
              _json(r),
              (v) => (v as List)
                  .map((e) => ProductDto.fromJson(e as Map<String, dynamic>))
                  .toList(),
            ),
    );
  }

  /// Resolves a unit barcode or a four-digit scale PLU.
  Future<ProductDto?> lookup(String code) async {
    final data = _json(
      await _request('GET', '/v1/catalog/lookup', query: {'code': code}),
    )['data'];
    return data == null
        ? null
        : ProductDto.fromJson(data as Map<String, dynamic>);
  }

  /// Releases the HTTP client's connections.
  void close() => _http.close();
}
