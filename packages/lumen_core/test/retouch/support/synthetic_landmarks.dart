/// Deterministic synthetic MediaPipe landmarks (no model needed).
///
/// Local frame: origin = midpoint of the iris centres, x to the image right,
/// y down, unit = IOD. The subject's right eye is on the image left.
library;

import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';

typedef LocalPt = ({double x, double y});

// Face proportions (IOD units).
const double kEyeOuterX = 0.74;
const double kEyeInnerX = 0.26;
const double kEyeUpper = 0.085;
const double kEyeLower = 0.075;
const double kIrisRadius = 0.093;
const double kOvalRx = 1.15;
const double kOvalCy = 0.6;
const double kOvalRyTop = 1.4;
const double kOvalRyBottom = 1.35;
const double kMouthY = 1.12;

/// All 478 landmarks in the local frame. [mouthOpen] scales the inner-lip
/// opening (1 = teeth visible).
Map<int, LocalPt> synthLandmarksLocal({double mouthOpen = 1}) {
  final m = <int, LocalPt>{};
  void put(int i, double x, double y) => m[i] = (x: x, y: y);
  void mirrored(List<int> right, List<int> left, List<LocalPt> pts) {
    for (var k = 0; k < right.length; k++) {
      put(right[k], pts[k].x, pts[k].y);
      put(left[k], -pts[k].x, pts[k].y);
    }
  }

  // Face oval: clockwise on screen from the top.
  const oval = FaceMesh.faceOval;
  for (var k = 0; k < oval.length; k++) {
    final th = -math.pi / 2 + 2 * math.pi * k / oval.length;
    final s = math.sin(th);
    final ry = s < 0 ? kOvalRyTop : kOvalRyBottom;
    put(oval[k], kOvalRx * math.cos(th), kOvalCy + ry * s);
  }
  // Eyes: upper lid outer → inner, then lower lid inner → outer.
  final eye = <LocalPt>[
    for (var j = 0; j <= 8; j++)
      (
        x: -kEyeOuterX + (kEyeOuterX - kEyeInnerX) * j / 8,
        y: -kEyeUpper * math.sin(math.pi * j / 8),
      ),
    for (var j = 0; j < 7; j++)
      (
        x: -kEyeOuterX + (kEyeOuterX - kEyeInnerX) * (1 - (j + 1) / 8),
        y: kEyeLower * math.sin(math.pi * (1 - (j + 1) / 8)),
      ),
  ];
  mirrored(FaceMesh.rightEye, FaceMesh.leftEye, eye);
  // Iris centres and rings.
  mirrored(
    [FaceMesh.rightIrisCenter, ...FaceMesh.rightIrisRing],
    [FaceMesh.leftIrisCenter, ...FaceMesh.leftIrisRing],
    [
      (x: -0.5, y: 0.0),
      (x: -0.5 + kIrisRadius, y: 0.0),
      (x: -0.5, y: -kIrisRadius),
      (x: -0.5 - kIrisRadius, y: 0.0),
      (x: -0.5, y: kIrisRadius),
    ],
  );
  // Under-eye rings 2–4: down and out monotonically.
  final rings = [
    (FaceMesh.rightUnderEye2, FaceMesh.leftUnderEye2, 0.06, 0.03),
    (FaceMesh.rightUnderEye3, FaceMesh.leftUnderEye3, 0.13, 0.06),
    (FaceMesh.rightUnderEye4, FaceMesh.leftUnderEye4, 0.22, 0.09),
  ];
  for (final (r, l, d, wid) in rings) {
    mirrored(r, l, [
      for (var j = 0; j <= 8; j++)
        (
          x: _lerp(-kEyeOuterX - wid, -kEyeInnerX + 0.3 * wid, j / 8),
          y:
              kEyeLower * math.sin(math.pi * j / 8) +
              d * (0.6 + 0.4 * math.sin(math.pi * j / 8)),
        ),
    ]);
  }
  // Brows: lower edge and upper edge, outer → inner.
  List<LocalPt> brow(double dy) => [
    for (var j = 0; j <= 4; j++)
      (
        x: _lerp(-0.80, -0.16, j / 4),
        y: -0.30 - 0.05 * math.sin(math.pi * j / 4) + dy,
      ),
  ];
  mirrored(FaceMesh.rightBrowLower, FaceMesh.leftBrowLower, brow(0));
  mirrored(FaceMesh.rightBrowUpper, FaceMesh.leftBrowUpper, brow(-0.07));
  // Nose.
  const ridgeY = [-0.05, 0.10, 0.25, 0.40, 0.55, 0.66, 0.72];
  for (var k = 0; k < FaceMesh.noseRidge.length; k++) {
    put(FaceMesh.noseRidge[k], 0, ridgeY[k]);
  }
  put(2, 0, 0.83);
  mirrored([97, 98], [326, 327], [(x: -0.07, y: 0.82), (x: -0.17, y: 0.78)]);
  mirrored([45, 220, 115, 48, 64], [275, 440, 344, 278, 294], [
    (x: -0.06, y: 0.62),
    (x: -0.10, y: 0.60),
    (x: -0.16, y: 0.66),
    (x: -0.21, y: 0.70),
    (x: -0.20, y: 0.76),
  ]);
  mirrored(FaceMesh.rightBridgeSide, FaceMesh.leftBridgeSide, [
    (x: -0.08, y: 0.0),
    (x: -0.10, y: 0.12),
    (x: -0.09, y: 0.28),
    (x: -0.10, y: 0.42),
    (x: -0.11, y: 0.52),
  ]);
  // Lips: outer (corners ±0.42), inner (corners ±0.36).
  _lipLoop(m, FaceMesh.lipsOuter, 0.42, 0.14, 0.16);
  _lipLoop(
    m,
    FaceMesh.lipsInner,
    0.36,
    0.03 * mouthOpen + 0.004,
    0.06 * mouthOpen + 0.004,
  );
  // Forehead, glabella, crow's feet, folds, cheeks, chin.
  put(9, 0, -0.42);
  put(8, 0, -0.22);
  mirrored([71], [301], [(x: -0.92, y: -0.50)]);
  mirrored([113, 124, 156, 139, 34, 143], [342, 353, 383, 368, 264, 372], [
    (x: -0.82, y: -0.05),
    (x: -0.86, y: -0.12),
    (x: -0.80, y: -0.15),
    (x: -0.92, y: -0.05),
    (x: -0.92, y: 0.08),
    (x: -0.86, y: 0.12),
  ]);
  mirrored(FaceMesh.rightNasolabial, FaceMesh.leftNasolabial, [
    (x: -0.22, y: 0.70),
    (x: -0.27, y: 0.82),
    (x: -0.32, y: 0.95),
    (x: -0.37, y: 1.05),
    (x: -0.42, y: 1.20),
  ]);
  mirrored(FaceMesh.rightMarionette, FaceMesh.leftMarionette, [
    (x: -0.46, y: 1.18),
    (x: -0.46, y: 1.28),
    (x: -0.44, y: 1.40),
    (x: -0.42, y: 1.52),
    (x: -0.40, y: 1.62),
  ]);
  mirrored([50, 205, 123], [280, 425, 352], [
    (x: -0.62, y: 0.52),
    (x: -0.50, y: 0.68),
    (x: -0.78, y: 0.33),
  ]);
  put(175, 0, 1.78);
  put(199, 0, 1.68);
  put(200, 0, 1.58);
  mirrored(FaceMesh.rightChin, FaceMesh.leftChin, [
    (x: -0.16, y: 1.72),
    (x: -0.21, y: 1.62),
    (x: -0.23, y: 1.52),
    (x: -0.26, y: 1.42),
  ]);
  // Every other index: a deterministic spiral around the nose bridge.
  var k = 0;
  for (var i = 0; i < FaceMesh.landmarkCount; i++) {
    if (m.containsKey(i)) continue;
    final a = k * 2.399963, r = 0.05 + 0.002 * k;
    put(i, r * math.cos(a), 0.35 + r * math.sin(a));
    k++;
  }
  return m;
}

/// Upper lip from the right corner over the top to the left corner, then
/// the lower lip back (20-point loops of [FaceMesh.lipsOuter] order).
void _lipLoop(
  Map<int, LocalPt> m,
  List<int> loop,
  double halfW,
  double up,
  double down,
) {
  for (var j = 0; j <= 10; j++) {
    final t = j / 10;
    m[loop[j]] = (
      x: -halfW + 2 * halfW * t,
      y: kMouthY - up * math.sin(math.pi * t),
    );
  }
  for (var j = 1; j <= 9; j++) {
    final t = j / 10;
    m[loop[10 + j]] = (
      x: halfW - 2 * halfW * t,
      y: kMouthY + down * math.sin(math.pi * t),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
