import 'dart:math' as math;

import 'face_detection.dart';
import 'weighted_nms.dart';

/// A detection tile, normalized to the image (0..1).
class DetectionTile {
  const DetectionTile(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  /// Lifts a detection normalized to this tile into image space.
  FaceDetection toImage(FaceDetection d) =>
      d.mapped(offsetX: x, offsetY: y, scaleX: width, scaleY: height);

  /// Pixel bounds (floor/ceil, clamped) for sampling this tile.
  ({int left, int top, int width, int height}) pixelBounds(
    int imageWidth,
    int imageHeight,
  ) {
    final l = (x * imageWidth).floor().clamp(0, imageWidth - 1);
    final t = (y * imageHeight).floor().clamp(0, imageHeight - 1);
    final r = ((x + width) * imageWidth).ceil().clamp(l + 1, imageWidth);
    final b = ((y + height) * imageHeight).ceil().clamp(t + 1, imageHeight);
    return (left: l, top: t, width: r - l, height: b - t);
  }

  @override
  bool operator ==(Object other) =>
      other is DetectionTile &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'DetectionTile($x, $y, $width, $height)';
}

/// When a group shot gets a second, tiled detection pass (research 07 §1.2).
class TilingPolicy {
  const TilingPolicy({
    this.maxFacesWithoutTiling = 4,
    this.minFaceFraction = 0.04,
    this.grid = 2,
    this.overlap = 0.25,
  });

  /// More faces than this in the full-frame pass → tile.
  final int maxFacesWithoutTiling;

  /// Any face whose long side is under this fraction of the image long edge
  /// → tile.
  final double minFaceFraction;
  final int grid;

  /// Overlap between neighbouring tiles as a fraction of the tile size.
  final double overlap;
}

/// The tiles for the second pass, or an empty list when the full-frame
/// [detections] (normalized to the image) do not call for tiling.
List<DetectionTile> planDetectionTiles({
  required int imageWidth,
  required int imageHeight,
  required List<FaceDetection> detections,
  TilingPolicy policy = const TilingPolicy(),
}) {
  if (detections.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
    return const [];
  }
  final longEdge = math.max(imageWidth, imageHeight).toDouble();
  final hasSmallFace = detections.any(
    (d) =>
        math.max(d.width * imageWidth, d.height * imageHeight) / longEdge <
        policy.minFaceFraction,
  );
  if (detections.length <= policy.maxFacesWithoutTiling && !hasSmallFace) {
    return const [];
  }
  return gridTiles(grid: policy.grid, overlap: policy.overlap);
}

/// A [grid]×[grid] cover of the unit square whose neighbours overlap by
/// [overlap] of the tile size: tile = 1 / (grid − (grid − 1)·overlap).
List<DetectionTile> gridTiles({int grid = 2, double overlap = 0.25}) {
  if (grid < 1) throw ArgumentError.value(grid, 'grid', 'must be >= 1');
  if (overlap < 0 || overlap >= 1) {
    throw ArgumentError.value(overlap, 'overlap', 'must be in [0, 1)');
  }
  final size = 1 / (grid - (grid - 1) * overlap);
  final step = size * (1 - overlap);
  return List.unmodifiable([
    for (var row = 0; row < grid; row++)
      for (var col = 0; col < grid; col++)
        DetectionTile(col * step, row * step, size, size),
  ]);
}

/// Merges the full-frame pass with the tile passes.
///
/// [fullFrame] is normalized to the image; each tile's detections are
/// normalized to that tile. Tile detections touching an edge of their tile
/// that lies inside the image are dropped (the face is cut; with the overlap
/// it appears whole in a neighbour). Everything is fused with weighted NMS.
List<FaceDetection> mergeTileDetections({
  required List<FaceDetection> fullFrame,
  required List<(DetectionTile, List<FaceDetection>)> tiles,
  double iouThreshold = 0.3,
  double edgeMargin = 0.005,
}) {
  final all = <FaceDetection>[...fullFrame];
  for (final (tile, dets) in tiles) {
    for (final d in dets) {
      if (_touchesInnerEdge(tile, d, edgeMargin)) continue;
      all.add(tile.toImage(d));
    }
  }
  return weightedNonMaxSuppression(all, iouThreshold: iouThreshold);
}

bool _touchesInnerEdge(DetectionTile t, FaceDetection d, double m) {
  const eps = 1e-9;
  final innerLeft = t.x > eps;
  final innerTop = t.y > eps;
  final innerRight = t.x + t.width < 1 - eps;
  final innerBottom = t.y + t.height < 1 - eps;
  return (innerLeft && d.xMin <= m) ||
      (innerTop && d.yMin <= m) ||
      (innerRight && d.xMax >= 1 - m) ||
      (innerBottom && d.yMax >= 1 - m);
}
