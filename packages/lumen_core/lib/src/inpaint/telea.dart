/// Telea fast-marching inpainting (A. Telea, "An Image Inpainting Technique
/// Based on the Fast Marching Method", JGT 2004). Pure Dart, deterministic.
/// Best for thin scratches, wires and sensor dust.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'distance_transform.dart';
import 'float_image.dart';

const int _known = 0, _band = 1, _inside = 2;
const double _inf = 1e12;

/// Fills hole pixels (`hole[i] != 0`) by marching inward from the
/// boundary; each new pixel is the weighted first-order extrapolation of
/// the known pixels within [radius] px (direction × distance × level-set
/// weights). Known pixels are returned unchanged.
FloatImage teleaInpaint(FloatImage img, Uint8List hole, {int radius = 5}) {
  final w = img.width, h = img.height, n = w * h;
  final out = img.copy();
  final flag = Uint8List(n);
  final t = Float64List(n);
  var holes = 0;
  for (var i = 0; i < n; i++) {
    if (hole[i] != 0) {
      flag[i] = _inside;
      t[i] = _inf;
      holes++;
    }
  }
  if (holes == 0 || holes == n) return out;
  // Known side: T = −(distance to the hole − 1), so the band is 0 and
  // far context weighs less (Telea's level-set term).
  final d2 = squaredDistanceTransform(hole, w, h);
  final heap = _MinHeap();
  for (var i = 0; i < n; i++) {
    if (flag[i] == _inside) continue;
    t[i] = 1 - math.sqrt(d2[i]);
    final x = i % w, y = i ~/ w;
    final edge =
        (x > 0 && flag[i - 1] == _inside) ||
        (x < w - 1 && flag[i + 1] == _inside) ||
        (y > 0 && flag[i - w] == _inside) ||
        (y < h - 1 && flag[i + w] == _inside);
    if (edge) {
      flag[i] = _band;
      t[i] = 0;
      heap.push(0, i);
    }
  }
  final march = _March(w, h, flag, t, out, radius);
  while (heap.isNotEmpty) {
    final i = heap.pop();
    if (flag[i] == _known) continue;
    flag[i] = _known;
    final x = i % w, y = i ~/ w;
    for (final (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final j = ny * w + nx;
      if (flag[j] != _inside) continue;
      t[j] = march.arrival(nx, ny);
      march.inpaint(nx, ny);
      flag[j] = _band;
      heap.push(t[j], j);
    }
  }
  return out;
}

class _March {
  _March(this.w, this.h, this.flag, this.t, this.img, this.radius);

  final int w;
  final int h;
  final Uint8List flag;
  final Float64List t;
  final FloatImage img;
  final int radius;

  bool _avail(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && flag[y * w + x] != _inside;

  bool _isKnown(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && flag[y * w + x] == _known;

  double _t(int x, int y) => t[y * w + x];

  /// Eikonal update: min over the four quadrant pairs.
  double arrival(int x, int y) => math.min(
    math.min(_solve(x, y - 1, x - 1, y), _solve(x, y + 1, x + 1, y)),
    math.min(_solve(x, y - 1, x + 1, y), _solve(x, y + 1, x - 1, y)),
  );

  double _solve(int x1, int y1, int x2, int y2) {
    final k1 = _isKnown(x1, y1), k2 = _isKnown(x2, y2);
    if (k1 && k2) {
      final t1 = _t(x1, y1), t2 = _t(x2, y2);
      final d = 2 - (t1 - t2) * (t1 - t2);
      if (d >= 0) {
        final r = math.sqrt(d);
        var s = (t1 + t2 - r) / 2;
        if (s >= t1 && s >= t2) return s;
        s += r;
        if (s >= t1 && s >= t2) return s;
      }
      return 1 + math.min(t1, t2);
    }
    if (k1) return 1 + _t(x1, y1);
    if (k2) return 1 + _t(x2, y2);
    return _inf;
  }

  /// Central (or one-sided) difference of [f] at (x, y) along one axis
  /// over available pixels; 0 when neither side is available.
  double _diff(int x, int y, int dx, int dy, double Function(int, int) f) {
    final p = _avail(x + dx, y + dy), m = _avail(x - dx, y - dy);
    if (p && m) return (f(x + dx, y + dy) - f(x - dx, y - dy)) / 2;
    if (p) return f(x + dx, y + dy) - f(x, y);
    if (m) return f(x, y) - f(x - dx, y - dy);
    return 0;
  }

  void inpaint(int x, int y) {
    final ch = img.channels;
    final gx = _diff(x, y, 1, 0, _t), gy = _diff(x, y, 0, 1, _t);
    final tp = _t(x, y);
    final r2max = radius * radius;
    for (var c = 0; c < ch; c++) {
      double val(int qx, int qy) => img.at(qx, qy, c);
      var sw = 0.0, acc = 0.0;
      var lo = double.infinity, hi = double.negativeInfinity;
      for (var qy = y - radius; qy <= y + radius; qy++) {
        for (var qx = x - radius; qx <= x + radius; qx++) {
          if (!_avail(qx, qy)) continue;
          final rx = x - qx, ry = y - qy;
          final r2 = rx * rx + ry * ry;
          if (r2 == 0 || r2 > r2max) continue;
          final len = math.sqrt(r2);
          var dir = (rx * gx + ry * gy) / len;
          if (dir.abs() <= 0.01) dir = 1e-6;
          final dst = 1 / (r2 * len);
          final lev = 1 / (1 + (_t(qx, qy) - tp).abs());
          final wt = (dir * dst * lev).abs();
          final iq = val(qx, qy);
          final grad =
              _diff(qx, qy, 1, 0, val) * rx + _diff(qx, qy, 0, 1, val) * ry;
          acc += wt * (iq + grad);
          sw += wt;
          lo = math.min(lo, iq);
          hi = math.max(hi, iq);
        }
      }
      if (sw > 0) img.set(x, y, c, (acc / sw).clamp(lo, hi));
    }
  }
}

/// Binary min-heap of (key, index); equal keys pop in a deterministic
/// (but unspecified) order.
class _MinHeap {
  final _keys = <double>[];
  final _vals = <int>[];

  bool get isNotEmpty => _keys.isNotEmpty;

  void push(double key, int v) {
    _keys.add(key);
    _vals.add(v);
    var i = _keys.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_keys[p] <= _keys[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  int pop() {
    final top = _vals[0];
    final lastK = _keys.removeLast(), lastV = _vals.removeLast();
    if (_keys.isNotEmpty) {
      _keys[0] = lastK;
      _vals[0] = lastV;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _keys.length && _keys[l] < _keys[m]) m = l;
        if (r < _keys.length && _keys[r] < _keys[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final k = _keys[a];
    _keys[a] = _keys[b];
    _keys[b] = k;
    final v = _vals[a];
    _vals[a] = _vals[b];
    _vals[b] = v;
  }
}
