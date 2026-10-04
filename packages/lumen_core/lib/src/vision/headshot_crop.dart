import 'dart:math' as math;

import '../model/face_analysis.dart';
import '../model/geometry.dart';
import 'mesh_keypoints.dart';

/// Headshot crop ratios (width / height).
enum HeadshotRatio {
  portrait4x5('4:5', 4 / 5),
  square('1:1', 1),
  portrait2x3('2:3', 2 / 3);

  const HeadshotRatio(this.id, this.value);

  /// Geometry aspect preset id.
  final String id;
  final double value;
}

/// Framing rules, as fractions of the crop height.
class HeadshotStyle {
  const HeadshotStyle({
    this.eyeLine = 1 / 3,
    this.headRoom = 0.08,
    this.chinMargin = 0.2,
    this.sideMargin = 0.6,
    this.maxStraighten = 5,
  });

  /// Eyes this far from the top.
  final double eyeLine;

  /// Space above the estimated crown.
  final double headRoom;

  /// Space below the chin (shoulders).
  final double chinMargin;

  /// Extra width beside each face, as a fraction of its half width.
  final double sideMargin;

  /// Largest levelling rotation, in degrees.
  final double maxStraighten;
}

class HeadshotCrop {
  const HeadshotCrop({
    required this.geometry,
    required this.rollDegrees,
    required this.clipped,
    required this.faceCount,
  });

  final Geometry geometry;

  /// Measured eye-line tilt in the oriented image (before levelling).
  final double rollDegrees;

  /// The ideal frame did not fit the photo and was shrunk.
  final bool clipped;
  final int faceCount;
}

typedef _P = (double, double);

/// A headshot crop for [faces] (normalized source boxes, landmarks when
/// available) on a [sourceWidth]×[sourceHeight] source: eyes on the upper
/// third, head room above the crown, a chin margin, centred on the face
/// midline(s), levelled by the eye roll within ±[HeadshotStyle.maxStraighten]°.
/// Groups are framed together. Keeps [current]'s quarter turns and flips;
/// the result is plain [Geometry] (undoable, editable). Null without faces.
HeadshotCrop? headshotCrop({
  required List<DetectedFace> faces,
  required int sourceWidth,
  required int sourceHeight,
  required HeadshotRatio ratio,
  Geometry current = Geometry.none,
  HeadshotStyle style = const HeadshotStyle(),
}) {
  if (faces.isEmpty || sourceWidth <= 0 || sourceHeight <= 0) return null;
  final dw = (current.swapsAxes ? sourceHeight : sourceWidth).toDouble();
  final dh = (current.swapsAxes ? sourceWidth : sourceHeight).toDouble();
  _P oriented(double u, double v) {
    var (x, y) = switch (current.rotate90 % 4) {
      1 => (1 - v, u),
      2 => (1 - u, 1 - v),
      3 => (v, 1 - u),
      _ => (u, v),
    };
    if (current.flipH) x = 1 - x;
    if (current.flipV) y = 1 - y;
    return ((x - 0.5) * dw, (y - 0.5) * dh);
  }

  final rolls = <double>[
    for (final f in faces)
      if (f.landmarkCount >= MeshKeypoints.pointCount)
        _roll(
          oriented(
            f.landmarks[2 * MeshKeypoints.rightEyeOuter],
            f.landmarks[2 * MeshKeypoints.rightEyeOuter + 1],
          ),
          oriented(
            f.landmarks[2 * MeshKeypoints.leftEyeOuter],
            f.landmarks[2 * MeshKeypoints.leftEyeOuter + 1],
          ),
        ),
  ];
  final roll = rolls.isEmpty
      ? 0.0
      : rolls.reduce((a, b) => a + b) / rolls.length;
  final angleDeg = (-roll * 180 / math.pi).clamp(
    -style.maxStraighten,
    style.maxStraighten,
  );
  final a = angleDeg * math.pi / 180;
  final ca = math.cos(a), sa = math.sin(a);
  _P level(_P o) => (o.$1 * ca - o.$2 * sa, o.$1 * sa + o.$2 * ca);
  _P at(DetectedFace f, int i) =>
      level(oriented(f.landmarks[2 * i], f.landmarks[2 * i + 1]));

  final metrics = [
    for (final f in faces) _metrics(f, at, (u, v) => level(oriented(u, v))),
  ];
  final r = ratio.value;
  final s = style;
  final top0 = metrics.map((m) => m.eyeY - m.d).reduce(math.min);
  final bottom0 = metrics.map((m) => m.chinY).reduce(math.max);
  final left0 = metrics
      .map((m) => m.midX - m.halfWidth * (1 + s.sideMargin))
      .reduce(math.min);
  final right0 = metrics
      .map((m) => m.midX + m.halfWidth * (1 + s.sideMargin))
      .reduce(math.max);
  final eyeY =
      metrics.map((m) => m.eyeY).reduce((x, y) => x + y) / metrics.length;
  final hc = [
    (eyeY - top0) / (s.eyeLine - s.headRoom),
    (bottom0 - eyeY) / (1 - s.chinMargin - s.eyeLine),
    (right0 - left0) / r,
    (bottom0 - top0) / (1 - s.headRoom - s.chinMargin),
  ].reduce(math.max);
  var top = eyeY - s.eyeLine * hc;
  top = math.min(top, top0 - s.headRoom * hc);
  top = math.max(top, bottom0 + s.chinMargin * hc - hc);
  final fit = _fit(
    (left0 + right0) / 2,
    top + hc / 2,
    r * hc / 2,
    hc / 2,
    dw,
    dh,
    a,
  );
  return HeadshotCrop(
    geometry: current.copyWith(
      angle: angleDeg,
      aspect: ratio.id,
      crop: CropRect.normalized(
        (fit.cx - fit.hw) / dw + 0.5,
        (fit.cy - fit.hh) / dh + 0.5,
        (fit.cx + fit.hw) / dw + 0.5,
        (fit.cy + fit.hh) / dh + 0.5,
      ),
    ),
    rollDegrees: roll * 180 / math.pi,
    clipped: fit.clipped,
    faceCount: faces.length,
  );
}

/// Eye-line angle normalized to (−90°, 90°] (flips reverse the vector).
double _roll(_P right, _P left) {
  var t = math.atan2(left.$2 - right.$2, left.$1 - right.$1);
  if (t > math.pi / 2) t -= math.pi;
  if (t <= -math.pi / 2) t += math.pi;
  return t;
}

typedef _Metrics = ({
  double eyeY,
  double chinY,
  double midX,
  double halfWidth,
  double d,
});

_Metrics _metrics(
  DetectedFace f,
  _P Function(DetectedFace f, int i) at,
  _P Function(double u, double v) map,
) {
  if (f.landmarkCount >= MeshKeypoints.pointCount) {
    final re = at(f, MeshKeypoints.rightIrisCenter);
    final le = at(f, MeshKeypoints.leftIrisCenter);
    final chin = at(f, MeshKeypoints.chin);
    final eyeY = (re.$2 + le.$2) / 2;
    final d = chin.$2 - eyeY;
    if (d > 0) {
      final cheeks =
          (at(f, MeshKeypoints.leftCheekEdge).$1 -
                  at(f, MeshKeypoints.rightCheekEdge).$1)
              .abs() /
          2;
      return (
        eyeY: eyeY,
        chinY: chin.$2,
        midX: (re.$1 + le.$1) / 2,
        halfWidth: math.max(cheeks, 0.6 * d),
        d: d,
      );
    }
  }
  // No usable mesh: the detector box (brows to chin) after the transform.
  final b = f.box;
  final corners = [
    map(b.x, b.y),
    map(b.x + b.width, b.y),
    map(b.x, b.y + b.height),
    map(b.x + b.width, b.y + b.height),
  ];
  final x0 = corners.map((c) => c.$1).reduce(math.min);
  final x1 = corners.map((c) => c.$1).reduce(math.max);
  final y0 = corners.map((c) => c.$2).reduce(math.min);
  final y1 = corners.map((c) => c.$2).reduce(math.max);
  final eyeY = y0 + 0.35 * (y1 - y0);
  return (
    eyeY: eyeY,
    chinY: y1,
    midX: (x0 + x1) / 2,
    halfWidth: (x1 - x0) / 2,
    d: y1 - eyeY,
  );
}

/// Moves (and, when it cannot fit, shrinks) a crop of half size
/// ([hw], [hh]) centred at ([cx], [cy]) so it lies inside both the
/// straightened frame (dw × dh) and the rotated source, i.e. never shows
/// pixels outside the photo. Coordinates are centred pixels.
({double cx, double cy, double hw, double hh, bool clipped}) _fit(
  double cx,
  double cy,
  double hw,
  double hh,
  double dw,
  double dh,
  double a,
) {
  final c = math.cos(a), s = math.sin(a);
  final ac = c.abs(), as = s.abs();
  var scale = [
    1.0,
    dw / 2 / hw,
    dh / 2 / hh,
    dw / 2 / (hw * ac + hh * as),
    dh / 2 / (hw * as + hh * ac),
  ].reduce(math.min);
  for (var attempt = 0; attempt < 40; attempt++) {
    final w = hw * scale, h = hh * scale;
    final ex = w * ac + h * as, ey = w * as + h * ac;
    var x = cx, y = cy;
    for (var i = 0; i < 50; i++) {
      x = x.clamp(-dw / 2 + w, dw / 2 - w);
      y = y.clamp(-dh / 2 + h, dh / 2 - h);
      final ox = x * c + y * s, oy = -x * s + y * c;
      final oxc = ox.clamp(-(dw / 2 - ex), dw / 2 - ex);
      final oyc = oy.clamp(-(dh / 2 - ey), dh / 2 - ey);
      if ((oxc - ox).abs() < 1e-9 && (oyc - oy).abs() < 1e-9) break;
      x = oxc * c - oyc * s;
      y = oxc * s + oyc * c;
    }
    final ox = x * c + y * s, oy = -x * s + y * c;
    final inside =
        x.abs() <= dw / 2 - w + 1e-6 &&
        y.abs() <= dh / 2 - h + 1e-6 &&
        ox.abs() <= dw / 2 - ex + 1e-6 &&
        oy.abs() <= dh / 2 - ey + 1e-6;
    if (inside) {
      return (cx: x, cy: y, hw: w, hh: h, clipped: scale < 0.999);
    }
    scale *= 0.97;
  }
  return (cx: 0, cy: 0, hw: hw * scale, hh: hh * scale, clipped: true);
}
