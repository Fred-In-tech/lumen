/// Hole masks for object removal: brush strokes → a binary mask stored
/// only over the region the strokes touch (a 24 MP source never needs a
/// full-size buffer).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/mask_shapes.dart';
import 'distance_transform.dart';
import 'pixel_box.dart';

/// Dilation applied to a removal mask before a model or PatchMatch fill
/// (§5.2.1): 6 px plus 1 % of the source long edge.
int holeDilationPx(int srcWidth, int srcHeight) =>
    (6 + 0.01 * math.max(srcWidth, srcHeight)).round();

/// One 8-connected hole region.
typedef HoleComponent = ({PixelBox bbox, int pixelCount});

/// A binary hole mask over a [srcWidth]×[srcHeight] source. [data] covers
/// only [rect] (row-major, `rect.width` per row): non-zero = hole. Pixels
/// outside [rect] are never holes.
class HoleMask {
  HoleMask(this.srcWidth, this.srcHeight, this.rect, this.data) {
    if (data.length != rect.area) {
      throw ArgumentError('hole data ${data.length} != ${rect.area}');
    }
  }

  factory HoleMask.empty(int srcWidth, int srcHeight) =>
      HoleMask(srcWidth, srcHeight, PixelBox.zero, Uint8List(0));

  /// From explicit hole pixels (outside the source → ignored).
  factory HoleMask.fromPixels(
    int srcWidth,
    int srcHeight,
    Iterable<(int, int)> pixels,
  ) {
    final src = PixelBox(0, 0, srcWidth, srcHeight);
    final inside = [
      for (final p in pixels)
        if (src.contains(p.$1, p.$2)) p,
    ];
    if (inside.isEmpty) return HoleMask.empty(srcWidth, srcHeight);
    var r = PixelBox(inside.first.$1, inside.first.$2, 1, 1);
    for (final p in inside) {
      r = r.union(PixelBox(p.$1, p.$2, 1, 1));
    }
    final data = Uint8List(r.area);
    for (final p in inside) {
      data[(p.$2 - r.y) * r.width + p.$1 - r.x] = 255;
    }
    return HoleMask(srcWidth, srcHeight, r, data);
  }

  /// From a full-source-size mask (non-zero = hole).
  factory HoleMask.fromFull(int srcWidth, int srcHeight, Uint8List full) {
    if (full.length != srcWidth * srcHeight) {
      throw ArgumentError('mask ${full.length} != $srcWidth x $srcHeight');
    }
    final m = HoleMask(
      srcWidth,
      srcHeight,
      PixelBox(0, 0, srcWidth, srcHeight),
      Uint8List.fromList([for (final v in full) v != 0 ? 255 : 0]),
    );
    return m.cropped(m.bbox);
  }

  final int srcWidth;
  final int srcHeight;
  final PixelBox rect;
  final Uint8List data;

  bool isHole(int x, int y) =>
      rect.contains(x, y) && data[(y - rect.y) * rect.width + x - rect.x] != 0;

  /// Number of hole pixels.
  late final int holeCount = data.where((v) => v != 0).length;

  bool get isEmpty => holeCount == 0;

  /// Tight bounding box of the hole pixels (source px; empty when none).
  late final PixelBox bbox = _bbox();

  PixelBox _bbox() {
    var x0 = 1 << 30, y0 = 1 << 30, x1 = -1, y1 = -1;
    for (var y = 0; y < rect.height; y++) {
      final row = y * rect.width;
      for (var x = 0; x < rect.width; x++) {
        if (data[row + x] == 0) continue;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
    if (x1 < 0) return PixelBox.zero;
    return PixelBox.fromLTRB(
      rect.x + x0,
      rect.y + y0,
      rect.x + x1 + 1,
      rect.y + y1 + 1,
    );
  }

  /// The same holes stored over [r] (clipped to the source).
  HoleMask cropped(PixelBox r) {
    final c = r.intersect(PixelBox(0, 0, srcWidth, srcHeight));
    final out = Uint8List(c.area);
    for (var y = 0; y < c.height; y++) {
      for (var x = 0; x < c.width; x++) {
        if (isHole(c.x + x, c.y + y)) out[y * c.width + x] = 255;
      }
    }
    return HoleMask(srcWidth, srcHeight, c, out);
  }

  /// Grown by a Euclidean disc of [radius] px (clipped to the source).
  HoleMask dilated(int radius) {
    if (radius <= 0 || isEmpty) return this;
    final r = bbox
        .inflate(radius)
        .intersect(PixelBox(0, 0, srcWidth, srcHeight));
    final seeds = cropped(r).data;
    final d2 = squaredDistanceTransform(seeds, r.width, r.height);
    final lim = radius * radius;
    final out = Uint8List(r.area);
    for (var i = 0; i < out.length; i++) {
      if (d2[i] <= lim) out[i] = 255;
    }
    return HoleMask(srcWidth, srcHeight, r, out);
  }

  /// 8-connected hole regions in raster order of their first pixel.
  List<HoleComponent> components() {
    final w = rect.width, h = rect.height;
    final seen = Uint8List(rect.area);
    final queue = Int32List(rect.area);
    final out = <HoleComponent>[];
    for (var start = 0; start < data.length; start++) {
      if (data[start] == 0 || seen[start] != 0) continue;
      var head = 0, tail = 0, count = 0;
      var x0 = w, y0 = h, x1 = -1, y1 = -1;
      queue[tail++] = start;
      seen[start] = 1;
      while (head < tail) {
        final i = queue[head++];
        final x = i % w, y = i ~/ w;
        count++;
        x0 = math.min(x0, x);
        x1 = math.max(x1, x);
        y0 = math.min(y0, y);
        y1 = math.max(y1, y);
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= w) continue;
            final j = ny * w + nx;
            if (data[j] == 0 || seen[j] != 0) continue;
            seen[j] = 1;
            queue[tail++] = j;
          }
        }
      }
      out.add((
        bbox: PixelBox.fromLTRB(
          rect.x + x0,
          rect.y + y0,
          rect.x + x1 + 1,
          rect.y + y1 + 1,
        ),
        pixelCount: count,
      ));
    }
    return out;
  }

  /// MI-GAN style keep mask for [crop] (source px, may extend past the
  /// source): 255 = keep, 0 = hole. Pixels outside the source mirror
  /// (reflect-101) like the padded image, so a hole near a border is also
  /// a hole in its mirror image.
  Uint8List keepMaskFor(PixelBox crop) {
    final out = Uint8List(crop.area);
    for (var y = 0; y < crop.height; y++) {
      final sy = mirrorIndex(crop.y + y, srcHeight);
      for (var x = 0; x < crop.width; x++) {
        final sx = mirrorIndex(crop.x + x, srcWidth);
        out[y * crop.width + x] = isHole(sx, sy) ? 0 : 255;
      }
    }
    return out;
  }
}

/// Rasterizes removal [strokes] (normalized uv, radius as a fraction of the
/// long edge; same falloff and add/erase rules as `MaskRasterizer`) at
/// [srcWidth]×[srcHeight]. A pixel is a hole when its 8-bit coverage is
/// ≥ [thresholdByte] (128 = half coverage, so add and erase are symmetric).
HoleMask rasterizeHoleMask(
  List<BrushStroke> strokes,
  int srcWidth,
  int srcHeight, {
  int thresholdByte = 128,
}) {
  final src = PixelBox(0, 0, srcWidth, srcHeight);
  var roi = PixelBox.zero;
  for (final s in strokes) {
    if (!s.erase && s.flow > 0) roi = roi.union(_strokeBox(s, src));
  }
  roi = roi.intersect(src);
  if (roi.isEmpty) return HoleMask.empty(srcWidth, srcHeight);
  final c = Float32List(roi.area);
  for (final s in strokes) {
    _paint(s, c, roi, srcWidth, srcHeight);
  }
  final out = Uint8List(roi.area);
  for (var i = 0; i < c.length; i++) {
    if ((c[i].clamp(0.0, 1.0) * 255).round() >= thresholdByte) out[i] = 255;
  }
  return HoleMask(srcWidth, srcHeight, roi, out).cropped(roi);
}

PixelBox _strokeBox(BrushStroke s, PixelBox src) {
  if (s.points.isEmpty) return PixelBox.zero;
  final le = math.max(src.width, src.height).toDouble();
  final r = s.radius * le;
  var x0 = double.infinity, y0 = double.infinity;
  var x1 = double.negativeInfinity, y1 = double.negativeInfinity;
  for (final p in s.points) {
    x0 = math.min(x0, p.$1 * src.width);
    x1 = math.max(x1, p.$1 * src.width);
    y0 = math.min(y0, p.$2 * src.height);
    y1 = math.max(y1, p.$2 * src.height);
  }
  return PixelBox.fromLTRB(
    (x0 - r).floor(),
    (y0 - r).floor(),
    (x1 + r).ceil() + 1,
    (y1 + r).ceil() + 1,
  ).intersect(src);
}

/// Mirrors `MaskRasterizer._stroke` restricted to [roi].
void _paint(BrushStroke s, Float32List c, PixelBox roi, int w, int h) {
  if (s.points.isEmpty || s.flow <= 0) return;
  final box = _strokeBox(s, PixelBox(0, 0, w, h)).intersect(roi);
  if (box.isEmpty) return;
  final le = math.max(w, h).toDouble();
  final r = s.radius * le;
  final strength = Float32List(box.area);
  final pts = [for (final p in s.points) (p.$1 * w, p.$2 * h)];
  final segs = pts.length == 1
      ? [(pts[0], pts[0])]
      : [for (var i = 0; i + 1 < pts.length; i++) (pts[i], pts[i + 1])];
  for (final ((ax, ay), (bx, by)) in segs) {
    final x0 = math.max(box.x, (math.min(ax, bx) - r).floor());
    final x1 = math.min(box.right - 1, (math.max(ax, bx) + r).ceil());
    final y0 = math.max(box.y, (math.min(ay, by) - r).floor());
    final y1 = math.min(box.bottom - 1, (math.max(ay, by) + r).ceil());
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final px = x + 0.5 - ax, py = y + 0.5 - ay;
        final t = len2 == 0
            ? 0.0
            : ((px * dx + py * dy) / len2).clamp(0.0, 1.0);
        final ex = px - t * dx, ey = py - t * dy;
        final v = _falloff(math.sqrt(ex * ex + ey * ey) / r, s.hardness);
        final i = (y - box.y) * box.width + x - box.x;
        if (v > strength[i]) strength[i] = v;
      }
    }
  }
  for (var y = 0; y < box.height; y++) {
    for (var x = 0; x < box.width; x++) {
      final k = strength[y * box.width + x] * s.flow;
      if (k == 0) continue;
      final i = (box.y + y - roi.y) * roi.width + box.x + x - roi.x;
      c[i] = s.erase ? c[i] * (1 - k) : c[i] + (1 - c[i]) * k;
    }
  }
}

double _falloff(double t, double hardness) {
  if (t >= 1) return 0;
  if (t <= hardness) return 1;
  final u = ((t - hardness) / (1 - hardness)).clamp(0.0, 1.0);
  return 1 - u * u * (3 - 2 * u);
}
