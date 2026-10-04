import 'dart:convert';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/gateway_client.dart';

/// [AutoEditProvider] backed by the gateway (Claude vision).
///
/// Every value is clamped and damped again here: never trust the network.
class VisionAutoEditProvider implements AutoEditProvider {
  VisionAutoEditProvider(this._client, {required this.clientInfo});

  final GatewayClient _client;
  final ClientInfo clientInfo;

  @override
  AutoEditEngine get engine => AutoEditEngine.vision;

  @override
  Future<ProviderStatus> status() async {
    try {
      final h = await _client.health();
      return h.visionAvailable
          ? const ProviderStatus.available()
          : const ProviderStatus.unavailable('No AI key on the gateway');
    } on GatewayFailure catch (e) {
      return ProviderStatus.unavailable(e.message);
    }
  }

  AutoEditRequest _request(AutoEditInput input) {
    final jpeg = input.previewJpeg;
    final proxy = input.proxy;
    if (jpeg == null) {
      throw const GatewayFailure('invalid_request', 'Missing preview image');
    }
    return AutoEditRequest(
      client: clientInfo,
      style: GatewayStyle.values.firstWhere(
        (s) => s.wire == input.style.id,
        orElse: () => GatewayStyle.natural,
      ),
      image: ImagePayload(
        mime: 'image/jpeg',
        width: proxy?.width ?? 0,
        height: proxy?.height ?? 0,
        base64: base64Encode(jpeg),
      ),
      stats: input.stats.toJson(),
      exif: input.exif,
      baseline: input.baseline?.nonDefaultValues ?? const {},
      current: input.current.nonDefaultValues,
      locked: input.locked.toList(),
    );
  }

  @override
  Future<AutoEditOutcome> autoEdit(AutoEditInput input) async {
    final res = await _client.autoEdit(_request(input));
    final result = res.result
        .clampedAbsolute()
        .withoutParams(input.locked)
        .damped();
    return _outcome(input, result, res, deltas: false);
  }

  @override
  Future<AutoEditOutcome> instruct(InstructInput input) async {
    final res = await _client.instruct(
      InstructRequest(request: _request(input), instruction: input.instruction),
    );
    final result = res.result
        .clampedDeltas(input.current.nonDefaultValues)
        .damped(deltas: true);
    return _outcome(input, result, res, deltas: true);
  }

  AutoEditOutcome _outcome(
    AutoEditInput input,
    AutoEditResponse result,
    GatewayEditResponse res, {
    required bool deltas,
  }) {
    final start = input.current;
    if (result.variants.isEmpty) {
      return AutoEditOutcome(
        settings: start,
        changes: const [],
        engineUsed: AutoEditEngine.vision,
        intent: result.intent,
      );
    }
    final v = result.variants.first;
    final ops = <EditOp>[
      for (final a in v.presetAtoms)
        if (StyleAtom.fromId(a.atom) case final atom?) ...atom.ops(a.amount),
      for (final adj in v.adjustments)
        deltas
            ? DeltaOp(adj.param, adj.value, explicit: true)
            : SetOp(adj.param, adj.value, explicit: true),
    ];
    final applied = applyOps(
      start,
      ops,
      locked: input.locked,
      baseline: input.baseline,
    );
    final reasons = {for (final a in v.adjustments) a.param: a.reason};
    final changes = <ParamChange>[
      for (final id in start.changedParams(applied.settings))
        ParamChange(
          param: id,
          from: start.value(id),
          to: applied.settings.value(id),
          reason: reasons[id] ?? 'Part of the ${v.label} look',
        ),
    ];
    return AutoEditOutcome(
      settings: applied.settings,
      changes: changes,
      engineUsed: AutoEditEngine.vision,
      intent: result.intent.isEmpty ? null : result.intent,
      scene: SceneInfo(
        subject: result.scene.subject,
        lighting: result.scene.lighting,
        timeOfDay: result.scene.timeOfDay,
        keyIntent: result.scene.keyIntent,
      ),
      confidence: v.confidence,
    );
  }
}

/// Seam for vision-suggested portrait retouch: `retouch.*` slider deltas the
/// vision engine proposes for [outcome], added on top of the need-scaled
/// Auto Retouch (capped). The gateway contract has no such field yet; when
/// it gains one, parse it from the response into the outcome and return it
/// here.
Map<String, double> visionPortraitDeltas(AutoEditOutcome outcome) => const {};
