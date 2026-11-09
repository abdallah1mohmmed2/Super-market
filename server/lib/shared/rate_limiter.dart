import 'dart:io';
import 'package:shelf/shelf.dart';
import '../core/http_responses.dart';

/// A bounded process-local fixed-window limiter; peer headers are not trusted.
class RateLimiter {
  final int maxRequests;
  final Duration window;
  final DateTime Function() now;
  final Map<String, ({DateTime start, int count})> _buckets = {};

  /// Configures per-peer limits and an injectable test clock.
  RateLimiter({
    this.maxRequests = 120,
    this.window = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : now = clock ?? DateTime.now;

  /// Limits requests using the socket peer rather than spoofable forwarding data.
  Middleware get middleware =>
      (inner) => (request) async {
        final time = now();
        _buckets.removeWhere((_, v) => time.difference(v.start) >= window);
        final info = request.context['shelf.io.connection_info'];
        final peer = info is HttpConnectionInfo
            ? info.remoteAddress.address
            : 'embedded';
        final old = _buckets[peer];
        if (old == null && _buckets.length >= 10000 ||
            old != null && old.count >= maxRequests) {
          return failure(
            request,
            429,
            'RATE_LIMITED',
            'طلبات كثيرة؛ حاول بعد قليل',
          ).change(headers: {'retry-after': '${window.inSeconds}'});
        }
        _buckets[peer] = (
          start: old?.start ?? time,
          count: (old?.count ?? 0) + 1,
        );
        return inner(request);
      };
}
