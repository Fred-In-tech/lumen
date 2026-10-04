/// OkLab (of linear sRGB) helpers for the retouch CPU code.
///
/// The math is `color/oklab.dart` inlined without allocation; the GPU port
/// uses `linSrgbToOklab` / `oklabToLinSrgb` from `lib/common.glsl`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../color/srgb.dart';
import '../render/rgba_buffer.dart';
import 'map_rect.dart';

double _cbrt(double x) =>
    x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

/// Linear sRGB → OkLab into `out[o..o+2]` (L, a, b).
void linearToOklab(double r, double g, double b, List<double> out, int o) {
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  out[o] = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  out[o + 1] = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  out[o + 2] = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
}

/// OkLab → linear sRGB into `out[o..o+2]` (unclamped).
void oklabToLinear(double lv, double av, double bv, List<double> out, int o) {
  final l1 = lv + 0.3963377774 * av + 0.2158037573 * bv;
  final m1 = lv - 0.1055613458 * av - 0.0638541728 * bv;
  final s1 = lv - 0.0894841775 * av - 1.2914855480 * bv;
  final l = l1 * l1 * l1, m = m1 * m1 * m1, s = s1 * s1 * s1;
  out[o] = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  out[o + 1] = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  out[o + 2] = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
}

/// Linear values where the 8-bit sRGB code steps from `k` to `k + 1`.
final Float64List _byteSteps = Float64List.fromList([
  for (var k = 0; k < 255; k++) srgbToLinear((k + 0.5) / 255),
]);

/// Linear → 8-bit sRGB code, `round(encode(v)·255)` without `pow`: a
/// binary search over the 255 code boundaries (clamps outside 0..1).
int linearToSrgbByte(double v) {
  final t = _byteSteps;
  if (!(v >= t[0])) return 0;
  if (v >= t[254]) return 255;
  var lo = 0, hi = 254; // t[lo] <= v < t[hi]
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (v >= t[mid]) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo + 1;
}

/// An interpolated sRGB byte value (0..255) → linear, like the shader's
/// `srgbDecode` of a bilinear tap (exact table for whole bytes).
double bandByteToLinear(double byteValue) {
  final k = byteValue.round();
  if (k == byteValue) return kSrgbByteToLinear[k];
  return srgbToLinear(byteValue / 255);
}

/// OkLab → 8-bit sRGB bytes `out[o..o+2]` (clamped, rounded).
void oklabToSrgbBytes(
  double l,
  double a,
  double b,
  Uint8List out,
  int o,
  Float64List scratch,
) {
  oklabToLinear(l, a, b, scratch, 0);
  out[o] = linearToSrgbByte(scratch[0]);
  out[o + 1] = linearToSrgbByte(scratch[1]);
  out[o + 2] = linearToSrgbByte(scratch[2]);
}

/// Three OkLab float planes covering [rect].
class LabPlanes {
  LabPlanes(this.rect, this.l, this.a, this.b);

  /// Converts the pixels of [img] inside [rect] to OkLab.
  factory LabPlanes.fromRgba(RgbaBuffer img, MapRect rect) {
    final n = rect.area;
    final l = Float32List(n), a = Float32List(n), b = Float32List(n);
    final tmp = Float64List(3);
    final lut = kSrgbByteToLinear;
    for (var y = rect.y0; y < rect.y1; y++) {
      var o = img.offset(rect.x0, y);
      var i = (y - rect.y0) * rect.w;
      for (var x = rect.x0; x < rect.x1; x++, o += 4, i++) {
        linearToOklab(
          lut[img.data[o]],
          lut[img.data[o + 1]],
          lut[img.data[o + 2]],
          tmp,
          0,
        );
        l[i] = tmp[0];
        a[i] = tmp[1];
        b[i] = tmp[2];
      }
    }
    return LabPlanes(rect, l, a, b);
  }

  final MapRect rect;
  final Float32List l;
  final Float32List a;
  final Float32List b;

  List<Float32List> get channels => [l, a, b];

  /// A new set with each channel transformed by [f].
  LabPlanes mapChannels(Float32List Function(Float32List c) f) =>
      LabPlanes(rect, f(l), f(a), f(b));

  /// Writes these planes as sRGB-encoded RGBA (A = 255) into the
  /// `gridW`-wide texture [tex] at this rect, where `owner[y·gridW + x]`
  /// equals [slot]. With a [seed], each channel is dithered between its
  /// two nearest codes (deterministic per texel, unbiased in linear light)
  /// so smooth bands do not contour at 8 bits.
  void writeSrgb(
    Uint8List tex,
    int gridW,
    Int8List owner,
    int slot, {
    int? seed,
  }) {
    final tmp = Float64List(3);
    for (var y = rect.y0; y < rect.y1; y++) {
      var i = (y - rect.y0) * rect.w;
      var g = y * gridW + rect.x0;
      for (var x = rect.x0; x < rect.x1; x++, i++, g++) {
        if (owner[g] != slot) continue;
        if (seed == null) {
          oklabToSrgbBytes(l[i], a[i], b[i], tex, g * 4, tmp);
          continue;
        }
        oklabToLinear(l[i], a[i], b[i], tmp, 0);
        final o = g * 4;
        tex[o] = linearToSrgbByteDithered(tmp[0], ditherAt(x, y, seed, 0));
        tex[o + 1] = linearToSrgbByteDithered(tmp[1], ditherAt(x, y, seed, 1));
        tex[o + 2] = linearToSrgbByteDithered(tmp[2], ditherAt(x, y, seed, 2));
      }
    }
  }
}

/// Dither seeds of the band textures.
const int kDitherSeedB1 = 1;
const int kDitherSeedB2 = 2;
const int kDitherSeedB3 = 3;

/// Linear value of each 8-bit sRGB code.
final Float64List _codeLinear = Float64List.fromList([
  for (var k = 0; k < 256; k++) srgbToLinear(k / 255),
]);

/// Deterministic uniform value in [0, 1) for texel `(x, y)`, [seed] and
/// [channel] (integer hash, no state).
double ditherAt(int x, int y, int seed, int channel) {
  var h =
      (x * 0x27d4eb2d) ^
      (y * 0x165667b1) ^
      (seed * 0x9e3779b9) ^
      (channel * 0x85ebca6b);
  h &= 0xffffffff;
  h ^= h >> 15;
  h = (h * 0x2c1b3c6d) & 0xffffffff;
  h ^= h >> 12;
  h = (h * 0x297a2d39) & 0xffffffff;
  h ^= h >> 15;
  return (h & 0xffffff) / 16777216.0;
}

/// Linear → 8-bit sRGB code, rounding up with probability equal to the
/// position of [v] between its two neighbouring codes (in linear light),
/// decided by [d] ∈ [0, 1). The expected decoded value equals [v].
int linearToSrgbByteDithered(double v, double d) {
  final t = _codeLinear;
  if (!(v > 0)) return 0;
  if (v >= 1) return 255;
  var lo = 0, hi = 255; // t[lo] <= v < t[hi]
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (v >= t[mid]) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final frac = (v - t[lo]) / (t[hi] - t[lo]);
  return frac > d ? hi : lo;
}
