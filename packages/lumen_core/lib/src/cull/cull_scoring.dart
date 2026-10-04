import 'dart:math' as math;

import 'cull_signals.dart';

/// Eye state from the eye aspect ratio.
enum EyeState { open, halfOpen, closed }

/// Why a photo was marked (tile badges, filters, tooltips).
enum CullReason {
  eyesClosed,
  eyesHalfOpen,
  blurryFace,
  blurry,
  highlightsClipped,
  shadowsCrushed,

  /// In a similar-shot cluster and not its best.
  notBestInCluster;

  static CullReason? fromName(Object? v) =>
      values.where((r) => r.name == v).firstOrNull;

  String get label => switch (this) {
    eyesClosed => 'Eyes closed',
    eyesHalfOpen => 'Eyes half open',
    blurryFace => 'Blurry face',
    blurry => 'Blurry',
    highlightsClipped => 'Blown highlights',
    shadowsCrushed => 'Crushed shadows',
    notBestInCluster => 'Similar to a better shot',
  };

  /// Reasons that make a photo a reject suggestion.
  bool get rejects => switch (this) {
    eyesClosed || blurryFace || blurry => true,
    highlightsClipped || shadowsCrushed => true,
    eyesHalfOpen || notBestInCluster => false,
  };
}

/// Thresholds and weights for Smart Cull. Defaults are first estimates
/// (🔶): calibrate them on a licensed portrait set before shipping.
class CullConfig {
  const CullConfig({
    this.closedEar = 0.16,
    this.halfOpenEar = 0.21,
    this.blurryFace = 0.004,
    this.blurryCenter = 0.003,
    this.blurryRelative = 0.4,
    this.highlightClipMax = 0.08,
    this.faceHighlightClipMax = 0.15,
    this.shadowClipMax = 0.25,
    this.maxFacesForEyeRule = 6,
    this.burstWindow = const Duration(seconds: 10),
    this.similarHash = 12,
    this.duplicateHash = 6,
    this.minPickScore = 0.55,
  });

  /// EAR below which eyes count as closed / half open.
  final double closedEar;
  final double halfOpenEar;

  /// Absolute sharpness floors for the main face / the centre (no face).
  /// Deliberately low (only gross blur): smooth, sharp faces score low on
  /// a contrast-normalized Laplacian, so most blur is caught by
  /// [blurryRelative] within a burst instead.
  final double blurryFace;
  final double blurryCenter;

  /// Also blurry when below this fraction of the sharpest in its cluster.
  final double blurryRelative;
  final double highlightClipMax;
  final double faceHighlightClipMax;
  final double shadowClipMax;

  /// Closed eyes do not reject groups larger than this.
  final int maxFacesForEyeRule;

  /// Shots closer than this (EXIF capture time) can be one burst.
  final Duration burstWindow;

  /// dHash distance for "similar" (with the time window) and "duplicate"
  /// (regardless of time).
  final int similarHash;
  final int duplicateHash;

  /// Singletons scoring below this are not suggested as picks.
  final double minPickScore;

  EyeState eyeState(double ear) => ear < closedEar
      ? EyeState.closed
      : ear < halfOpenEar
      ? EyeState.halfOpen
      : EyeState.open;
}

/// Quality score (0..1, higher is better) and the reasons behind it.
class CullAssessment {
  const CullAssessment(this.score, this.reasons);

  final double score;
  final Set<CullReason> reasons;

  bool get suggestsReject => reasons.any((r) => r.rejects);
}

/// The sharpness that represents a photo: its main face, else the centre.
double primarySharpness(CullSignals s) => s.mainFace?.sharpness ?? s.sharpness;

/// Scores [s] with [config]. [clusterBestSharpness] (the sharpest
/// [primarySharpness] among similar shots) enables the relative blur rule.
CullAssessment assessCull(
  CullSignals s, {
  CullConfig config = const CullConfig(),
  double? clusterBestSharpness,
}) {
  final c = config;
  final reasons = <CullReason>{};
  final main = s.mainFace;
  final sharp = primarySharpness(s);
  final floor = main == null ? c.blurryCenter : c.blurryFace;
  final best = clusterBestSharpness;
  if (sharp < floor || (best != null && sharp < c.blurryRelative * best)) {
    reasons.add(main == null ? CullReason.blurry : CullReason.blurryFace);
  }
  final states = [
    for (final f in s.faces)
      if (f.ear case final ear?) c.eyeState(ear),
  ];
  if (states.contains(EyeState.closed) &&
      s.faces.length <= c.maxFacesForEyeRule) {
    reasons.add(CullReason.eyesClosed);
  } else if (states.contains(EyeState.halfOpen) ||
      states.contains(EyeState.closed)) {
    reasons.add(CullReason.eyesHalfOpen);
  }
  if (s.highlightClip > c.highlightClipMax ||
      s.faceHighlightClip > c.faceHighlightClipMax) {
    reasons.add(CullReason.highlightsClipped);
  }
  if (s.shadowClip > c.shadowClipMax) reasons.add(CullReason.shadowsCrushed);

  // Sharpness on a log scale between "clearly soft" and "crisp".
  const lo = 0.002, hi = 0.2;
  final sharpN = (math.log(math.max(sharp, 1e-6) / lo) / math.log(hi / lo))
      .clamp(0.0, 1.0);
  final eyesN = states.contains(EyeState.closed)
      ? 0.0
      : states.contains(EyeState.halfOpen)
      ? 0.5
      : 1.0;
  final expN =
      (1 -
              0.6 * (s.highlightClip / (2 * c.highlightClipMax)).clamp(0, 1) -
              0.4 * (s.shadowClip / (2 * c.shadowClipMax)).clamp(0, 1))
          .clamp(0.0, 1.0);
  return CullAssessment(
    0.5 * sharpN + 0.3 * eyesN + 0.2 * expN,
    Set.unmodifiable(reasons),
  );
}
