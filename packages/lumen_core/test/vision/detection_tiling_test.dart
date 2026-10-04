import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'synthetic_face.dart';

void main() {
  const w = 4000, h = 3000;

  FaceDetection face(double x, double y, double size, [double score = 0.9]) =>
      syntheticDetection(
        x: x,
        y: y,
        size: size,
        imageWidth: w,
        imageHeight: h,
        score: score,
      );

  group('planDetectionTiles', () {
    test('no tiling for up to 4 normal-size faces or none', () {
      final four = [
        for (var i = 0; i < 4; i++) face(200.0 + i * 900, 1000, 400),
      ];
      expect(
        planDetectionTiles(imageWidth: w, imageHeight: h, detections: four),
        isEmpty,
      );
      expect(
        planDetectionTiles(imageWidth: w, imageHeight: h, detections: []),
        isEmpty,
      );
    });

    test('more than 4 faces → 2×2 tiles with 25 % overlap', () {
      final five = [
        for (var i = 0; i < 5; i++) face(100.0 + i * 700, 1000, 400),
      ];
      final tiles = planDetectionTiles(
        imageWidth: w,
        imageHeight: h,
        detections: five,
      );
      expect(tiles, hasLength(4));
      const size = 1 / 1.75;
      expect(tiles.first, const DetectionTile(0, 0, size, size));
      expect(tiles[1].x, closeTo(0.75 * size, 1e-12));
      expect(tiles[1].x + tiles[1].width, closeTo(1, 1e-12));
      expect(tiles[3].y + tiles[3].height, closeTo(1, 1e-12));
      // Overlap is 25 % of the tile.
      final overlap = tiles[0].x + tiles[0].width - tiles[1].x;
      expect(overlap / size, closeTo(0.25, 1e-12));
    });

    test('a face under 4 % of the long edge → tiles', () {
      // 150 px < 4 % of 4000 = 160 px.
      expect(
        planDetectionTiles(
          imageWidth: w,
          imageHeight: h,
          detections: [face(2000, 1500, 150)],
        ),
        hasLength(4),
      );
      expect(
        planDetectionTiles(
          imageWidth: w,
          imageHeight: h,
          detections: [face(2000, 1500, 170)],
        ),
        isEmpty,
      );
    });
  });

  group('mergeTileDetections', () {
    test('a face seen full-frame and in a tile is fused; new ones added', () {
      final tiles = gridTiles();
      final t0 = tiles.first;
      final full = face(400, 400, 200, 0.8);
      // The same face as tile 0 sees it (tile-normalized).
      final inTile = FaceDetection(
        xMin: (full.xMin - t0.x) / t0.width,
        yMin: (full.yMin - t0.y) / t0.height,
        width: full.width / t0.width,
        height: full.height / t0.height,
        keypoints: const [],
        score: 0.85,
      );
      // A small face only the tile found, well inside the tile.
      const small = FaceDetection.new;
      final extra = small(
        xMin: 0.6,
        yMin: 0.6,
        width: 0.04,
        height: 0.05,
        keypoints: const [],
        score: 0.7,
      );
      final merged = mergeTileDetections(
        fullFrame: [full],
        tiles: [
          (t0, [inTile, extra]),
        ],
      );
      expect(merged, hasLength(2));
      expect(merged.first.score, 0.85);
      expect(merged.first.centerX, closeTo(full.centerX, 1e-9));
      expect(merged.last.xMin, closeTo(t0.x + 0.6 * t0.width, 1e-12));
    });

    test('cut faces on an inner tile edge are dropped', () {
      final t0 = gridTiles().first; // inner edges: right and bottom
      final cut = FaceDetection(
        xMin: 0.95,
        yMin: 0.4,
        width: 0.05,
        height: 0.1,
        keypoints: const [],
        score: 0.9,
      );
      final atImageEdge = FaceDetection(
        xMin: 0.0,
        yMin: 0.4,
        width: 0.05,
        height: 0.1,
        keypoints: const [],
        score: 0.9,
      );
      final merged = mergeTileDetections(
        fullFrame: const [],
        tiles: [
          (t0, [cut, atImageEdge]),
        ],
      );
      expect(merged, hasLength(1));
      expect(merged.single.xMin, 0);
    });

    test('tile pixel bounds stay inside the image', () {
      for (final t in gridTiles()) {
        final b = t.pixelBounds(w, h);
        expect(b.left, greaterThanOrEqualTo(0));
        expect(b.left + b.width, lessThanOrEqualTo(w));
        expect(b.top + b.height, lessThanOrEqualTo(h));
      }
      expect(() => gridTiles(overlap: 1), throwsArgumentError);
    });
  });
}
