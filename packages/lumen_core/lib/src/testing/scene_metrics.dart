import 'dart:math' as math;
import 'dart:typed_data';

import '../analysis/histogram.dart';
import '../color/cielab.dart';
import '../color/srgb.dart';
import '../render/rgba_buffer.dart';

/// An integer pixel rectangle (left/top inclusive, right/bottom exclusive).
class PixelRect {
  const PixelRect(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;
  int get area => width * height;

  bool contains(int x, int y) =>
      x >= left && x < right && y >= top && y < bottom;

  @override
  String toString() => 'PixelRect($left, $top, $width x $height)';
}

/// Measurements used by tests and acceptance checks on rendered buffers.
///
/// All "luma" values are display luma: `v = srgbEncode(Y)` with Rec. 709
/// luminance computed in linear light, in 0..1.
abstract final class SceneMetrics {
  /// Median display luma.
  static double medianLuma(RgbaBuffer img) => percentileLuma(img, 0.5);

  /// Display-luma percentile [q] in 0..1, linear interpolation between ranks.
  static double percentileLuma(RgbaBuffer img, double q) {
    final n = img.pixelCount;
    final values = Float64List(n);
    final d = img.data;
    for (var i = 0; i < n; i++) {
      values[i] = displayLuma(d[i * 4], d[i * 4 + 1], d[i * 4 + 2]);
    }
    values.sort();
    final pos = q.clamp(0, 1) * (n - 1);
    final lo = pos.floor();
    final hi = math.min(lo + 1, n - 1);
    final t = pos - lo;
    return values[lo] * (1 - t) + values[hi] * t;
  }

  /// Fraction of pixels whose brightest encoded channel is ≥ [threshold].
  static double clipFraction(RgbaBuffer img, {double threshold = 0.995}) {
    final limit = threshold * 255;
    var count = 0;
    final d = img.data;
    for (var i = 0; i < d.length; i += 4) {
      final m = math.max(d[i], math.max(d[i + 1], d[i + 2]));
      if (m >= limit) count++;
    }
    return count / img.pixelCount;
  }

  /// Fraction of pixels whose display luma is below [threshold].
  static double crushFraction(RgbaBuffer img, {double threshold = 0.01}) {
    var count = 0;
    final d = img.data;
    for (var i = 0; i < d.length; i += 4) {
      if (displayLuma(d[i], d[i + 1], d[i + 2]) < threshold) count++;
    }
    return count / img.pixelCount;
  }

  /// `log2(R/B)` of the mean linear color (> 0 = warm cast).
  static double castA(RgbaBuffer img, [Iterable<PixelRect>? region]) {
    final m = _meanLinear(img, region);
    return _log2(m[0] / m[2]);
  }

  /// `log2(G / sqrt(R·B))` of the mean linear color (> 0 = green cast).
  static double castM(RgbaBuffer img, [Iterable<PixelRect>? region]) {
    final m = _meanLinear(img, region);
    return _log2(m[1] / math.sqrt(m[0] * m[2]));
  }

  /// Standard deviation of L* over valid pixels (not clipped, not black).
  static double sigmaLStar(RgbaBuffer img) {
    var sum = 0.0, sum2 = 0.0;
    var n = 0;
    final d = img.data;
    for (var i = 0; i < d.length; i += 4) {
      final mx = math.max(d[i], math.max(d[i + 1], d[i + 2]));
      if (mx >= 254) continue;
      final y = linearLuminanceOfBytes(d[i], d[i + 1], d[i + 2]);
      if (y < 0.002) continue;
      final l = lStarFromY(y);
      sum += l;
      sum2 += l * l;
      n++;
    }
    if (n == 0) return 0;
    final mean = sum / n;
    return math.sqrt(math.max(0, sum2 / n - mean * mean));
  }

  /// Mean CIELAB chroma C* over all pixels.
  static double meanChroma(RgbaBuffer img) {
    var sum = 0.0;
    final d = img.data;
    for (var i = 0; i < d.length; i += 4) {
      sum += linearSrgbToLab(
        kSrgbByteToLinear[d[i]],
        kSrgbByteToLinear[d[i + 1]],
        kSrgbByteToLinear[d[i + 2]],
      ).chroma;
    }
    return sum / img.pixelCount;
  }

  /// 32-bit FNV-1a hash of the RGBA bytes (stable across runs and platforms).
  static int hash(RgbaBuffer img) {
    var h = 0x811C9DC5;
    for (final byte in img.data) {
      h ^= byte;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static List<double> _meanLinear(RgbaBuffer img, Iterable<PixelRect>? region) {
    var r = 0.0, g = 0.0, b = 0.0;
    var n = 0;
    void add(int x, int y) {
      final o = img.offset(x, y);
      r += kSrgbByteToLinear[img.data[o]];
      g += kSrgbByteToLinear[img.data[o + 1]];
      b += kSrgbByteToLinear[img.data[o + 2]];
      n++;
    }

    if (region == null) {
      for (var y = 0; y < img.height; y++) {
        for (var x = 0; x < img.width; x++) {
          add(x, y);
        }
      }
    } else {
      for (final rect in region) {
        for (var y = rect.top; y < rect.bottom; y++) {
          for (var x = rect.left; x < rect.right; x++) {
            add(x, y);
          }
        }
      }
    }
    const floor = 1e-9;
    return [
      math.max(r / n, floor),
      math.max(g / n, floor),
      math.max(b / n, floor),
    ];
  }

  static double _log2(double x) => math.log(x) / math.ln2;
}
