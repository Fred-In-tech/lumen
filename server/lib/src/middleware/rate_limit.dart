import 'dart:io';

import 'package:lumen_core/lumen_core.dart';
import 'package:shelf/shelf.dart';

import '../support.dart';

class _Bucket {
  const _Bucket(this.tokens, this.at);
  final double tokens;
  final DateTime at;
}

/// In-memory token bucket per client key: [burst] capacity, refilled at
/// [ratePerMinute]. Swap for Redis/Firestore counters when scaled out.
class TokenBucketLimiter {
  TokenBucketLimiter({
    required this.ratePerMinute,
    required this.burst,
    required this._clock,
    this.maxKeys = 10000,
  });

  final int ratePerMinute;
  final int burst;
  final int maxKeys;
  final Clock _clock;
  final Map<String, _Bucket> _buckets = {};

  double get _perMs => ratePerMinute / 60000;

  /// Takes one token for [key]. Returns null when allowed, otherwise how
  /// long until a token is available.
  Duration? tryAcquire(String key) {
    final now = _clock.now();
    final previous = _buckets[key];
    final elapsedMs = previous == null
        ? 0
        : now.difference(previous.at).inMilliseconds;
    final available = previous == null
        ? burst.toDouble()
        : (previous.tokens + elapsedMs * _perMs).clamp(0, burst).toDouble();
    if (available < 1) {
      _buckets[key] = _Bucket(available, now);
      final waitMs = ((1 - available) / _perMs).ceil();
      return Duration(milliseconds: waitMs);
    }
    if (previous == null && _buckets.length >= maxKeys) _evictFull(now);
    _buckets[key] = _Bucket(available - 1, now);
    return null;
  }

  void _evictFull(DateTime now) {
    _buckets.removeWhere(
      (_, b) =>
          b.tokens + now.difference(b.at).inMilliseconds * _perMs >= burst,
    );
  }
}

/// Client key: first `x-forwarded-for` hop when [trustProxy], else the
/// socket's remote address.
String clientKeyOf(Request request, {bool trustProxy = false}) {
  if (trustProxy) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.trim().isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
  }
  final info = request.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return 'unknown';
}

Middleware rateLimit(
  TokenBucketLimiter limiter, {
  bool trustProxy = false,
  Set<String> exemptPaths = const {},
}) =>
    (inner) => (request) {
      if (exemptPaths.contains(pathOf(request))) return inner(request);
      final wait = limiter.tryAcquire(
        clientKeyOf(request, trustProxy: trustProxy),
      );
      if (wait != null) {
        throw GatewayException(
          GatewayErrorCode.rateLimited,
          'Too many requests; retry later',
          retryAfter: wait,
        );
      }
      return inner(request);
    };
