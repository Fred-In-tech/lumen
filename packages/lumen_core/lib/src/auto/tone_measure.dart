import 'dart:math' as math;
import 'dart:typed_data';

import '../analysis/histogram.dart';
import '../analysis/image_stats.dart';
import '../analysis/stats_kernels.dart';
import '../color/cielab.dart';
import '../color/srgb.dart';
import '../render/rgba_buffer.dart';

/// Fast luma/tone measurements of a rendered proxy, used inside solver
/// loops (a subset of [ImageStats] without WB, chroma and dark channel).
class ToneMeasure {
  const ToneMeasure._({
    required this.medianY,
    required this.p0_5,
    required this.highlightP99_5,
    required this.clipFraction,
    required this.crushFraction,
    required this.hiMean,
    required this.loMean,
    required this.hiClip,
    required this.loCrush,
    required this.sigmaLStar,
    required this.medianLStar,
  });

  factory ToneMeasure.of(RgbaBuffer img) {
    final n = img.pixelCount;
    final d = img.data;
    final luma = Float64List(n);
    final ys = Float64List(n);
    final maxEnc = Float64List(n);
    final validL = <double>[];
    var clip = 0, crush = 0, hiClip = 0, loCrush = 0;
    var lSum = 0.0, l2Sum = 0.0;
    for (var i = 0; i < n; i++) {
      final r8 = d[i * 4], g8 = d[i * 4 + 1], b8 = d[i * 4 + 2];
      final y = linearLuminanceOfBytes(r8, g8, b8);
      ys[i] = y;
      final v = srgbEncodeFast(y);
      luma[i] = v;
      final mx = math.max(r8, math.max(g8, b8)) / 255;
      maxEnc[i] = mx;
      if (mx >= 0.995) clip++;
      if (mx >= 0.99) hiClip++;
      if (v < 0.01) crush++;
      if (v <= 0.02) loCrush++;
      if (mx < 0.995 && y >= 0.002) {
        final l = lStarFromY(y);
        validL.add(l);
        lSum += l;
        l2Sum += l * l;
      }
    }
    luma.sort();
    ys.sort();
    maxEnc.sort();
    final p10 = quantileSorted(luma, 0.1), p90 = quantileSorted(luma, 0.9);
    var hiSum = 0.0, hiN = 0, loSum = 0.0, loN = 0;
    for (final v in luma) {
      if (v >= p90) {
        hiSum += v;
        hiN++;
      }
      if (v <= p10) {
        loSum += v;
        loN++;
      }
    }
    final nl = validL.length;
    final meanL = nl == 0 ? 0.0 : lSum / nl;
    validL.sort();
    return ToneMeasure._(
      medianY: quantileSorted(ys, 0.5),
      p0_5: quantileSorted(luma, 0.005),
      highlightP99_5: quantileSorted(maxEnc, 0.995),
      clipFraction: clip / n,
      crushFraction: crush / n,
      hiMean: hiN == 0 ? 0 : hiSum / hiN,
      loMean: loN == 0 ? 0 : loSum / loN,
      hiClip: hiClip / n,
      loCrush: loCrush / n,
      sigmaLStar: nl == 0
          ? 0
          : math.sqrt(math.max(0, l2Sum / nl - meanL * meanL)),
      medianLStar: quantileSorted(validL, 0.5),
    );
  }

  /// Median linear luminance Y.
  final double medianY;
  final double p0_5;
  final double highlightP99_5;
  final double clipFraction;
  final double crushFraction;
  final double hiMean;
  final double loMean;
  final double hiClip;
  final double loCrush;
  final double sigmaLStar;
  final double medianLStar;

  double get medianLuma => linearToSrgb(medianY);
}

/// Chroma statistics of research 01 §6.8 on a rendered proxy.
class ChromaMeasure {
  const ChromaMeasure._(this.meanChroma, this.highChromaShare, this.skinShare);

  factory ChromaMeasure.of(RgbaBuffer img) {
    final d = img.data;
    var sum = 0.0, count = 0, high = 0, skin = 0;
    for (var i = 0; i < d.length; i += 4) {
      final lab = linearSrgbToLab(
        kSrgbByteToLinear[d[i]],
        kSrgbByteToLinear[d[i + 1]],
        kSrgbByteToLinear[d[i + 2]],
      );
      if (isSkinLab(lab)) {
        skin++;
      } else if (lab.l > 15 && lab.l < 90) {
        sum += lab.chroma;
        count++;
        if (lab.chroma > 60) high++;
      }
    }
    return ChromaMeasure._(
      count == 0 ? 0 : sum / count,
      count == 0 ? 0 : high / count,
      skin / img.pixelCount,
    );
  }

  final double meanChroma;
  final double highChromaShare;
  final double skinShare;
}
