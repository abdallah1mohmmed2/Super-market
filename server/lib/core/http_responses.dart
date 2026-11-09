import 'dart:convert';
import 'package:core_contracts/core_contracts.dart';
import 'package:shelf/shelf.dart';

/// Reads the request correlation assigned by the outer boundary.
String requestIdOf(Request request) => request.context['requestId']! as String;

/// Creates the version-one success envelope and correlates its headers.
Response success(
  Request request,
  Object? data, {
  int status = 200,
  int limit = 30,
  String? nextCursor,
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: jsonEncode({
    'data': data,
    'meta': PageMeta(
      requestId: requestIdOf(request),
      limit: limit,
      nextCursor: nextCursor,
    ).toJson(),
  }),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-request-id': requestIdOf(request),
    ...headers,
  },
);

/// Creates a safe failure envelope with no internal implementation details.
Response failure(Request request, int status, String code, String message) =>
    Response(
      status,
      body: jsonEncode({
        'error': ApiError(
          code: code,
          message: message,
          requestId: requestIdOf(request),
        ).toJson(),
      }),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        'x-request-id': requestIdOf(request),
      },
    );
