import 'dart:math' as math;
import 'dart:typed_data';

import '../color/luminance.dart';
import '../color/rgb.dart';
import '../color/srgb.dart';
import 'engine_constants.dart';
import 'float_buffer.dart';
import 'lut_packing.dart';
import 'rgba_buffer.dart';

/// Normalized log luma: `(log2(max(Y, 2^-14)) + 14) / 16`, clamped to 0..1.
double normalizedLogLuma(double y) {
  final l = math.log(math.max(y, kLumaFloor)) / math.ln2;
  return ((l + kLogLumaOffset) / kLogLumaRange).clamp(0.0, 1.0);
}

/// One bilinear sample of the aux maps (see [AuxMaps.sample]).
typedef AuxSample = ({double baseMid, double dark, double meanA, double meanB});

/// Spatial analysis maps, computed once per photo on the CPU from a
/// ≤ 512-px proxy of the unedited source, in source-uv space.
///
/// Two packed RGBA8888 planes (always opaque) feed `develop.frag`:
/// * [auxA]: RG = clarity base (Gaussian of normalized log luma, 16-bit),
///   B = smoothed dark channel (8-bit, sRGB-encoded).
/// * [auxB]: RG = guided-filter `meanB` (16-bit), B = `meanA` (8-bit).
///
/// The shadows/highlights base at full resolution is `meanA·I + meanB`
/// (guided upsampling). Both CPU and GPU read these exact quantized values.
class AuxMaps {
  AuxMaps._(this.width, this.height, this.auxA, this.auxB, this.airlight);

  /// A 1×1 neutral map for renders without spatial ops.
  factory AuxMaps.neutral() => AuxMaps._(
    1,
    1,
    Uint8List.fromList([0, 0, 0, 255]),
    Uint8List.fromList([0, 0, 0, 255]),
    const Rgb(1, 1, 1),
  );

  /// Computes the maps from an analysis-size image (see [proxy]).
  factory AuxMaps.compute(RgbaBuffer img) {
    final n = img.width * img.height;
    final lumaN = Float32List(n);
    final darkPix = Float32List(n);
    for (var i = 0; i < n; i++) {
      final o = i * 4;
      final r = img.data[o], g = img.data[o + 1], b = img.data[o + 2];
      lumaN[i] = normalizedLogLuma(
        relativeLuminance(
          kSrgbByteToLinear[r],
          kSrgbByteToLinear[g],
          kSrgbByteToLinear[b],
        ),
      );
      darkPix[i] = math.min(r, math.min(g, b)) / 255;
    }
    return AuxMaps._build(
      img.width,
      img.height,
      lumaN,
      darkPix,
      (i) => kSrgbByteToLinear[img.data[i]],
    );
  }

  /// [compute] for a float source (see [proxyFloat]): log luma keeps
  /// highlights above display white (up to 4×, the range of
  /// [normalizedLogLuma]), so the guided base and the clarity base
  /// represent them. Equal to [compute] for 8-bit-equivalent input.
  factory AuxMaps.computeFloat(FloatBuffer img) {
    final n = img.width * img.height;
    final lumaN = Float32List(n);
    final darkPix = Float32List(n);
    final d = img.data;
    for (var i = 0; i < n; i++) {
      final o = i * 4;
      lumaN[i] = normalizedLogLuma(
        relativeLuminance(
          _floatToLinear(d[o]),
          _floatToLinear(d[o + 1]),
          _floatToLinear(d[o + 2]),
        ),
      );
      darkPix[i] = math.min(d[o], math.min(d[o + 1], d[o + 2])).clamp(0.0, 1.0);
    }
    // The airlight stays inside display range, like the 8-bit one.
    return AuxMaps._build(
      img.width,
      img.height,
      lumaN,
      darkPix,
      (i) => math.min(_floatToLinear(d[i]), 1.0),
    );
  }

  /// Extended-sRGB float → linear, exact for byte-equivalent values.
  static double _floatToLinear(double e) {
    if (e <= 0) return 0;
    if (e <= 1) {
      final k = e * 255, r = k.roundToDouble();
      if ((k - r).abs() < 1e-5) return kSrgbByteToLinear[r.toInt()];
    }
    return srgbToLinear(e);
  }

  /// The maps from normalized log luma and the dark-channel input (min of
  /// the encoded channels, 0..1); [linear] reads channel value `i` of the
  /// interleaved RGBA image in linear light (airlight).
  factory AuxMaps._build(
    int w,
    int h,
    Float32List lumaN,
    Float32List darkPix,
    double Function(int i) linear,
  ) {
    final n = w * h;
    final longEdge = math.max(w, h);
    // Clarity base: Gaussian (3 box passes) with sigma = 1.2 % long edge.
    final sigma = 0.012 * longEdge;
    final rb = math.max(
      1,
      ((math.sqrt(1 + 4 * sigma * sigma) - 1) / 2).round(),
    );
    final baseMid = _box(_box(_box(lumaN, w, h, rb), w, h, rb), w, h, rb);
    // Self-guided filter on normalized log luma.
    final rg = math.max(1, (0.032 * longEdge).round());
    final sq = Float32List(n);
    for (var i = 0; i < n; i++) {
      sq[i] = lumaN[i] * lumaN[i];
    }
    final meanI = _box(lumaN, w, h, rg);
    final meanII = _box(sq, w, h, rg);
    final a = Float32List(n), b = Float32List(n);
    for (var i = 0; i < n; i++) {
      final v = math.max(0.0, meanII[i] - meanI[i] * meanI[i]);
      a[i] = v / (v + _guidedEps);
      b[i] = meanI[i] - a[i] * meanI[i];
    }
    final meanA = _box(a, w, h, rg);
    final meanB = _box(b, w, h, rg);
    // Dark channel: 15×15 min filter, then a smoothing blur.
    final dark = _minFilter(darkPix, w, h, 7);
    final darkSmooth = _box(_box(dark, w, h, 4), w, h, 4);
    return AuxMaps._(
      w,
      h,
      packPlane16(baseMid, blue: _bytes(darkSmooth)),
      packPlane16(meanB, blue: _bytes(meanA)),
      _airlight(linear, dark),
    );
  }

  /// Area-averaged downscale of [src] to [longEdge] (never upscales).
  static RgbaBuffer proxy(RgbaBuffer src, {int longEdge = kAnalysisLongEdge}) {
    final le = math.max(src.width, src.height);
    if (le <= longEdge) return src;
    final scale = longEdge / le;
    final w = math.max(1, (src.width * scale).round());
    final h = math.max(1, (src.height * scale).round());
    final out = RgbaBuffer(w, h);
    for (var y = 0; y < h; y++) {
      final y0 = y * src.height ~/ h;
      final y1 = math.max(y0 + 1, (y + 1) * src.height ~/ h);
      for (var x = 0; x < w; x++) {
        final x0 = x * src.width ~/ w;
        final x1 = math.max(x0 + 1, (x + 1) * src.width ~/ w);
        var r = 0, g = 0, b = 0;
        for (var sy = y0; sy < y1; sy++) {
          var o = src.offset(x0, sy);
          for (var sx = x0; sx < x1; sx++, o += 4) {
            r += src.data[o];
            g += src.data[o + 1];
            b += src.data[o + 2];
          }
        }
        final c = (x1 - x0) * (y1 - y0);
        out.setPixel(x, y, (r / c).round(), (g / c).round(), (b / c).round());
      }
    }
    return out;
  }

  /// [proxy] for a float source: area average of the encoded values.
  static FloatBuffer proxyFloat(
    FloatBuffer src, {
    int longEdge = kAnalysisLongEdge,
  }) {
    final le = math.max(src.width, src.height);
    if (le <= longEdge) return src;
    final scale = longEdge / le;
    final w = math.max(1, (src.width * scale).round());
    final h = math.max(1, (src.height * scale).round());
    final out = FloatBuffer(w, h);
    for (var y = 0; y < h; y++) {
      final y0 = y * src.height ~/ h;
      final y1 = math.max(y0 + 1, (y + 1) * src.height ~/ h);
      for (var x = 0; x < w; x++) {
        final x0 = x * src.width ~/ w;
        final x1 = math.max(x0 + 1, (x + 1) * src.width ~/ w);
        var r = 0.0, g = 0.0, b = 0.0;
        for (var sy = y0; sy < y1; sy++) {
          var o = src.offset(x0, sy);
          for (var sx = x0; sx < x1; sx++, o += 4) {
            r += src.data[o];
            g += src.data[o + 1];
            b += src.data[o + 2];
          }
        }
        final c = (x1 - x0) * (y1 - y0);
        out.setPixel(x, y, r / c, g / c, b / c);
      }
    }
    return out;
  }

  static const double _guidedEps = 0.01;

  final int width;
  final int height;
  final Uint8List auxA;
  final Uint8List auxB;

  /// Dehaze airlight, linear sRGB.
  final Rgb airlight;

  /// Manual bilinear sample at texel centers, unpacking every tap before
  /// interpolating: identical to `sampleAux()` in `develop.frag`.
  AuxSample sample(double u, double v) {
    final px = u * width - 0.5, py = v * height - 0.5;
    final fx0 = px.floorToDouble(), fy0 = py.floorToDouble();
    final fx = px - fx0, fy = py - fy0;
    final x0 = fx0.toInt().clamp(0, width - 1);
    final x1 = (fx0.toInt() + 1).clamp(0, width - 1);
    final y0 = fy0.toInt().clamp(0, height - 1);
    final y1 = (fy0.toInt() + 1).clamp(0, height - 1);
    final o00 = (y0 * width + x0) * 4, o10 = (y0 * width + x1) * 4;
    final o01 = (y1 * width + x0) * 4, o11 = (y1 * width + x1) * 4;
    final a = auxA, b = auxB;
    const k = 1 / 65535;
    final w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy);
    final w01 = (1 - fx) * fy, w11 = fx * fy;
    return (
      baseMid:
          ((a[o00] * 256 + a[o00 + 1]) * w00 +
              (a[o10] * 256 + a[o10 + 1]) * w10 +
              (a[o01] * 256 + a[o01 + 1]) * w01 +
              (a[o11] * 256 + a[o11 + 1]) * w11) *
          k,
      dark:
          (a[o00 + 2] * w00 +
              a[o10 + 2] * w10 +
              a[o01 + 2] * w01 +
              a[o11 + 2] * w11) /
          255,
      meanA:
          (b[o00 + 2] * w00 +
              b[o10 + 2] * w10 +
              b[o01 + 2] * w01 +
              b[o11 + 2] * w11) /
          255,
      meanB:
          ((b[o00] * 256 + b[o00 + 1]) * w00 +
              (b[o10] * 256 + b[o10 + 1]) * w10 +
              (b[o01] * 256 + b[o01 + 1]) * w01 +
              (b[o11] * 256 + b[o11 + 1]) * w11) *
          k,
    );
  }

  static List<int> _bytes(Float32List v) => Uint8List.fromList([
    for (final x in v) (x.clamp(0.0, 1.0) * 255).round(),
  ]);

  /// Mean linear color of the top 0.1 % dark-channel pixels.
  static Rgb _airlight(double Function(int i) linear, Float32List dark) {
    final hist = List<int>.filled(256, 0);
    for (final d in dark) {
      hist[(d * 255).round()]++;
    }
    final want = math.max(1, (dark.length * 0.001).ceil());
    var thr = 255, acc = 0;
    while (thr > 0 && acc + hist[thr] < want) {
      acc += hist[thr];
      thr--;
    }
    var r = 0.0, g = 0.0, b = 0.0, c = 0;
    for (var i = 0; i < dark.length; i++) {
      if ((dark[i] * 255).round() < thr) continue;
      final o = i * 4;
      r += linear(o);
      g += linear(o + 1);
      b += linear(o + 2);
      c++;
    }
    double fl(double x) => math.max(x / c, 0.05);
    return Rgb(fl(r), fl(g), fl(b));
  }

  /// Separable box filter of radius [r] with clamp-to-edge.
  static Float32List _box(Float32List src, int w, int h, int r) =>
      _pass(_pass(src, w, h, r, true), w, h, r, false);

  static Float32List _pass(Float32List src, int w, int h, int r, bool horiz) {
    final out = Float32List(src.length);
    final len = horiz ? w : h, lines = horiz ? h : w;
    final step = horiz ? 1 : w;
    final inv = 1 / (2 * r + 1);
    final last = len - 1;
    for (var line = 0; line < lines; line++) {
      final base = horiz ? line * w : line;
      var sum = 0.0;
      for (var i = -r; i <= r; i++) {
        sum += src[base + (i < 0 ? 0 : (i > last ? last : i)) * step];
      }
      for (var i = 0; i < len; i++) {
        out[base + i * step] = sum * inv;
        final ia = i + r + 1, ib = i - r;
        sum +=
            src[base + (ia > last ? last : ia) * step] -
            src[base + (ib < 0 ? 0 : ib) * step];
      }
    }
    return out;
  }

  /// Separable min filter of radius [r] with clamp-to-edge.
  static Float32List _minFilter(Float32List src, int w, int h, int r) {
    Float32List pass(Float32List s, bool horiz) {
      final out = Float32List(s.length);
      final len = horiz ? w : h, lines = horiz ? h : w;
      final step = horiz ? 1 : w;
      for (var line = 0; line < lines; line++) {
        final base = horiz ? line * w : line;
        for (var i = 0; i < len; i++) {
          var m = 1.0;
          final lo = math.max(0, i - r), hi = math.min(len - 1, i + r);
          for (var j = lo; j <= hi; j++) {
            final v = s[base + j * step];
            if (v < m) m = v;
          }
          out[base + i * step] = m;
        }
      }
      return out;
    }

    return pass(pass(src, true), false);
  }
}
