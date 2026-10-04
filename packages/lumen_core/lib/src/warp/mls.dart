/// Moving Least Squares, similarity variant (Schaefer, McPhail & Warren,
/// SIGGRAPH 2006), α = 1. Used backward (research 07 §3.10): `p` = deformed
/// control points, `q` = original ones, so `mls(v)` is the source position
/// an output pixel `v` reads.
library;

import 'dart:typed_data';

/// Control points as flat arrays (`px[i], py[i]` → `qx[i], qy[i]`).
class MlsControls {
  MlsControls(this.px, this.py, this.qx, this.qy) : w = Float64List(px.length) {
    if (py.length != px.length ||
        qx.length != px.length ||
        qy.length != px.length) {
      throw ArgumentError('control point arrays differ in length');
    }
  }

  final Float64List px;
  final Float64List py;
  final Float64List qx;
  final Float64List qy;

  /// Scratch weights.
  final Float64List w;

  int get length => px.length;

  /// Similarity MLS at (vx, vy) → the mapped position.
  (double, double) map(double vx, double vy) {
    final n = length;
    var ws = 0.0, psx = 0.0, psy = 0.0, qsx = 0.0, qsy = 0.0;
    for (var i = 0; i < n; i++) {
      final ex = px[i] - vx, ey = py[i] - vy;
      final d2 = ex * ex + ey * ey;
      if (d2 < 1e-9) return (qx[i], qy[i]);
      final wi = 1 / d2;
      w[i] = wi;
      ws += wi;
      psx += px[i] * wi;
      psy += py[i] * wi;
      qsx += qx[i] * wi;
      qsy += qy[i] * wi;
    }
    psx /= ws;
    psy /= ws;
    qsx /= ws;
    qsy /= ws;
    var mu = 0.0, a = 0.0, b = 0.0;
    for (var i = 0; i < n; i++) {
      final phx = px[i] - psx, phy = py[i] - psy;
      final qhx = qx[i] - qsx, qhy = qy[i] - qsy;
      mu += w[i] * (phx * phx + phy * phy);
      a += w[i] * (phx * qhx + phy * qhy);
      b += w[i] * (phx * qhy - phy * qhx);
    }
    if (mu <= 0) return (vx + qsx - psx, vy + qsy - psy);
    a /= mu;
    b /= mu;
    final dx = vx - psx, dy = vy - psy;
    return (dx * a - dy * b + qsx, dx * b + dy * a + qsy);
  }
}
