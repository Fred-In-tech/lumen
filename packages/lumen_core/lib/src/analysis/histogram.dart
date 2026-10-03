import 'dart:math' as math;
import 'dart:typed_data';

import '../color/luminance.dart';
import '../color/srgb.dart';
import '../render/rgba_buffer.dart';

const int _kEncodeLutSize = 4096;

final Float64List _encodeLut = () {
  final lut = Float64List(_kEncodeLutSize + 1);
  for (var i = 0; i <= _kEncodeLutSize; i++) {
    lut[i] = linearToSrgb(i / _kEncodeLutSize);
  }
  return lut;
}();

/// Fast sRGB encode (linear 0..1 → encoded 0..1) via a 4097-entry table with
/// linear interpolation. Max error ≈ 2e-5; inputs are clamped to 0..1.
double srgbEncodeFast(double linear) {
  if (linear <= 0) return 0;
  if (linear >= 1) return 1;
  final pos = linear * _kEncodeLutSize;
  final i = pos.floor();
  final t = pos - i;
  return _encodeLut[i] * (1 - t) + _encodeLut[i + 1] * t;
}

/// Linear Rec. 709 luminance Y of an 8-bit sRGB pixel.
double linearLuminanceOfBytes(int r, int g, int b) => relativeLuminance(
  kSrgbByteToLinear[r],
  kSrgbByteToLinear[g],
  kSrgbByteToLinear[b],
);

/// Display luma `v = encode(Y)` of an 8-bit sRGB pixel, 0..1.
double displayLuma(int r, int g, int b) =>
    srgbEncodeFast(linearLuminanceOfBytes(r, g, b));

/// 256-bin R, G, B and display-luma histogram with clip counts.
class Histogram {
  const Histogram._({
    required this.red,
    required this.green,
    required this.blue,
    required this.luma,
    required this.pixelCount,
    required this.highClipped,
    required this.lowClipped,
  });

  factory Histogram.compute(RgbaBuffer img) {
    final r = Int32List(256), g = Int32List(256), b = Int32List(256);
    final l = Int32List(256);
    var high = 0, low = 0;
    final d = img.data;
    for (var i = 0; i < d.length; i += 4) {
      final pr = d[i], pg = d[i + 1], pb = d[i + 2];
      r[pr]++;
      g[pg]++;
      b[pb]++;
      l[(displayLuma(pr, pg, pb) * 255).round()]++;
      if (pr == 255 || pg == 255 || pb == 255) high++;
      if (pr == 0 && pg == 0 && pb == 0) low++;
    }
    List<int> frozen(Int32List x) => List<int>.unmodifiable(x);
    return Histogram._(
      red: frozen(r),
      green: frozen(g),
      blue: frozen(b),
      luma: frozen(l),
      pixelCount: img.pixelCount,
      highClipped: high,
      lowClipped: low,
    );
  }

  /// Fraction of pixels at which the UI lights the clipping triangles.
  static const double kClipWarningFraction = 0.001;

  final List<int> red;
  final List<int> green;
  final List<int> blue;

  /// Display luma `encode(Y)` quantized to 0..255.
  final List<int> luma;
  final int pixelCount;

  /// Pixels with at least one channel at 255.
  final int highClipped;

  /// Pixels with every channel at 0.
  final int lowClipped;

  double get highClipFraction => pixelCount == 0 ? 0 : highClipped / pixelCount;
  double get lowClipFraction => pixelCount == 0 ? 0 : lowClipped / pixelCount;
  bool get showHighClipWarning => highClipFraction >= kClipWarningFraction;
  bool get showLowClipWarning => lowClipFraction >= kClipWarningFraction;

  /// Luma percentile [q] (0..1) as 0..1, interpolating between ranks.
  double lumaPercentile(double q) {
    if (pixelCount == 0) return 0;
    final pos = q.clamp(0, 1) * (pixelCount - 1);
    final lo = pos.floor();
    final hi = math.min(lo + 1, pixelCount - 1);
    final t = pos - lo;
    return (_valueAtRank(lo) * (1 - t) + _valueAtRank(hi) * t) / 255;
  }

  int _valueAtRank(int rank) {
    var cum = 0;
    for (var k = 0; k < 256; k++) {
      cum += luma[k];
      if (rank < cum) return k;
    }
    return 255;
  }
}
