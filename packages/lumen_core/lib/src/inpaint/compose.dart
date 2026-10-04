/// Compositing heal patches onto a source at any resolution (§5.5).
library;

import 'dart:math' as math;

import '../render/rgba_buffer.dart';
import 'heal_op.dart';
import 'pixel_box.dart';

/// Resolves a heal op's decoded patch (bbox-sized RGBA, straight alpha).
/// The app stores PNGs under the photo's asset folder; core only sees
/// buffers. Return null when the patch is missing (the op is skipped and
/// the app should regenerate it from source + mask + engine).
abstract interface class PatchLookup {
  RgbaBuffer? patchFor(HealOp op);
}

/// A [PatchLookup] over already-decoded patches keyed by [HealOp.patch].
class MapPatchLookup implements PatchLookup {
  const MapPatchLookup(this.patches);

  final Map<String, RgbaBuffer> patches;

  @override
  RgbaBuffer? patchFor(HealOp op) => patches[op.patch];
}

/// [source] with every visible op's patch drawn in order. A patch lands on
/// its bbox scaled from the op's source size to [source]'s size, so the
/// same ops serve the preview and the full-resolution export. Returns a
/// new buffer; pixels no patch covers are bit-identical.
RgbaBuffer composeHealed(
  RgbaBuffer source,
  List<HealOp> ops,
  PatchLookup lookup,
) {
  final out = source.copy();
  for (final op in ops) {
    if (op.hidden || !op.isRenderable) continue;
    final p = lookup.patchFor(op);
    if (p == null || p.width == 0 || p.height == 0) continue;
    final sx = out.width / op.srcWidth, sy = out.height / op.srcHeight;
    if (sx == 1 &&
        sy == 1 &&
        p.width == op.bbox.width &&
        p.height == op.bbox.height) {
      _blendExact(out, p, op.bbox);
    } else {
      _blendScaled(out, p, op.bbox, sx, sy);
    }
  }
  return out;
}

void _blendExact(RgbaBuffer out, RgbaBuffer p, PixelBox box) {
  final clip = box.intersect(PixelBox(0, 0, out.width, out.height));
  for (var y = clip.y; y < clip.bottom; y++) {
    for (var x = clip.x; x < clip.right; x++) {
      final s = ((y - box.y) * p.width + x - box.x) * 4;
      final a = p.data[s + 3];
      if (a == 0) continue;
      final o = out.offset(x, y);
      for (var c = 0; c < 3; c++) {
        out.data[o + c] =
            (p.data[s + c] * a + out.data[o + c] * (255 - a) + 127) ~/ 255;
      }
    }
  }
}

typedef _Taps = List<(int, double)>;

/// Box-filtered (area-weighted, premultiplied) resampling of [p] onto the
/// scaled bbox, then `out·(1 − A) + P`.
void _blendScaled(
  RgbaBuffer out,
  RgbaBuffer p,
  PixelBox box,
  double sx,
  double sy,
) {
  final tx = _taps(box.x, box.width, p.width, sx, out.width);
  final ty = _taps(box.y, box.height, p.height, sy, out.height);
  for (final (dy, rows) in ty) {
    for (final (dx, cols) in tx) {
      var a = 0.0, r = 0.0, g = 0.0, b = 0.0;
      for (final (py, wy) in rows) {
        for (final (px, wx) in cols) {
          final s = (py * p.width + px) * 4;
          final w = wy * wx * p.data[s + 3] / 255;
          a += w;
          r += w * p.data[s];
          g += w * p.data[s + 1];
          b += w * p.data[s + 2];
        }
      }
      if (a <= 0) continue;
      final o = out.offset(dx, dy);
      out.data[o] = (out.data[o] * (1 - a) + r).round().clamp(0, 255);
      out.data[o + 1] = (out.data[o + 1] * (1 - a) + g).round().clamp(0, 255);
      out.data[o + 2] = (out.data[o + 2] * (1 - a) + b).round().clamp(0, 255);
    }
  }
}

/// Per destination pixel along one axis: the patch pixels its footprint
/// overlaps, weighted by overlap / footprint (edges get partial cover).
List<(int, _Taps)> _taps(int start, int len, int n, double scale, int size) {
  final k = n / len; // patch px per source px
  final d0 = math.max(0, (start * scale).floor());
  final d1 = math.min(size, ((start + len) * scale).ceil());
  final foot = k / scale;
  return [
    for (var d = d0; d < d1; d++)
      (
        d,
        () {
          final u0 = (d / scale - start) * k, u1 = u0 + foot;
          return <(int, double)>[
            for (
              var j = math.max(0, u0.floor());
              j < math.min(n, u1.ceil());
              j++
            )
              (j, (math.min(u1, j + 1.0) - math.max(u0, j.toDouble())) / foot),
          ];
        }(),
      ),
  ];
}

/// Fraction of the image covered by the union of the visible, renderable
/// ops' boxes (each normalized by its own source size).
double healedAreaFraction(List<HealOp> ops) {
  final rects = [
    for (final o in ops)
      if (!o.hidden && !o.bbox.isEmpty && o.srcWidth > 0 && o.srcHeight > 0)
        (
          o.bbox.x / o.srcWidth,
          o.bbox.y / o.srcHeight,
          o.bbox.right / o.srcWidth,
          o.bbox.bottom / o.srcHeight,
        ),
  ];
  if (rects.isEmpty) return 0;
  final xs = {
    for (final r in rects) ...[r.$1, r.$3],
  }.toList()..sort();
  final ys = {
    for (final r in rects) ...[r.$2, r.$4],
  }.toList()..sort();
  var area = 0.0;
  for (var i = 0; i + 1 < xs.length; i++) {
    for (var j = 0; j + 1 < ys.length; j++) {
      final cx = (xs[i] + xs[i + 1]) / 2, cy = (ys[j] + ys[j + 1]) / 2;
      final covered = rects.any(
        (r) => cx > r.$1 && cx < r.$3 && cy > r.$2 && cy < r.$4,
      );
      if (covered) area += (xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j]);
    }
  }
  return area.clamp(0.0, 1.0);
}

/// Whether AuxMaps must be recomputed on the healed source: the healed
/// area exceeds [threshold] (0.5 %) of the image, so the shadows/
/// highlights base and dehaze stats would otherwise "remember" the removed
/// object (§5.5).
bool needsAuxRecompute(List<HealOp> ops, {double threshold = 0.005}) =>
    healedAreaFraction(ops) > threshold;
