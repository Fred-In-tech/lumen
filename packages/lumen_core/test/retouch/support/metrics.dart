/// Image metrics for the retouch tests (independent of the library's own
/// filters, so a filter bug cannot hide behind itself).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// OkLab (L, a, b) planes of [img].
({Float64List l, Float64List a, Float64List b}) labOf(RgbaBuffer img) {
  final n = img.pixelCount;
  final l = Float64List(n), a = Float64List(n), b = Float64List(n);
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    final lab = linearSrgbToOklab(
      kSrgbByteToLinear[img.data[o]],
      kSrgbByteToLinear[img.data[o + 1]],
      kSrgbByteToLinear[img.data[o + 2]],
    );
    l[i] = lab.l;
    a[i] = lab.a;
    b[i] = lab.b;
  }
  return (l: l, a: a, b: b);
}

/// Separable sampled Gaussian (clamp to edge).
Float64List blur(Float64List p, int w, int h, double sigma) {
  final r = (3 * sigma).ceil();
  final k = [
    for (var i = -r; i <= r; i++) math.exp(-i * i / (2 * sigma * sigma)),
  ];
  final s = k.reduce((x, y) => x + y);
  Float64List pass(Float64List src, bool horiz) {
    final out = Float64List(src.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var acc = 0.0;
        for (var j = -r; j <= r; j++) {
          final xx = horiz ? (x + j).clamp(0, w - 1) : x;
          final yy = horiz ? y : (y + j).clamp(0, h - 1);
          acc += k[j + r] * src[yy * w + xx];
        }
        out[y * w + x] = acc / s;
      }
    }
    return out;
  }

  return pass(pass(p, true), false);
}

/// Mean of `f(i)` over pixels where [mask] is true.
double meanWhere(int n, bool Function(int i) mask, double Function(int i) f) {
  var sum = 0.0, count = 0;
  for (var i = 0; i < n; i++) {
    if (!mask(i)) continue;
    sum += f(i);
    count++;
  }
  return count == 0 ? double.nan : sum / count;
}

/// Mean of [p] over a disc of radius [r] around `(cx, cy)` (pixels).
double discMean(Float64List p, int w, double cx, double cy, double r) =>
    _annulus(p, w, cx, cy, 0, r);

/// Mean of [p] over the annulus `r0 ≤ d ≤ r1` around `(cx, cy)`.
double ringMean(
  Float64List p,
  int w,
  double cx,
  double cy,
  double r0,
  double r1,
) => _annulus(p, w, cx, cy, r0, r1);

double _annulus(
  Float64List p,
  int w,
  double cx,
  double cy,
  double r0,
  double r1,
) {
  var sum = 0.0, n = 0;
  for (var y = (cy - r1).floor(); y <= (cy + r1).ceil(); y++) {
    for (var x = (cx - r1).floor(); x <= (cx + r1).ceil(); x++) {
      final d = math.sqrt(
        math.pow(x + 0.5 - cx, 2) + math.pow(y + 0.5 - cy, 2),
      );
      if (d < r0 || d > r1) continue;
      sum += p[y * w + x];
      n++;
    }
  }
  return sum / n;
}

/// Region weight (0..1) of [c] at pixel `(x, y)` of a `w × h` image.
double regionAt(RetouchMaps m, RetouchChannel c, int x, int y, int w, int h) =>
    m.sourceRegion(c, (x + 0.5) / w, (y + 0.5) / h) / 255;

/// Erosion of a 0/1 [mask] by a square of radius [r] (box-count based).
Uint8List erodeMask(Uint8List mask, int w, int h, int r) {
  Uint8List pass(Uint8List m, bool horiz) {
    final out = Uint8List(m.length);
    final len = horiz ? w : h, lines = horiz ? h : w;
    final step = horiz ? 1 : w;
    for (var line = 0; line < lines; line++) {
      final base = horiz ? line * w : line;
      var run = 0;
      final ok = Uint8List(len);
      for (var i = 0; i < len; i++) {
        run = m[base + i * step] == 1 ? run + 1 : 0;
        ok[i] = run;
      }
      // A pixel survives if the window [i - r, i + r] is all ones.
      for (var i = 0; i < len; i++) {
        final end = i + r;
        if (i - r < 0 || end >= len) continue;
        if (ok[end] >= 2 * r + 1) out[base + i * step] = 1;
      }
    }
    return out;
  }

  return pass(pass(mask, true), false);
}
