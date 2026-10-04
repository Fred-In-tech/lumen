/// Separable CPU filters on row-major float planes (`w × h`, clamp-to-edge).
///
/// All functions return new lists; inputs are never modified.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Box filter of radius [r] (width `2r + 1`) in both directions.
Float32List boxBlur(Float32List src, int w, int h, int r) {
  if (r <= 0) return Float32List.fromList(src);
  return _boxPass(_boxPass(src, w, h, r, true), w, h, r, false);
}

Float32List _boxPass(Float32List src, int w, int h, int r, bool horiz) {
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

/// Box radii of three passes approximating a Gaussian of [sigma]
/// (Kovesi's "boxes for Gauss": mixed widths match the variance).
List<int> gaussBoxRadii(double sigma) {
  if (sigma < 0.5) return const [0, 0, 0];
  const n = 3;
  final wIdeal = math.sqrt(12 * sigma * sigma / n + 1);
  var wl = wIdeal.floor();
  if (wl.isEven) wl--;
  final wu = wl + 2;
  final m =
      ((12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4))
          .round();
  return [for (var i = 0; i < n; i++) ((i < m ? wl : wu) - 1) ~/ 2];
}

/// Below this sigma, [gaussianBlur] uses an exact sampled kernel.
const double kExactGaussianBelow = 1.2;

/// Gaussian blur of [sigma] pixels: an exact separable kernel for small
/// sigmas, three box passes (O(1) per pixel) otherwise.
Float32List gaussianBlur(Float32List src, int w, int h, double sigma) {
  if (sigma < kExactGaussianBelow) return _exactGaussian(src, w, h, sigma);
  var out = src;
  var copied = false;
  for (final r in gaussBoxRadii(sigma)) {
    if (r <= 0) continue;
    out = boxBlur(out, w, h, r);
    copied = true;
  }
  return copied ? out : Float32List.fromList(src);
}

Float32List _exactGaussian(Float32List src, int w, int h, double sigma) {
  if (sigma < 0.2) return Float32List.fromList(src);
  final r = (3 * sigma).ceil();
  final k = Float64List(2 * r + 1);
  var sum = 0.0;
  for (var i = -r; i <= r; i++) {
    sum += k[i + r] = math.exp(-i * i / (2 * sigma * sigma));
  }
  for (var i = 0; i < k.length; i++) {
    k[i] /= sum;
  }
  Float32List pass(Float32List s, bool horiz) {
    final out = Float32List(s.length);
    final len = horiz ? w : h, lines = horiz ? h : w;
    final step = horiz ? 1 : w, last = len - 1;
    for (var line = 0; line < lines; line++) {
      final base = horiz ? line * w : line;
      for (var i = 0; i < len; i++) {
        var acc = 0.0;
        for (var j = -r; j <= r; j++) {
          final t = i + j;
          acc +=
              k[j + r] * s[base + (t < 0 ? 0 : (t > last ? last : t)) * step];
        }
        out[base + i * step] = acc;
      }
    }
    return out;
  }

  return pass(pass(src, true), false);
}

/// Separable min ([isMax] false) or max filter with a square of radius [r].
Float32List rankFilter(Float32List src, int w, int h, int r, bool isMax) {
  if (r <= 0) return Float32List.fromList(src);
  Float32List pass(Float32List s, bool horiz) {
    final out = Float32List(s.length);
    final len = horiz ? w : h, lines = horiz ? h : w;
    final step = horiz ? 1 : w;
    for (var line = 0; line < lines; line++) {
      final base = horiz ? line * w : line;
      for (var i = 0; i < len; i++) {
        final lo = math.max(0, i - r), hi = math.min(len - 1, i + r);
        var m = s[base + lo * step];
        for (var j = lo + 1; j <= hi; j++) {
          final v = s[base + j * step];
          if (isMax ? v > m : v < m) m = v;
        }
        out[base + i * step] = m;
      }
    }
    return out;
  }

  return pass(pass(src, true), false);
}

/// Guided filter (He et al. 2010) of each plane in [inputs] with [guide],
/// box radius [r] and regularization [eps]. Returns one plane per input.
List<Float32List> guidedFilter(
  Float32List guide,
  List<Float32List> inputs,
  int w,
  int h,
  int r,
  double eps,
) {
  final n = guide.length;
  final sq = Float32List(n);
  for (var i = 0; i < n; i++) {
    sq[i] = guide[i] * guide[i];
  }
  final meanI = boxBlur(guide, w, h, r);
  final varI = boxBlur(sq, w, h, r);
  for (var i = 0; i < n; i++) {
    varI[i] = math.max(0.0, varI[i] - meanI[i] * meanI[i]);
  }
  final out = <Float32List>[];
  for (final p in inputs) {
    final ip = Float32List(n);
    for (var i = 0; i < n; i++) {
      ip[i] = guide[i] * p[i];
    }
    final meanP = boxBlur(p, w, h, r);
    final meanIp = boxBlur(ip, w, h, r);
    final a = Float32List(n), b = Float32List(n);
    for (var i = 0; i < n; i++) {
      final cov = meanIp[i] - meanI[i] * meanP[i];
      a[i] = cov / (varI[i] + eps);
      b[i] = meanP[i] - a[i] * meanI[i];
    }
    final ma = boxBlur(a, w, h, r), mb = boxBlur(b, w, h, r);
    final q = Float32List(n);
    for (var i = 0; i < n; i++) {
      q[i] = ma[i] * guide[i] + mb[i];
    }
    out.add(q);
  }
  return out;
}

/// Binary dilation of [mask] (> 0.5 is "in") by a square of radius [r].
Float32List dilate(Float32List mask, int w, int h, int r) =>
    _threshold(boxBlur(_binary(mask), w, h, r), 1e-4);

/// Binary erosion of [mask] (> 0.5 is "in") by a square of radius [r].
Float32List erode(Float32List mask, int w, int h, int r) =>
    _threshold(boxBlur(_binary(mask), w, h, r), 1 - 1e-4);

Float32List _binary(Float32List m) {
  final out = Float32List(m.length);
  for (var i = 0; i < m.length; i++) {
    if (m[i] > 0.5) out[i] = 1;
  }
  return out;
}

Float32List _threshold(Float32List m, double t) {
  final out = Float32List(m.length);
  for (var i = 0; i < m.length; i++) {
    if (m[i] >= t) out[i] = 1;
  }
  return out;
}

/// Element-wise `a·(1 − b)` clamped to 0..1.
Float32List subtractMask(Float32List a, Float32List b) {
  final out = Float32List(a.length);
  for (var i = 0; i < a.length; i++) {
    final v = a[i] * (1 - b[i]);
    out[i] = v < 0 ? 0 : (v > 1 ? 1 : v);
  }
  return out;
}

/// Element-wise `a + b`.
Float32List addPlanes(Float32List a, Float32List b) {
  final out = Float32List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = a[i] + b[i];
  }
  return out;
}

/// Element-wise `a − b`.
Float32List subtractPlanes(Float32List a, Float32List b) {
  final out = Float32List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = a[i] - b[i];
  }
  return out;
}

/// Element-wise maximum of [planes] (all the same length).
Float32List maxOf(List<Float32List> planes) {
  final out = Float32List.fromList(planes.first);
  for (final p in planes.skip(1)) {
    for (var i = 0; i < out.length; i++) {
      if (p[i] > out[i]) out[i] = p[i];
    }
  }
  return out;
}

/// Element-wise product of [planes].
Float32List productOf(List<Float32List> planes) {
  final out = Float32List.fromList(planes.first);
  for (final p in planes.skip(1)) {
    for (var i = 0; i < out.length; i++) {
      out[i] *= p[i];
    }
  }
  return out;
}

/// GLSL `smoothstep` (no `num.clamp`: it is called per pixel).
double smoothstep(double e0, double e1, double x) {
  final t = (x - e0) / (e1 - e0);
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  return t * t * (3 - 2 * t);
}

/// GLSL `clamp(x, 0, 1)`.
double clamp01(double x) => x <= 0 ? 0 : (x >= 1 ? 1 : x);
