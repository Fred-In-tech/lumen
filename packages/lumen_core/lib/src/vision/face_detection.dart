import 'dart:math' as math;

import '../model/face_analysis.dart';

/// BlazeFace keypoint order (6 points, as the detector emits them).
abstract final class BlazeFaceKeypoint {
  /// Subject's right eye (image left in a non-mirrored photo).
  static const rightEye = 0;
  static const leftEye = 1;
  static const noseTip = 2;
  static const mouthCenter = 3;
  static const rightEarTragion = 4;
  static const leftEarTragion = 5;
  static const count = 6;
}

/// One detected face: an axis-aligned box plus keypoints, normalized to the
/// space it was decoded in (detector input, tile, or the whole image).
class FaceDetection {
  FaceDetection({
    required this.xMin,
    required this.yMin,
    required this.width,
    required this.height,
    required List<double> keypoints,
    required this.score,
  }) : keypoints = List.unmodifiable(keypoints);

  final double xMin;
  final double yMin;
  final double width;
  final double height;

  /// Flat (x, y) pairs in [BlazeFaceKeypoint] order.
  final List<double> keypoints;

  /// Sigmoid confidence in 0..1.
  final double score;

  double get xMax => xMin + width;
  double get yMax => yMin + height;
  double get centerX => xMin + width / 2;
  double get centerY => yMin + height / 2;
  double get area => math.max(0, width) * math.max(0, height);
  int get keypointCount => keypoints.length ~/ 2;

  double keypointX(int i) => keypoints[2 * i];
  double keypointY(int i) => keypoints[2 * i + 1];

  /// Maps every coordinate with x' = offsetX + x·scaleX (same for y). Used to
  /// undo letterboxing and to lift tile detections into image space.
  FaceDetection mapped({
    double offsetX = 0,
    double offsetY = 0,
    double scaleX = 1,
    double scaleY = 1,
  }) => FaceDetection(
    xMin: offsetX + xMin * scaleX,
    yMin: offsetY + yMin * scaleY,
    width: width * scaleX,
    height: height * scaleY,
    keypoints: [
      for (var i = 0; i < keypoints.length; i += 2) ...[
        offsetX + keypoints[i] * scaleX,
        offsetY + keypoints[i + 1] * scaleY,
      ],
    ],
    score: score,
  );

  /// Intersection over union of the two boxes (0 when either is empty).
  double iou(FaceDetection other) {
    final ix = math.min(xMax, other.xMax) - math.max(xMin, other.xMin);
    final iy = math.min(yMax, other.yMax) - math.max(yMin, other.yMin);
    if (ix <= 0 || iy <= 0) return 0;
    final inter = ix * iy;
    final union = area + other.area - inter;
    return union <= 0 ? 0 : inter / union;
  }

  /// The box clamped to 0..1 as the persisted [FaceBox].
  FaceBox toFaceBox() {
    final x0 = xMin.clamp(0.0, 1.0);
    final y0 = yMin.clamp(0.0, 1.0);
    final x1 = xMax.clamp(0.0, 1.0);
    final y1 = yMax.clamp(0.0, 1.0);
    return FaceBox(x0, y0, x1 - x0, y1 - y0);
  }

  @override
  String toString() =>
      'FaceDetection(${xMin.toStringAsFixed(3)}, ${yMin.toStringAsFixed(3)}, '
      '${width.toStringAsFixed(3)}x${height.toStringAsFixed(3)}, '
      'score ${score.toStringAsFixed(3)})';
}
