/// Push-pull membrane fill (Gortler et al. 1996) with a harmonic
/// (Laplace) relaxation at every pyramid level, and its frequency-separated
/// variant (§3.3): membrane low band + fine band from the ring or the
/// original.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'distance_transform.dart';
import 'float_image.dart';
import 'pixel_box.dart';

/// Where the fine (high-frequency) band inside the hole comes from.
enum FineBand {
  /// From a donor offset chosen on the ring around the hole (removal).
  ring,

  /// The original fine band (blemish healing: pores continue through).
  original,

  /// None: a smooth membrane only.
  none,
}

/// Fills hole pixels (`hole[i] != 0`) with a smooth membrane interpolated
/// from the known pixels; known pixels are returned unchanged. With
/// [relax] each level gets [sweeps] SOR sweeps of the Laplace equation
/// (exact for linear ramps); without it this is plain push-pull.
FloatImage pushPullFill(
  FloatImage img,
  Uint8List hole, {
  bool relax = true,
  int sweeps = 24,
}) {
  final ch = img.channels;
  final v0 = Float32List.fromList(img.data);
  final w0 = Float32List(img.pixelCount);
  var known = 0;
  for (var i = 0; i < w0.length; i++) {
    if (hole[i] == 0) {
      w0[i] = 1;
      known++;
    } else {
      for (var c = 0; c < ch; c++) {
        v0[i * ch + c] = 0;
      }
    }
  }
  if (known == 0 || known == w0.length) return img.copy();
  final levels = <_Level>[_Level(img.width, img.height, v0, w0)];
  while (levels.last.hasGaps && levels.last.w * levels.last.h > 1) {
    levels.add(levels.last.pull(ch));
  }
  for (var k = levels.length - 2; k >= 0; k--) {
    final fine = levels[k];
    fine.push(levels[k + 1], ch);
    if (relax) fine.relax(ch, sweeps);
  }
  return FloatImage(img.width, img.height, channels: ch, data: levels[0].v);
}

class _Level {
  _Level(this.w, this.h, this.v, this.wt);

  final int w;
  final int h;
  final Float32List v;
  final Float32List wt;

  bool get hasGaps => wt.any((x) => x < 1);

  _Level pull(int ch) {
    final nw = (w + 1) >> 1, nh = (h + 1) >> 1;
    final nv = Float32List(nw * nh * ch), nwt = Float32List(nw * nh);
    final acc = Float64List(ch);
    for (var y = 0; y < nh; y++) {
      for (var x = 0; x < nw; x++) {
        var sw = 0.0;
        acc.fillRange(0, ch, 0);
        for (var dy = 0; dy < 2; dy++) {
          final fy = 2 * y + dy;
          if (fy >= h) continue;
          for (var dx = 0; dx < 2; dx++) {
            final fx = 2 * x + dx;
            if (fx >= w) continue;
            final i = fy * w + fx;
            sw += wt[i];
            for (var c = 0; c < ch; c++) {
              acc[c] += wt[i] * v[i * ch + c];
            }
          }
        }
        final o = y * nw + x;
        nwt[o] = math.min(1, sw);
        if (sw > 0) {
          for (var c = 0; c < ch; c++) {
            nv[o * ch + c] = acc[c] / sw;
          }
        }
      }
    }
    return _Level(nw, nh, nv, nwt);
  }

  /// Blends the filled [coarse] level into pixels whose weight is < 1.
  void push(_Level coarse, int ch) {
    for (var y = 0; y < h; y++) {
      final cy = (y + 0.5) / 2 - 0.5;
      final y0 = cy.floor(), fy = cy - y0;
      final ya = y0.clamp(0, coarse.h - 1),
          yb = (y0 + 1).clamp(0, coarse.h - 1);
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final a = wt[i];
        if (a >= 1) continue;
        final cx = (x + 0.5) / 2 - 0.5;
        final x0 = cx.floor(), fx = cx - x0;
        final xa = x0.clamp(0, coarse.w - 1);
        final xb = (x0 + 1).clamp(0, coarse.w - 1);
        for (var c = 0; c < ch; c++) {
          final top =
              coarse.v[(ya * coarse.w + xa) * ch + c] * (1 - fx) +
              coarse.v[(ya * coarse.w + xb) * ch + c] * fx;
          final bot =
              coarse.v[(yb * coarse.w + xa) * ch + c] * (1 - fx) +
              coarse.v[(yb * coarse.w + xb) * ch + c] * fx;
          final up = top + (bot - top) * fy;
          v[i * ch + c] = a * v[i * ch + c] + (1 - a) * up;
        }
      }
    }
  }

  /// Symmetric SOR on the Laplace equation over pixels with weight < 1.
  void relax(int ch, int sweeps) {
    final free = <int>[
      for (var i = 0; i < wt.length; i++)
        if (wt[i] < 1) i,
    ];
    const omega = 1.6;
    for (var s = 0; s < sweeps; s++) {
      final forward = s.isEven;
      for (var k = 0; k < free.length; k++) {
        final i = free[forward ? k : free.length - 1 - k];
        final x = i % w, y = i ~/ w;
        var n = 0;
        for (var c = 0; c < ch; c++) {
          var sum = 0.0;
          n = 0;
          if (x > 0) {
            sum += v[(i - 1) * ch + c];
            n++;
          }
          if (x < w - 1) {
            sum += v[(i + 1) * ch + c];
            n++;
          }
          if (y > 0) {
            sum += v[(i - w) * ch + c];
            n++;
          }
          if (y < h - 1) {
            sum += v[(i + w) * ch + c];
            n++;
          }
          final cur = v[i * ch + c];
          v[i * ch + c] = cur + omega * (sum / n - cur);
        }
      }
    }
  }
}

/// Membrane low band + a fine band chosen by [fine] (§3.3). [sigma] is the
/// Gaussian split scale in px. With [FineBand.ring] the fine band is copied
/// from [donorOffset] (or [findDonorOffset] when null).
FloatImage frequencySeparatedFill(
  FloatImage img,
  Uint8List hole, {
  double sigma = 1.5,
  FineBand fine = FineBand.ring,
  (int, int)? donorOffset,
}) {
  final b = maskBounds(hole, img.width, img.height);
  if (b == null) return img.copy();
  // Only the hole, its blur support and the donor search reach matter.
  final donorReach = donorOffset == null
      ? 0
      : math.max(donorOffset.$1.abs(), donorOffset.$2.abs());
  final reach =
      3 * (b.maxSide + 2 * _ring) + _ring + (3 * sigma).ceil() + 2 + donorReach;
  final win = b.inflate(reach).intersect(PixelBox(0, 0, img.width, img.height));
  if (win.area == img.pixelCount) {
    return _freqSep(img, hole, sigma, fine, donorOffset);
  }
  final sub = img.window(win.x, win.y, win.width, win.height);
  final subHole = Uint8List(win.area);
  for (var y = 0; y < win.height; y++) {
    final s = (win.y + y) * img.width + win.x;
    subHole.setRange(y * win.width, (y + 1) * win.width, hole, s);
  }
  final filled = _freqSep(sub, subHole, sigma, fine, donorOffset);
  final out = img.copy();
  final ch = img.channels;
  for (var y = 0; y < win.height; y++) {
    for (var x = 0; x < win.width; x++) {
      if (subHole[y * win.width + x] == 0) continue;
      final o = ((win.y + y) * img.width + win.x + x) * ch;
      for (var c = 0; c < ch; c++) {
        out.data[o + c] = filled.data[(y * win.width + x) * ch + c];
      }
    }
  }
  return out;
}

const int _ring = 4;

FloatImage _freqSep(
  FloatImage img,
  Uint8List hole,
  double sigma,
  FineBand fine,
  (int, int)? donorOffset,
) {
  final ch = img.channels, w = img.width;
  final known = Float32List(img.pixelCount);
  for (var i = 0; i < known.length; i++) {
    known[i] = hole[i] == 0 ? 1 : 0;
  }
  final low = pushPullFill(gaussianBlur(img, sigma, weights: known), hole);
  final out = img.copy();
  final donor = fine == FineBand.ring
      ? donorOffset ?? findDonorOffset(img, hole)
      : null;
  final lowAll = fine == FineBand.original ? gaussianBlur(img, sigma) : null;
  final lowKnown = donor != null
      ? gaussianBlur(img, sigma, weights: known)
      : null;
  for (var i = 0; i < hole.length; i++) {
    if (hole[i] == 0) continue;
    final x = i % w, y = i ~/ w;
    var j = -1;
    if (donor != null) {
      final sx = x + donor.$1, sy = y + donor.$2;
      if (sx >= 0 && sy >= 0 && sx < w && sy < img.height) j = sy * w + sx;
    }
    for (var c = 0; c < ch; c++) {
      final hi = switch (fine) {
        FineBand.original => img.data[i * ch + c] - lowAll!.data[i * ch + c],
        FineBand.ring when j >= 0 =>
          img.data[j * ch + c] - lowKnown!.data[j * ch + c],
        _ => 0.0,
      };
      out.data[i * ch + c] = low.data[i * ch + c] + hi;
    }
  }
  return out;
}

/// The offset (dx, dy) whose shifted ring best matches the ring around the
/// hole (min mean SSD over all channels), such that the shifted hole and
/// ring are fully known and inside the image. Null when there is no hole
/// or no valid donor. Deterministic (raster scan order breaks ties).
(int, int)? findDonorOffset(
  FloatImage img,
  Uint8List hole, {
  int ring = _ring,
}) {
  final w = img.width, h = img.height, ch = img.channels;
  final full = maskBounds(hole, w, h);
  if (full == null) return null;
  final region = full.inflate(ring).intersect(PixelBox(0, 0, w, h));
  final seeds = Uint8List(region.area);
  for (var y = 0; y < region.height; y++) {
    for (var x = 0; x < region.width; x++) {
      seeds[y * region.width + x] = hole[(region.y + y) * w + region.x + x];
    }
  }
  final d2 = squaredDistanceTransform(seeds, region.width, region.height);
  final ringPx = <int>[];
  for (var i = 0; i < seeds.length; i++) {
    if (seeds[i] == 0 && d2[i] <= ring * ring) {
      ringPx.add(
        (region.y + i ~/ region.width) * w + region.x + i % region.width,
      );
    }
  }
  if (ringPx.isEmpty) return null;
  final stride = math.max(1, ringPx.length ~/ 1500);
  final sat = _holeSat(hole, w, h);
  bool valid(int dx, int dy) {
    final r = region.translate(dx, dy);
    if (r.x < 0 || r.y < 0 || r.right > w || r.bottom > h) return false;
    return _satSum(sat, w, r) == 0;
  }

  double score(int dx, int dy) {
    var s = 0.0;
    var n = 0;
    for (var k = 0; k < ringPx.length; k += stride) {
      final i = ringPx[k];
      final j = i + dy * w + dx;
      for (var c = 0; c < ch; c++) {
        final d = img.data[j * ch + c] - img.data[i * ch + c];
        s += d * d;
      }
      n++;
    }
    return s / n;
  }

  final side = region.maxSide;
  final step = math.max(1, side ~/ 4);
  (int, int)? best;
  var bestScore = double.infinity;
  void consider(int dx, int dy) {
    if ((dx == 0 && dy == 0) || !valid(dx, dy)) return;
    final s = score(dx, dy);
    if (s < bestScore) {
      bestScore = s;
      best = (dx, dy);
    }
  }

  final reach = (3 * side / step).ceil();
  for (var ky = -reach; ky <= reach; ky++) {
    for (var kx = -reach; kx <= reach; kx++) {
      consider(kx * step, ky * step);
    }
  }
  final coarse = best;
  if (coarse == null) return null;
  for (var dy = coarse.$2 - step; dy <= coarse.$2 + step; dy++) {
    for (var dx = coarse.$1 - step; dx <= coarse.$1 + step; dx++) {
      consider(dx, dy);
    }
  }
  return best;
}

/// Tight bbox of `mask[i] != 0` on a [w]×[h] grid, or null when empty.
PixelBox? maskBounds(Uint8List mask, int w, int h) {
  var x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mask[y * w + x] == 0) continue;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  return x1 < 0 ? null : PixelBox.fromLTRB(x0, y0, x1 + 1, y1 + 1);
}

/// Summed-area table of hole pixels, size (w+1)×(h+1).
Int32List _holeSat(Uint8List hole, int w, int h) {
  final sat = Int32List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0;
    for (var x = 0; x < w; x++) {
      if (hole[y * w + x] != 0) row++;
      sat[(y + 1) * (w + 1) + x + 1] = sat[y * (w + 1) + x + 1] + row;
    }
  }
  return sat;
}

int _satSum(Int32List sat, int w, PixelBox r) {
  final s = w + 1;
  return sat[r.bottom * s + r.right] -
      sat[r.y * s + r.right] -
      sat[r.bottom * s + r.x] +
      sat[r.y * s + r.x];
}
