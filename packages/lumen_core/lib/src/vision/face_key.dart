import 'dart:math' as math;

import '../model/face_analysis.dart';

/// Grid that [faceKey] snaps face centres to (1/64 of each axis).
const kFaceKeyGrid = 64;

/// Non-identifying per-photo face id: the normalized box centre rounded to
/// 1/[kFaceKeyGrid] (research 07 §1.5). Stable across re-analysis of the same
/// photo, meaningless across photos. Example: `f32_17`.
String faceKey(FaceBox box) {
  final ix = (box.centerX * kFaceKeyGrid).round();
  final iy = (box.centerY * kFaceKeyGrid).round();
  return 'f${ix}_$iy';
}

/// Pixel rectangle for the per-face Selfie Multiclass crop.
class SegmentationCrop {
  const SegmentationCrop(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  bool get isSquare => width == height;

  FaceBox toFaceBox(int imageWidth, int imageHeight) => FaceBox(
    left / imageWidth,
    top / imageHeight,
    width / imageWidth,
    height / imageHeight,
  );

  @override
  bool operator ==(Object other) =>
      other is SegmentationCrop &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'SegmentationCrop($left, $top, ${width}x$height)';
}

/// The axis-aligned crop for per-face segmentation (research 07 §2.2 step 1):
/// box long side × [scale], squared in pixels, shifted inside the image when
/// it fits and clamped to the image when it does not.
SegmentationCrop segmentationCropFor(
  FaceBox box, {
  required int imageWidth,
  required int imageHeight,
  double scale = 2.2,
}) {
  final side =
      math.max(box.width * imageWidth, box.height * imageHeight) * scale;
  final (left, width) = _fit(box.centerX * imageWidth, side, imageWidth);
  final (top, height) = _fit(box.centerY * imageHeight, side, imageHeight);
  return SegmentationCrop(left, top, width, height);
}

(int, int) _fit(double center, double side, int extent) {
  final size = math.min(side.round(), extent);
  if (size <= 0) return (0, 0);
  final start = (center - size / 2).round().clamp(0, extent - size);
  return (start, size);
}
