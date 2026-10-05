/// Manual Tuning Pen for skin (Evoto P0): user strokes that add skin the
/// AI missed or take skin away (beard, hair over the face, jewellery,
/// glasses frames, tattoos to keep).
///
/// The pen acts on the finished, pen-free maps (`applySkinPen`): it only
/// rewrites the region atlases, so a stroke costs milliseconds instead of
/// a re-analysis, and preview and export apply it identically.
///
/// * Strokes are rasterized like `MaskRasterizer` brush strokes: strength
///   `S = flow × max over segments of falloff(d / r, hardness)` with
///   `falloff = 1 − smoothstep(hardness, 1, t)`; paint
///   `skin += (cap − skin)·S`, erase `skin *= 1 − S`, in stroke order.
///   Paint never adds skin over the eyes, mouth or lips (`cap`).
/// * Erase also protects everything skin-derived: blush and wrinkle fill
///   fade by the erase coverage, clipped-shine fills and blemish candidates
///   centred in an erase stroke are not healed.
/// * Only texels inside a face's work rect and owned by it change; painted
///   texels get that face's id, so its effects apply there. Strokes
///   outside every face change nothing.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/mask_shapes.dart';
import 'blemish_heal.dart';
import 'blemish_types.dart';
import 'face_ids.dart';
import 'filters.dart';
import 'map_rect.dart';
import 'retouch_maps.dart';

/// Spot codes reach this far (IOD) beyond a candidate's centre (largest
/// heal hole plus the low-band spill, `blemish_heal.dart`).
const double kPenSpotReachIod = 0.12;

/// [base] (pen-free maps) with [strokes] applied; [base] itself when no
/// stroke reaches a face. Only the strokes' bounding box is touched.
RetouchMaps applySkinPen(RetouchMaps base, List<BrushStroke> strokes) {
  if (strokes.isEmpty || !base.hasFaces) return base;
  final w = base.width, h = base.height;
  final box = _strokesBox(strokes, w, h);
  if (box == null) return base;
  final maxIod = base.faces.map((f) => f.iod).reduce(math.max);
  final pad = (kPenSpotReachIod * maxIod).ceil() + 2;
  final region = MapRect(
    box.x0 - pad,
    box.y0 - pad,
    box.w + 2 * pad,
    box.h + 2 * pad,
  ).intersect(MapRect(0, 0, w, h));
  Uint8List? ra, rb;
  Int8List? owner;
  for (final f in base.faces) {
    final sub = f.rect.intersect(region);
    if (sub.isEmpty) continue;
    Float32List? skin, keep, cap;
    for (final s in strokes) {
      final st = penStrokeStrength(s, sub, w, h);
      if (st == null) continue;
      ra ??= Uint8List.fromList(base.regionA);
      rb ??= Uint8List.fromList(base.regionB);
      owner ??= faceOwners(
        base.faces,
        w,
        h,
        within: MapRect(
          region.x0 - 1,
          region.y0 - 1,
          region.w + 2,
          region.h + 2,
        ),
      );
      skin ??= _plane(base.regionA, sub, w, 0, 0);
      keep ??= Float32List(sub.area);
      cap ??= _paintCap(base, sub, w);
      for (var i = 0; i < st.length; i++) {
        final k = st[i];
        if (k == 0) continue;
        if (s.erase) {
          skin[i] *= 1 - k;
          keep[i] += (1 - keep[i]) * k;
        } else {
          final room = cap[i] - skin[i];
          if (room > 0) skin[i] += room * k;
          keep[i] *= 1 - k;
        }
      }
    }
    if (skin == null || keep == null || owner == null) continue;
    _write(base, f, sub, w, h, owner, skin, keep, ra!, rb!);
    assignFaceIds(f, w, owner, base.deltaB, ra, rb, within: sub);
  }
  if (ra == null || rb == null) return base;
  return base.withRegions(ra, rb);
}

/// Grid-pixel bounding box of every stroke (brush radius included), or
/// null when no stroke can paint.
MapRect? _strokesBox(List<BrushStroke> strokes, int w, int h) {
  var x0 = double.infinity, y0 = double.infinity;
  var x1 = -double.infinity, y1 = -double.infinity;
  final le = math.max(w, h);
  for (final s in strokes) {
    if (s.points.isEmpty || s.flow <= 0) continue;
    final r = s.radius * le + 1;
    for (final p in s.points) {
      x0 = math.min(x0, p.$1 * w - r);
      y0 = math.min(y0, p.$2 * h - r);
      x1 = math.max(x1, p.$1 * w + r);
      y1 = math.max(y1, p.$2 * h + r);
    }
  }
  if (x1 < x0) return null;
  final a = x0.floor(), b = y0.floor();
  final box = MapRect(a, b, x1.ceil() - a, y1.ceil() - b);
  final clipped = box.intersect(MapRect(0, 0, w, h));
  return clipped.isEmpty ? null : clipped;
}

/// Stroke strength (0..1, flow included) over [rect] of a `w × h` grid, or
/// null when the stroke misses [rect]. Matches `MaskRasterizer`'s brush.
Float32List? penStrokeStrength(BrushStroke s, MapRect rect, int w, int h) {
  if (s.points.isEmpty || s.flow <= 0) return null;
  final r = s.radius * math.max(w, h);
  final pts = [for (final p in s.points) (p.$1 * w, p.$2 * h)];
  final segs = pts.length == 1
      ? [(pts[0], pts[0])]
      : [for (var i = 0; i + 1 < pts.length; i++) (pts[i], pts[i + 1])];
  Float32List? out;
  for (final ((ax, ay), (bx, by)) in segs) {
    final x0 = math.max(rect.x0, (math.min(ax, bx) - r).floor());
    final x1 = math.min(rect.x1 - 1, (math.max(ax, bx) + r).ceil());
    final y0 = math.max(rect.y0, (math.min(ay, by) - r).floor());
    final y1 = math.min(rect.y1 - 1, (math.max(ay, by) + r).ceil());
    if (x1 < x0 || y1 < y0) continue;
    out ??= Float32List(rect.area);
    final dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final px = x + 0.5 - ax, py = y + 0.5 - ay;
        var t = len2 == 0 ? 0.0 : (px * dx + py * dy) / len2;
        t = t < 0 ? 0 : (t > 1 ? 1 : t);
        final ex = px - t * dx, ey = py - t * dy;
        final v =
            _falloff(math.sqrt(ex * ex + ey * ey) / r, s.hardness) * s.flow;
        final i = rect.index(x, y);
        if (v > out[i]) out[i] = v;
      }
    }
  }
  return out;
}

double _falloff(double t, double hardness) {
  if (t >= 1) return 0;
  if (t <= hardness) return 1;
  return 1 - smoothstep(hardness, 1, t);
}

/// One channel of an atlas tile over [rect], 0..1.
Float32List _plane(Uint8List atlas, MapRect rect, int w, int tile, int c) {
  final out = Float32List(rect.area);
  for (var y = rect.y0; y < rect.y1; y++) {
    var i = (y - rect.y0) * rect.w;
    var o = (y * 2 * w + tile * w + rect.x0) * 4 + c;
    for (var x = rect.x0; x < rect.x1; x++, i++, o += 4) {
      out[i] = atlas[o] / 255;
    }
  }
  return out;
}

/// Paint can raise skin up to `1 − max(mouth, sclera, iris, lips)`.
Float32List _paintCap(RetouchMaps m, MapRect rect, int w) {
  final mouth = _plane(m.regionA, rect, w, 1, 0);
  final sclera = _plane(m.regionA, rect, w, 1, 1);
  final iris = _plane(m.regionA, rect, w, 1, 2);
  final lips = _plane(m.regionB, rect, w, 0, 0);
  for (var i = 0; i < mouth.length; i++) {
    mouth[i] =
        1 - math.max(math.max(mouth[i], sclera[i]), math.max(iris[i], lips[i]));
  }
  return mouth;
}

int _byte(double v) => v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255 + 0.5).toInt());

void _write(
  RetouchMaps base,
  RetouchFaceInfo f,
  MapRect rect,
  int w,
  int h,
  Int8List owner,
  Float32List skin,
  Float32List keep,
  Uint8List ra,
  Uint8List rb,
) {
  // Blemish candidates centred in an erase stroke are not healed.
  final erased = <BlemishCandidate>[];
  final others = <BlemishCandidate>[];
  for (final b in base.blemishes) {
    if (b.slot != f.slot) continue;
    final cx = (b.u * w).floor(), cy = (b.v * h).floor();
    final inRect =
        cx >= rect.x0 && cx < rect.x1 && cy >= rect.y0 && cy < rect.y1;
    (inRect && keep[rect.index(cx, cy)] > 0.5 ? erased : others).add(b);
  }
  final sigma1 = kHealSpillIod * f.iod;
  for (var y = rect.y0; y < rect.y1; y++) {
    var i = (y - rect.y0) * rect.w;
    for (var x = rect.x0; x < rect.x1; x++, i++) {
      if (owner[y * w + x] != f.slot) continue;
      final left = (y * 2 * w + x) * 4, right = left + w * 4;
      ra[left] = _byte(skin[i]);
      final k = keep[i];
      if (k > 0) {
        rb[left + 1] = _byte(rb[left + 1] / 255 * (1 - k));
        rb[left + 2] = _byte(rb[left + 2] / 255 * (1 - k));
        if (rb[left + 2] == 0) rb[right + 2] = 0;
        if (k > 0.5 && rb[right + 1] == kShineCoreCode) rb[right + 1] = 0;
      }
      if (erased.isEmpty || rb[right + 1] == 0) continue;
      if (rb[right + 1] == kShineCoreCode) continue;
      // The spot code here belongs to the nearest candidate centre.
      final px = x + 0.5, py = y + 0.5;
      BlemishCandidate? nearest;
      var best = double.infinity, fromErased = false;
      for (final group in [erased, others]) {
        for (final b in group) {
          final dx = px - b.u * w, dy = py - b.v * h;
          final d = dx * dx + dy * dy;
          if (d < best) {
            best = d;
            nearest = b;
            fromErased = identical(group, erased);
          }
        }
      }
      if (nearest == null || !fromErased) continue;
      final reach =
          nearest.radiusIod * f.iod * kHealHoleScale +
          kSpotCodeSpillSigmas * sigma1;
      if (math.sqrt(best) <= reach + 1) rb[right + 1] = 0;
    }
  }
}
