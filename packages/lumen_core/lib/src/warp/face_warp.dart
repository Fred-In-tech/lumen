/// Slider-driven face reshape (research 07 §3.10): landmark control points
/// moved by the shape sliders, an anchor ring, backward similarity MLS on a
/// coarse lattice, a feather to exactly zero outside the face, a radial
/// bulge for eye size, a 0.15-IOD cap and a Jacobian guard (no fold-over).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/face_analysis.dart';
import '../model/portrait.dart';
import '../retouch/face_mesh.dart';
import 'mls.dart';

/// The face-scope shape params this module reads.
const List<String> kFaceShapeIds = [
  PortraitIds.faceWidth,
  PortraitIds.vShape,
  PortraitIds.chin,
  PortraitIds.eyeSize,
  PortraitIds.noseWidth,
  PortraitIds.mouthSize,
];

/// Resolved shape values of one face, normalized to −1..1. Positive =
/// wider face, more V-shape, longer chin, bigger eyes, wider nose, bigger
/// mouth.
class FaceShape {
  const FaceShape(this.values);

  factory FaceShape.resolve(PortraitSettings s, DetectedFace f) => FaceShape([
    for (final id in kFaceShapeIds)
      (s.valueFor(id, group: f.group, personId: f.personId) / 100).clamp(
        -1.0,
        1.0,
      ),
  ]);

  /// In [kFaceShapeIds] order.
  final List<double> values;

  double get faceWidth => values[0];
  double get vShape => values[1];
  double get chin => values[2];
  double get eyeSize => values[3];
  double get noseWidth => values[4];
  double get mouthSize => values[5];

  bool get isIdentity => values.every((v) => v == 0);
}

// Displacements in IOD units at ±1 (research 07 §3.10 table).
const double _kFaceWidth = 0.06;
const double _kVShapeIn = 0.05;
const double _kVShapeUp = 0.02;
const double _kChin = 0.08;
const double _kNose = 0.035;
const double _kMouthScale = 0.12;
const double _kEyeBulge = 0.25;
const double _kEyeRadius = 1.6; // × eye half-width
const double _kCapIod = 0.15;
const double _kRing = 1.35; // anchor ring, × face radius
const double _kFeatherEnd = 1.6; // displacement is exactly 0 beyond
const int _kRingPoints = 24;
const int _kLattice = 4; // MLS lattice step (grid texels)
const double _kMinJacobian = 0.25;

const _faceWidthW = {93: .5, 132: .8, 58: 1.0, 172: .8, 136: .5};
const _faceWidthWL = {323: .5, 361: .8, 288: 1.0, 397: .8, 365: .5};
const _vShapeIdx = [172, 136, 150, 149, 397, 365, 379, 378];
const _chinW = {152: 1.0, 148: .85, 377: .85, 176: .6, 400: .6};
const _alar = [48, 64, 98, 115, 129, 278, 294, 327, 344, 358];

/// Adds the reshape displacement of [face] (uv units) into [dx], [dy], a
/// [gw]×[gh] grid over a [srcW]×[srcH] source.
void addFaceReshape(
  DetectedFace face,
  FaceShape shape, {
  required int srcW,
  required int srcH,
  required int gw,
  required int gh,
  required Float32List dx,
  required Float32List dy,
}) {
  final lm = face.landmarks;
  if (shape.isIdentity || lm.length < FaceMesh.landmarkCount * 2) return;
  double px(int i) => lm[2 * i] * srcW;
  double py(int i) => lm[2 * i + 1] * srcH;
  final rx = px(FaceMesh.rightIrisCenter), ry = py(FaceMesh.rightIrisCenter);
  final lx = px(FaceMesh.leftIrisCenter), ly = py(FaceMesh.leftIrisCenter);
  final iod = math.sqrt((lx - rx) * (lx - rx) + (ly - ry) * (ly - ry));
  if (iod < 4) return;
  final ox = (rx + lx) / 2, oy = (ry + ly) / 2;
  final exX = (lx - rx) / iod, exY = (ly - ry) / iod; // image right
  final eyX = -exY, eyY = exX; // down the face
  double side(int i) => (px(i) - ox) * exX + (py(i) - oy) * exY < 0 ? -1 : 1;

  // Control displacements (pixels) keyed by landmark.
  final moves = <int, (double, double)>{};
  void add(int i, double ddx, double ddy) {
    final m = moves[i] ?? (0.0, 0.0);
    moves[i] = (m.$1 + ddx, m.$2 + ddy);
  }

  final fw = shape.faceWidth, vs = shape.vShape, ch = shape.chin;
  for (final e in [..._faceWidthW.entries, ..._faceWidthWL.entries]) {
    final k = _kFaceWidth * fw * e.value * iod * side(e.key);
    add(e.key, k * exX, k * exY);
  }
  for (final i in _vShapeIdx) {
    final k = -_kVShapeIn * vs * iod * side(i), up = -_kVShapeUp * vs * iod;
    add(i, k * exX + up * eyX, k * exY + up * eyY);
  }
  for (final e in _chinW.entries) {
    final k = _kChin * ch * e.value * iod;
    add(e.key, k * eyX, k * eyY);
  }
  for (final i in _alar) {
    final k = _kNose * shape.noseWidth * iod * side(i);
    add(i, k * exX, k * exY);
  }
  var mcx = 0.0, mcy = 0.0;
  for (final i in FaceMesh.lipsOuter) {
    mcx += px(i) / FaceMesh.lipsOuter.length;
    mcy += py(i) / FaceMesh.lipsOuter.length;
  }
  for (final i in FaceMesh.lipsOuter) {
    final k = _kMouthScale * shape.mouthSize;
    add(i, (px(i) - mcx) * k, (py(i) - mcy) * k);
  }
  // Fixed features (zero unless a slider moved them).
  for (final i in [
    ...FaceMesh.faceOval,
    ...FaceMesh.rightEye,
    ...FaceMesh.leftEye,
    FaceMesh.rightIrisCenter,
    FaceMesh.leftIrisCenter,
    ...FaceMesh.noseRidge,
    ...FaceMesh.chinCenterLine,
  ]) {
    add(i, 0, 0);
  }
  // Face centre/radius and the anchor ring (in the face frame).
  var cx = 0.0, cy = 0.0;
  for (final i in FaceMesh.faceOval) {
    cx += px(i) / FaceMesh.faceOval.length;
    cy += py(i) / FaceMesh.faceOval.length;
  }
  var radius = 0.0;
  for (final i in FaceMesh.faceOval) {
    radius = math.max(
      radius,
      math.sqrt(math.pow(px(i) - cx, 2) + math.pow(py(i) - cy, 2)),
    );
  }
  final n = moves.length + _kRingPoints;
  final cp = MlsControls(
    Float64List(n),
    Float64List(n),
    Float64List(n),
    Float64List(n),
  );
  var k = 0;
  for (final e in moves.entries) {
    cp.qx[k] = px(e.key);
    cp.qy[k] = py(e.key);
    cp.px[k] = cp.qx[k] + e.value.$1;
    cp.py[k] = cp.qy[k] + e.value.$2;
    k++;
  }
  for (var j = 0; j < _kRingPoints; j++) {
    final t = -math.pi / 2 + 2 * math.pi * j / _kRingPoints;
    final ax = math.cos(t) * _kRing * radius,
        ay = math.sin(t) * _kRing * radius;
    cp.qx[k] = cp.px[k] = cx + ax * exX + ay * eyX;
    cp.qy[k] = cp.py[k] = cy + ax * exY + ay * eyY;
    k++;
  }
  final region = _Region.around(
    cx,
    cy,
    _kFeatherEnd * radius,
    srcW,
    srcH,
    gw,
    gh,
  );
  if (region == null) return;
  final ldx = Float32List(region.count), ldy = Float32List(region.count);
  _mlsOnLattice(cp, region, ldx, ldy);
  // Feather, eye bulge, cap.
  final eyes = [
    for (final (c, a, b) in [
      (FaceMesh.rightIrisCenter, 33, 133),
      (FaceMesh.leftIrisCenter, 263, 362),
    ])
      (
        px(c),
        py(c),
        _kEyeRadius *
            math.sqrt(math.pow(px(a) - px(b), 2) + math.pow(py(a) - py(b), 2)) /
            2,
      ),
  ];
  final bulge = _kEyeBulge * shape.eyeSize, cap = _kCapIod * iod;
  for (var j = 0; j < region.h; j++) {
    for (var i = 0; i < region.w; i++) {
      final (vx, vy) = region.pixelOf(i, j);
      final idx = j * region.w + i;
      final r =
          math.sqrt((vx - cx) * (vx - cx) + (vy - cy) * (vy - cy)) / radius;
      final feather = 1 - _smoothstep(_kRing, _kFeatherEnd, r);
      var ddx = ldx[idx] * feather, ddy = ldy[idx] * feather;
      if (bulge != 0) {
        for (final (ex, ey, rb) in eyes) {
          final qx = vx - ex, qy = vy - ey;
          final t = (qx * qx + qy * qy) / (rb * rb);
          if (t >= 1) continue;
          final f = (1 - t) * (1 - t);
          ddx -= qx * bulge * f;
          ddy -= qy * bulge * f;
        }
      }
      final m = math.sqrt(ddx * ddx + ddy * ddy);
      if (m > cap) {
        ddx *= cap / m;
        ddy *= cap / m;
      }
      ldx[idx] = ddx;
      ldy[idx] = ddy;
    }
  }
  final scale = _foldGuard(ldx, ldy, region);
  for (var j = 0; j < region.h; j++) {
    for (var i = 0; i < region.w; i++) {
      final g = (region.y0 + j) * gw + region.x0 + i, idx = j * region.w + i;
      dx[g] += ldx[idx] * scale / srcW;
      dy[g] += ldy[idx] * scale / srcH;
    }
  }
}

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// MLS displacement (pixels) on a lattice, bilinearly filled per texel.
void _mlsOnLattice(
  MlsControls cp,
  _Region r,
  Float32List ldx,
  Float32List ldy,
) {
  final nx = (r.w - 1) ~/ _kLattice + 2, ny = (r.h - 1) ~/ _kLattice + 2;
  final lx = Float64List(nx * ny), ly = Float64List(nx * ny);
  for (var b = 0; b < ny; b++) {
    for (var a = 0; a < nx; a++) {
      final (vx, vy) = r.pixelOf(a * _kLattice, b * _kLattice);
      final (sx, sy) = cp.map(vx, vy);
      lx[b * nx + a] = sx - vx;
      ly[b * nx + a] = sy - vy;
    }
  }
  for (var j = 0; j < r.h; j++) {
    final b = j ~/ _kLattice, fy = (j % _kLattice) / _kLattice;
    for (var i = 0; i < r.w; i++) {
      final a = i ~/ _kLattice, fx = (i % _kLattice) / _kLattice;
      double bl(Float64List v) {
        final top = v[b * nx + a] + (v[b * nx + a + 1] - v[b * nx + a]) * fx;
        final bot =
            v[(b + 1) * nx + a] +
            (v[(b + 1) * nx + a + 1] - v[(b + 1) * nx + a]) * fx;
        return top + (bot - top) * fy;
      }

      ldx[j * r.w + i] = bl(lx);
      ldy[j * r.w + i] = bl(ly);
    }
  }
}

/// Largest k ≤ 1 (bisection) such that k·d keeps every Jacobian ≥ the
/// minimum: the face edit is scaled down rather than folding over.
double _foldGuard(Float32List ldx, Float32List ldy, _Region r) {
  bool ok(double k) {
    for (var j = 0; j + 1 < r.h; j++) {
      for (var i = 0; i + 1 < r.w; i++) {
        final o = j * r.w + i;
        final a = k * (ldx[o + 1] - ldx[o]) / r.sx;
        final b = k * (ldx[o + r.w] - ldx[o]) / r.sy;
        final c = k * (ldy[o + 1] - ldy[o]) / r.sx;
        final d = k * (ldy[o + r.w] - ldy[o]) / r.sy;
        if ((1 + a) * (1 + d) - b * c < _kMinJacobian) return false;
      }
    }
    return true;
  }

  if (ok(1)) return 1;
  var lo = 0.0, hi = 1.0;
  for (var it = 0; it < 12; it++) {
    final mid = (lo + hi) / 2;
    if (ok(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// A rectangle of grid texels and its pixel geometry.
class _Region {
  _Region(this.x0, this.y0, this.w, this.h, this.sx, this.sy);

  static _Region? around(
    double cx,
    double cy,
    double rad,
    int srcW,
    int srcH,
    int gw,
    int gh,
  ) {
    final sx = srcW / gw, sy = srcH / gh;
    final x0 = math.max(0, ((cx - rad) / sx).floor());
    final x1 = math.min(gw, ((cx + rad) / sx).ceil() + 1);
    final y0 = math.max(0, ((cy - rad) / sy).floor());
    final y1 = math.min(gh, ((cy + rad) / sy).ceil() + 1);
    if (x1 <= x0 || y1 <= y0) return null;
    return _Region(x0, y0, x1 - x0, y1 - y0, sx, sy);
  }

  final int x0;
  final int y0;
  final int w;
  final int h;

  /// Source pixels per grid texel.
  final double sx;
  final double sy;

  int get count => w * h;

  /// Pixel position of region texel (i, j)'s centre.
  (double, double) pixelOf(int i, int j) =>
      ((x0 + i + 0.5) * sx, (y0 + j + 0.5) * sy);
}
