/// Liquify strokes composed into the warp field (research 07 §3.10).
///
/// Works in grid-texel space (isotropic: the grid has the source aspect).
/// Every dab is a small diffeomorphism composed with the existing backward
/// map by resampling it (`new(p) = old(T(p))`), so strokes accumulate
/// correctly. Dabs sit every quarter radius along the polyline and move at
/// most a quarter radius, which keeps each step fold-free.
///
/// [LiquifyLive] applies one stroke incrementally (a live stroke growing
/// point by point costs only its new dabs); [applyLiquifyStrokes] replays
/// strokes through the same code, so both give identical fields.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/liquify.dart';
import 'warp_field.dart';

const double _kSpacing = 0.25; // dab spacing, × radius
const double _kBloatRate = 0.12; // radial scale per dab at strength 1

/// [field] with [strokes] applied, one quantized step per stroke.
WarpField applyLiquifyStrokes(
  WarpField field,
  List<LiquifyStroke> strokes, {
  required int sourceWidth,
  required int sourceHeight,
}) {
  var f = field;
  for (final s in strokes) {
    if (s.points.isEmpty || s.strength <= 0) continue;
    f = LiquifyLive(f, s).snapshot();
  }
  return f;
}

/// One stroke applied onto a base field, extendable as the stroke grows.
class LiquifyLive {
  LiquifyLive(WarpField base, LiquifyStroke stroke)
    : w = base.width,
      h = base.height,
      _stroke = stroke {
    final (dx, dy) = base.toFloats();
    _dx = dx;
    _dy = dy;
    final le = math.max(w, h).toDouble();
    _r = math.max(stroke.radius * le, 1.0);
    _step = math.max(_kSpacing * _r, 0.5);
    _consume(stroke.points);
  }

  final int w;
  final int h;
  LiquifyStroke _stroke;
  late final Float32List _dx;
  late final Float32List _dy;
  late final double _r;
  late final double _step;
  int _consumed = 0; // stroke points already resampled
  double _carry = 0; // distance walked since the last dab
  (double, double)? _lastDab;

  LiquifyStroke get stroke => _stroke;

  /// True when [next] is this stroke with more points (same brush).
  bool canExtend(LiquifyStroke next) {
    final s = _stroke;
    if (next.tool != s.tool ||
        next.radius != s.radius ||
        next.strength != s.strength ||
        next.points.length < s.points.length) {
      return false;
    }
    for (var i = 0; i < s.points.length; i++) {
      if (next.points[i] != s.points[i]) return false;
    }
    return true;
  }

  /// Applies the new points of [next] (see [canExtend]).
  void extend(LiquifyStroke next) {
    if (!canExtend(next)) throw ArgumentError('stroke does not extend');
    _stroke = next;
    _consume(next.points);
  }

  /// The field so far, sample positions clamped inside the image.
  WarpField snapshot() {
    final dx = Float32List.fromList(_dx), dy = Float32List.fromList(_dy);
    for (var y = 0; y < h; y++) {
      final v = (y + 0.5) / h;
      for (var x = 0; x < w; x++) {
        final i = y * w + x, u = (x + 0.5) / w;
        final a = dx[i], b = dy[i];
        if (a < -u) dx[i] = -u;
        if (a > 1 - u) dx[i] = 1 - u;
        if (b < -v) dy[i] = -v;
        if (b > 1 - v) dy[i] = 1 - v;
      }
    }
    return WarpField(w, h, dx, dy);
  }

  /// Resamples points [_consumed..] into dabs every [_step] texels.
  void _consume(List<(double, double)> pts) {
    if (pts.isEmpty) return;
    if (_consumed == 0) {
      _dab((pts[0].$1 * w, pts[0].$2 * h));
      _consumed = 1;
    }
    for (var i = _consumed; i < pts.length; i++) {
      final ax = pts[i - 1].$1 * w, ay = pts[i - 1].$2 * h;
      final bx = pts[i].$1 * w, by = pts[i].$2 * h;
      final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
      var t = _step - _carry;
      while (t <= len) {
        _dab((ax + (bx - ax) * t / len, ay + (by - ay) * t / len));
        t += _step;
      }
      _carry = len - (t - _step);
    }
    _consumed = pts.length;
  }

  void _dab((double, double) p) {
    final prev = _lastDab;
    _lastDab = p;
    final s = _stroke.strength;
    final (cx, cy) = p;
    switch (_stroke.tool) {
      case LiquifyTool.push:
        if (prev == null) return;
        _remap(cx, cy, s, 0, prev.$1 - cx, prev.$2 - cy);
      case LiquifyTool.reconstruct:
        _reconstruct(cx, cy, s);
      case LiquifyTool.bloat:
        _remap(cx, cy, s, _kBloatRate, 0, 0);
      case LiquifyTool.pucker:
        _remap(cx, cy, s, -_kBloatRate, 0, 0);
    }
  }

  static double _falloff(double d2, double r2) {
    if (d2 >= r2) return 0;
    final t = 1 - d2 / r2;
    return t * t;
  }

  /// new(p) = old(T(p)) with T(p) = o + (p − o)(1 − k·wg) + m·wg, where
  /// wg is the falloff around o. Push: o = previous dab, m = previous −
  /// current (content follows the brush, k = 0); bloat/pucker: o = current
  /// dab, m = 0, k = ±rate.
  void _remap(double cx, double cy, double s, double k, double mx, double my) {
    final r = _r, r2 = r * r;
    // Push dabs are centred on the previous dab (where the content comes
    // from), so the brush footprint follows the stroke.
    final ox = cx + mx, oy = cy + my;
    final x0 = math.max(0, (ox - r).floor()),
        x1 = math.min(w - 1, (ox + r).ceil());
    final y0 = math.max(0, (oy - r).floor()),
        y1 = math.min(h - 1, (oy + r).ceil());
    if (x1 < x0 || y1 < y0) return;
    final rw = x1 - x0 + 1;
    final nx = Float32List(rw * (y1 - y0 + 1)), ny = Float32List(nx.length);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final px = x + 0.5, py = y + 0.5, i = y * w + x;
        final o = (y - y0) * rw + x - x0;
        final wg =
            _falloff((px - ox) * (px - ox) + (py - oy) * (py - oy), r2) * s;
        if (wg == 0) {
          nx[o] = _dx[i];
          ny[o] = _dy[i];
          continue;
        }
        final t = 1 - k * wg;
        final qx = ox + (px - ox) * t + mx * wg;
        final qy = oy + (py - oy) * t + my * wg;
        _src(qx, qy);
        nx[o] = (_sx - px) / w;
        ny[o] = (_sy - py) / h;
      }
    }
    for (var y = y0; y <= y1; y++) {
      final row = (y - y0) * rw - x0;
      for (var x = x0; x <= x1; x++) {
        _dx[y * w + x] = nx[row + x];
        _dy[y * w + x] = ny[row + x];
      }
    }
  }

  void _reconstruct(double cx, double cy, double s) {
    final r = _r, r2 = r * r;
    final x0 = math.max(0, (cx - r).floor()),
        x1 = math.min(w - 1, (cx + r).ceil());
    final y0 = math.max(0, (cy - r).floor()),
        y1 = math.min(h - 1, (cy + r).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final px = x + 0.5, py = y + 0.5, i = y * w + x;
        final k =
            1 - _falloff((px - cx) * (px - cx) + (py - cy) * (py - cy), r2) * s;
        _dx[i] *= k;
        _dy[i] *= k;
      }
    }
  }

  double _sx = 0;
  double _sy = 0;

  /// The current backward map at texel position (qx, qy) into
  /// ([_sx], [_sy]): bilinear over texel centres, clamp to edge.
  void _src(double qx, double qy) {
    final fx0 = (qx - 0.5).floorToDouble(), fy0 = (qy - 0.5).floorToDouble();
    final fx = qx - 0.5 - fx0, fy = qy - 0.5 - fy0;
    final ix = fx0.toInt(), iy = fy0.toInt();
    final x0 = ix < 0 ? 0 : (ix >= w ? w - 1 : ix);
    final x1 = ix + 1 < 0 ? 0 : (ix + 1 >= w ? w - 1 : ix + 1);
    final y0 = iy < 0 ? 0 : (iy >= h ? h - 1 : iy);
    final y1 = iy + 1 < 0 ? 0 : (iy + 1 >= h ? h - 1 : iy + 1);
    final i00 = y0 * w + x0, i10 = y0 * w + x1;
    final i01 = y1 * w + x0, i11 = y1 * w + x1;
    final dxt = _dx[i00] + (_dx[i10] - _dx[i00]) * fx;
    final dxb = _dx[i01] + (_dx[i11] - _dx[i01]) * fx;
    final dyt = _dy[i00] + (_dy[i10] - _dy[i00]) * fx;
    final dyb = _dy[i01] + (_dy[i11] - _dy[i01]) * fx;
    _sx = qx + (dxt + (dxb - dxt) * fy) * w;
    _sy = qy + (dyt + (dyb - dyt) * fy) * h;
  }
}
