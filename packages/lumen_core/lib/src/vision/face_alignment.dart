import 'dart:math' as math;
import 'dart:typed_data';

import 'affine.dart';
import 'face_detection.dart';
import 'mesh_keypoints.dart';

/// A square, rotated crop of the source that the landmark model sees, with
/// the eyes level (research 07 §1.2 step 2).
///
/// Coordinates are continuous pixels: pixel (i, j) covers [i, i+1)×[j, j+1),
/// so its centre is (i + 0.5, j + 0.5). The crop spans [0, outputSize]².
class AlignedCrop {
  const AlignedCrop({
    required this.centerX,
    required this.centerY,
    required this.side,
    required this.rotation,
    this.outputSize = 256,
  });

  /// From a detection normalized to the image: centre = box centre,
  /// side = long side × [scale] (1.5 = the card's 25 % margin per side),
  /// roll = angle of the right-eye → left-eye keypoint line.
  factory AlignedCrop.fromDetection(
    FaceDetection det, {
    required int imageWidth,
    required int imageHeight,
    double scale = 1.5,
    int outputSize = 256,
  }) {
    final w = det.width * imageWidth;
    final h = det.height * imageHeight;
    var rotation = 0.0;
    if (det.keypointCount > BlazeFaceKeypoint.leftEye) {
      final rx = det.keypointX(BlazeFaceKeypoint.rightEye) * imageWidth;
      final ry = det.keypointY(BlazeFaceKeypoint.rightEye) * imageHeight;
      final lx = det.keypointX(BlazeFaceKeypoint.leftEye) * imageWidth;
      final ly = det.keypointY(BlazeFaceKeypoint.leftEye) * imageHeight;
      rotation = math.atan2(ly - ry, lx - rx);
    }
    return AlignedCrop(
      centerX: det.centerX * imageWidth,
      centerY: det.centerY * imageHeight,
      side: math.max(w, h) * scale,
      rotation: rotation,
      outputSize: outputSize,
    );
  }

  /// The refine pass (§1.2 step 4): the crop recomputed from first-pass mesh
  /// landmarks ([landmarks] = flat normalized x, y), as MediaPipe's tracking
  /// mode does: bbox of all points, roll from 33 → 263, × [scale].
  factory AlignedCrop.fromLandmarks(
    List<double> landmarks, {
    required int imageWidth,
    required int imageHeight,
    double scale = 1.5,
    int outputSize = 256,
  }) {
    final n = landmarks.length ~/ 2;
    if (n <= MeshKeypoints.leftEyeOuter) {
      throw ArgumentError('need >= ${MeshKeypoints.leftEyeOuter + 1} points');
    }
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = double.negativeInfinity, y1 = double.negativeInfinity;
    for (var i = 0; i < n; i++) {
      final x = landmarks[2 * i] * imageWidth;
      final y = landmarks[2 * i + 1] * imageHeight;
      x0 = math.min(x0, x);
      y0 = math.min(y0, y);
      x1 = math.max(x1, x);
      y1 = math.max(y1, y);
    }
    double px(int i) => landmarks[2 * i] * imageWidth;
    double py(int i) => landmarks[2 * i + 1] * imageHeight;
    const r = MeshKeypoints.rightEyeOuter;
    const l = MeshKeypoints.leftEyeOuter;
    return AlignedCrop(
      centerX: (x0 + x1) / 2,
      centerY: (y0 + y1) / 2,
      side: math.max(x1 - x0, y1 - y0) * scale,
      rotation: math.atan2(py(l) - py(r), px(l) - px(r)),
      outputSize: outputSize,
    );
  }

  /// Crop centre and side, in source pixels.
  final double centerX;
  final double centerY;
  final double side;

  /// Roll in radians (image coordinates, y down). The crop's +x axis points
  /// along the eye line, so the eyes come out level.
  final double rotation;

  /// Model input size (square).
  final int outputSize;

  /// Crop pixels → source pixels.
  Affine2x3 get cropToSource {
    final k = side / outputSize;
    final cs = math.cos(rotation) * k;
    final sn = math.sin(rotation) * k;
    final half = outputSize / 2;
    return Affine2x3(
      cs,
      -sn,
      centerX - cs * half + sn * half,
      sn,
      cs,
      centerY - sn * half - cs * half,
    );
  }

  /// Source pixels → crop pixels (the 2×3 used to sample the model input).
  Affine2x3 get sourceToCrop => cropToSource.inverse();

  @override
  String toString() =>
      'AlignedCrop(c: ${centerX.toStringAsFixed(1)}, '
      '${centerY.toStringAsFixed(1)}, side: ${side.toStringAsFixed(1)}, '
      'roll: ${(rotation * 180 / math.pi).toStringAsFixed(1)}°)';
}

/// Maps raw mesh output ([raw]: x, y[, z] per point in crop-input pixels,
/// 0..[inputSize]) back through [crop] to normalized source coordinates.
/// Returns flat (x, y) pairs, the [DetectedFace.landmarks] layout.
List<double> landmarksToSource(
  Float32List raw,
  AlignedCrop crop, {
  required int imageWidth,
  required int imageHeight,
  int valuesPerPoint = 3,
  int? inputSize,
}) {
  if (valuesPerPoint < 2) {
    throw ArgumentError.value(valuesPerPoint, 'valuesPerPoint', 'must be >= 2');
  }
  final n = raw.length ~/ valuesPerPoint;
  final unit = crop.outputSize / (inputSize ?? crop.outputSize);
  final m = crop.cropToSource;
  final out = Float64List(n * 2);
  for (var i = 0; i < n; i++) {
    final u = raw[i * valuesPerPoint] * unit;
    final v = raw[i * valuesPerPoint + 1] * unit;
    final (x, y) = m.apply(u, v);
    out[2 * i] = x / imageWidth;
    out[2 * i + 1] = y / imageHeight;
  }
  return List.unmodifiable(out);
}
