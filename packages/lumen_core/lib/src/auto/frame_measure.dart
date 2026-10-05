import 'dart:math' as math;
import 'dart:typed_data';

import '../analysis/image_stats.dart' show isSkinLab;
import '../color/cielab.dart';
import '../color/srgb.dart';
import 'enhance_constants.dart';
import 'enhance_pixels.dart';

typedef _C = EnhanceConstants;

const int _kBins = 4096;

final Float64List _lStarOfBin = Float64List.fromList([
  for (var b = 0; b <= _kBins; b++) lStarFromY(srgbToLinear(b / _kBins)),
]);

int _bin(double encoded) => (encoded * _kBins).round().clamp(0, _kBins);

/// Value (0..1) at quantile [q] of histogram [h] holding [n] samples.
double _quantile(Int32List h, int n, double q) {
  if (n <= 0) return 0;
  final rank = (q.clamp(0, 1) * (n - 1)).round();
  var cum = 0;
  for (var b = 0; b < h.length; b++) {
    cum += h[b];
    if (rank < cum) return b / _kBins;
  }
  return 1;
}

/// Tone statistics of one frame (research 09 §2.2), from linear pixels that
/// may exceed 1.0. "Luma" `v` is the sRGB-encoded luminance, clamped to 0..1.
class FrameMeasure {
  const FrameMeasure._({
    required this.p0_1,
    required this.p0_5,
    required this.p5,
    required this.p50,
    required this.p95,
    required this.p99_5,
    required this.maxP99_5,
    required this.maxP99_9,
    required this.clipFraction,
    required this.hiClip,
    required this.nearClip,
    required this.crushFraction,
    required this.loCrush,
    required this.hiMean,
    required this.loMean,
    required this.sigmaLStar,
    required this.medianLStar,
    required this.lAvg,
    required this.yP1,
    required this.yP99,
    required this.sceneWhiteY,
  });

  /// Measures [px]. Pixels flagged in [skin] (non-zero) are left out of the
  /// scene-white reference.
  factory FrameMeasure.of(LinearPixels px, {Uint8List? skin}) {
    final n = px.pixelCount;
    final d = px.rgb;
    final luma = Int32List(_kBins + 1);
    final valid = Int32List(_kBins + 1);
    final white = Int32List(_kBins + 1);
    final maxCh = Int32List(_kBins + 1);
    var clip = 0, hiClip = 0, near = 0, crush = 0, loCrush = 0, whiteN = 0;
    var logSum = 0.0, logN = 0;
    for (var i = 0, o = 0; i < n; i++, o += 3) {
      final r = d[o], g = d[o + 1], b = d[o + 2];
      final y = luminanceOf(r, g, b);
      final v = linearToSrgb(y);
      final bin = _bin(v);
      luma[bin]++;
      final mx = linearToSrgb(math.max(r, math.max(g, b)));
      maxCh[_bin(mx)]++;
      final clipped = mx >= _C.clipEncoded;
      if (clipped) clip++;
      if (mx >= 0.99) hiClip++;
      if (mx >= 0.93 && !clipped) near++;
      if (v < 0.01) crush++;
      if (v <= 0.02) loCrush++;
      if (clipped || y < _C.darkY) continue;
      valid[bin]++;
      logSum += math.log(y);
      logN++;
      if (skin == null || skin[i] == 0) {
        white[bin]++;
        whiteN++;
      }
    }
    final p10 = _quantile(luma, n, 0.1), p90 = _quantile(luma, n, 0.9);
    var hiSum = 0.0, hiN = 0, loSum = 0.0, loN = 0;
    var lSum = 0.0, l2Sum = 0.0;
    for (var b = 0; b <= _kBins; b++) {
      final c = luma[b];
      final v = b / _kBins;
      if (c > 0 && v >= p90) {
        hiSum += v * c;
        hiN += c;
      }
      if (c > 0 && v <= p10) {
        loSum += v * c;
        loN += c;
      }
      final vc = valid[b];
      if (vc > 0) {
        final l = _lStarOfBin[b];
        lSum += l * vc;
        l2Sum += l * l * vc;
      }
    }
    final meanL = logN == 0 ? 0.0 : lSum / logN;
    double y(Int32List h, int count, double q) =>
        srgbToLinear(_quantile(h, count, q));
    return FrameMeasure._(
      p0_1: _quantile(luma, n, 0.001),
      p0_5: _quantile(luma, n, 0.005),
      p5: _quantile(luma, n, 0.05),
      p50: _quantile(luma, n, 0.5),
      p95: _quantile(luma, n, 0.95),
      p99_5: _quantile(luma, n, 0.995),
      maxP99_5: _quantile(maxCh, n, 0.995),
      maxP99_9: _quantile(maxCh, n, 0.999),
      clipFraction: n == 0 ? 0 : clip / n,
      hiClip: n == 0 ? 0 : hiClip / n,
      nearClip: n == 0 ? 0 : near / n,
      crushFraction: n == 0 ? 0 : crush / n,
      loCrush: n == 0 ? 0 : loCrush / n,
      hiMean: hiN == 0 ? 0 : hiSum / hiN,
      loMean: loN == 0 ? 0 : loSum / loN,
      sigmaLStar: logN == 0
          ? 0
          : math.sqrt(math.max(0, l2Sum / logN - meanL * meanL)),
      medianLStar: logN == 0
          ? 0
          : lStarFromY(srgbToLinear(_quantile(valid, logN, 0.5))),
      lAvg: logN == 0 ? 0 : math.exp(logSum / logN),
      yP1: y(valid, logN, 0.01),
      yP99: y(valid, logN, 0.99),
      sceneWhiteY: whiteN == 0 ? 0 : y(white, whiteN, 0.98),
    );
  }

  /// Luma percentiles (0..1).
  final double p0_1;
  final double p0_5;
  final double p5;
  final double p50;
  final double p95;
  final double p99_5;

  /// Percentiles of the brightest encoded channel.
  final double maxP99_5;
  final double maxP99_9;

  /// Share with the brightest channel ≥ 0.995 / ≥ 0.99.
  final double clipFraction;
  final double hiClip;

  /// Share whose brightest channel is in [0.93, 0.995): very bright but
  /// not blown, where a highlight pull still finds detail.
  final double nearClip;

  /// Share with luma < 0.01 / ≤ 0.02.
  final double crushFraction;
  final double loCrush;

  /// Mean luma of the brightest and the darkest 10 %.
  final double hiMean;
  final double loMean;

  /// Spread and median of L* over valid (not clipped, not black) pixels.
  final double sigmaLStar;
  final double medianLStar;

  /// Log-average luminance and its 1 % / 99 % range over valid pixels.
  final double lAvg;
  final double yP1;
  final double yP99;

  /// P98 luminance of valid non-skin pixels: the in-image white reference.
  final double sceneWhiteY;

  double get medianY => srgbToLinear(p50);
}

/// Colourfulness of a frame (research 09 §2.9).
class ChromaReading {
  const ChromaReading._(
    this.meanChroma,
    this.highChromaShare,
    this.vividShare,
    this.skinShare,
  );

  /// CIELAB chroma over pixels with 15 < L* < 90 that are not skin: by
  /// [skin] mask when given, and always by skin colour.
  factory ChromaReading.of(LinearPixels px, {Uint8List? skin}) {
    final d = px.rgb;
    final n = px.pixelCount;
    var sum = 0.0, count = 0, high = 0, vivid = 0, skinN = 0;
    for (var i = 0, o = 0; i < n; i++, o += 3) {
      final lab = linearSrgbToLab(
        d[o].clamp(0.0, 1.0),
        d[o + 1].clamp(0.0, 1.0),
        d[o + 2].clamp(0.0, 1.0),
      );
      if ((skin != null && skin[i] != 0) || isSkinLab(lab)) {
        skinN++;
      } else if (lab.l > 15 && lab.l < 90) {
        sum += lab.chroma;
        count++;
        if (lab.chroma > 60) high++;
        if (lab.chroma > 45) vivid++;
      }
    }
    return ChromaReading._(
      count == 0 ? 0 : sum / count,
      count == 0 ? 0 : high / count,
      count == 0 ? 0 : vivid / count,
      n == 0 ? 0 : skinN / n,
    );
  }

  final double meanChroma;

  /// Share of the measured pixels with C* > 60.
  final double highChromaShare;

  /// Share of the measured pixels with C* > 45: colour that is already
  /// strong, whatever the average says.
  final double vividShare;

  /// Share of all pixels that are skin (mask or colour).
  final double skinShare;
}
