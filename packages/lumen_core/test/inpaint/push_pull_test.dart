import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'synthetic_images.dart';

void main() {
  group('FloatImage', () {
    test('round-trips an RgbaBuffer and resizes', () {
      final rgba = RgbaBuffer.filled(8, 6, 10, 120, 250);
      rgba.setPixel(3, 2, 1, 2, 3);
      final f = FloatImage.fromRgba(rgba);
      expect(f.at(3, 2, 2), 3);
      expect(f.toRgba().data, rgba.data);
      final g = gradientImage(64, 32);
      final small = resizeArea(g, 32, 16);
      expect(small.width, 32);
      expect(small.at(10, 5, 0), closeTo(g.at(21, 11, 0), 2.5));
      final big = resizeBilinear(small, 64, 32);
      expect(big.at(30, 20, 1), closeTo(g.at(30, 20, 1), 2.5));
    });
  });

  group('pushPullFill', () {
    test('smooth gradient + hole: membrane error is tiny', () {
      final gt = gradientImage(96, 96);
      final hole = discHole(96, 96, 48, 40, 15);
      final out = pushPullFill(withObject(gt, hole), hole);
      expect(holeMae(out, gt, hole), lessThan(0.3));
      expect(holeMaxErr(out, gt, hole), lessThan(1.5));
    });

    test('keeps known pixels exactly', () {
      final gt = grainTexture(64, 48);
      final hole = rectHole(64, 48, 20, 10, 12, 9);
      final src = withObject(gt, hole, 255);
      final out = pushPullFill(src, hole);
      for (var i = 0; i < hole.length; i++) {
        if (hole[i] != 0) continue;
        expect(out.data[i * 3], src.data[i * 3]);
      }
    });

    test('works when the hole touches the image border', () {
      final gt = gradientImage(40, 40);
      final hole = rectHole(40, 40, 0, 0, 10, 40);
      final out = pushPullFill(withObject(gt, hole), hole);
      // Extrapolation is constant-ish, but must stay finite and in range.
      for (final v in out.data) {
        expect(v.isFinite && v >= 0 && v <= 255, isTrue);
      }
    });

    test('plain push-pull (no relaxation) is cruder than the membrane', () {
      final gt = gradientImage(96, 96);
      final hole = discHole(96, 96, 48, 48, 20);
      final src = withObject(gt, hole);
      final crude = pushPullFill(src, hole, relax: false);
      final fine = pushPullFill(src, hole);
      expect(holeMae(fine, gt, hole), lessThan(holeMae(crude, gt, hole)));
    });
  });

  group('frequencySeparatedFill', () {
    test('ring mode restores grain that a plain membrane loses', () {
      final gt = grainTexture(128, 128);
      final hole = discHole(128, 128, 64, 64, 14);
      final src = withObject(gt, hole, 20);
      final smooth = pushPullFill(src, hole);
      final textured = frequencySeparatedFill(src, hole);
      final want = holeLaplacianStd(gt, hole);
      expect(holeLaplacianStd(smooth, hole), lessThan(0.3 * want));
      expect(holeLaplacianStd(textured, hole), greaterThan(0.6 * want));
      expect(holeLaplacianStd(textured, hole), lessThan(1.5 * want));
      // Low band still follows the surroundings.
      expect(holeMae(textured, gt, hole), lessThan(20));
    });

    test('original mode keeps the pores under a low-frequency blemish', () {
      final gt = grainTexture(96, 96);
      final hole = discHole(96, 96, 48, 48, 12);
      final blem = gt.copy();
      for (var y = 0; y < 96; y++) {
        for (var x = 0; x < 96; x++) {
          final d2 = (x - 48) * (x - 48) + (y - 48) * (y - 48);
          final k = 45 * math.exp(-d2 / (2 * 6.0 * 6.0));
          for (var c = 0; c < 3; c++) {
            blem.set(x, y, c, blem.at(x, y, c) - k);
          }
        }
      }
      final healed = frequencySeparatedFill(
        blem,
        hole,
        fine: FineBand.original,
      );
      final smooth = pushPullFill(blem, hole);
      expect(
        holeMae(healed, gt, hole),
        lessThan(0.6 * holeMae(smooth, gt, hole)),
      );
    });

    test(
      'findDonorOffset picks a period-aligned donor on a periodic image',
      () {
        final img = brickImage(160, 120);
        final hole = rectHole(160, 120, 74, 51, 8, 8);
        final o = findDonorOffset(img, hole);
        expect(o, isNotNull);
        // Running bond: rows repeat every 12 px with a half-brick shift.
        final (dx, dy) = o!;
        expect(dy % 12, 0);
        expect((dx + ((dy ~/ 12).isOdd ? 12 : 0)) % 24, 0);
      },
    );
  });
}
