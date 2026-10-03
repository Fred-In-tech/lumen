/// Error codes and the error envelope of the gateway contract (PLAN §1.9).
library;

enum GatewayErrorCode {
  invalidRequest('invalid_request', 400, false),
  unsupportedContract('unsupported_contract', 400, false),
  unauthorized('unauthorized', 401, false),
  notFound('not_found', 404, false),
  payloadTooLarge('payload_too_large', 413, false),
  upstreamRefusal('upstream_refusal', 422, false),
  rateLimited('rate_limited', 429, true),
  internalError('internal_error', 500, true),
  upstreamError('upstream_error', 502, true),
  upstreamIncomplete('upstream_incomplete', 502, true),
  upstreamInvalidOutput('upstream_invalid_output', 502, true),
  visionUnavailable('vision_unavailable', 503, false),
  upstreamTimeout('upstream_timeout', 504, true);

  const GatewayErrorCode(this.wire, this.httpStatus, this.retryable);

  /// The snake_case value sent on the wire.
  final String wire;
  final int httpStatus;

  /// Default for [GatewayError.retryable].
  final bool retryable;

  /// Unknown codes map to [internalError] so old apps survive new codes.
  static GatewayErrorCode fromWire(Object? wire) {
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return internalError;
  }
}

class GatewayError {
  const GatewayError({
    required this.code,
    required this.message,
    this._retryable,
    this.retryAfterMs,
    this.details = const {},
  });

  factory GatewayError.fromJson(Object? json) {
    if (json is! Map) {
      return const GatewayError(
        code: GatewayErrorCode.internalError,
        message: 'Malformed error envelope',
      );
    }
    final details = json['details'];
    return GatewayError(
      code: GatewayErrorCode.fromWire(json['code']),
      message: json['message'] is String ? json['message']! as String : '',
      retryable: json['retryable'] is bool ? json['retryable']! as bool : null,
      retryAfterMs: (json['retryAfterMs'] as num?)?.toInt(),
      details: details is Map
          ? Map.unmodifiable(details.cast<String, Object?>())
          : const {},
    );
  }

  final GatewayErrorCode code;
  final String message;
  final bool? _retryable;
  final int? retryAfterMs;
  final Map<String, Object?> details;

  bool get retryable => _retryable ?? code.retryable;

  Map<String, Object?> toJson() => {
    'code': code.wire,
    'message': message,
    'retryable': retryable,
    if (retryAfterMs != null) 'retryAfterMs': retryAfterMs,
    'details': details,
  };
}

/// `{"error": {...}, "requestId": "..."}`.
class GatewayErrorEnvelope {
  const GatewayErrorEnvelope({required this.error, this.requestId});

  factory GatewayErrorEnvelope.fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    return GatewayErrorEnvelope(
      error: GatewayError.fromJson(map['error']),
      requestId: map['requestId'] as String?,
    );
  }

  final GatewayError error;
  final String? requestId;

  Map<String, Object?> toJson() => {
    'error': error.toJson(),
    if (requestId != null) 'requestId': requestId,
  };
}

/// Thrown by request DTO parsing when the body violates the contract.
class ContractViolation implements Exception {
  const ContractViolation(
    this.message, {
    this.code = GatewayErrorCode.invalidRequest,
    this.details = const {},
  });

  final GatewayErrorCode code;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => 'ContractViolation(${code.wire}): $message';
}
