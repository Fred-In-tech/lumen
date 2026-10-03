import 'dart:math' as math;
import 'dart:typed_data';

import '../analysis/histogram.dart';
import '../analysis/image_stats.dart';
import '../color/cielab.dart';
import '../color/srgb.dart';
import '../render/rgba_buffer.dart';

const int _kBins = 4096;

/// L* of each luma bin (display luma → Y → L*).
final Float64List _lStarOfBin = Float64List.fromList([
  for (var b = 0; b <= _kBins; b++) lStarFromY(srgbToLinear(b / _kBins)),
]);

/// Bin holding the value of rank `q·(n−1)` in histogram [h] of [n] samples.
int _quantileBin(Int32List h, int n, double q) {
  final rank = (q.clamp(0, 1) * (n - 1)).round();
  var cum = 0;
  for (var b = 0; b < h.length; b++) {
    cum += h[b];
    if (rank < cum) return b;
  }
  return h.length - 1;
}

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

  /// [clipLevel] is the encoded value at or above which a pixel counts as
  /// clipped (0.995 of the output white; lower it when whites < 0 compress
  /// the output white so the compression cannot hide blown pixels).
  ///
  /// Percentiles come from a 4096-bin luma histogram (±1/8192 in luma).
  factory ToneMeasure.of(RgbaBuffer img, {double clipLevel = 0.995}) {
    final n = img.pixelCount;
    final d = img.data;
    final luma = Int32List(_kBins + 1);
    final validLuma = Int32List(_kBins + 1);
    final maxByte = Int32List(256);
    var clip = 0, crush = 0, hiClip = 0, loCrush = 0;
    final clipByte = clipLevel * 255, hiClipByte = 0.99 * 255;
    for (var i = 0; i < d.length; i += 4) {
      final r8 = d[i], g8 = d[i + 1], b8 = d[i + 2];
      final y = linearLuminanceOfBytes(r8, g8, b8);
      final v = srgbEncodeFast(y);
      final bin = (v * _kBins).round();
      luma[bin]++;
      final mx = math.max(r8, math.max(g8, b8));
      maxByte[mx]++;
      if (mx >= clipByte) clip++;
      if (mx >= hiClipByte) hiClip++;
      if (v < 0.01) crush++;
      if (v <= 0.02) loCrush++;
      if (mx < clipByte && y >= 0.002) validLuma[bin]++;
    }
    final p10 = _quantileBin(luma, n, 0.1), p90 = _quantileBin(luma, n, 0.9);
    var hiSum = 0.0, hiN = 0, loSum = 0.0, loN = 0;
    var lSum = 0.0, l2Sum = 0.0, lN = 0;
    for (var b = 0; b <= _kBins; b++) {
      final c = luma[b];
      if (c > 0) {
        final v = b / _kBins;
        if (b >= p90) {
          hiSum += v * c;
          hiN += c;
        }
        if (b <= p10) {
          loSum += v * c;
          loN += c;
        }
      }
      final vc = validLuma[b];
      if (vc > 0) {
        final l = _lStarOfBin[b];
        lSum += l * vc;
        l2Sum += l * l * vc;
        lN += vc;
      }
    }
    final meanL = lN == 0 ? 0.0 : lSum / lN;
    return ToneMeasure._(
      medianY: srgbToLinear(_quantileBin(luma, n, 0.5) / _kBins),
      p0_5: _quantileBin(luma, n, 0.005) / _kBins,
      highlightP99_5: _quantileBin(maxByte, n, 0.995) / 255,
      clipFraction: clip / n,
      crushFraction: crush / n,
      hiMean: hiN == 0 ? 0 : hiSum / hiN,
      loMean: loN == 0 ? 0 : loSum / loN,
      hiClip: hiClip / n,
      loCrush: loCrush / n,
      sigmaLStar: lN == 0
          ? 0
          : math.sqrt(math.max(0, l2Sum / lN - meanL * meanL)),
      medianLStar: lN == 0 ? 0 : _lStarOfBin[_quantileBin(validLuma, lN, 0.5)],
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
