import 'dart:math' as math;

import '../color/cielab.dart';
import 'enhance_constants.dart';
import 'skin_measure.dart';

typedef _C = EnhanceConstants;

/// Where one face's lit skin should sit (research 09 §1.2, §2.4).
///
/// The tone class is never read from the skin's own brightness (that is the
/// thing being solved): it comes from the skin's luminance relative to the
/// scene white. With no usable white the class is unknown and the band is
/// the union of every class, so nothing is "fixed" towards a light target.
class SkinTarget {
  const SkinTarget({
    required this.toneIndex,
    required this.confidence,
    required this.low,
    required this.high,
    required this.centre,
  });

  /// Target for lit skin of luminance [litY] in a frame whose white
  /// reference is [sceneWhiteY] and whose clipped share is [clipFraction]. [shift] moves the band (a style's look),
  /// clamped to ±[EnhanceConstants.styleSkinShiftMax] L*.
  factory SkinTarget.of({
    required double litY,
    required double sceneWhiteY,
    double clipFraction = 0,
    double shift = 0,
  }) {
    final s = shift.clamp(-_C.styleSkinShiftMax, _C.styleSkinShiftMax);
    // In a blown frame the white is at least display white.
    final blown = clipFraction > _C.blownClip;
    if (blown) sceneWhiteY = math.max(sceneWhiteY, 1);
    final usable = sceneWhiteY >= litY * _C.whiteRefMinRatio && litY > 0;
    if (!usable) {
      return SkinTarget(
        toneIndex: 0.5,
        confidence: 0,
        low: _C.lowDark + s,
        high: _C.highLight + s,
        centre: (_C.lowDark + _C.highLight) / 2 + s,
      );
    }
    final rho = litY / sceneWhiteY;
    final idx =
        (math.log(rho / _C.rhoDark) / math.log(_C.rhoLight / _C.rhoDark)).clamp(
          0.0,
          1.0,
        );
    // A white that sits at the clip ceiling may really be brighter, which
    // would make the skin darker than it reads: widen the band downwards.
    final ceiling = blown || sceneWhiteY >= 0.93;
    final lo = math.max(0.0, idx - _C.toneSpreadSure * (ceiling ? 2 : 1));
    final hi = math.min(1.0, idx + _C.toneSpreadSure);
    return SkinTarget(
      toneIndex: idx,
      confidence: ceiling ? 0.6 : 0.8,
      low: _lerp(_C.lowDark, _C.lowLight, lo) + s,
      high: _lerp(_C.highDark, _C.highLight, hi) + s,
      centre: _lerp(_C.centreDark, _C.centreLight, idx) + s,
    );
  }

  /// 0 = dark … 1 = very light.
  final double toneIndex;

  /// 0 when the tone class is unknown.
  final double confidence;

  /// Accept band of lit-skin L*: no correction inside it.
  final double low;
  final double high;
  final double centre;

  bool accepts(double lStar) => lStar >= low && lStar <= high;

  /// Out-of-band distance in L*: > 0 too dark, < 0 too bright, 0 inside.
  double error(double lStar) => lStar < low
      ? low - lStar
      : lStar > high
      ? high - lStar
      : 0;

  /// Highest skin chroma (C*) this tone carries before it reads as orange.
  double get chromaMax =>
      _lerp(_C.skinChromaMaxDeep, _C.skinChromaMaxLight, toneIndex);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// One face as the exposure and colour stages see it.
class FaceRead {
  const FaceRead(this.region, this.skin, this.target);

  final SkinRegion region;
  final SkinReading skin;
  final SkinTarget target;

  double get lStar => skin.lStar;

  /// L* of the lit skin after an exposure change of [ev] stops.
  double lStarAt(double ev) =>
      lStarFromY((skin.litY * math.pow(2, ev)).clamp(0.0, 1.0));
}
