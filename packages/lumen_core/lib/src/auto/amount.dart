import '../model/develop_settings.dart';
import '../model/tone_curve.dart';

/// Range of the AI Amount slider, in percent.
const double kAiAmountMin = 0;
const double kAiAmountMax = 150;

/// AI Amount (PLAN.md §1.8): interpolates every AI-changed value between the
/// pre-AI state [pre] and the AI result [ai]. 0 % returns [pre], 100 %
/// returns [ai], above 100 % extrapolates (clamped to each param's range).
///
/// Treatment follows [ai] from 50 %; curves blend pointwise along [ai]'s
/// control points. Geometry and masks always come from [pre].
DevelopSettings applyAiAmount({
  required DevelopSettings pre,
  required DevelopSettings ai,
  required double percent,
}) {
  final k = percent.clamp(kAiAmountMin, kAiAmountMax) / 100;
  if (k == 0) return pre;
  final values = {
    for (final id in pre.changedParams(ai))
      id: pre.value(id) + k * (ai.value(id) - pre.value(id)),
  };
  final curves = k == 1
      ? ai.curves
      : CurveSet(
          master: _blend(pre.curves.master, ai.curves.master, k),
          red: _blend(pre.curves.red, ai.curves.red, k),
          green: _blend(pre.curves.green, ai.curves.green, k),
          blue: _blend(pre.curves.blue, ai.curves.blue, k),
        );
  return pre
      .withValues(values)
      .copyWith(
        curves: curves,
        treatment: k >= 0.5 ? ai.treatment : pre.treatment,
      );
}

ToneCurve _blend(ToneCurve pre, ToneCurve ai, double k) {
  if (pre == ai) return pre;
  return ToneCurve.normalized([
    for (final p in ai.points)
      CurvePoint(p.x, pre.evaluate(p.x) + k * (p.y - pre.evaluate(p.x))),
  ]);
}
