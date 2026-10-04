import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';

/// Builds 478 normalized landmarks for a synthetic face (test fixture).
///
/// A 3-D toy head: outer eye corners at (±span/2, 0, 0), iris centres at
/// (±iod/2, 0, 0), nose tip at (0, 0.3·span, kNoseDepthToEyeSpan·span)
/// toward the camera, chin at (0, 0.9·span, 0). It is turned by [yawDegrees]
/// about the vertical axis, projected orthographically, rolled in-plane by
/// [rollDegrees] and placed at ([cx], [cy]) source pixels. Every other mesh
/// point sits at the face centre.
List<double> syntheticLandmarks({
  required int imageWidth,
  required int imageHeight,
  double cx = 500,
  double cy = 400,
  double iod = 100,
  double yawDegrees = 0,
  double rollDegrees = 0,
  double irisRadius = 6,
}) {
  final span = iod * 1.45;
  final yaw = yawDegrees * math.pi / 180;
  final roll = rollDegrees * math.pi / 180;
  (double, double) project(double x, double y, double z) {
    final px = x * math.cos(yaw) + z * math.sin(yaw);
    final rx = px * math.cos(roll) - y * math.sin(roll);
    final ry = px * math.sin(roll) + y * math.cos(roll);
    return (cx + rx, cy + ry);
  }

  final pts = List<(double, double)>.filled(MeshKeypoints.pointCount, (cx, cy));
  pts[MeshKeypoints.rightEyeOuter] = project(-span / 2, 0, 0);
  pts[MeshKeypoints.leftEyeOuter] = project(span / 2, 0, 0);
  pts[MeshKeypoints.rightIrisCenter] = project(-iod / 2, 0, 0);
  pts[MeshKeypoints.leftIrisCenter] = project(iod / 2, 0, 0);
  pts[MeshKeypoints.noseTip] = project(
    0,
    0.3 * span,
    kNoseDepthToEyeSpan * span,
  );
  pts[MeshKeypoints.chin] = project(0, 0.9 * span, 0);
  void ring(int center, List<int> ring) {
    final (ox, oy) = pts[center];
    for (var k = 0; k < ring.length; k++) {
      final a = k * math.pi / 2;
      pts[ring[k]] = (
        ox + irisRadius * math.cos(a),
        oy + irisRadius * math.sin(a),
      );
    }
  }

  ring(MeshKeypoints.rightIrisCenter, MeshKeypoints.rightIrisRing);
  ring(MeshKeypoints.leftIrisCenter, MeshKeypoints.leftIrisRing);
  return [
    for (final (x, y) in pts) ...[x / imageWidth, y / imageHeight],
  ];
}

/// A detection normalized to a [imageWidth]×[imageHeight] image, with the
/// eye keypoints placed a third of the way down the box.
FaceDetection syntheticDetection({
  required double x,
  required double y,
  required double size,
  int imageWidth = 1000,
  int imageHeight = 1000,
  double score = 0.9,
}) {
  final w = size / imageWidth;
  final h = size / imageHeight;
  final x0 = x / imageWidth;
  final y0 = y / imageHeight;
  return FaceDetection(
    xMin: x0,
    yMin: y0,
    width: w,
    height: h,
    keypoints: [
      x0 + w * 0.3, y0 + h * 0.35, // right eye
      x0 + w * 0.7, y0 + h * 0.35, // left eye
      x0 + w * 0.5, y0 + h * 0.55, // nose
      x0 + w * 0.5, y0 + h * 0.75, // mouth
      x0, y0 + h * 0.4, // right tragion
      x0 + w, y0 + h * 0.4, // left tragion
    ],
    score: score,
  );
}
