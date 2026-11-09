import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../core/http_responses.dart';

/// Logs duration and correlation without bodies, bearer tokens or query values.
Middleware requestLogger(void Function(String) log) =>
    (inner) => (request) async {
      final watch = Stopwatch()..start();
      final response = await inner(request);
      log(
        jsonEncode({
          'requestId': requestIdOf(request),
          'method': request.method,
          'path': request.url.path,
          'status': response.statusCode,
          'durationMs': watch.elapsedMicroseconds / 1000,
        }),
      );
      return response;
    };
