import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import '../model/tone_curve.dart';
import '../model/treatment.dart';

/// One parametric edit operation. Atoms, styles and the instruction lexicon
/// all compile to lists of these, so they compose with one set of rules.
sealed class EditOp {
  const EditOp();
}

/// Adds [delta] to [param]. [named]: the user named this slider, so it may
/// override a lock. [explicit]: the user gave the number, so caps don't apply.
final class DeltaOp extends EditOp {
  const DeltaOp(this.param, this.delta, {this.explicit = false, bool? named})
    : named = named ?? explicit;

  final ParamId param;
  final double delta;
  final bool explicit;
  final bool named;
}

/// Sets [param] to [value] (grading hues, "shadows to 40").
final class SetOp extends EditOp {
  const SetOp(this.param, this.value, {this.explicit = false, bool? named})
    : named = named ?? explicit;

  final ParamId param;
  final double value;
  final bool explicit;
  final bool named;
}

/// "Less X": removes [fraction] of what was added to [param] since the
/// baseline in [direction] (+1 or −1). Never crosses the baseline.
final class LessOp extends EditOp {
  const LessOp(this.param, this.fraction, this.direction, {this.named = false});

  final ParamId param;
  final double fraction;
  final int direction;
  final bool named;
}

/// Blends the master point curve toward [points] by [amount] (0..1).
final class CurveOp extends EditOp {
  const CurveOp(this.points, this.amount);

  final List<CurvePoint> points;
  final double amount;
}

final class TreatmentOp extends EditOp {
  const TreatmentOp(this.treatment);

  final Treatment treatment;
}

/// Per-instruction caps on non-explicit changes (research 01 §7.2).
class InstructionCaps {
  const InstructionCaps({this.exposure = 1.0, this.temp = 30, this.other = 40});

  static const standard = InstructionCaps();

  final double exposure;
  final double temp;
  final double other;

  double capFor(ParamId id) => switch (id) {
    P.exposure => exposure,
    P.temp => temp,
    _ => other,
  };
}

/// Result of [applyOps].
class OpsResult {
  const OpsResult(this.settings, this.touched, this.notes);

  final DevelopSettings settings;

  /// Scalar params an op wrote to (after locks).
  final Set<ParamId> touched;

  /// Human notes about ops that had no effect (e.g. "less" at baseline).
  final List<String> notes;
}

/// Applies [ops] in order to [start]. Non-named ops skip [locked] params;
/// non-explicit changes are limited by [caps] relative to [start]; "less"
/// ops are measured against [baseline] (defaults to [start]). Absolute
/// [SetOp]s (e.g. grading hues) are never capped.
OpsResult applyOps(
  DevelopSettings start,
  Iterable<EditOp> ops, {
  DevelopSettings? baseline,
  Set<ParamId> locked = const {},
  InstructionCaps? caps,
}) {
  final base = baseline ?? start;
  final values = <ParamId, double>{};
  final explicit = <ParamId>{};
  final cappable = <ParamId>{};
  final notes = <String>[];
  var curves = start.curves;
  var treatment = start.treatment;
  double now(ParamId id) => values[id] ?? start.value(id);
  bool blocked(ParamId id, bool named) => !named && locked.contains(id);

  for (final op in ops) {
    switch (op) {
      case DeltaOp(:final param, :final delta, :final named):
        if (blocked(param, named)) continue;
        values[param] = now(param) + delta;
        if (op.explicit) explicit.add(param);
        if (!op.explicit) cappable.add(param);
      case SetOp(:final param, :final value, :final named):
        if (blocked(param, named)) continue;
        values[param] = value;
        if (op.explicit) explicit.add(param);
        cappable.remove(param);
      case LessOp(:final param, :final fraction, :final direction):
        if (blocked(param, op.named)) continue;
        final added = now(param) - base.value(param);
        if (added * direction <= 1e-9) {
          notes.add(
            '${ParamRegistry.byId(param).label} is already at its starting '
            'value',
          );
          continue;
        }
        values[param] = now(param) - fraction.clamp(0, 1) * added;
      case CurveOp(:final points, :final amount):
        if (amount <= 0) continue;
        final cur = curves.master;
        final k = amount.clamp(0, 1);
        final blended = [
          for (final p in points)
            CurvePoint(p.x, cur.evaluate(p.x) + k * (p.y - p.x)),
        ];
        curves = curves.withChannel(
          CurveChannel.master,
          ToneCurve.normalized(blended),
        );
      case TreatmentOp(treatment: final t):
        treatment = t;
    }
  }

  if (caps != null) {
    for (final id in cappable) {
      if (explicit.contains(id)) continue;
      final cap = caps.capFor(id);
      final from = start.value(id);
      values[id] = values[id]!.clamp(from - cap, from + cap).toDouble();
    }
  }
  final settings = start
      .withValues(values)
      .copyWith(curves: curves, treatment: treatment);
  return OpsResult(
    settings,
    Set.unmodifiable(values.keys),
    List.unmodifiable(notes),
  );
}

/// Style atoms of research 01 §7.3: Δ vectors at amount 1.0.
enum StyleAtom {
  warm('warm', 'Warm', {P.temp: 15, P.tint: 3, 'hsl.orange.sat': 5}),
  cool('cool', 'Cool', {P.temp: -15, P.tint: -2, 'hsl.blue.sat': 5}),
  brightAiry('bright_airy', 'Bright & airy', {
    P.exposure: 0.4,
    P.contrast: -10,
    P.highlights: -20,
    P.shadows: 25,
    P.whites: 10,
    P.blacks: 10,
    P.vibrance: 5,
    'hsl.orange.lum': 5,
  }),
  moody(
    'moody',
    'Moody',
    {
      P.exposure: -0.3,
      P.highlights: -25,
      P.shadows: -5,
      P.blacks: -10,
      P.vibrance: -15,
      P.saturation: -5,
      P.temp: -5,
      P.vignetteAmount: -15,
      'grade.shadows.sat': 10,
    },
    sets: {'grade.shadows.hue': 215},
  ),
  punchy('punchy', 'Punchy', {
    P.contrast: 20,
    P.whites: 8,
    P.blacks: -8,
    P.clarity: 8,
    P.vibrance: 10,
  }),
  softMatte(
    'soft_matte',
    'Soft matte',
    {P.contrast: -15, P.highlights: -15, P.shadows: 15, P.clarity: -10},
    curve: [CurvePoint(0, 18), CurvePoint(255, 255)],
  ),
  cinematicTealOrange(
    'cinematic_teal_orange',
    'Cinematic teal & orange',
    {
      P.contrast: 10,
      P.blacks: 6,
      'grade.shadows.sat': 15,
      'grade.highlights.sat': 12,
      'hsl.blue.hue': -10,
      'hsl.orange.sat': 5,
      P.vibrance: -5,
      P.vignetteAmount: -10,
    },
    sets: {'grade.shadows.hue': 200, 'grade.highlights.hue': 40},
  ),
  filmFaded(
    'film_faded',
    'Faded film',
    {
      P.contrast: -10,
      P.saturation: -10,
      'grade.highlights.sat': 10,
      P.grainAmount: 20,
      P.vignetteAmount: -8,
    },
    sets: {'grade.highlights.hue': 45},
    curve: [
      CurvePoint(0, 20),
      CurvePoint(64, 60),
      CurvePoint(192, 200),
      CurvePoint(255, 245),
    ],
  ),
  goldenHour(
    'golden_hour',
    'Golden hour',
    {
      P.temp: 20,
      P.tint: 5,
      'grade.highlights.sat': 15,
      'hsl.orange.sat': 10,
      'hsl.yellow.sat': 5,
      P.highlights: -10,
    },
    sets: {'grade.highlights.hue': 40},
  ),
  skyPop('sky_pop', 'Sky pop', {
    'hsl.blue.sat': 15,
    'hsl.blue.lum': -15,
    'hsl.aqua.sat': 8,
    P.highlights: -15,
    P.dehaze: 8,
  }),
  vibrant('vibrant', 'Vibrant', {
    P.vibrance: 25,
    P.saturation: 5,
    P.clarity: 5,
  }),
  muted('muted', 'Muted', {P.vibrance: -25, P.saturation: -10}),
  bwClassic('bw_classic', 'Classic black & white', {
    P.contrast: 15,
    'bw.blue': -20,
    'bw.orange': 10,
  }, treatment: Treatment.bw);

  const StyleAtom(
    this.id,
    this.label,
    this.deltas, {
    this.sets = const {},
    this.curve,
    this.treatment,
  });

  /// Wire id (gateway `presetAtoms[].atom`).
  final String id;
  final String label;

  /// Additive Δ at amount 1.0.
  final Map<ParamId, double> deltas;

  /// Absolute values (grading hues) applied when amount > 0.
  final Map<ParamId, double> sets;
  final List<CurvePoint>? curve;
  final Treatment? treatment;

  static StyleAtom? fromId(String id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Ops for this atom at [amount] (negative amounts only scale the deltas).
  List<EditOp> ops(double amount, {bool named = false}) => [
    for (final e in deltas.entries)
      DeltaOp(e.key, e.value * amount, named: named),
    if (amount > 0)
      for (final e in sets.entries) SetOp(e.key, e.value, named: named),
    if (curve != null && amount > 0) CurveOp(curve!, amount),
    if (treatment != null && amount >= 0.5) TreatmentOp(treatment!),
  ];

  /// "Less `atom`": remove [fraction] of each delta added since the baseline.
  List<EditOp> lessOps(double fraction) => [
    for (final e in deltas.entries)
      LessOp(e.key, fraction, e.value > 0 ? 1 : -1),
    if (treatment == Treatment.bw) const TreatmentOp(Treatment.color),
  ];
}
