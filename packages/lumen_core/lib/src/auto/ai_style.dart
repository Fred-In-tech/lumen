import '../model/param_registry.dart';
import 'atoms.dart';

/// Target shifts a style applies to the local auto-tone solver
/// (research 01 §6.12 "Styles in local mode").
class AutoToneTargets {
  const AutoToneTargets({
    this.keyScale = 1,
    this.blackTargetShift = 0,
    this.sigmaShift = 0,
    this.chromaShift = 0,
    this.wbStrength,
    this.vibranceCap,
    this.skinProtect = false,
  });

  static const neutral = AutoToneTargets();

  /// Multiplies the scene-adaptive exposure key.
  final double keyScale;

  /// Added to the black target `T_lo` (0.025).
  final double blackTargetShift;

  /// Added to the σ(L*) contrast target (20).
  final double sigmaShift;

  /// Added to the C* chroma target (28).
  final double chromaShift;

  /// Overrides the white-balance strength (default 0.7 / 0.35 intentional).
  final double? wbStrength;

  /// Upper bound for the vibrance the solver may set.
  final double? vibranceCap;

  /// Extra skin protection: caps saturation too.
  final bool skinProtect;
}

/// The nine AI Styles (PLAN.md §1.8): local target shifts + atoms.
enum AiStyle {
  natural('natural', 'Natural', AutoToneTargets(), []),
  vibrant(
    'vibrant',
    'Vibrant',
    AutoToneTargets(chromaShift: 8, sigmaShift: 3),
    [(StyleAtom.vibrant, 0.6)],
  ),
  moody(
    'moody',
    'Moody',
    AutoToneTargets(
      keyScale: 0.7,
      sigmaShift: 3,
      chromaShift: -6,
      wbStrength: 0.4,
    ),
    [(StyleAtom.moody, 0.8)],
  ),
  cinematic('cinematic', 'Cinematic', AutoToneTargets(sigmaShift: 2), [
    (StyleAtom.cinematicTealOrange, 1.0),
  ]),
  film('film', 'Film', AutoToneTargets(sigmaShift: -2), [
    (StyleAtom.filmFaded, 1.0),
  ]),
  goldenHour('golden_hour', 'Golden Hour', AutoToneTargets(wbStrength: 0.2), [
    (StyleAtom.goldenHour, 1.0),
  ]),
  cleanBright(
    'clean_bright',
    'Clean & Bright',
    AutoToneTargets(
      keyScale: 1.3,
      blackTargetShift: 0.03,
      sigmaShift: -3,
      chromaShift: -2,
    ),
    [(StyleAtom.brightAiry, 0.6)],
  ),
  bw('bw', 'B&W', AutoToneTargets(sigmaShift: 3), [(StyleAtom.bwClassic, 1.0)]),
  portraitSoft(
    'portrait_soft',
    'Portrait Soft',
    AutoToneTargets(vibranceCap: 10, skinProtect: true),
    [(StyleAtom.softMatte, 0.4)],
    extras: {P.clarity: -10, P.texture: -15},
  );

  const AiStyle(
    this.id,
    this.label,
    this.targets,
    this.atoms, {
    this.extras = const {},
  });

  /// Wire id (gateway `style`).
  final String id;
  final String label;
  final AutoToneTargets targets;
  final List<(StyleAtom, double)> atoms;

  /// Extra fixed deltas (Portrait Soft: clarity −10, texture −15).
  final Map<ParamId, double> extras;

  static AiStyle? fromId(String id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The look this style layers on top of the solved base edit.
  List<EditOp> ops() => [
    for (final (atom, amount) in atoms) ...atom.ops(amount),
    for (final e in extras.entries) DeltaOp(e.key, e.value),
  ];
}
