/// Small shared pieces: clock, gateway exception, JSON responses, request id.
library;

import 'dart:convert';

import 'package:lumen_core/lumen_core.dart';
import 'package:shelf/shelf.dart';

/// Injectable time source (tests use a fake).
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Any failure that maps to a contract error code. Thrown anywhere inside
/// the pipeline and rendered by the error-envelope middleware.
class GatewayException implements Exception {
  const GatewayException(
    this.code,
    this.message, {
    this.details = const {},
    this.retryAfter,
  });

  final GatewayErrorCode code;
  final String message;
  final Map<String, Object?> details;
  final Duration? retryAfter;

  GatewayErrorEnvelope toEnvelope(String? requestId) => GatewayErrorEnvelope(
    requestId: requestId,
    error: GatewayError(
      code: code,
      message: message,
      retryAfterMs: retryAfter?.inMilliseconds,
      details: details,
    ),
  );

  @override
  String toString() => 'GatewayException(${code.wire}): $message';
}

const String kRequestIdHeader = 'x-request-id';
const String kRequestIdContextKey = 'lumen.requestId';
const Map<String, String> kJsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

String? requestIdOf(Request request) =>
    request.context[kRequestIdContextKey] as String?;

Response jsonResponse(
  int status,
  Object? body, {
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: jsonEncode(body),
  headers: {...kJsonHeaders, ...headers},
);

Response errorResponse(GatewayException e, String? requestId) {
  final retry = e.retryAfter;
  return jsonResponse(
    e.code.httpStatus,
    e.toEnvelope(requestId).toJson(),
    headers: {
      if (retry != null)
        'retry-after': '${(retry.inMilliseconds / 1000).ceil()}',
    },
  );
}

/// Path of [request] with a leading slash (`/v1/health`).
String pathOf(Request request) => '/${request.url.path}';
