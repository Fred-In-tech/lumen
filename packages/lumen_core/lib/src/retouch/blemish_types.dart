/// Blemish candidates and the slider → selection math (research 07 §3.3).
///
/// Detection runs once per photo; the `blemish.*` sliders only *select*
/// among the stored candidates. Selection happens in the retouch pass from
/// a per-pixel spot code, so dragging a blemish slider is uniform-only.
library;

import '../model/spot_anchor.dart';

export '../model/spot_anchor.dart';

/// Spot class. Each class has its own slider (`blemish.acne`,
/// `blemish.freckle`, `blemish.mole`); freckles and moles stay unless their
/// slider asks otherwise.
enum BlemishKind { acne, freckle, mole }

/// z-score threshold at slider 0 / 100: `k = mix(4.0, 1.8, v)`.
const double kBlemishKMax = 4.0;
const double kBlemishKMin = 1.8;

/// Largest healable radius at slider 0 / 100 (IOD units):
/// `maxR = mix(0.02, 0.06, v)`. Larger spots need the MI-GAN path.
const double kBlemishRMin = 0.02;
const double kBlemishRMax = 0.06;

/// A spot fades in over this much slider travel (0..1) past its threshold.
const double kSpotRamp = 0.08;

/// Spot codes: `0` = no spot, else `1 + kind·64 + q`, where `q` ∈ 0..62 is
/// the threshold quantized to [kSpotLevels] steps and 63 = forced removal.
/// Kind 3 is a clipped shine core ([kShineCoreCode]); it is selected by
/// the Shine slider above 50 % (`shineFill`), not by a threshold.
const int kSpotLevels = 62;
const int kSpotForced = 63;
const int kShineCoreKind = 3;
const int kShineCoreCode = 1 + kShineCoreKind * 64;

/// Slider value (0..1) at which a spot with z-score [z] and radius
/// [radiusIod] starts to heal: the smallest `v` with `z ≥ k(v)` and
/// `r ≤ maxR(v)`.
double blemishThreshold(double z, double radiusIod) {
  final vk = (kBlemishKMax - z) / (kBlemishKMax - kBlemishKMin);
  final vr = (radiusIod - kBlemishRMin) / (kBlemishRMax - kBlemishRMin);
  return (vk > vr ? vk : vr).clamp(0.0, 1.0);
}

/// Encodes one spot for the spot-code channel.
int encodeSpotCode(BlemishKind kind, double threshold, {bool forced = false}) {
  final q = forced
      ? kSpotForced
      : (threshold.clamp(0.0, 1.0) * kSpotLevels).round();
  return 1 + kind.index * 64 + q;
}

/// Heal weight (0..1) of a pixel with spot code [code] given the face's
/// slider values (0..1) and its shine fill weight. Mirrors `spotSelect()`
/// in `retouch.frag`.
double spotSelection(
  int code,
  double acne,
  double freckle,
  double mole, [
  double shineFill = 0,
]) {
  if (code <= 0) return 0;
  final c = code - 1;
  final kind = c >> 6, q = c & 63;
  if (kind == kShineCoreKind) return shineFill;
  if (q == kSpotForced) return 1;
  final slider = kind == 0 ? acne : (kind == 1 ? freckle : mole);
  if (slider <= 0) return 0;
  final w = (slider - q / kSpotLevels) / kSpotRamp;
  return w <= 0 ? 0 : (w >= 1 ? 1 : w);
}

/// One detected spot. Positions are normalized source uv; sizes are in IOD
/// units of its face so they are resolution independent.
class BlemishCandidate {
  const BlemishCandidate({
    required this.id,
    required this.faceId,
    required this.slot,
    required this.u,
    required this.v,
    required this.radiusIod,
    required this.kind,
    required this.score,
    required this.depthL,
    required this.deltaA,
    required this.deltaB,
  });

  /// Stable id (face id + quantized centre) for keep/remove overrides.
  final String id;
  final String faceId;
  final int slot;
  final double u;
  final double v;
  final double radiusIod;
  final BlemishKind kind;

  /// Detection z-score (contrast / local mid-band noise).
  final double score;

  /// Ring L minus centre L (positive = darker spot).
  final double depthL;

  /// Centre minus ring a* / b* (positive = redder / yellower).
  final double deltaA;
  final double deltaB;

  /// Slider value (0..1) at which this spot starts to heal.
  double get threshold => blemishThreshold(score, radiusIod);

  Map<String, Object?> toJson() => {
    'id': id,
    'faceId': faceId,
    'u': u,
    'v': v,
    'r': radiusIod,
    'kind': kind.name,
    'score': score,
  };

  @override
  String toString() =>
      'Blemish($id ${kind.name} r=${radiusIod.toStringAsFixed(3)} '
      'z=${score.toStringAsFixed(1)})';
}

/// The persisted anchor of a detected candidate.
extension BlemishCandidateAnchor on BlemishCandidate {
  SpotAnchor get anchor => SpotAnchor(u, v, radiusIod);
}

/// An anchor matches a candidate within this distance (IOD units) plus
/// half the larger radius.
const double kAnchorMatchIod = 0.02;

/// Per-spot user decisions: [keep] spots are never healed, [remove] spots
/// heal whatever the slider says. Changing these rebuilds the spot codes.
///
/// [keep] / [remove] hold candidate ids of the current maps (session
/// state); [keepAt] / [removeAt] hold persisted [SpotAnchor]s. A remove
/// anchor that matches no candidate still heals its disc (manual spot).
class BlemishOverrides {
  const BlemishOverrides({
    this.keep = const {},
    this.remove = const {},
    this.keepAt = const [],
    this.removeAt = const [],
  });

  static const none = BlemishOverrides();

  final Set<String> keep;
  final Set<String> remove;
  final List<SpotAnchor> keepAt;
  final List<SpotAnchor> removeAt;

  bool get isEmpty =>
      keep.isEmpty && remove.isEmpty && keepAt.isEmpty && removeAt.isEmpty;
}
