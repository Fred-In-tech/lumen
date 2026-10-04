import 'dart:math' as math;
import 'dart:typed_data';

import 'face_detection.dart';
import 'ssd_anchors.dart';

/// MediaPipe `TensorsToDetectionsCalculator` options for BlazeFace.
class BlazeFaceDecodeOptions {
  const BlazeFaceDecodeOptions({
    required this.xScale,
    required this.yScale,
    required this.wScale,
    required this.hScale,
    this.numCoords = 16,
    this.boxCoordOffset = 0,
    this.keypointCoordOffset = 4,
    this.numKeypoints = BlazeFaceKeypoint.count,
    this.valuesPerKeypoint = 2,
    this.scoreClippingThreshold = 100,
    this.minScore = 0.5,
    this.reverseOutputOrder = true,
  });

  /// Scales equal to the detector input size, as MediaPipe configures them.
  /// [numCoords] comes from the regressor's last dimension.
  factory BlazeFaceDecodeOptions.forInput({
    required int inputWidth,
    required int inputHeight,
    int numCoords = 16,
    double minScore = 0.5,
  }) {
    const keypointOffset = 4;
    return BlazeFaceDecodeOptions(
      xScale: inputWidth.toDouble(),
      yScale: inputHeight.toDouble(),
      wScale: inputWidth.toDouble(),
      hScale: inputHeight.toDouble(),
      numCoords: numCoords,
      numKeypoints: math.max(0, (numCoords - keypointOffset) ~/ 2),
      minScore: minScore,
    );
  }

  final double xScale;
  final double yScale;
  final double wScale;
  final double hScale;
  final int numCoords;
  final int boxCoordOffset;
  final int keypointCoordOffset;
  final int numKeypoints;
  final int valuesPerKeypoint;

  /// Raw logits are clipped to ±this before the sigmoid.
  final double scoreClippingThreshold;
  final double minScore;

  /// True when the box is stored x, y, w, h (BlazeFace); false for y, x, h, w.
  final bool reverseOutputOrder;
}

/// Logistic sigmoid.
double logistic(double x) => 1 / (1 + math.exp(-x));

/// Decodes BlazeFace raw tensors into detections normalized to the detector
/// input (before letterbox removal). Scores below [BlazeFaceDecodeOptions.minScore]
/// are dropped. Run [weightedNonMaxSuppression] on the result.
List<FaceDetection> decodeBlazeFace({
  required Float32List regressors,
  required Float32List scores,
  required List<SsdAnchor> anchors,
  required BlazeFaceDecodeOptions options,
}) {
  final o = options;
  final n = anchors.length;
  if (regressors.length != n * o.numCoords) {
    throw ArgumentError(
      'regressors has ${regressors.length} values, expected '
      '$n anchors x ${o.numCoords}',
    );
  }
  if (scores.length != n) {
    throw ArgumentError('scores has ${scores.length} values, expected $n');
  }
  final clip = o.scoreClippingThreshold;
  final out = <FaceDetection>[];
  for (var i = 0; i < n; i++) {
    final score = logistic(scores[i].clamp(-clip, clip).toDouble());
    if (score < o.minScore) continue;
    final a = anchors[i];
    final base = i * o.numCoords;
    final b = base + o.boxCoordOffset;
    final double rx, ry, rw, rh;
    if (o.reverseOutputOrder) {
      (rx, ry, rw, rh) = (
        regressors[b],
        regressors[b + 1],
        regressors[b + 2],
        regressors[b + 3],
      );
    } else {
      (ry, rx, rh, rw) = (
        regressors[b],
        regressors[b + 1],
        regressors[b + 2],
        regressors[b + 3],
      );
    }
    final cx = rx / o.xScale * a.width + a.centerX;
    final cy = ry / o.yScale * a.height + a.centerY;
    final w = rw / o.wScale * a.width;
    final h = rh / o.hScale * a.height;
    final keypoints = <double>[];
    for (var k = 0; k < o.numKeypoints; k++) {
      final kb = base + o.keypointCoordOffset + k * o.valuesPerKeypoint;
      final kx = o.reverseOutputOrder ? regressors[kb] : regressors[kb + 1];
      final ky = o.reverseOutputOrder ? regressors[kb + 1] : regressors[kb];
      keypoints
        ..add(kx / o.xScale * a.width + a.centerX)
        ..add(ky / o.yScale * a.height + a.centerY);
    }
    if (w <= 0 || h <= 0) continue;
    out.add(
      FaceDetection(
        xMin: cx - w / 2,
        yMin: cy - h / 2,
        width: w,
        height: h,
        keypoints: keypoints,
        score: score,
      ),
    );
  }
  return out;
}
