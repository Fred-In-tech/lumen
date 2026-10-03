/// Shared pipeline behind `/v1/auto-edit` and `/v1/instruct`: validate the
/// image, consult the cache, call Claude through the upstream gate, parse,
/// clamp, drop locked params, meter, cache.
library;

import 'dart:convert';

import 'package:lumen_core/lumen_core.dart';

import '../cache/result_cache.dart';
import '../claude/claude_client.dart';
import '../claude/messages_request.dart';
import '../config.dart';
import '../metering/usage_meter.dart';
import '../prompt/system_prompt.dart';
import '../prompt/user_message.dart';
import '../support.dart';
import 'upstream_gate.dart';

class EditService {
  EditService({
    required this.config,
    required this._claude,
    required this._cache,
    required this._meter,
    required this._gate,
    required this._clock,
  });

  final GatewayConfig config;
  final ClaudeClient _claude;
  final ResultCache _cache;
  final UsageMeter _meter;
  final UpstreamGate _gate;
  final Clock _clock;

  static final Map<String, Object?> _schema = Map.unmodifiable(
    AutoEditResponseSchema.build(),
  );

  void ensureAvailable() {
    if (!config.visionAvailable) {
      throw const GatewayException(
        GatewayErrorCode.visionUnavailable,
        'Vision editing is not configured on this gateway',
      );
    }
  }

  Future<GatewayEditResponse> autoEdit(
    AutoEditRequest request, {
    required String requestId,
  }) => _run(request, null, requestId, GatewayPaths.autoEdit);

  Future<GatewayEditResponse> instruct(
    InstructRequest request, {
    required String requestId,
  }) => _run(
    request.request,
    request.instruction,
    requestId,
    GatewayPaths.instruct,
  );

  Future<GatewayEditResponse> _run(
    AutoEditRequest request,
    String? instruction,
    String transportId,
    String route,
  ) async {
    ensureAvailable();
    _validateImage(request.image);
    final started = _clock.now();
    final requestId = request.requestId ?? transportId;
    final key = resultCacheKey(
      request: request,
      instruction: instruction,
      model: config.model,
      effort: config.effort,
      promptVersion: kPromptVersion,
    );

    final hit = _cache.get(key);
    if (hit != null) {
      final cached = hit.copyWith(
        requestId: requestId,
        cached: true,
        latencyMs: _elapsedMs(started),
        usage: GatewayUsage.zero,
      );
      _record(cached, route);
      return cached;
    }

    final reply = await _gate.run(
      () => _claude.send(
        MessagesRequest(
          model: config.model,
          effort: config.effort,
          maxTokens: config.maxTokens,
          systemPrompt: kSystemPrompt,
          schema: _schema,
          imageMime: request.image.mime,
          imageBase64: request.image.base64,
          userText: buildUserText(request, instruction: instruction),
        ),
      ),
    );
    final result = _sanitize(reply.decodeJson(), request, instruction);
    final response = GatewayEditResponse(
      requestId: requestId,
      model: config.model,
      servedBy: reply.servedBy.isEmpty ? config.model : reply.servedBy,
      promptVersion: kPromptVersion,
      latencyMs: _elapsedMs(started),
      valueMode: instruction == null ? ValueMode.absolute : ValueMode.delta,
      result: result,
      usage: reply.usage,
    );
    _cache.put(key, response);
    _record(response, route);
    return response;
  }

  AutoEditResponse _sanitize(
    Map<String, Object?> json,
    AutoEditRequest request,
    String? instruction,
  ) {
    final parsed = AutoEditResponse.fromJson(json);
    if (parsed.variants.isEmpty && !parsed.done) {
      throw const GatewayException(
        GatewayErrorCode.upstreamInvalidOutput,
        'The model returned no edit variants',
      );
    }
    final clamped = instruction == null
        ? parsed.clampedAbsolute()
        : parsed.clampedDeltas(request.current);
    return clamped.withoutParams(request.locked.toSet());
  }

  void _validateImage(ImagePayload image) {
    if (image.longEdge > kMaxImageLongEdge) {
      throw GatewayException(
        GatewayErrorCode.payloadTooLarge,
        'Image long edge ${image.longEdge}px exceeds ${kMaxImageLongEdge}px',
        details: {'maxLongEdge': kMaxImageLongEdge},
      );
    }
    try {
      base64Decode(image.base64);
    } on FormatException {
      throw const GatewayException(
        GatewayErrorCode.invalidRequest,
        'image.base64 is not valid base64',
      );
    }
  }

  int _elapsedMs(DateTime started) =>
      _clock.now().difference(started).inMilliseconds;

  void _record(GatewayEditResponse r, String route) => _meter.record(
    UsageEvent(
      requestId: r.requestId,
      route: route,
      model: r.model,
      servedBy: r.servedBy,
      usage: r.usage,
      cached: r.cached,
      latencyMs: r.latencyMs,
    ),
  );
}
