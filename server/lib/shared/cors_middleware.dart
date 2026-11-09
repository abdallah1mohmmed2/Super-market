import 'package:shelf/shelf.dart';
import '../core/http_responses.dart';

/// Allows only explicit browser origins and exposes conditional-fetch metadata.
Middleware corsMiddleware(Set<String> origins) =>
    (inner) => (request) async {
      final origin = request.headers['origin'];
      if (origin != null && !origins.contains(origin))
        return failure(request, 403, 'ORIGIN_DENIED', 'مصدر الطلب غير مصرح');
      final headers = <String, String>{
        'vary': 'Origin',
        if (origin != null) 'access-control-allow-origin': origin,
        'access-control-expose-headers': 'ETag, X-Request-Id',
        'access-control-allow-methods': 'GET, POST, OPTIONS',
        'access-control-allow-headers':
            'Authorization, Content-Type, X-Request-Id, Idempotency-Key, If-None-Match',
        'access-control-max-age': '600',
      };
      if (request.method == 'OPTIONS') return Response(204, headers: headers);
      return (await inner(request)).change(headers: headers);
    };
