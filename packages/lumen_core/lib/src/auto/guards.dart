import 'dart:math' as math;

import '../analysis/proxy.dart';
import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import '../render/rgba_buffer.dart';
import 'local_auto_tone.dart';
import 'tone_measure.dart';

/// Limits a proposed edit must respect (PLAN.md §1.8 step 4).
class GuardLimits {
  const GuardLimits({
    this.maxClip = 0.01,
    this.maxCrush = 0.02,
    this.minMedianLStar = 15,
    this.maxMedianLStar = 85,
  });

  /// For vision / instruction proposals: clip ≤ 1 %, crush ≤ 2 %.
  static const proposal = GuardLimits();

  /// For the local engine's own result (research clip guard 0.5 %).
  static const local = GuardLimits(maxClip: 0.005);

  final double maxClip;
  final double maxCrush;
  final double minMedianLStar;
  final double maxMedianLStar;
}

/// Measured guard quantities of one render.
class GuardReport {
  const GuardReport({
    required this.clipFraction,
    required this.crushFraction,
    required this.medianLStar,
  });

  /// Measures [rendered]; [whites] is the whites value it was rendered with
  /// (negative whites lower the output white, and so the clip level).
  factory GuardReport.of(RgbaBuffer rendered, {double whites = 0}) {
    final ceiling = 1 + 0.25 * math.min(whites, 0) / 100;
    final m = ToneMeasure.of(rendered, clipLevel: 0.995 * ceiling);
    return GuardReport(
      clipFraction: m.clipFraction,
      crushFraction: m.crushFraction,
      medianLStar: m.medianLStar,
    );
  }

  final double clipFraction;
  final double crushFraction;
  final double medianLStar;

  List<String> violations(GuardLimits l) => [
    if (clipFraction > l.maxClip) 'clip',
    if (crushFraction > l.maxCrush) 'crush',
    if (medianLStar < l.minMedianLStar) 'too dark',
    if (medianLStar > l.maxMedianLStar) 'too bright',
  ];
}

/// Result of [Guards.enforce].
class GuardResult {
  const GuardResult({
    required this.settings,
    required this.before,
    required this.after,
    required this.reasons,
  });

  final DevelopSettings settings;
  final GuardReport before;
  final GuardReport after;

  /// Short note per guard-adjusted param ("held back to stop highlight
  /// clipping"); combine with the final change via `Reasons.guarded`.
  final Map<ParamId, String> reasons;

  bool get changed => reasons.isNotEmpty;
}

/// Clip / crush / key checks on the CPU reference render at 256 px, with a
/// fixer that only touches whites, exposure and blacks.
abstract final class Guards {
  static const _iterations = 7;

  static GuardResult enforce({
    required RgbaBuffer proxy,
    required DevelopSettings settings,
    GuardLimits limits = GuardLimits.proposal,
    Set<ParamId> locked = const {},
    ProxyRenderer? renderer,
  }) {
    final src = makeProxy(proxy, longEdge: kSolverLongEdge);
    final render = renderer ?? referenceRendererFor(src, auxSource: proxy);
    GuardReport measure(DevelopSettings s) =>
        GuardReport.of(render(src, s), whites: s.value(P.whites));
    final before = measure(settings);
    var s = settings;
    final reasons = <ParamId, String>{};
    bool free(ParamId p) => !locked.contains(p);

    // Clipping: undo a whites stretch first, then lower exposure.
    if (before.clipFraction > limits.maxClip) {
      if (free(P.whites) && s.value(P.whites) > 0) {
        s = _bisect(
          s,
          P.whites,
          0,
          measure,
          (r) => r.clipFraction <= limits.maxClip,
        );
        reasons[P.whites] = 'held back to stop highlight clipping';
      }
      if (measure(s).clipFraction > limits.maxClip && free(P.exposure)) {
        s = _bisect(
          s,
          P.exposure,
          s.value(P.exposure) - 3,
          measure,
          (r) => r.clipFraction <= limits.maxClip,
        );
        reasons[P.exposure] = 'held back to stop highlight clipping';
      }
    }
    // Crushed shadows: lift blacks.
    if (measure(s).crushFraction > limits.maxCrush && free(P.blacks)) {
      s = _bisect(
        s,
        P.blacks,
        math.max(30, s.value(P.blacks)),
        measure,
        (r) => r.crushFraction <= limits.maxCrush,
      );
      reasons[P.blacks] = 'set to keep shadow detail';
    }
    // Key band: bring an extreme median back with exposure.
    final key = measure(s);
    if (free(P.exposure) &&
        (key.medianLStar < limits.minMedianLStar ||
            key.medianLStar > limits.maxMedianLStar)) {
      final dark = key.medianLStar < limits.minMedianLStar;
      s = _bisect(
        s,
        P.exposure,
        s.value(P.exposure) + (dark ? 3 : -3),
        measure,
        (r) =>
            r.medianLStar >= limits.minMedianLStar &&
            r.medianLStar <= limits.maxMedianLStar &&
            r.clipFraction <= math.max(limits.maxClip, before.clipFraction),
      );
      reasons[P.exposure] = dark
          ? 'set to keep the image from going too dark'
          : 'set to keep the image from going too bright';
    }
    return GuardResult(
      settings: s,
      before: before,
      after: reasons.isEmpty ? before : measure(s),
      reasons: Map.unmodifiable(reasons),
    );
  }

  /// Moves [param] from its current value toward [limit] by bisection until
  /// [ok] holds, taking the value closest to the original that passes.
  static DevelopSettings _bisect(
    DevelopSettings s,
    ParamId param,
    double limit,
    GuardReport Function(DevelopSettings) measure,
    bool Function(GuardReport) ok,
  ) {
    final spec = ParamRegistry.byId(param);
    var good = spec.clamp(limit);
    var bad = s.value(param);
    if (!ok(measure(s.withValue(param, good)))) return s.withValue(param, good);
    for (var i = 0; i < _iterations; i++) {
      final mid = (good + bad) / 2;
      if (ok(measure(s.withValue(param, mid)))) {
        good = mid;
      } else {
        bad = mid;
      }
    }
    return s.withValue(param, good);
  }
}
