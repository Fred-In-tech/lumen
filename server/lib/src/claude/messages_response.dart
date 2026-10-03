/// Parses a `/v1/messages` response: `stop_reason` first, then the first
/// `text` block (skipping `thinking`, fallback and other blocks), usage and
/// the model that actually served.
library;

import 'dart:convert';

import 'package:lumen_core/lumen_core.dart';

import '../support.dart';

const Set<String> _incompleteStops = {
  'max_tokens',
  'model_context_window_exceeded',
  'pause_turn',
};

int _int(Object? v) => v is num ? v.toInt() : 0;

class MessagesReply {
  const MessagesReply({
    required this.text,
    required this.servedBy,
    required this.usage,
    this.stopReason,
  });

  /// Throws [GatewayException] for refusals, truncation and malformed bodies.
  factory MessagesReply.parse(Object? json) {
    if (json is! Map) {
      throw const GatewayException(
        GatewayErrorCode.upstreamInvalidOutput,
        'Upstream response is not a JSON object',
      );
    }
    final stop = json['stop_reason'];
    if (stop == 'refusal') {
      final stopDetails = json['stop_details'];
      throw GatewayException(
        GatewayErrorCode.upstreamRefusal,
        'The model declined to edit this image',
        details: {
          'category': stopDetails is Map ? stopDetails['category'] : null,
        },
      );
    }
    if (_incompleteStops.contains(stop)) {
      throw GatewayException(
        GatewayErrorCode.upstreamIncomplete,
        'The model stopped before finishing ($stop)',
        details: {'stopReason': stop},
      );
    }
    final content = json['content'];
    final textBlock = content is List
        ? content.whereType<Map<Object?, Object?>>().firstWhere(
            (b) => b['type'] == 'text' && b['text'] is String,
            orElse: () => const {},
          )
        : const <Object?, Object?>{};
    final text = textBlock['text'];
    if (text is! String) {
      throw const GatewayException(
        GatewayErrorCode.upstreamInvalidOutput,
        'Upstream response has no text block',
      );
    }
    return MessagesReply(
      text: text,
      servedBy: json['model'] is String ? json['model']! as String : '',
      usage: _usage(json['usage']),
      stopReason: stop is String ? stop : null,
    );
  }

  final String text;

  /// Top-level `model`: the model that served (may be a fallback model).
  final String servedBy;
  final GatewayUsage usage;
  final String? stopReason;

  /// The structured-output JSON. Throws `upstream_invalid_output` when the
  /// text is not a JSON object with a `variants` list.
  Map<String, Object?> decodeJson() {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map<String, Object?> || decoded['variants'] is! List) {
      throw const GatewayException(
        GatewayErrorCode.upstreamInvalidOutput,
        'The model returned output that does not match the schema',
      );
    }
    return decoded;
  }
}

GatewayUsage _usage(Object? usage) {
  if (usage is! Map) return GatewayUsage.zero;
  final iterations = usage['iterations'];
  final fallbackUsed =
      iterations is List &&
      iterations.whereType<Map<Object?, Object?>>().any(
        (i) => i['type'] == 'fallback_message',
      );
  return GatewayUsage(
    inputTokens: _int(usage['input_tokens']),
    outputTokens: _int(usage['output_tokens']),
    cacheReadTokens: _int(usage['cache_read_input_tokens']),
    cacheWriteTokens: _int(usage['cache_creation_input_tokens']),
    fallbackUsed: fallbackUsed,
  );
}
