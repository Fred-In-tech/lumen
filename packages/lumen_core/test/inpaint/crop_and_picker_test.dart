import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

HoleMask _rectMask(int sw, int sh, int x, int y, int w, int h) =>
    HoleMask.fromPixels(sw, sh, [
      for (var yy = y; yy < y + h; yy++)
        for (var xx = x; xx < x + w; xx++) (xx, yy),
    ]);

HoleMask _discMask(int sw, int sh, int cx, int cy, int r) =>
    HoleMask.fromPixels(sw, sh, [
      for (var y = cy - r; y <= cy + r; y++)
        for (var x = cx - r; x <= cx + r; x++)
          if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) (x, y),
    ]);

void main() {
  group('planContextCrop', () {
    test('small hole: 512 square centred on the hole', () {
      final c = planContextCrop(
        const PixelBox(2950, 1970, 100, 60),
        6000,
        4000,
      );
      expect(c, const PixelBox(2744, 1744, 512, 512));
    });

    test('side = 2.5 x hole, clamped to 2048', () {
      expect(
        planContextCrop(const PixelBox(1000, 1000, 300, 200), 6000, 4000).width,
        750,
      );
      expect(
        planContextCrop(const PixelBox(1000, 1000, 1000, 10), 6000, 4000).width,
        2048,
      );
    });

    test('a hole larger than the max side still fits with a margin', () {
      final c = planContextCrop(
        const PixelBox(500, 500, 2000, 100),
        6000,
        4000,
      );
      expect(c.width, 2000 + 2 * const CropPolicy().minMargin);
      expect(c.x, lessThanOrEqualTo(500));
      expect(c.right, greaterThanOrEqualTo(2500));
    });

    test('shifted inside the image at the borders', () {
      final tl = planContextCrop(const PixelBox(10, 10, 300, 300), 6000, 4000);
      expect(tl, const PixelBox(0, 0, 750, 750));
      final br = planContextCrop(
        const PixelBox(5900, 3950, 90, 40),
        6000,
        4000,
      );
      expect(br.right, 6000);
      expect(br.bottom, 4000);
      expect(br.width, 512);
    });

    test('source smaller than the crop: covers it, mirror-pads the rest', () {
      final c = planContextCrop(const PixelBox(10, 100, 40, 40), 400, 300);
      expect(c.width, 512);
      expect(c.x, lessThanOrEqualTo(0));
      expect(c.right, greaterThanOrEqualTo(400));
      expect(c.y, lessThanOrEqualTo(0));
      expect(c.bottom, greaterThanOrEqualTo(300));
      final src = RgbaBuffer(400, 300);
      for (var y = 0; y < 300; y++) {
        for (var x = 0; x < 400; x++) {
          src.setPixel(x, y, x % 256, y % 256, (x + y) % 256);
        }
      }
      final crop = extractCrop(src, c);
      // crop pixel for source (-1, 5) mirrors source (1, 5).
      final cx = -1 - c.x, cy = 5 - c.y;
      expect(crop.r(cx, cy), 1);
      expect(crop.g(cx, cy), 5);
      // crop pixel for source (5, 300) mirrors (5, 298).
      expect(crop.g(5 - c.x, 300 - c.y), 298 % 256);
      // inside pixels are copied verbatim.
      expect(crop.b(20 - c.x, 30 - c.y), 50);
    });
  });

  group('planCrops', () {
    test('disjoint holes get one crop each; overlapping crops merge', () {
      final far = planCrops(
        [const PixelBox(500, 500, 50, 50), const PixelBox(3500, 3000, 50, 50)],
        6000,
        4000,
      );
      expect(far.length, 2);
      final near = planCrops(
        [const PixelBox(500, 500, 50, 50), const PixelBox(800, 520, 50, 50)],
        6000,
        4000,
      );
      expect(near.length, 1);
      expect(near.single.holes, const PixelBox(500, 500, 350, 70));
      expect(near.single.crop.x, lessThanOrEqualTo(500));
      expect(near.single.crop.right, greaterThanOrEqualTo(850));
    });
  });

  group('HoleStats', () {
    test('measures area, inscribed radius and roundness', () {
      final disc = HoleStats.measure(_discMask(1000, 1000, 500, 500, 20));
      expect(disc.areaFraction, closeTo(3.14159 * 400 / 1e6, 2e-4));
      expect(disc.inscribedRadius, closeTo(20, 1.5));
      expect(disc.roundness, lessThan(1.5));
      final line = HoleStats.measure(_rectMask(1000, 1000, 100, 500, 600, 4));
      expect(line.inscribedRadius, lessThanOrEqualTo(2.5));
      expect(line.roundness, greaterThan(10));
    });
  });

  group('InpaintMethodPicker', () {
    test('thin and < 0.3 % → Telea', () {
      final s = HoleStats.measure(_rectMask(6000, 4000, 100, 500, 3000, 5));
      expect(s.areaFraction, lessThan(0.003));
      expect(
        InpaintMethodPicker.pick(s, modelAvailable: true),
        InpaintMethod.telea,
      );
    });

    test('small round → push-pull', () {
      final s = HoleStats.measure(_discMask(6000, 4000, 3000, 2000, 15));
      expect(
        InpaintMethodPicker.pick(s, modelAvailable: true),
        InpaintMethod.pushPull,
      );
    });

    test('everything else → model when available, else PatchMatch', () {
      final s = HoleStats.measure(_discMask(1000, 1000, 500, 500, 80));
      expect(s.areaFraction, greaterThan(0.003));
      expect(
        InpaintMethodPicker.pick(s, modelAvailable: true),
        InpaintMethod.model,
      );
      expect(
        InpaintMethodPicker.pick(s, modelAvailable: false),
        InpaintMethod.patchMatch,
      );
      // A thick (not thin) small blob is not a push-pull spot either.
      final blob = HoleStats.measure(_rectMask(6000, 4000, 100, 100, 200, 60));
      expect(blob.areaFraction, lessThan(0.003));
      expect(
        InpaintMethodPicker.pick(blob, modelAvailable: false),
        InpaintMethod.patchMatch,
      );
    });

    test('a long thin stroke above 0.3 % is not Telea', () {
      final s = HoleStats.measure(_rectMask(1000, 1000, 0, 500, 1000, 4));
      expect(s.areaFraction, greaterThan(0.003));
      expect(
        InpaintMethodPicker.pick(s, modelAvailable: false),
        InpaintMethod.patchMatch,
      );
    });
  });

  group('faces', () {
    test('holeIntersectsFaces checks hole pixels against normalized boxes', () {
      final m = _discMask(1000, 800, 500, 400, 10);
      expect(
        holeIntersectsFaces(m, const [FaceBox(0.45, 0.45, 0.1, 0.1)]),
        isTrue,
      );
      expect(
        holeIntersectsFaces(m, const [FaceBox(0.1, 0.1, 0.1, 0.1)]),
        isFalse,
      );
      expect(holeIntersectsFaces(m, const []), isFalse);
    });
  });
}
