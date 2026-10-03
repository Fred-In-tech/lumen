/// Response DTOs of the gateway contract v1 (PLAN §1.9).
library;

import 'auto_edit_response.dart';
import 'gateway_contract.dart';

int _int(Object? v) => v is num ? v.toInt() : 0;
String? _str(Object? v) => v is String ? v : null;

/// `GET /v1/health`.
class HealthResponse {
  const HealthResponse({
    this.status = 'ok',
    this.version = '',
    this.visionAvailable = false,
    this.model,
    this.promptVersion = '',
  });

  factory HealthResponse.fromJson(Object? json) {
    final m = json is Map ? json : const <String, Object?>{};
    return HealthResponse(
      status: _str(m['status']) ?? 'unknown',
      version: _str(m['version']) ?? '',
      visionAvailable: m['visionAvailable'] == true,
      model: _str(m['model']),
      promptVersion: _str(m['promptVersion']) ?? '',
    );
  }

  final String status;
  final String version;

  /// True when the gateway has an Anthropic API key.
  final bool visionAvailable;

  /// Configured model when [visionAvailable], else null.
  final String? model;
  final String promptVersion;

  Map<String, Object?> toJson() => {
    'status': status,
    'version': version,
    'contractVersion': kContractVersion,
    'visionAvailable': visionAvailable,
    'model': model,
    'promptVersion': promptVersion,
  };
}

class GatewayUsage {
  const GatewayUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.fallbackUsed = false,
  });

  factory GatewayUsage.fromJson(Object? json) {
    final m = json is Map ? json : const <String, Object?>{};
    return GatewayUsage(
      inputTokens: _int(m['inputTokens']),
      outputTokens: _int(m['outputTokens']),
      cacheReadTokens: _int(m['cacheReadTokens']),
      cacheWriteTokens: _int(m['cacheWriteTokens']),
      fallbackUsed: m['fallbackUsed'] == true,
    );
  }

  static const zero = GatewayUsage();

  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;

  /// True when Anthropic's server-side fallback served the request.
  final bool fallbackUsed;

  Map<String, Object?> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadTokens': cacheReadTokens,
    'cacheWriteTokens': cacheWriteTokens,
    'fallbackUsed': fallbackUsed,
  };
}

/// Whether adjustment values are absolute (auto-edit) or deltas from
/// `current` (instruct).
enum ValueMode {
  absolute,
  delta;

  static ValueMode fromWire(Object? v) => v == 'delta' ? delta : absolute;
}

/// `200` body of `/v1/auto-edit` and `/v1/instruct`.
class GatewayEditResponse {
  const GatewayEditResponse({
    required this.requestId,
    this.engine = 'vision',
    required this.model,
    required this.servedBy,
    required this.promptVersion,
    this.cached = false,
    this.latencyMs = 0,
    this.valueMode = ValueMode.absolute,
    required this.result,
    this.usage = GatewayUsage.zero,
  });

  factory GatewayEditResponse.fromJson(Object? json) {
    final m = json is Map ? json : const <String, Object?>{};
    return GatewayEditResponse(
      requestId: _str(m['requestId']) ?? '',
      engine: _str(m['engine']) ?? 'vision',
      model: _str(m['model']) ?? '',
      servedBy: _str(m['servedBy']) ?? '',
      promptVersion: _str(m['promptVersion']) ?? '',
      cached: m['cached'] == true,
      latencyMs: _int(m['latencyMs']),
      valueMode: ValueMode.fromWire(m['valueMode']),
      result: AutoEditResponse.fromJson(m['result']),
      usage: GatewayUsage.fromJson(m['usage']),
    );
  }

  final String requestId;
  final String engine;

  /// Model the gateway asked for.
  final String model;

  /// Model that actually served (differs when a fallback was used).
  final String servedBy;
  final String promptVersion;
  final bool cached;
  final int latencyMs;
  final ValueMode valueMode;

  /// Already clamped by the gateway; clamp again in the app.
  final AutoEditResponse result;
  final GatewayUsage usage;

  GatewayEditResponse copyWith({
    String? requestId,
    bool? cached,
    int? latencyMs,
    GatewayUsage? usage,
  }) => GatewayEditResponse(
    requestId: requestId ?? this.requestId,
    engine: engine,
    model: model,
    servedBy: servedBy,
    promptVersion: promptVersion,
    cached: cached ?? this.cached,
    latencyMs: latencyMs ?? this.latencyMs,
    valueMode: valueMode,
    result: result,
    usage: usage ?? this.usage,
  );

  Map<String, Object?> toJson() => {
    'requestId': requestId,
    'engine': engine,
    'model': model,
    'servedBy': servedBy,
    'promptVersion': promptVersion,
    'cached': cached,
    'latencyMs': latencyMs,
    'valueMode': valueMode.name,
    'result': result.toJson(),
    'usage': usage.toJson(),
  };
}
