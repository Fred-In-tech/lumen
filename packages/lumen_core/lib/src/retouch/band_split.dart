/// Multi-band separation of a face (research 09 §4.3).
///
/// Five components by difference of low-passes, sized relative to the
/// inter-ocular distance so one set of numbers serves every resolution:
///
/// | Band | σ (IOD) | Holds |
/// |---|---|---|
/// | B0 fine | < 0.006 | pores, vellus hair, grain: never attenuated |
/// | B1 small | 0.006–0.020 | fine lines, small bumps |
/// | B2 mid | 0.020–0.065 | blemish bodies, blotches: the working band |
/// | B3 broad | 0.065–0.22 | patchiness, under-eye bags |
/// | Base | > 0.22 | form, lighting, make-up contour: untouched |
///
/// The two widest low-passes are masked (normalised) convolutions over
/// the skin, `blur(M·x) / blur(M)`, so hair, background, lips and eyes
/// never bleed into a skin band: that is what removes halos at the
/// hairline, jaw and nostrils.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'filters.dart';
import 'lab_planes.dart';

const double kBandSigma0Iod = 0.006;
const double kBandSigma1Iod = 0.020;
const double kBandSigma2Iod = 0.065;
const double kBandSigma3Iod = 0.22;

/// The fine low-pass is at least this wide (map px): below it the map
/// grid cannot tell pores from the band above, so nothing finer than
/// this is ever handed to an effect.
const double kBandSigma0MinPx = 0.8;

/// Each low-pass is at least this much wider than the one before.
const double kBandMinRatio = 1.6;

/// Weight of the plain blur inside a masked blur: where no skin is near,
/// the result falls back to the unmasked blur instead of dividing by 0.
const double kMaskedBlurEps = 0.02;

/// Amplitude selectivity (§4.3): `A = 1 − smoothstep(τ, 2.5·τ, envelope)`.
/// Low-amplitude variation (blotches) is evened; strong structure
/// (nostril shadow, lid crease, dimple, jaw line) keeps its contrast.
const double kAmpTau1 = 0.020;
const double kAmpTau2 = 0.035;
const double kAmpTau3 = 0.050;
const double kAmpRamp = 2.5;

/// Wide blurs run on a grid reduced so that σ stays at least this many
/// (reduced) pixels: the result is smooth at that scale anyway.
const double kCoarseBlurMinSigma = 4;
const int kCoarseBlurMaxFactor = 8;

/// Masked (normalised) Gaussian of several planes with one mask:
/// `(G∗(m·x) + ε·G∗x) / (G∗m + ε)` per plane, Gaussian [sigma].
List<Float32List> maskedGaussians(
  List<Float32List> planes,
  Float32List m,
  int w,
  int h,
  double sigma,
) {
  final factor = (sigma / kCoarseBlurMinSigma).floor().clamp(
    1,
    kCoarseBlurMaxFactor,
  );
  if (factor > 1) {
    final sm = downsample(m, w, h, factor);
    final small = [for (final p in planes) downsample(p, w, h, factor).plane];
    return [
      for (final p in _masked(small, sm.plane, sm.w, sm.h, sigma / factor))
        upsample(p, sm.w, sm.h, w, h, factor),
    ];
  }
  return _masked(planes, m, w, h, sigma);
}

List<Float32List> _masked(
  List<Float32List> planes,
  Float32List m,
  int w,
  int h,
  double sigma,
) {
  final den = gaussianBlur(m, w, h, sigma);
  final out = <Float32List>[];
  for (final x in planes) {
    final num = gaussianBlur(productOf([m, x]), w, h, sigma);
    final plain = gaussianBlur(x, w, h, sigma);
    final q = Float32List(x.length);
    for (var i = 0; i < q.length; i++) {
      q[i] = (num[i] + kMaskedBlurEps * plain[i]) / (den[i] + kMaskedBlurEps);
    }
    out.add(q);
  }
  return out;
}

/// Blurred mask `G∗m` (how much of the masked blur's support is skin),
/// on the same reduced grid as [maskedGaussians].
Float32List maskedCoverage(Float32List m, int w, int h, double sigma) {
  final factor = (sigma / kCoarseBlurMinSigma).floor().clamp(
    1,
    kCoarseBlurMaxFactor,
  );
  if (factor == 1) return gaussianBlur(m, w, h, sigma);
  final sm = downsample(m, w, h, factor);
  return upsample(
    gaussianBlur(sm.plane, sm.w, sm.h, sigma / factor),
    sm.w,
    sm.h,
    w,
    h,
    factor,
  );
}

/// [maskedGaussians] of the three channels of [x].
LabPlanes maskedLab(LabPlanes x, Float32List m, double sigma) {
  final r = maskedGaussians(x.channels, m, x.rect.w, x.rect.h, sigma);
  return LabPlanes(x.rect, r[0], r[1], r[2]);
}

/// The low-passes and bands of one face.
class SkinBands {
  SkinBands._(this.l0, this.l1, this.l2, this.l3, this.a1, this.a2, this.a3);

  /// Splits [x] (OkLab, heals and wrinkle fill applied) with [mask] as
  /// the skin weight of the masked blurs; [iod] in map pixels.
  factory SkinBands.split(LabPlanes x, Float32List mask, double iod) {
    final w = x.rect.w, h = x.rect.h;
    final s0 = math.max(kBandSigma0MinPx, kBandSigma0Iod * iod);
    final s1 = math.max(kBandMinRatio * s0, kBandSigma1Iod * iod);
    final s2 = math.max(kBandMinRatio * s1, kBandSigma2Iod * iod);
    final s3 = math.max(kBandMinRatio * s2, kBandSigma3Iod * iod);
    final l0 = x.mapChannels((c) => gaussianBlur(c, w, h, s0));
    final l1 = x.mapChannels((c) => gaussianBlur(c, w, h, s1));
    final l2 = maskedLab(x, mask, s2);
    final l3 = maskedLab(x, mask, s3);
    Float32List keep(Float32List hi, Float32List lo, double sigma, double tau) {
      final mag = Float32List(hi.length);
      for (var i = 0; i < mag.length; i++) {
        mag[i] = (hi[i] - lo[i]).abs();
      }
      // Envelope: local maximum, then a blur, both at the band's scale
      // (on a reduced grid when the scale is wide).
      final factor = (sigma / kCoarseBlurMinSigma).floor().clamp(
        1,
        kCoarseBlurMaxFactor,
      );
      final small = factor > 1 ? downsample(mag, w, h, factor) : null;
      final sw = small?.w ?? w, sh = small?.h ?? h, sg = sigma / factor;
      final blurred = gaussianBlur(
        rankFilter(small?.plane ?? mag, sw, sh, math.max(1, sg.round()), true),
        sw,
        sh,
        sg,
      );
      final env = small == null
          ? blurred
          : upsample(blurred, sw, sh, w, h, factor);
      for (var i = 0; i < env.length; i++) {
        env[i] = 1 - smoothstep(tau, kAmpRamp * tau, env[i]);
      }
      return env;
    }

    return SkinBands._(
      l0,
      l1,
      l2,
      l3,
      keep(l0.l, l1.l, s1, kAmpTau1),
      keep(l1.l, l2.l, s2, kAmpTau2),
      keep(l2.l, l3.l, s3, kAmpTau3),
    );
  }

  /// Low-passes at σ0 (plain), σ1 (plain), σ2 and σ3 (masked).
  final LabPlanes l0;
  final LabPlanes l1;
  final LabPlanes l2;
  final LabPlanes l3;

  /// Amplitude selectivity of B1, B2, B3 (1 = low amplitude, evened).
  final Float32List a1;
  final Float32List a2;
  final Float32List a3;
}
