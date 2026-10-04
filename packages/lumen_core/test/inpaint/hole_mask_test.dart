import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('PixelBox', () {
    test('union, intersect, inflate and overlap', () {
      const a = PixelBox(10, 10, 20, 10);
      const b = PixelBox(25, 15, 10, 10);
      expect(a.union(b), const PixelBox(10, 10, 25, 15));
      expect(a.intersect(b), const PixelBox(25, 15, 5, 5));
      expect(a.overlaps(b), isTrue);
      expect(a.overlaps(const PixelBox(30, 10, 5, 5)), isFalse);
      expect(a.inflate(2), const PixelBox(8, 8, 24, 14));
      expect(a.intersect(const PixelBox(100, 100, 1, 1)).isEmpty, isTrue);
      expect(PixelBox.tryFromJson(a.toJson()), a);
      expect(PixelBox.tryFromJson('x'), isNull);
    });
  });

  group('rasterizeHoleMask', () {
    test('matches MaskRasterizer coverage >= 0.5 for add and erase', () {
      const strokes = [
        BrushStroke(
          points: [(0.2, 0.3), (0.7, 0.4)],
          radius: 0.06,
          hardness: 0.3,
        ),
        BrushStroke(points: [(0.5, 0.5)], radius: 0.1, hardness: 0.8),
        BrushStroke(
          points: [(0.45, 0.35)],
          radius: 0.05,
          hardness: 0.5,
          erase: true,
        ),
      ];
      const w = 120, h = 80;
      final ref = MaskRasterizer.rasterize(
        const LocalMask(
          id: 'm',
          name: 'm',
          kind: MaskKind.brush,
          strokes: strokes,
        ),
        w,
        h,
      );
      final hole = rasterizeHoleMask(strokes, w, h);
      var holes = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final expected = ref[y * w + x] >= 128;
          expect(hole.isHole(x, y), expected, reason: '($x, $y)');
          if (expected) holes++;
        }
      }
      expect(holes, greaterThan(100));
      expect(hole.holeCount, holes);
    });

    test('limits storage to the stroke region and reports a tight bbox', () {
      const s = BrushStroke(points: [(0.5, 0.5)], radius: 0.01, hardness: 1);
      final m = rasterizeHoleMask([s], 4000, 3000);
      expect(m.rect.width, lessThan(200));
      expect(m.bbox.width, inInclusiveRange(78, 82)); // diameter 80 px
      expect(m.bbox.x, inInclusiveRange(1958, 1962));
      expect(m.isHole(2000, 1500), isTrue);
      expect(m.isHole(10, 10), isFalse);
    });

    test('empty strokes give an empty mask', () {
      final m = rasterizeHoleMask(const [], 100, 100);
      expect(m.holeCount, 0);
      expect(m.bbox.isEmpty, isTrue);
    });
  });

  group('dilation', () {
    test('holeDilationPx is 6 px + 1 % of the long edge', () {
      expect(holeDilationPx(6000, 4000), 66);
      expect(holeDilationPx(400, 1000), 16);
    });

    test('dilates by a Euclidean disc and clamps to the source', () {
      final m = HoleMask.fromPixels(50, 50, [(25, 25), (0, 0)]);
      final d = m.dilated(5);
      expect(d.isHole(30, 25), isTrue);
      expect(d.isHole(31, 25), isFalse);
      expect(d.isHole(28, 29), isTrue); // 3² + 4² = 25
      expect(d.isHole(29, 29), isFalse); // 4² + 4² = 32
      expect(d.rect.x, 0);
      expect(d.bbox, const PixelBox(0, 0, 31, 31));
    });
  });

  group('components', () {
    test('splits disjoint holes with their pixel counts', () {
      final m = HoleMask.fromPixels(40, 40, [
        (2, 2),
        (3, 2),
        (3, 3),
        (30, 30),
        (31, 31), // 8-connected to (30, 30)
      ]);
      final c = m.components();
      expect(c.length, 2);
      expect(c[0].bbox, const PixelBox(2, 2, 2, 2));
      expect(c[0].pixelCount, 3);
      expect(c[1].bbox, const PixelBox(30, 30, 2, 2));
      expect(c[1].pixelCount, 2);
    });
  });

  group('keepMaskFor', () {
    test('255 = keep, 0 = hole, mirrored outside the source', () {
      final m = HoleMask.fromPixels(10, 10, [(1, 1)]);
      final keep = m.keepMaskFor(const PixelBox(-3, -3, 8, 8));
      // crop (0,0) = source (-3,-3) → mirror (3,3): keep
      expect(keep[0], 255);
      // crop (4,4) = source (1,1): hole
      expect(keep[4 * 8 + 4], 0);
      // crop (2,2) = source (-1,-1) → mirror (1,1): hole
      expect(keep[2 * 8 + 2], 0);
    });
  });

  group('squaredDistanceTransform', () {
    test('exact squared Euclidean distance to the nearest seed', () {
      final seeds = Uint8List(7 * 5);
      seeds[2 * 7 + 3] = 1;
      final d = squaredDistanceTransform(seeds, 7, 5);
      expect(d[2 * 7 + 3], 0);
      expect(d[0], 9 + 4);
      expect(d[4 * 7 + 6], 9 + 4);
      expect(d[2 * 7 + 6], 9);
    });
  });
}
