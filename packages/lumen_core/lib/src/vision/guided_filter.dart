import 'dart:math' as math;
import 'dart:typed_data';

import '../render/rgba_buffer.dart';

/// Mean over the (2r+1)² window around each pixel, clipped at the borders
/// (the divisor is the number of pixels actually inside). O(1) per pixel:
/// two separable running-sum passes.
Float32List boxMean(Float32List src, int width, int height, int radius) {
  if (src.length != width * height) {
    throw ArgumentError('plane ${src.length} != $width x $height');
  }
  if (radius <= 0) return Float32List.fromList(src);
  final tmp = Float32List(src.length);
  final out = Float32List(src.length);
  final line = Float64List(math.max(width, height) + 1);
  // Rows.
  for (var y = 0; y < height; y++) {
    final o = y * width;
    line[0] = 0;
    for (var x = 0; x < width; x++) {
      line[x + 1] = line[x] + src[o + x];
    }
    for (var x = 0; x < width; x++) {
      final a = math.max(0, x - radius), b = math.min(width, x + radius + 1);
      tmp[o + x] = (line[b] - line[a]) / (b - a);
    }
  }
  // Columns.
  for (var x = 0; x < width; x++) {
    line[0] = 0;
    for (var y = 0; y < height; y++) {
      line[y + 1] = line[y] + tmp[y * width + x];
    }
    for (var y = 0; y < height; y++) {
      final a = math.max(0, y - radius), b = math.min(height, y + radius + 1);
      out[y * width + x] = (line[b] - line[a]) / (b - a);
    }
  }
  return out;
}

/// Guided filter (He, Sun & Tang 2010) of each plane in [inputs] with the
/// grey [guide] (same size), window radius [radius] and regularization
/// [eps]. Edges of the guide are kept, flat guide regions are smoothed;
/// it is linear in each input, so filter(1 − p) = 1 − filter(p).
List<Float32List> guidedFilterPlanes(
  Float32List guide,
  List<Float32List> inputs,
  int width,
  int height, {
  required int radius,
  required double eps,
}) {
  final n = width * height;
  if (guide.length != n) throw ArgumentError('guide is not $width x $height');
  final sq = Float32List(n);
  for (var i = 0; i < n; i++) {
    sq[i] = guide[i] * guide[i];
  }
  final meanI = boxMean(guide, width, height, radius);
  final varI = boxMean(sq, width, height, radius);
  for (var i = 0; i < n; i++) {
    varI[i] = math.max(0, varI[i] - meanI[i] * meanI[i]);
  }
  return [
    for (final p in inputs)
      _filterOne(guide, p, meanI, varI, width, height, radius, eps),
  ];
}

Float32List _filterOne(
  Float32List guide,
  Float32List p,
  Float32List meanI,
  Float32List varI,
  int w,
  int h,
  int r,
  double eps,
) {
  final n = w * h;
  if (p.length != n) throw ArgumentError('input is not $w x $h');
  final ip = Float32List(n);
  for (var i = 0; i < n; i++) {
    ip[i] = guide[i] * p[i];
  }
  final meanP = boxMean(p, w, h, r);
  final meanIp = boxMean(ip, w, h, r);
  final a = Float32List(n), b = Float32List(n);
  for (var i = 0; i < n; i++) {
    final ai = (meanIp[i] - meanI[i] * meanP[i]) / (varI[i] + eps);
    a[i] = ai;
    b[i] = meanP[i] - ai * meanI[i];
  }
  final ma = boxMean(a, w, h, r), mb = boxMean(b, w, h, r);
  final q = Float32List(n);
  for (var i = 0; i < n; i++) {
    q[i] = ma[i] * guide[i] + mb[i];
  }
  return q;
}

/// Rec. 709 luma of [src]'s 8-bit codes (0..1), area-averaged onto a
/// [width]×[height] grid that spans the whole image (the guide for mask
/// edge refinement; gamma-encoded luma follows visible edges).
Float32List lumaPlane(
  RgbaBuffer src, {
  required int width,
  required int height,
}) {
  final cols = _spans(width, src.width);
  final rows = _spans(height, src.height);
  final out = Float32List(width * height);
  final d = src.data;
  for (var j = 0; j < height; j++) {
    final (y0, y1) = rows[j];
    for (var i = 0; i < width; i++) {
      final (x0, x1) = cols[i];
      var sum = 0.0;
      for (var y = y0; y <= y1; y++) {
        var p = (y * src.width + x0) * 4;
        for (var x = x0; x <= x1; x++, p += 4) {
          sum += 0.2126 * d[p] + 0.7152 * d[p + 1] + 0.0722 * d[p + 2];
        }
      }
      out[j * width + i] = sum / ((y1 - y0 + 1) * (x1 - x0 + 1) * 255);
    }
  }
  return out;
}

/// Source pixel span (inclusive) whose centres fall in each output cell.
List<(int, int)> _spans(int n, int len) => List.generate(n, (i) {
  final s0 = i * len / n, s1 = (i + 1) * len / n;
  var a = (s0 - 0.5).ceil(), b = (s1 - 0.5).ceil() - 1;
  if (b < a) a = b = ((s0 + s1) / 2).floor();
  a = a.clamp(0, len - 1);
  return (a, b.clamp(a, len - 1));
}, growable: false);
