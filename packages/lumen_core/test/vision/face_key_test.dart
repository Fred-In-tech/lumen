import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('faceKey', () {
    test('is the box centre rounded to 1/64', () {
      expect(faceKey(const FaceBox(0.4, 0.2, 0.2, 0.1)), 'f32_16');
      expect(faceKey(const FaceBox(0, 0, 0, 0)), 'f0_0');
    });

    test('is stable under small re-detection jitter', () {
      // Centre on a grid point (20/64, 26/64); jitter < 1/128 keeps the key.
      const base = FaceBox(0.2525, 0.33125, 0.120, 0.150);
      final key = faceKey(base);
      for (final d in [-0.003, -0.001, 0.001, 0.003]) {
        expect(
          faceKey(FaceBox(base.x + d, base.y - d, base.width, base.height)),
          key,
        );
        // Size jitter around the same centre keeps the key too.
        expect(
          faceKey(
            FaceBox(base.x - d, base.y - d, base.width + 2 * d, base.height),
          ),
          key,
        );
      }
    });

    test('distinguishes faces in different places', () {
      final a = faceKey(const FaceBox(0.1, 0.1, 0.1, 0.1));
      final b = faceKey(const FaceBox(0.6, 0.1, 0.1, 0.1));
      expect(a, isNot(b));
    });
  });

  group('segmentationCropFor', () {
    test('box × 2.2, squared in pixels, centred', () {
      // 100×150 px face in a 1000×1000 image.
      final c = segmentationCropFor(
        const FaceBox(0.45, 0.4, 0.1, 0.15),
        imageWidth: 1000,
        imageHeight: 1000,
      );
      expect(c.isSquare, isTrue);
      expect(c.width, 330);
      expect(c.left, 500 - 165);
      expect(c.top, 475 - 165);
    });

    test('shifted inside the image near an edge, still square', () {
      final c = segmentationCropFor(
        const FaceBox(0.0, 0.85, 0.1, 0.1),
        imageWidth: 1000,
        imageHeight: 1000,
      );
      expect(c.isSquare, isTrue);
      expect(c.left, 0);
      expect(c.top + c.height, 1000);
    });

    test('clamped to the image when it cannot fit', () {
      final c = segmentationCropFor(
        const FaceBox(0.2, 0.1, 0.6, 0.8),
        imageWidth: 800,
        imageHeight: 600,
      );
      expect(c, const SegmentationCrop(0, 0, 800, 600));
      final n = c.toFaceBox(800, 600);
      expect(n, const FaceBox(0, 0, 1, 1));
    });
  });
}
