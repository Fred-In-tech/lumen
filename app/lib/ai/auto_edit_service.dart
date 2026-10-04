import 'dart:async';

import 'package:lumen/platform/background.dart';

import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/gateway_client.dart';
import 'package:lumen/ai/vision_provider.dart';

final _log = Logger('AutoEditService');

/// What auto retouch gives a photo: the portrait settings to apply (null:
/// leave portrait alone) and a note for the user.
typedef RetouchPlan = ({PortraitSettings? portrait, String? note});

/// What the editor needs to run an AI edit on one photo.
class AiPhotoContext {
  const AiPhotoContext({
    required this.proxy,
    required this.current,
    this.exif,
    this.locked = const {},
    this.visionJpeg,
    this.cachedStats,
    this.retouch,
  });

  /// 512 px unedited analysis proxy.
  final RgbaBuffer proxy;
  final DevelopSettings current;
  final ExifSummary? exif;
  final Set<ParamId> locked;

  /// Lazily produces the 1024 px metadata-free JPEG for the vision engine.
  final Future<Uint8List> Function()? visionJpeg;
  final ImageStats? cachedStats;

  /// Plans need-scaled Auto Retouch for the photo (null: colour only). It
  /// starts with the colour edit and both land as one AI step.
  final Future<RetouchPlan> Function()? retouch;

  AiPhotoContext copyWith({Future<RetouchPlan> Function()? retouch}) =>
      AiPhotoContext(
        proxy: proxy,
        current: current,
        exif: exif,
        locked: locked,
        visionJpeg: visionJpeg,
        cachedStats: cachedStats,
        retouch: retouch ?? this.retouch,
      );
}

/// Final AI result plus the record that powers Explain and AI Amount.
class AiRunResult {
  const AiRunResult({
    required this.outcome,
    required this.record,
    required this.label,
    this.note,
  });

  final AutoEditOutcome outcome;
  final AiRecord record;

  /// History label, e.g. "AI Auto · Moody".
  final String label;

  /// Something the user should know (e.g. faces could not be retouched).
  final String? note;
}

/// Orchestrates local → vision (PLAN.md §1.8). Never throws for AI failures:
/// it degrades to the local engine with a reason.
class AutoEditService {
  AutoEditService({
    required this.local,
    this.vision,
    this.promptVersion,
    this.isolateLocal = true,
  });

  final AutoEditProvider local;

  /// Null when the gateway reports no key / is unreachable.
  final AutoEditProvider? vision;
  final String? promptVersion;

  /// Runs the CPU-heavy local engine in a background isolate (keeps the UI at 60 fps).
  final bool isolateLocal;

  bool get visionAvailable => vision != null;

  static Future<ImageStats> computeStats(RgbaBuffer proxy) =>
      runInBackground(() => ImageStats.compute(proxy));

  Future<AiRunResult> autoEdit(
    AiPhotoContext ctx, {
    AiStyle style = AiStyle.natural,
    void Function(AutoEditOutcome local)? onLocal,
  }) async {
    // Faces are measured while the colour edit runs (never throws).
    final retouchPlan = _awaitPlan(ctx.retouch?.call());
    final stats = ctx.cachedStats ?? await computeStats(ctx.proxy);
    final input = AutoEditInput(
      stats: stats,
      exif: ctx.exif,
      style: style,
      current: ctx.current,
      locked: ctx.locked,
      proxy: ctx.proxy,
    );
    final engine = local;
    final localOutcome = isolateLocal
        ? await _autoEditInIsolate(engine, input)
        : await engine.autoEdit(input);
    onLocal?.call(localOutcome);
    var outcome = localOutcome;
    String? degraded = vision == null ? 'offline' : null;
    final v = vision;
    if (v != null) {
      try {
        final jpeg = await ctx.visionJpeg?.call();
        outcome = await v
            .autoEdit(
              AutoEditInput(
                stats: stats,
                exif: ctx.exif,
                style: style,
                current: ctx.current,
                locked: ctx.locked,
                proxy: ctx.proxy,
                previewJpeg: jpeg,
                baseline: localOutcome.settings,
              ),
            )
            .timeout(const Duration(seconds: 40));
      } on GatewayFailure catch (e) {
        _log.info('Vision auto-edit failed, using local: $e');
        degraded = e.code;
      } on TimeoutException {
        degraded = 'timeout';
      }
    }
    final retouch = await retouchPlan;
    final portrait = retouch?.portrait;
    if (portrait != null) {
      outcome = _withPortrait(
        outcome,
        PortraitPresets.withDeltas(portrait, visionPortraitDeltas(outcome)),
      );
    }
    final record = AiRecord(
      engine: outcome.engineUsed.name,
      style: style.id,
      promptVersion: outcome.engineUsed == AutoEditEngine.vision
          ? promptVersion
          : null,
      intent: outcome.intent,
      preAi: ctx.current,
      postAi: outcome.settings,
      changes: [
        for (final c in outcome.changes)
          AiChange(param: c.param, from: c.from, to: c.to, reason: c.reason),
      ],
      degradedReason: degraded,
    );
    final basic = outcome.engineUsed == AutoEditEngine.local;
    return AiRunResult(
      outcome: outcome,
      record: record,
      label:
          'AI Auto · ${style.label}${basic ? ' (basic)' : ''}'
          '${portrait != null ? ' + Retouch' : ''}',
      note: retouch?.note,
    );
  }

  static Future<RetouchPlan?> _awaitPlan(Future<RetouchPlan>? plan) async {
    if (plan == null) return null;
    try {
      return await plan;
    } on Exception catch (e) {
      _log.warning('auto retouch failed, colour only: $e');
      return null;
    }
  }

  static AutoEditOutcome _withPortrait(
    AutoEditOutcome o,
    PortraitSettings portrait,
  ) => AutoEditOutcome(
    settings: o.settings.copyWith(portrait: portrait),
    changes: o.changes,
    engineUsed: o.engineUsed,
    intent: o.intent,
    scene: o.scene,
    degraded: o.degraded,
    degradedReason: o.degradedReason,
    confidence: o.confidence,
    suggestions: o.suggestions,
  );

  Future<AiRunResult> instruct(
    AiPhotoContext ctx,
    String instruction, {
    DevelopSettings? baseline,
  }) async {
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
        outcome = await v
            .instruct(build(jpeg: jpeg))
            .timeout(const Duration(seconds: 40));
      } on GatewayFailure catch (e) {
        degraded = e.code;
      } on TimeoutException {
        degraded = 'timeout';
      }
    }
    final AutoEditOutcome result;
    if (outcome != null) {
      result = outcome;
    } else {
      final engine = local;
      final input = build();
      result = isolateLocal
          ? await _instructInIsolate(engine, input)
          : await engine.instruct(input);
    }
    final record = AiRecord(
      engine: result.engineUsed.name,
      style: 'instruction',
      instruction: instruction,
      intent: result.intent,
      preAi: ctx.current,
      postAi: result.settings,
      changes: [
        for (final c in result.changes)
          AiChange(param: c.param, from: c.from, to: c.to, reason: c.reason),
      ],
      degradedReason: degraded,
    );
    return AiRunResult(
      outcome: result,
      record: record,
      label: '“$instruction”',
    );
  }
}

// Top-level so the isolate closure captures only the engine and its input
// (a closure inside a method would drag the whole scope, including UI objects).
Future<AutoEditOutcome> _autoEditInIsolate(
  AutoEditProvider engine,
  AutoEditInput input,
) => runInBackground(() => engine.autoEdit(input));

Future<AutoEditOutcome> _instructInIsolate(
  AutoEditProvider engine,
  InstructInput input,
) => runInBackground(() => engine.instruct(input));
