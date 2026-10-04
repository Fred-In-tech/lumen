/// Small image helpers for the backdrop builder (CPU, deterministic).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../color/srgb.dart';
import '../render/rgba_buffer.dart';
import '../vision/guided_filter.dart';

/// Three box passes of radius [r] (≈ a Gaussian with σ ≈ r), clipped at the
/// borders.
Float32List blur3(Float32List p, int w, int h, int r) {
  if (r <= 0) return Float32List.fromList(p);
  return boxMean(boxMean(boxMean(p, w, h, r), w, h, r), w, h, r);
}

/// Linear-light planes (r, g, b) of an RGBA buffer.
(Float32List, Float32List, Float32List) linearPlanes(RgbaBuffer img) {
  final n = img.width * img.height;
  final r = Float32List(n), g = Float32List(n), b = Float32List(n);
  final lut = kSrgbByteToLinear, d = img.data;
  for (var i = 0; i < n; i++) {
    r[i] = lut[d[4 * i]];
    g[i] = lut[d[4 * i + 1]];
    b[i] = lut[d[4 * i + 2]];
  }
  return (r, g, b);
}

/// One RGBA8 texture.
typedef ByteTexture = ({int width, int height, Uint8List rgba});

/// Linear values where the sRGB byte steps up: byte k+1 starts at
/// `srgbToLinear((k + 0.5) / 255)`.
final Float64List _byteSteps = Float64List.fromList([
  for (var k = 0; k < 255; k++) srgbToLinear((k + 0.5) / 255),
]);

/// `round(linearToSrgb(v) · 255)` by binary search (no `pow`).
int linearToByte(double v) {
  var lo = 0, hi = 255; // answer in [lo, hi]
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (v >= _byteSteps[mid]) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Linear planes → sRGB RGBA8 bytes (A = 255).
Uint8List encodePlanes(Float32List r, Float32List g, Float32List b) {
  final out = Uint8List(r.length * 4);
  for (var i = 0; i < r.length; i++) {
    out[4 * i] = linearToByte(r[i]);
    out[4 * i + 1] = linearToByte(g[i]);
    out[4 * i + 2] = linearToByte(b[i]);
    out[4 * i + 3] = 255;
  }
  return out;
}

/// Push-pull fill (Gortler et al.): pixels with weight [w] = 1 keep their
/// colour, pixels with 0 get a smooth estimate from the weighted pyramid.
(Float32List, Float32List, Float32List) pushPullFill(
  Float32List r,
  Float32List g,
  Float32List b,
  Float32List w,
  int width,
  int height,
) {
  final levels = <_Level>[_Level(width, height, r, g, b, w)];
  while (levels.last.w > 1 || levels.last.h > 1) {
    levels.add(levels.last.down());
  }
  var coarse = levels.last;
  for (var k = levels.length - 2; k >= 0; k--) {
    coarse = levels[k].fillFrom(coarse);
  }
  return (coarse.c0, coarse.c1, coarse.c2);
}

class _Level {
  _Level(this.w, this.h, this.c0, this.c1, this.c2, this.wt);

  final int w;
  final int h;
  final Float32List c0;
  final Float32List c1;
  final Float32List c2;
  final Float32List wt;

  _Level down() {
    final nw = (w + 1) ~/ 2, nh = (h + 1) ~/ 2, n = nw * nh;
    final o0 = Float32List(n), o1 = Float32List(n), o2 = Float32List(n);
    final ow = Float32List(n);
    for (var y = 0; y < nh; y++) {
      for (var x = 0; x < nw; x++) {
        var sw = 0.0, s0 = 0.0, s1 = 0.0, s2 = 0.0;
        for (var dy = 0; dy < 2; dy++) {
          for (var dx = 0; dx < 2; dx++) {
            final fx = 2 * x + dx, fy = 2 * y + dy;
            if (fx >= w || fy >= h) continue;
            final i = fy * w + fx, q = wt[i];
            sw += q;
            s0 += c0[i] * q;
            s1 += c1[i] * q;
            s2 += c2[i] * q;
          }
        }
        final o = y * nw + x;
        if (sw > 0) {
          o0[o] = s0 / sw;
          o1[o] = s1 / sw;
          o2[o] = s2 / sw;
        }
        ow[o] = math.min(1, sw);
      }
    }
    return _Level(nw, nh, o0, o1, o2, ow);
  }

  /// This level with weight < 1 pixels completed from [c] (coarser, final).
  _Level fillFrom(_Level c) {
    final n = w * h;
    final f0 = Float32List(n), f1 = Float32List(n), f2 = Float32List(n);
    for (var y = 0; y < h; y++) {
      final cy = ((y + 0.5) / 2 - 0.5).clamp(0.0, c.h - 1.0);
      final y0 = cy.floor(), y1 = math.min(y0 + 1, c.h - 1), fy = cy - y0;
      for (var x = 0; x < w; x++) {
        final cx = ((x + 0.5) / 2 - 0.5).clamp(0.0, c.w - 1.0);
        final x0 = cx.floor(), x1 = math.min(x0 + 1, c.w - 1), fx = cx - x0;
        double bl(Float32List p) {
          final top =
              p[y0 * c.w + x0] + (p[y0 * c.w + x1] - p[y0 * c.w + x0]) * fx;
          final bot =
              p[y1 * c.w + x0] + (p[y1 * c.w + x1] - p[y1 * c.w + x0]) * fx;
          return top + (bot - top) * fy;
        }

        final i = y * w + x, q = math.min(1.0, wt[i]);
        f0[i] = q * c0[i] + (1 - q) * bl(c.c0);
        f1[i] = q * c1[i] + (1 - q) * bl(c.c1);
        f2[i] = q * c2[i] + (1 - q) * bl(c.c2);
      }
    }
    return _Level(w, h, f0, f1, f2, Float32List(n)..fillRange(0, n, 1));
  }
}

/// Bilinear sample (texel centres, clamp to edge) of RGB bytes of a
/// [w]×[h] RGBA texture whose rows are [stride] texels wide, in byte units
/// (0..255), into `out[0..2]`. Mirrors the shaders' manual 4-tap sampler.
void sampleBytes(
  Uint8List tex,
  int w,
  int h,
  double u,
  double v,
  List<double> out,
) {
  final px = u * w - 0.5, py = v * h - 0.5;
  final fx0 = px.floorToDouble(), fy0 = py.floorToDouble();
  final fx = px - fx0, fy = py - fy0;
  final ix = fx0.toInt(), iy = fy0.toInt();
  final xa = ix < 0 ? 0 : (ix >= w ? w - 1 : ix);
  final xb = ix + 1 < 0 ? 0 : (ix + 1 >= w ? w - 1 : ix + 1);
  final ya = iy < 0 ? 0 : (iy >= h ? h - 1 : iy);
  final yb = iy + 1 < 0 ? 0 : (iy + 1 >= h ? h - 1 : iy + 1);
  final o00 = (ya * w + xa) * 4, o10 = (ya * w + xb) * 4;
  final o01 = (yb * w + xa) * 4, o11 = (yb * w + xb) * 4;
  for (var c = 0; c < 3; c++) {
    final top = tex[o00 + c] + (tex[o10 + c] - tex[o00 + c]) * fx;
    final bot = tex[o01 + c] + (tex[o11 + c] - tex[o01 + c]) * fx;
    out[c] = top + (bot - top) * fy;
  }
}
