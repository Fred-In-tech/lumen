import 'dart:math' as math;
import 'dart:typed_data';

import '../color/cielab.dart';
import '../color/oklab.dart';
import '../color/rgb.dart';
import '../color/srgb.dart';
import '../model/param_registry.dart';
import '../render/engine_constants.dart';
import '../render/rgba_buffer.dart';
import 'histogram.dart';
import 'stats_kernels.dart';

export 'stats_kernels.dart' show WbEstimate, estimateWhiteBalanceOf;

/// Display-luma percentiles of an image (0..1).
class LumaPercentiles {
  const LumaPercentiles({
    required this.p0_5,
    required this.p5,
    required this.p50,
    required this.p95,
    required this.p99_5,
  });

  final double p0_5;
  final double p5;
  final double p50;
  final double p95;
  final double p99_5;

  Map<String, double> toJson() => {
    'p0_5': _r4(p0_5),
    'p5': _r4(p5),
    'p50': _r4(p50),
    'p95': _r4(p95),
    'p99_5': _r4(p99_5),
  };
}

/// Image statistics of research 01 §6.1–6.9, computed on an analysis proxy.
///
/// "Luma" is display luma `v = encode(Y)`; `Y` is linear Rec. 709 luminance.
/// Fractions are 0..1 here; [toJson] reports the contract's percentages.
class ImageStats {
  const ImageStats({
    required this.width,
    required this.height,
    required this.lumaP,
    required this.clipFraction,
    required this.crushFraction,
    required this.lAvg,
    required this.yP1,
    required this.yP99,
    required this.highlightP99_5,
    required this.hiMean,
    required this.loMean,
    required this.hiClip,
    required this.loCrush,
    required this.sigmaLStar,
    required this.medianLStar,
    required this.wb,
    required this.meanChroma,
    required this.highChromaShare,
    required this.skinShare,
    required this.haze,
    required this.airlight,
    required this.hslShare,
  });

  /// Computes every statistic in one pass family over [image].
  factory ImageStats.compute(RgbaBuffer image) => _compute(image);

  final int width;
  final int height;
  final LumaPercentiles lumaP;

  /// Pixels whose brightest encoded channel is ≥ 0.995.
  final double clipFraction;

  /// Pixels with display luma < 0.01.
  final double crushFraction;

  /// Log-average luminance over valid pixels trimmed to [yP1, yP99].
  final double lAvg;
  final double yP1;
  final double yP99;

  /// P99.5 of the brightest encoded channel (`P_hi` of research §6.5).
  final double highlightP99_5;

  /// Mean luma of the brightest 10 % and darkest 10 % of pixels.
  final double hiMean;
  final double loMean;

  /// Fraction with brightest encoded channel ≥ 0.99 / luma ≤ 0.02.
  final double hiClip;
  final double loCrush;

  /// Standard deviation and median of L* over valid pixels.
  final double sigmaLStar;
  final double medianLStar;
  final WbEstimate wb;

  /// Mean C* over non-skin pixels with 15 < L* < 90, and share with C* > 60.
  final double meanChroma;
  final double highChromaShare;
  final double skinShare;

  /// Mean dark channel over pixels with luma < 0.9.
  final double haze;

  /// Mean encoded color of the brightest 0.1 % dark-channel pixels.
  final Rgb airlight;

  /// Share of all pixels per OkLCh hue band (chroma > 0.04).
  final Map<HslBand, double> hslShare;

  /// The gateway contract's `stats` object (PLAN.md §1.9).
  Map<String, Object?> toJson() => {
    'lumaP': lumaP.toJson(),
    'clipPct': _r4(clipFraction * 100),
    'crushPct': _r4(crushFraction * 100),
    'lAvg': _r4(lAvg),
    'wb': {'a': _r4(wb.a), 'm': _r4(wb.m), 'confidence': _r4(wb.confidence)},
    'meanChroma': _r4(meanChroma),
    'skinShare': _r4(skinShare),
    'haze': _r4(haze),
    'hslShare': {
      for (final e in hslShare.entries)
        if (e.value >= 0.01) e.key.name: _r4(e.value),
    },
  };
}

double _r4(double v) => (v * 10000).roundToDouble() / 10000;

/// Valid-pixel thresholds of research 01 §6.1.
const double _kClipEnc = 0.995;
const double _kDarkY = 0.002;

ImageStats _compute(RgbaBuffer image) {
  final n = image.pixelCount;
  final d = image.data;
  final lin = Float64List(n * 3);
  final yLin = Float64List(n);
  final luma = Float64List(n);
  final maxEnc = Float64List(n);
  final minEnc = Float64List(n);
  final valid = Uint8List(n);
  final wbUse = Uint8List(n);
  var clipped = 0, crushed = 0, hiClip = 0, loCrush = 0;
  for (var i = 0; i < n; i++) {
    final r8 = d[i * 4], g8 = d[i * 4 + 1], b8 = d[i * 4 + 2];
    final r = kSrgbByteToLinear[r8];
    final g = kSrgbByteToLinear[g8];
    final b = kSrgbByteToLinear[b8];
    lin[i * 3] = r;
    lin[i * 3 + 1] = g;
    lin[i * 3 + 2] = b;
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    yLin[i] = y;
    final v = srgbEncodeFast(y);
    luma[i] = v;
    final mx = math.max(r8, math.max(g8, b8)),
        mn = math.min(r8, math.min(g8, b8));
    maxEnc[i] = mx / 255;
    minEnc[i] = mn / 255;
    if (maxEnc[i] >= _kClipEnc) clipped++;
    if (maxEnc[i] >= 0.99) hiClip++;
    if (v < 0.01) crushed++;
    if (v <= 0.02) loCrush++;
    if (maxEnc[i] < _kClipEnc && y >= _kDarkY) {
      valid[i] = 1;
      final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
      if (sat <= 0.6) wbUse[i] = 1;
    }
  }

  final sortedLuma = Float64List.fromList(luma)..sort();
  final p10 = quantileSorted(sortedLuma, 0.1);
  final p90 = quantileSorted(sortedLuma, 0.9);
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

  final validY = <double>[
    for (var i = 0; i < n; i++)
      if (valid[i] == 1) yLin[i],
  ]..sort();
  final ySource = validY.isEmpty ? (List<double>.of(yLin)..sort()) : validY;
  final yP1 = quantileSorted(ySource, 0.01);
  final yP99 = quantileSorted(ySource, 0.99);
  var logSum = 0.0, logN = 0;
  for (final y in ySource) {
    if (y < yP1 || y > yP99) continue;
    logSum += math.log(y + 1e-4);
    logN++;
  }
  final lAvg = logN == 0 ? 0.0 : math.exp(logSum / logN);

  final color = _colorStats(lin, valid, n);
  final dark = darkChannel(minEnc, image.width, image.height);
  final haze = _haze(dark, luma);

  return ImageStats(
    width: image.width,
    height: image.height,
    lumaP: LumaPercentiles(
      p0_5: quantileSorted(sortedLuma, 0.005),
      p5: quantileSorted(sortedLuma, 0.05),
      p50: quantileSorted(sortedLuma, 0.5),
      p95: quantileSorted(sortedLuma, 0.95),
      p99_5: quantileSorted(sortedLuma, 0.995),
    ),
    clipFraction: clipped / n,
    crushFraction: crushed / n,
    lAvg: lAvg,
    yP1: yP1,
    yP99: yP99,
    highlightP99_5: quantileSorted(Float64List.fromList(maxEnc)..sort(), 0.995),
    hiMean: hiN == 0 ? 0 : hiSum / hiN,
    loMean: loN == 0 ? 0 : loSum / loN,
    hiClip: hiClip / n,
    loCrush: loCrush / n,
    sigmaLStar: color.sigmaL,
    medianLStar: color.medianL,
    wb: estimateWhiteBalance(lin, image.width, image.height, wbUse),
    meanChroma: color.meanChroma,
    highChromaShare: color.highChroma,
    skinShare: color.skin,
    haze: haze,
    airlight: _airlight(dark, d),
    hslShare: color.hsl,
  );
}

class _ColorStats {
  const _ColorStats({
    required this.sigmaL,
    required this.medianL,
    required this.meanChroma,
    required this.highChroma,
    required this.skin,
    required this.hsl,
  });

  final double sigmaL;
  final double medianL;
  final double meanChroma;
  final double highChroma;
  final double skin;
  final Map<HslBand, double> hsl;
}

/// Skin candidate test of research 01 §6.8.
bool isSkinLab(Lab lab) {
  final h = lab.hue, c = lab.chroma;
  return h >= 20 && h <= 75 && c >= 10 && c <= 45 && lab.l >= 30 && lab.l <= 85;
}

_ColorStats _colorStats(Float64List lin, Uint8List valid, int n) {
  var lSum = 0.0, l2Sum = 0.0, lN = 0;
  final ls = <double>[];
  var cSum = 0.0, cN = 0, highC = 0, skin = 0;
  final bandCount = {for (final b in HslBand.values) b: 0};
  for (var i = 0; i < n; i++) {
    final r = lin[i * 3], g = lin[i * 3 + 1], b = lin[i * 3 + 2];
    final lab = linearSrgbToLab(r, g, b);
    if (valid[i] == 1) {
      lSum += lab.l;
      l2Sum += lab.l * lab.l;
      lN++;
      ls.add(lab.l);
    }
    if (isSkinLab(lab)) {
      skin++;
    } else if (lab.l > 15 && lab.l < 90) {
      cSum += lab.chroma;
      cN++;
      if (lab.chroma > 60) highC++;
    }
    final lch = linearSrgbToOklab(r, g, b).toLch();
    if (lch.c > 0.04) {
      final band = nearestHslBand(lch.h);
      bandCount[band] = bandCount[band]! + 1;
    }
  }
  final meanL = lN == 0 ? 0.0 : lSum / lN;
  ls.sort();
  return _ColorStats(
    sigmaL: lN == 0 ? 0 : math.sqrt(math.max(0, l2Sum / lN - meanL * meanL)),
    medianL: quantileSorted(ls, 0.5),
    meanChroma: cN == 0 ? 0 : cSum / cN,
    highChroma: cN == 0 ? 0 : highC / cN,
    skin: skin / n,
    hsl: Map.unmodifiable({
      for (final e in bandCount.entries) e.key: e.value / n,
    }),
  );
}

/// The HSL band whose OkLCh center (engine constants) is closest to [hueDeg] (circular).
HslBand nearestHslBand(double hueDeg) {
  var best = HslBand.red;
  var bestDist = double.infinity;
  for (final band in HslBand.values) {
    final raw = (hueDeg - kHslBandCenters[band.index]).abs() % 360;
    final dist = math.min(raw, 360 - raw);
    if (dist < bestDist) {
      bestDist = dist;
      best = band;
    }
  }
  return best;
}

double _haze(Float64List dark, Float64List luma) {
  var sum = 0.0, count = 0;
  for (var i = 0; i < dark.length; i++) {
    if (luma[i] >= 0.9) continue;
    sum += dark[i];
    count++;
  }
  return count == 0 ? 0 : sum / count;
}

Rgb _airlight(Float64List dark, Uint8List data) {
  final order = List<int>.generate(dark.length, (i) => i)
    ..sort((a, b) => dark[b].compareTo(dark[a]));
  final take = math.max(1, (dark.length * 0.001).round());
  var r = 0.0, g = 0.0, b = 0.0;
  for (var k = 0; k < take; k++) {
    final i = order[k];
    r += data[i * 4] / 255;
    g += data[i * 4 + 1] / 255;
    b += data[i * 4 + 2] / 255;
  }
  return Rgb(r / take, g / take, b / take);
}
