import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/gateway_client.dart';

final _log = Logger('AutoEditService');

/// What the editor needs to run an AI edit on one photo.
class AiPhotoContext {
  const AiPhotoContext({
    required this.proxy,
    required this.current,
    this.exif,
    this.locked = const {},
    this.visionJpeg,
    this.cachedStats,
  });

  /// 512 px unedited analysis proxy.
  final RgbaBuffer proxy;
  final DevelopSettings current;
  final ExifSummary? exif;
  final Set<ParamId> locked;

  /// Lazily produces the 1024 px metadata-free JPEG for the vision engine.
  final Future<Uint8List> Function()? visionJpeg;
  final ImageStats? cachedStats;
}

/// Final AI result plus the record that powers Explain and AI Amount.
class AiRunResult {
  const AiRunResult({required this.outcome, required this.record, required this.label});

  final AutoEditOutcome outcome;
  final AiRecord record;

  /// History label, e.g. "AI Auto · Moody".
  final String label;
}

/// Orchestrates local → vision (PLAN.md §1.8). Never throws for AI failures:
/// it degrades to the local engine with a reason.
class AutoEditService {
  AutoEditService({required this.local, this.vision, this.promptVersion});

  final AutoEditProvider local;

  /// Null when the gateway reports no key / is unreachable.
  final AutoEditProvider? vision;
  final String? promptVersion;

  bool get visionAvailable => vision != null;

  static Future<ImageStats> computeStats(RgbaBuffer proxy) => Isolate.run(() => ImageStats.compute(proxy));

  Future<AiRunResult> autoEdit(
    AiPhotoContext ctx, {
    AiStyle style = AiStyle.natural,
    void Function(AutoEditOutcome local)? onLocal,
  }) async {
    final stats = ctx.cachedStats ?? await computeStats(ctx.proxy);
    final input = AutoEditInput(
      stats: stats,
      exif: ctx.exif,
      style: style,
      current: ctx.current,
      locked: ctx.locked,
      proxy: ctx.proxy,
    );
    final localOutcome = await local.autoEdit(input);
    onLocal?.call(localOutcome);
    var outcome = localOutcome;
    String? degraded = vision == null ? 'offline' : null;
    final v = vision;
    if (v != null) {
      try {
        final jpeg = await ctx.visionJpeg?.call();
        outcome = await v
            .autoEdit(AutoEditInput(
              stats: stats,
              exif: ctx.exif,
              style: style,
              current: ctx.current,
              locked: ctx.locked,
              proxy: ctx.proxy,
              previewJpeg: jpeg,
              baseline: localOutcome.settings,
            ))
            .timeout(const Duration(seconds: 40));
      } on GatewayFailure catch (e) {
        _log.info('Vision auto-edit failed, using local: $e');
        degraded = e.code;
      } on TimeoutException {
        degraded = 'timeout';
      }
    }
    final record = AiRecord(
      engine: outcome.engineUsed.name,
      style: style.id,
      promptVersion: outcome.engineUsed == AutoEditEngine.vision ? promptVersion : null,
      intent: outcome.intent,
      preAi: ctx.current,
      postAi: outcome.settings,
      changes: [for (final c in outcome.changes) AiChange(param: c.param, from: c.from, to: c.to, reason: c.reason)],
      degradedReason: degraded,
    );
    final basic = outcome.engineUsed == AutoEditEngine.local;
    return AiRunResult(
      outcome: outcome,
      record: record,
      label: 'AI Auto · ${style.label}${basic ? ' (basic)' : ''}',
    );
  }

  Future<AiRunResult> instruct(AiPhotoContext ctx, String instruction, {DevelopSettings? baseline}) async {
    final stats = ctx.cachedStats ?? await computeStats(ctx.proxy);
    InstructInput build({Uint8List? jpeg}) => InstructInput(
          instruction: instruction,
          stats: stats,
          exif: ctx.exif,
          current: ctx.current,
          locked: ctx.locked,
          proxy: ctx.proxy,
          previewJpeg: jpeg,
          baseline: baseline ?? ctx.current,
        );
    AutoEditOutcome? outcome;
    String? degraded = vision == null ? 'offline' : null;
    final v = vision;
    if (v != null) {
      try {
        final jpeg = await ctx.visionJpeg?.call();
        outcome = await v.instruct(build(jpeg: jpeg)).timeout(const Duration(seconds: 40));
      } on GatewayFailure catch (e) {
        degraded = e.code;
      } on TimeoutException {
        degraded = 'timeout';
      }
    }
    outcome ??= await local.instruct(build());
    final record = AiRecord(
      engine: outcome.engineUsed.name,
      style: 'instruction',
      instruction: instruction,
      intent: outcome.intent,
      preAi: ctx.current,
      postAi: outcome.settings,
      changes: [for (final c in outcome.changes) AiChange(param: c.param, from: c.from, to: c.to, reason: c.reason)],
      degradedReason: degraded,
    );
    return AiRunResult(outcome: outcome, record: record, label: '“$instruction”');
  }
}
