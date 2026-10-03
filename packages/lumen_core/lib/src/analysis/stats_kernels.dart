import 'dart:math' as math;
import 'dart:typed_data';

import '../color/rgb.dart';
import '../color/srgb.dart';
import '../render/rgba_buffer.dart';

/// Illuminant estimate and the cast metrics derived from it (research 01 §6.3).
class WbEstimate {
  const WbEstimate({
    required this.a,
    required this.m,
    required this.confidence,
    required this.illuminant,
  });

  static const neutral = WbEstimate(
    a: 0,
    m: 0,
    confidence: 1,
    illuminant: Rgb(1, 1, 1),
  );

  /// `log2(eR/eB)`: > 0 means a warm cast.
  final double a;

  /// `log2(eG/sqrt(eR·eB))`: > 0 means a green cast.
  final double m;

  /// 1 when shades-of-gray and gray-edge agree, 0 when they disagree ≥ 5°.
  final double confidence;

  /// Combined estimate, normalized so G = 1.
  final Rgb illuminant;
}

/// Minkowski exponent for shades-of-gray and gray-edge.
const double kWbMinkowskiP = 6;

/// Angle (degrees) at which the WB confidence reaches zero.
const double kWbConfidenceAngle = 5;

/// White-balance estimate of an 8-bit image over valid (not clipped, not
/// black) pixels with HSV saturation ≤ 0.6 (research 01 §6.3 step 1).
WbEstimate estimateWhiteBalanceOf(RgbaBuffer img) {
  final n = img.pixelCount;
  final d = img.data;
  final lin = Float64List(n * 3);
  final use = Uint8List(n);
  for (var i = 0; i < n; i++) {
    final r8 = d[i * 4], g8 = d[i * 4 + 1], b8 = d[i * 4 + 2];
    final r = kSrgbByteToLinear[r8];
    final g = kSrgbByteToLinear[g8];
    final b = kSrgbByteToLinear[b8];
    lin[i * 3] = r;
    lin[i * 3 + 1] = g;
    lin[i * 3 + 2] = b;
    final mx = math.max(r8, math.max(g8, b8));
    final mn = math.min(r8, math.min(g8, b8));
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    if (mx / 255 < 0.995 && y >= 0.002 && (mx - mn) <= 0.6 * mx) use[i] = 1;
  }
  return estimateWhiteBalance(lin, img.width, img.height, use);
}

/// Estimates the illuminant from linear [lin] (3 floats per pixel) using
/// pixels where [use] is true, then derives the cast metrics.
WbEstimate estimateWhiteBalance(
  Float64List lin,
  int width,
  int height,
  Uint8List use,
) {
  final sog = _shadesOfGray(lin, use);
  if (sog == null) return WbEstimate.neutral;
  final ge = _grayEdge(lin, width, height, use);
  final List<double> e;
  var confidence = 1.0;
  if (ge == null) {
    e = sog;
  } else {
    e = [for (var c = 0; c < 3; c++) math.sqrt(sog[c] * ge[c])];
    final angle = _angleDeg(sog, ge);
    confidence = (1 - angle / kWbConfidenceAngle).clamp(0, 1).toDouble();
  }
  final g = e[1];
  final r = e[0] / g, b = e[2] / g;
  double log2(double x) => math.log(x) / math.ln2;
  return WbEstimate(
    a: log2(r / b),
    m: log2(1 / math.sqrt(r * b)),
    confidence: confidence,
    illuminant: Rgb(r, 1, b),
  );
}

List<double>? _shadesOfGray(Float64List lin, Uint8List use) {
  final acc = [0.0, 0.0, 0.0];
  var n = 0;
  for (var i = 0; i < use.length; i++) {
    if (use[i] == 0) continue;
    for (var c = 0; c < 3; c++) {
      acc[c] += math.pow(lin[i * 3 + c], kWbMinkowskiP).toDouble();
    }
    n++;
  }
  if (n == 0) return null;
  final out = [
    for (final v in acc) math.pow(v / n, 1 / kWbMinkowskiP).toDouble(),
  ];
  return out.every((v) => v > 1e-9) ? out : null;
}

/// Gray-edge (n = 1, p = 6, σ = 1): Minkowski mean of gradient magnitudes.
List<double>? _grayEdge(Float64List lin, int w, int h, Uint8List use) {
  if (w < 3 || h < 3) return null;
  const k = [0.0044, 0.0540, 0.2420, 0.3992, 0.2420, 0.0540, 0.0044];
  final blurred = _separableBlur(lin, w, h, k);
  final acc = [0.0, 0.0, 0.0];
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (use[i] == 0) continue;
      for (var c = 0; c < 3; c++) {
        final gx = (blurred[(i + 1) * 3 + c] - blurred[(i - 1) * 3 + c]) / 2;
        final gy = (blurred[(i + w) * 3 + c] - blurred[(i - w) * 3 + c]) / 2;
        final mag = math.sqrt(gx * gx + gy * gy);
        acc[c] += math.pow(mag, kWbMinkowskiP).toDouble();
      }
      n++;
    }
  }
  if (n == 0) return null;
  final out = [
    for (final v in acc) math.pow(v / n, 1 / kWbMinkowskiP).toDouble(),
  ];
  final maxV = out.reduce(math.max);
  if (maxV < 1e-6 || out.any((v) => v < maxV * 1e-3)) return null;
  return out;
}

Float64List _separableBlur(Float64List src, int w, int h, List<double> k) {
  final r = k.length ~/ 2;
  final tmp = Float64List(src.length);
  final out = Float64List(src.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        var s = 0.0;
        for (var t = -r; t <= r; t++) {
          final xx = (x + t).clamp(0, w - 1);
          s += src[(y * w + xx) * 3 + c] * k[t + r];
        }
        tmp[(y * w + x) * 3 + c] = s;
      }
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        var s = 0.0;
        for (var t = -r; t <= r; t++) {
          final yy = (y + t).clamp(0, h - 1);
          s += tmp[(yy * w + x) * 3 + c] * k[t + r];
        }
        out[(y * w + x) * 3 + c] = s;
      }
    }
  }
  return out;
}

double _angleDeg(List<double> u, List<double> v) {
  var dot = 0.0, nu = 0.0, nv = 0.0;
  for (var c = 0; c < 3; c++) {
    dot += u[c] * v[c];
    nu += u[c] * u[c];
    nv += v[c] * v[c];
  }
  final cos = (dot / math.sqrt(nu * nv)).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

/// Dark channel (He et al. 2009): per-pixel min over channels of [minEnc],
/// then a (2·[radius]+1)² min filter.
Float64List darkChannel(Float64List minEnc, int w, int h, {int radius = 7}) {
  final tmp = Float64List(minEnc.length);
  final out = Float64List(minEnc.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var m = 1.0;
      final x0 = math.max(0, x - radius), x1 = math.min(w - 1, x + radius);
      for (var xx = x0; xx <= x1; xx++) {
        m = math.min(m, minEnc[y * w + xx]);
      }
      tmp[y * w + x] = m;
    }
  }
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - radius), y1 = math.min(h - 1, y + radius);
    for (var x = 0; x < w; x++) {
      var m = 1.0;
      for (var yy = y0; yy <= y1; yy++) {
        m = math.min(m, tmp[yy * w + x]);
      }
      out[y * w + x] = m;
    }
  }
  return out;
}

/// Value at quantile [q] of an ascending-sorted list (linear interpolation).
double quantileSorted(List<double> sorted, double q) {
  if (sorted.isEmpty) return 0;
  final pos = q.clamp(0, 1) * (sorted.length - 1);
  final lo = pos.floor();
  final hi = math.min(lo + 1, sorted.length - 1);
  final t = pos - lo;
  return sorted[lo] * (1 - t) + sorted[hi] * t;
}
