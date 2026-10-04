import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'synthetic_images.dart';

void main() {
  group('SeededRng', () {
    test('same seed, same sequence; bounded', () {
      final a = SeededRng(42), b = SeededRng(42), c = SeededRng(43);
      final sa = [for (var i = 0; i < 20; i++) a.nextInt(1000)];
      final sb = [for (var i = 0; i < 20; i++) b.nextInt(1000)];
      final sc = [for (var i = 0; i < 20; i++) c.nextInt(1000)];
      expect(sa, sb);
      expect(sa, isNot(sc));
      expect(sa.every((v) => v >= 0 && v < 1000), isTrue);
    });
  });

  group('patchMatchFill', () {
    test('brick texture, medium hole: reproduces the period', () {
      final gt = brickImage(200, 160);
      final hole = rectHole(200, 160, 80, 56, 40, 40);
      final src = withObject(gt, hole, 0);
      final out = patchMatchFill(src, hole);
      final pm = holeMae(out, gt, hole);
      final naive = holeMae(meanFill(src, hole), gt, hole);
      expect(pm, lessThan(0.35 * naive), reason: 'pm $pm vs mean $naive');
      // Mortar rows (y % 12 < 2) come out bright inside the hole.
      var mortar = 0.0, brick = 0.0, nm = 0, nb = 0;
      for (var y = 56; y < 96; y++) {
        for (var x = 80; x < 120; x++) {
          if (y % 12 < 2) {
            mortar += out.at(x, y, 0);
            nm++;
          } else if (y % 12 > 3 && y % 12 < 10) {
            brick += out.at(x, y, 0);
            nb++;
          }
        }
      }
      expect(mortar / nm - brick / nb, greaterThan(25));
    });

    test('stripes: error far below a membrane fill', () {
      final gt = FloatImage(120, 120);
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 120; x++) {
          final v = (x ~/ 5).isEven ? 60.0 : 190.0;
          for (var c = 0; c < 3; c++) {
            gt.set(x, y, c, v);
          }
        }
      }
      final hole = discHole(120, 120, 60, 60, 16);
      final src = withObject(gt, hole, 255);
      final pm = holeMae(patchMatchFill(src, hole), gt, hole);
      final smooth = holeMae(pushPullFill(src, hole), gt, hole);
      expect(pm, lessThan(0.3 * smooth), reason: 'pm $pm vs membrane $smooth');
    });

    test('deterministic: same seed gives identical bytes', () {
      final gt = grainTexture(96, 80);
      final hole = discHole(96, 80, 48, 40, 12);
      final src = withObject(gt, hole, 0);
      const p = PatchMatchParams(seed: 9);
      final a = patchMatchFill(src, hole, params: p).toRgba().data;
      final b = patchMatchFill(src, hole, params: p).toRgba().data;
      expect(a, b);
      final c = patchMatchFill(
        src,
        hole,
        params: const PatchMatchParams(seed: 10),
      ).toRgba().data;
      expect(c, isNot(a));
    });

    test('pixels outside the hole are untouched', () {
      final gt = grainTexture(64, 64);
      final hole = rectHole(64, 64, 0, 20, 14, 14); // touches the border
      final src = withObject(gt, hole, 0);
      final out = patchMatchFill(src, hole);
      for (var i = 0; i < hole.length; i++) {
        if (hole[i] != 0) continue;
        for (var c = 0; c < 3; c++) {
          expect(out.data[i * 3 + c], src.data[i * 3 + c]);
        }
      }
    });

    test('cancellation hook aborts with InpaintCancelled', () {
      final gt = grainTexture(96, 96);
      final hole = discHole(96, 96, 48, 48, 15);
      var calls = 0;
      expect(
        () => patchMatchFill(
          withObject(gt, hole),
          hole,
          shouldCancel: () => ++calls > 3,
        ),
        throwsA(isA<InpaintCancelled>()),
      );
    });
  });

  group('patchMatchDetail', () {
    test('restores grain on a smooth low-band guide', () {
      final gt = grainTexture(192, 192, grain: 12);
      final hole = discHole(192, 192, 96, 96, 30);
      // A "model output" at 1/4 resolution, upsampled: right colours, no grain.
      final guide = resizeBilinear(resizeArea(gt, 48, 48), 192, 192);
      final src = withObject(gt, hole, 0);
      final out = patchMatchDetail(src, hole, guide, sigma: 3);
      final want = holeLaplacianStd(gt, hole);
      expect(holeLaplacianStd(guide, hole), lessThan(0.35 * want));
      expect(holeLaplacianStd(out, hole), greaterThan(0.6 * want));
      expect(holeLaplacianStd(out, hole), lessThan(1.5 * want));
      // The low band follows the guide (colours stay right).
      final lowOut = gaussianBlur(out, 3), lowGt = gaussianBlur(gt, 3);
      expect(holeMae(lowOut, lowGt, hole), lessThan(6));
      for (var i = 0; i < hole.length; i++) {
        if (hole[i] == 0) expect(out.data[i * 3], src.data[i * 3]);
      }
    });
  });
}
