import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

RgbaBuffer _halves(List<int> top, List<int> bottom) {
  final buf = RgbaBuffer(4, 4);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      final c = y < 2 ? top : bottom;
      buf.setPixel(x, y, c[0], c[1], c[2]);
    }
  }
  return buf;
}

void main() {
  group('PixelRect', () {
    test('area, edges and containment', () {
      const r = PixelRect(2, 3, 4, 5);
      expect(r.right, 6);
      expect(r.bottom, 8);
      expect(r.area, 20);
      expect(r.contains(2, 3), isTrue);
      expect(r.contains(6, 3), isFalse);
      expect(r.contains(5, 7), isTrue);
    });
  });

  group('SceneMetrics', () {
    test('median luma of a uniform gray equals its encoded value', () {
      final buf = RgbaBuffer.filled(8, 8, 128, 128, 128);
      expect(SceneMetrics.medianLuma(buf), closeTo(128 / 255, 1e-3));
    });

    test('percentile interpolates between two levels', () {
      final buf = _halves([0, 0, 0], [255, 255, 255]);
      expect(SceneMetrics.percentileLuma(buf, 0), 0);
      expect(SceneMetrics.percentileLuma(buf, 1), closeTo(1, 1e-9));
      expect(SceneMetrics.percentileLuma(buf, 0.25), 0);
      expect(SceneMetrics.medianLuma(buf), closeTo(0.5, 1e-9));
    });

    test('clip fraction counts any channel at the top', () {
      final buf = _halves([255, 10, 10], [200, 200, 200]);
      expect(SceneMetrics.clipFraction(buf), 0.5);
      expect(SceneMetrics.clipFraction(RgbaBuffer.filled(2, 2, 254, 0, 0)), 1);
      expect(SceneMetrics.clipFraction(RgbaBuffer.filled(2, 2, 253, 0, 0)), 0);
    });

    test('crush fraction counts display luma below 1 %', () {
      final buf = _halves([0, 0, 0], [60, 60, 60]);
      expect(SceneMetrics.crushFraction(buf), 0.5);
    });

    test('cast metrics: gray is neutral, gains are recovered', () {
      final gray = RgbaBuffer.filled(4, 4, 120, 120, 120);
      expect(SceneMetrics.castA(gray), closeTo(0, 1e-9));
      expect(SceneMetrics.castM(gray), closeTo(0, 1e-9));
      final r = srgbToLinear(200 / 255), b = srgbToLinear(100 / 255);
      final warm = RgbaBuffer.filled(4, 4, 200, 150, 100);
      expect(
        SceneMetrics.castA(warm),
        closeTo(math.log(r / b) / math.ln2, 1e-9),
      );
    });

    test('cast metrics can be restricted to regions', () {
      final buf = _halves([200, 150, 100], [120, 120, 120]);
      final a = SceneMetrics.castA(buf, const [PixelRect(0, 2, 4, 2)]);
      expect(a, closeTo(0, 1e-9));
      expect(
        SceneMetrics.castA(buf, const [PixelRect(0, 0, 4, 2)]),
        greaterThan(1),
      );
    });

    test('sigma L* is zero for a flat image and known for two levels', () {
      expect(
        SceneMetrics.sigmaLStar(RgbaBuffer.filled(4, 4, 90, 90, 90)),
        closeTo(0, 1e-9),
      );
      final buf = _halves([60, 60, 60], [180, 180, 180]);
      final l1 = lStarFromY(srgbToLinear(60 / 255));
      final l2 = lStarFromY(srgbToLinear(180 / 255));
      expect(SceneMetrics.sigmaLStar(buf), closeTo((l2 - l1) / 2, 1e-6));
    });

    test('mean chroma is zero for grays and positive for colors', () {
      expect(
        SceneMetrics.meanChroma(RgbaBuffer.filled(2, 2, 90, 90, 90)),
        closeTo(0, 1e-3),
      );
      expect(
        SceneMetrics.meanChroma(RgbaBuffer.filled(2, 2, 200, 60, 60)),
        greaterThan(30),
      );
    });

    test('fnv1a hash is stable and content sensitive', () {
      final a = RgbaBuffer.filled(2, 2, 1, 2, 3);
      final b = RgbaBuffer.filled(2, 2, 1, 2, 4);
      expect(SceneMetrics.hash(a), SceneMetrics.hash(a.copy()));
      expect(SceneMetrics.hash(a), isNot(SceneMetrics.hash(b)));
    });
  });
}
