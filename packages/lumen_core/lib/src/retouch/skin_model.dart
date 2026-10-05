import 'dart:math' as math;
import 'dart:typed_data';

import 'filters.dart';
import 'lab_planes.dart';
import 'map_rect.dart';

/// Floor (OkLab units) added to the skin chroma standard deviations so a
/// very uniform cheek does not reject every slightly redder pixel.
const double kSkinChromaFloor = 0.012;

/// Mahalanobis distances are measured against the covariance × this².
const double kSkinChromaScale = 2.0;

/// Skin L gate: full weight above `lowL − kSkinLGateFull`, zero below
/// `lowL − kSkinLGateZero` (catches hair, brows and deep shadow).
const double kSkinLGateFull = 0.10;
const double kSkinLGateZero = 0.22;

/// Pixels brighter than the skin mean may lose chroma down to this fraction
/// of the mean chroma and still count as skin (specular shine adds white
/// light; without this, Reduce Shine would not see the shine it reduces).
const double kShineMinChroma = 0.3;

/// Robust core of the samples: within this many robust σ (1.4826·MAD,
/// at least [kSkinCoreFloor]) of the median chroma.
const double kSkinCoreSigmas = 2.5;
const double kSkinCoreFloor = 0.006;

/// Fraction of sampled L trimmed at each end before fitting (§2.2 step 3).
const double kSkinSampleTrim = 0.10;

/// Per-face colour skin model (research 07 §2.2 step 3): mean and
/// covariance of OkLab (a, b) sampled from the cheeks and forehead, plus
/// an L range. `p = exp(−½·d²_Mahalanobis(ab)) · gate(L)`.
class SkinColorModel {
  const SkinColorModel({
    required this.meanL,
    required this.meanA,
    required this.meanB,
    required this.covAA,
    required this.covAB,
    required this.covBB,
    required this.lowL,
  });

  /// Generic fallback when too few samples are available.
  static const fallback = SkinColorModel(
    meanL: 0.70,
    meanA: 0.03,
    meanB: 0.04,
    covAA: 9e-4,
    covAB: 0,
    covBB: 9e-4,
    lowL: 0.55,
  );

  /// Fits the model to the pixels of [lab] inside the [discs]
  /// (centre, radius in map pixels).
  factory SkinColorModel.fit(
    LabPlanes lab,
    List<({MapPoint centre, double radius})> discs,
  ) {
    final rect = lab.rect;
    final samples = <int>[];
    for (final d in discs) {
      final r2 = d.radius * d.radius;
      final box = MapRect.around(
        d.centre.x,
        d.centre.y,
        d.radius + 1,
        d.radius + 1,
        rect.x1,
        rect.y1,
      );
      for (var y = math.max(box.y0, rect.y0); y < box.y1; y++) {
        for (var x = math.max(box.x0, rect.x0); x < box.x1; x++) {
          final dx = x + 0.5 - d.centre.x, dy = y + 0.5 - d.centre.y;
          if (dx * dx + dy * dy <= r2) samples.add(rect.index(x, y));
        }
      }
    }
    if (samples.length < 16) return fallback;
    // Robust core first: the discs may partly sit on hair, lips or the
    // background when the mesh is off, so samples far from the median
    // colour (in robust σ) are dropped before anything is averaged.
    final core = _robustCore(lab, samples);
    if (core.length < 16) return fallback;
    core.sort((i, j) => lab.l[i].compareTo(lab.l[j]));
    final cut = (core.length * kSkinSampleTrim).floor();
    final kept = core.sublist(cut, core.length - cut);
    var sl = 0.0, sa = 0.0, sb = 0.0;
    for (final i in kept) {
      sl += lab.l[i];
      sa += lab.a[i];
      sb += lab.b[i];
    }
    final n = kept.length;
    final ma = sa / n, mb = sb / n;
    var caa = 0.0, cab = 0.0, cbb = 0.0;
    for (final i in kept) {
      final da = lab.a[i] - ma, db = lab.b[i] - mb;
      caa += da * da;
      cab += da * db;
      cbb += db * db;
    }
    return SkinColorModel(
      meanL: sl / n,
      meanA: ma,
      meanB: mb,
      covAA: caa / n,
      covAB: cab / n,
      covBB: cbb / n,
      lowL: lab.l[kept.first],
    );
  }

  /// Samples within [kSkinCoreSigmas] robust σ of the median (a, b) and
  /// not far darker than the median L (two rounds).
  static List<int> _robustCore(LabPlanes lab, List<int> samples) {
    var kept = samples;
    for (var round = 0; round < 2; round++) {
      double median(double Function(int i) v) {
        final xs = [for (final i in kept) v(i)]..sort();
        return xs[xs.length ~/ 2];
      }

      final ml = median((i) => lab.l[i]);
      final ma = median((i) => lab.a[i]), mb = median((i) => lab.b[i]);
      double mad(double Function(int i) v, double m) =>
          1.4826 * median((i) => (v(i) - m).abs());
      final sa = math.max(mad((i) => lab.a[i], ma), kSkinCoreFloor);
      final sb = math.max(mad((i) => lab.b[i], mb), kSkinCoreFloor);
      final sl = math.max(mad((i) => lab.l[i], ml), 2 * kSkinCoreFloor);
      final next = [
        for (final i in kept)
          if ((lab.a[i] - ma).abs() <= kSkinCoreSigmas * sa &&
              (lab.b[i] - mb).abs() <= kSkinCoreSigmas * sb &&
              lab.l[i] >= ml - 2 * kSkinCoreSigmas * sl)
            i,
      ];
      if (next.length < 16) break;
      kept = next;
    }
    return kept;
  }

  final double meanL;
  final double meanA;
  final double meanB;
  final double covAA;
  final double covAB;
  final double covBB;

  /// Lowest L kept after trimming (≈ P10 of the samples).
  final double lowL;

  /// Skin-colour probability of one OkLab colour.
  double probability(double l, double a, double b) {
    const f2 = kSkinChromaFloor * kSkinChromaFloor;
    const k2 = kSkinChromaScale * kSkinChromaScale;
    final saa = (covAA + f2) * k2, sbb = (covBB + f2) * k2, sab = covAB * k2;
    final det = saa * sbb - sab * sab;
    var da = a - meanA, db = b - meanB;
    final mm = meanA * meanA + meanB * meanB;
    if (l > meanL && mm > 1e-6) {
      final proj = (a * meanA + b * meanB) / mm;
      final fit = proj < kShineMinChroma
          ? kShineMinChroma
          : (proj > 1 ? 1.0 : proj);
      final s = 1 + (fit - 1) * smoothstep(meanL, meanL + 0.05, l);
      da = a - s * meanA;
      db = b - s * meanB;
    }
    final d2 = (sbb * da * da - 2 * sab * da * db + saa * db * db) / det;
    return math.exp(-0.5 * d2) *
        smoothstep(lowL - kSkinLGateZero, lowL - kSkinLGateFull, l);
  }

  /// [probability] of every pixel of [lab].
  Float32List probabilityPlane(LabPlanes lab) {
    final out = Float32List(lab.rect.area);
    for (var i = 0; i < out.length; i++) {
      out[i] = probability(lab.l[i], lab.a[i], lab.b[i]);
    }
    return out;
  }
}
