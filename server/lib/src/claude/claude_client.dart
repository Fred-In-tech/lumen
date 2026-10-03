/// Raw-HTTP Claude client (there is no official Dart SDK).
///
/// One retry on 429/529/5xx and network errors, honoring `retry-after`;
/// a single deadline ([timeout], default 90 s) covers all attempts.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support.dart';
import 'messages_request.dart';
import 'messages_response.dart';

typedef Sleep = Future<void> Function(Duration duration);

Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

final Logger _log = Logger('lumen.claude');

abstract interface class ClaudeClient {
  /// Sends [request]; throws [GatewayException] on any failure.
  Future<MessagesReply> send(MessagesRequest request);
}

class HttpClaudeClient implements ClaudeClient {
  HttpClaudeClient({
    required this._apiKey,
    required this.messagesUri,
    required http.Client httpClient,
    this.timeout = const Duration(seconds: 90),
    this.defaultRetryDelay = const Duration(seconds: 1),
    this.maxRetryDelay = const Duration(seconds: 20),
    this._sleep = _realSleep,
  }) : _http = httpClient;

  final String _apiKey;
  final Uri messagesUri;
  final http.Client _http;
  final Duration timeout;
  final Duration defaultRetryDelay;
  final Duration maxRetryDelay;
  final Sleep _sleep;

  static const int _maxAttempts = 2;

  @override
  Future<MessagesReply> send(MessagesRequest request) async {
    try {
      return await _sendWithRetry(request).timeout(timeout);
    } on TimeoutException {
      throw GatewayException(
        GatewayErrorCode.upstreamTimeout,
        'Upstream did not answer within ${timeout.inSeconds} s',
      );
    }
  }

  Future<MessagesReply> _sendWithRetry(MessagesRequest request) async {
    final body = jsonEncode(request.toJson());
    final headers = request.headers(_apiKey);
    for (var attempt = 1; ; attempt++) {
      final isLast = attempt >= _maxAttempts;
      http.Response response;
      try {
        response = await _http.post(messagesUri, headers: headers, body: body);
      } on http.ClientException catch (e) {
        _log.warning('upstream network error (attempt $attempt): $e');
        if (isLast) {
          throw const GatewayException(
            GatewayErrorCode.upstreamError,
            'Could not reach the vision service',
          );
        }
        await _sleep(defaultRetryDelay);
        continue;
      }
      final status = response.statusCode;
      if (status == 200) return _parse(response);
      final retryable = status == 429 || status >= 500;
      final delay = _retryAfter(response) ?? defaultRetryDelay;
      if (retryable && !isLast) {
        _log.info('upstream $status, retrying in ${delay.inMilliseconds} ms');
        await _sleep(delay);
        continue;
      }
      throw _statusError(response, delay);
    }
  }

  MessagesReply _parse(http.Response response) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    return MessagesReply.parse(json);
  }

  Duration? _retryAfter(http.Response response) {
    final raw = response.headers['retry-after'];
    final seconds = raw == null ? null : double.tryParse(raw.trim());
    if (seconds == null || seconds < 0) return null;
    final d = Duration(milliseconds: (seconds * 1000).round());
    return d > maxRetryDelay ? maxRetryDelay : d;
  }

  GatewayException _statusError(http.Response response, Duration retry) {
    final status = response.statusCode;
    final type = _errorType(response);
    _log.warning('upstream HTTP $status ($type)');
    if (status == 429) {
      return GatewayException(
        GatewayErrorCode.rateLimited,
        'The vision service is rate limited; retry later',
        retryAfter: retry,
        details: {'upstreamStatus': status},
      );
    }
    return GatewayException(
      GatewayErrorCode.upstreamError,
      'The vision service returned an error',
      details: {'upstreamStatus': status, 'upstreamType': ?type},
    );
  }

  String? _errorType(http.Response response) {
    try {
      final json = jsonDecode(response.body);
      final error = json is Map ? json['error'] : null;
      return error is Map && error['type'] is String
          ? error['type'] as String
          : null;
    } on FormatException {
      return null;
    }
  }
}
