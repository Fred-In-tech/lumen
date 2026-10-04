/// Deterministic, pure-Dart region rasterizer (research 07 §1.4).
///
/// Every function returns a coverage plane (0..1) covering a [MapRect] of
/// the map grid. Pixel `(i, j)` covers `[i, i+1) × [j, j+1)`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'filters.dart' show clamp01;
import 'map_rect.dart';

/// Vertical supersampling factor of [rasterizePolygon] (§1.4: 4×).
const int kPolygonSupersample = 4;

/// Scanline fill of the closed polygon [poly] (even-odd rule) with
/// [ss] sub-scanlines per pixel row and exact horizontal span coverage.
Float32List rasterizePolygon(
  List<MapPoint> poly,
  MapRect rect, {
  int ss = kPolygonSupersample,
}) {
  final out = Float32List(rect.area);
  if (poly.length < 3 || rect.isEmpty) return out;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in poly) {
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final yStart = math.max(rect.y0, minY.floor());
  final yEnd = math.min(rect.y1, maxY.ceil());
  final xs = <double>[];
  final inv = 1 / ss;
  for (var y = yStart; y < yEnd; y++) {
    final row = (y - rect.y0) * rect.w;
    for (var j = 0; j < ss; j++) {
      final sy = y + (j + 0.5) * inv;
      xs.clear();
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        if ((a.y <= sy && sy < b.y) || (b.y <= sy && sy < a.y)) {
          xs.add(a.x + (sy - a.y) * (b.x - a.x) / (b.y - a.y));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        _addSpan(out, row, rect, xs[k], xs[k + 1], inv);
      }
    }
  }
  return out;
}

void _addSpan(
  Float32List out,
  int row,
  MapRect rect,
  double xa,
  double xb,
  double weight,
) {
  final a = math.max(xa, rect.x0.toDouble());
  final b = math.min(xb, rect.x1.toDouble());
  if (b <= a) return;
  final p0 = a.floor(), p1 = b.ceil();
  for (var px = p0; px < p1; px++) {
    final cover = math.min(px + 1.0, b) - math.max(px.toDouble(), a);
    if (cover > 0) out[row + px - rect.x0] += cover * weight;
  }
}

/// Anti-aliased disc of radius [r] around `(cx, cy)`.
Float32List rasterizeDisc(double cx, double cy, double r, MapRect rect) =>
    rasterizeEllipse(cx, cy, r, r, 0, rect);

/// Anti-aliased ellipse with semi-axes [ax], [ay] rotated by [angle]
/// radians (approximate signed-distance edge, about one pixel wide).
Float32List rasterizeEllipse(
  double cx,
  double cy,
  double ax,
  double ay,
  double angle,
  MapRect rect,
) {
  final out = Float32List(rect.area);
  if (ax <= 0 || ay <= 0 || rect.isEmpty) return out;
  final c = math.cos(angle), s = math.sin(angle);
  final ext = math.max(ax, ay) + 1;
  final bx = MapRect.around(cx, cy, ext, ext, 1 << 30, 1 << 30);
  final minAxis = math.min(ax, ay);
  for (var y = math.max(rect.y0, bx.y0); y < math.min(rect.y1, bx.y1); y++) {
    for (var x = math.max(rect.x0, bx.x0); x < math.min(rect.x1, bx.x1); x++) {
      final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      final u = (dx * c + dy * s) / ax, v = (-dx * s + dy * c) / ay;
      final rho = math.sqrt(u * u + v * v);
      final cover = clamp01(0.5 - (rho - 1) * minAxis);
      if (cover > 0) out[rect.index(x, y)] = cover;
    }
  }
  return out;
}

/// Distance (pixels) from each pixel centre to the open polyline [pts],
/// capped at [maxDist] (pixels farther away hold [maxDist]).
Float32List polylineDistance(List<MapPoint> pts, MapRect rect, double maxDist) {
  final out = Float32List(rect.area)..fillRange(0, rect.area, maxDist);
  if (pts.isEmpty || rect.isEmpty) return out;
  var x0 = double.infinity, y0 = double.infinity;
  var x1 = -double.infinity, y1 = -double.infinity;
  for (final p in pts) {
    x0 = math.min(x0, p.x);
    y0 = math.min(y0, p.y);
    x1 = math.max(x1, p.x);
    y1 = math.max(y1, p.y);
  }
  final ys = math.max(rect.y0, (y0 - maxDist).floor());
  final ye = math.min(rect.y1, (y1 + maxDist).ceil());
  final xs = math.max(rect.x0, (x0 - maxDist).floor());
  final xe = math.min(rect.x1, (x1 + maxDist).ceil());
  for (var y = ys; y < ye; y++) {
    for (var x = xs; x < xe; x++) {
      final d = _segmentsDistance(pts, x + 0.5, y + 0.5);
      if (d < maxDist) out[rect.index(x, y)] = d;
    }
  }
  return out;
}

double _segmentsDistance(List<MapPoint> pts, double px, double py) {
  if (pts.length == 1) {
    return math.sqrt(_sq(px - pts[0].x) + _sq(py - pts[0].y));
  }
  var best = double.infinity;
  for (var i = 0; i + 1 < pts.length; i++) {
    final a = pts[i], b = pts[i + 1];
    final vx = b.x - a.x, vy = b.y - a.y;
    final len2 = vx * vx + vy * vy;
    var t = len2 > 0 ? ((px - a.x) * vx + (py - a.y) * vy) / len2 : 0.0;
    t = clamp01(t);
    final d2 = _sq(px - a.x - t * vx) + _sq(py - a.y - t * vy);
    if (d2 < best) best = d2;
  }
  return math.sqrt(best);
}

double _sq(double v) => v * v;
