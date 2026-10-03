import 'dart:math' as math;

import '../color/srgb.dart';
import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import 'ai_style.dart';
import 'atoms.dart';
import 'auto_edit_provider.dart';
import 'auto_tone_constants.dart';
import 'guards.dart';
import 'lexicon.dart';
import 'local_auto_tone.dart';
import 'reasons.dart';

typedef _C = AutoToneConstants;

/// The offline engine: staged auto-tone + style atoms + guards, and the
/// lexicon for instructions. Always available; never touches the network.
class LocalAutoEditProvider implements AutoEditProvider {
  const LocalAutoEditProvider({
    this.renderer,
    this.autoLimits = GuardLimits.local,
    this.instructLimits = GuardLimits.proposal,
  });

  /// Proxy renderer; defaults to the CPU reference pipeline.
  final ProxyRenderer? renderer;
  final GuardLimits autoLimits;
  final GuardLimits instructLimits;

  @override
  AutoEditEngine get engine => AutoEditEngine.local;

  @override
  Future<ProviderStatus> status() async => const ProviderStatus.available();

  @override
  Future<AutoEditOutcome> autoEdit(AutoEditInput input) async {
    final style = input.style;
    final proxy = input.proxy;
    if (proxy == null) return _fromStatsOnly(input);
    final tone = LocalAutoTone.run(
      proxy: proxy,
      base: input.current,
      targets: style.targets,
      exif: input.exif,
      scene: input.scene,
      locked: input.locked,
      renderer: renderer,
    );
    final styled = applyOps(tone.settings, style.ops(), locked: input.locked);
    final guard = Guards.enforce(
      proxy: proxy,
      settings: styled.settings,
      limits: autoLimits,
      locked: input.locked,
      renderer: renderer,
    );
    return AutoEditOutcome(
      settings: guard.settings,
      changes: _explain(
        input.current,
        tone.settings,
        guard.settings,
        style,
        styled.touched,
        guard.reasons,
      ),
      intent: _intent(style),
      engineUsed: AutoEditEngine.local,
      confidence: tone.confidence,
    );
  }

  @override
  Future<AutoEditOutcome> instruct(InstructInput input) async {
    final parsed = Lexicon.parse(input.instruction);
    if (!parsed.isRecognized) {
      return AutoEditOutcome(
        settings: input.current,
        changes: const [],
        engineUsed: AutoEditEngine.local,
        confidence: 0,
        suggestions: parsed.suggestions,
      );
    }
    final applied = parsed.apply(
      input.current,
      baseline: input.baseline ?? input.current,
      locked: input.locked,
    );
    var settings = applied.settings;
    var guardReasons = const <ParamId, String>{};
    final proxy = input.proxy;
    if (proxy != null) {
      final guard = Guards.enforce(
        proxy: proxy,
        settings: settings,
        limits: instructLimits,
        locked: {...input.locked, ..._namedParams(parsed.ops)},
        renderer: renderer,
      );
      settings = guard.settings;
      guardReasons = guard.reasons;
    }
    final recognized = parsed.clauses.where((c) => c.recognized).length;
    return AutoEditOutcome(
      settings: settings,
      changes: Reasons.diff(input.current, settings, (p, from, to) {
        final r = Reasons.instruction(input.instruction, p, from, to);
        final note = guardReasons[p];
        return note == null ? r : '$r, $note';
      }),
      intent: 'Applied “${input.instruction.trim()}”',
      engineUsed: AutoEditEngine.local,
      confidence: recognized / parsed.clauses.length,
      suggestions: parsed.unrecognizedClauses.isEmpty
          ? const []
          : parsed.suggestions,
    );
  }

  /// Fallback without pixels: closed-form WB, exposure and levels from the
  /// stats (research §6.3–6.5), then the style look.
  AutoEditOutcome _fromStatsOnly(AutoEditInput input) {
    final st = input.stats;
    final style = input.style;
    final values = <ParamId, double>{};
    final strength = style.targets.wbStrength ?? _C.wbStrength;
    final c = st.wb.confidence;
    if (c >= _C.wbConfidenceLo) {
      values[P.temp] = (-100 * st.wb.a * strength).clamp(-40, 40).toDouble();
      values[P.tint] = (200 * st.wb.m * strength).clamp(-25, 25).toDouble();
    }
    final median = math.max(srgbToLinear(st.lumaP.p50), 1e-4);
    final key = LocalAutoTone.sceneKey(st) * style.targets.keyScale;
    final (lo, hi) = LocalAutoTone.exposureBand(style.targets);
    if (median < lo || median > hi) {
      values[P.exposure] = (math.log(key / median) / math.ln2)
          .clamp(_C.evMin, _C.evMax)
          .toDouble();
    }
    final tLo = _C.blackTarget + style.targets.blackTargetShift;
    if (st.lumaP.p0_5 > tLo) {
      values[P.blacks] = (-400 * (st.lumaP.p0_5 - tLo) / (1 - tLo))
          .clamp(_C.blacksMin, 0)
          .toDouble();
    }
    final base = input.current.withValues({
      for (final e in values.entries)
        if (!input.locked.contains(e.key)) e.key: e.value,
    });
    final styled = applyOps(base, style.ops(), locked: input.locked);
    return AutoEditOutcome(
      settings: styled.settings,
      changes: _explain(
        input.current,
        base,
        styled.settings,
        style,
        styled.touched,
        const {},
      ),
      intent: _intent(style),
      engineUsed: AutoEditEngine.local,
      degraded: true,
      degradedReason: 'No preview pixels: estimated from image statistics',
      confidence: 0.3,
    );
  }

  static Set<ParamId> _namedParams(List<EditOp> ops) => {
    for (final op in ops)
      if (op case DeltaOp(named: true, :final param))
        param
      else if (op case SetOp(named: true, :final param))
        param
      else if (op case LessOp(named: true, :final param))
        param,
  };

  static String _intent(AiStyle style) => style == AiStyle.natural
      ? 'Natural: balanced exposure, neutral color'
      : '${style.label}: balanced base edit with the ${style.label} look';

  /// One reason per change, always describing the final change from `from`
  /// to `to`: guard note > tone stage (+ style note) > style look.
  static List<ParamChange> _explain(
    DevelopSettings from,
    DevelopSettings tone,
    DevelopSettings to,
    AiStyle style,
    Set<ParamId> styleTouched,
    Map<ParamId, String> guardReasons,
  ) {
    final toneChanged = from.changedParams(tone);
    return Reasons.diff(
      from,
      to,
      (p, a, b) {
        final guard = guardReasons[p];
        if (guard != null) return Reasons.guarded(p, a, b, guard);
        if (toneChanged.contains(p)) {
          final r = Reasons.auto(p, a, b);
          return styleTouched.contains(p) ? '$r (${style.label} look)' : r;
        }
        return Reasons.style(style.label, p, a, b);
      },
      treatmentReason: '${style.label} look: converted to black and white',
      curveReason: '${style.label} look: shaped the tone curve',
    );
  }
}
