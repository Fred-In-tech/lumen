import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

RgbaBuffer _split(int w, int h, int left, int right) {
  final b = RgbaBuffer(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = x < w ~/ 2 ? left : right;
      b.setPixel(x, y, v, v, v);
    }
  }
  return b;
}

void main() {
  group('AuxMaps.proxy', () {
    test('downscales to the long edge with area averaging', () {
      final src = RgbaBuffer.filled(1024, 512, 10, 20, 30);
      final p = AuxMaps.proxy(src);
      expect(p.width, 512);
      expect(p.height, 256);
      expect([p.r(100, 100), p.g(100, 100), p.b(100, 100)], [10, 20, 30]);
    });

    test('never upscales', () {
      final src = RgbaBuffer.filled(100, 50, 1, 2, 3);
      expect(identical(AuxMaps.proxy(src), src), isTrue);
    });
  });

  group('AuxMaps.compute', () {
    test('a constant image gives constant bases', () {
      final aux = AuxMaps.compute(RgbaBuffer.filled(64, 48, 128, 128, 128));
      final y = srgbToLinear(128 / 255);
      final n = normalizedLogLuma(relativeLuminance(y, y, y));
      for (final (u, v) in [(0.0, 0.0), (0.5, 0.5), (0.99, 0.2)]) {
        final s = aux.sample(u, v);
        expect(s.baseMid, closeTo(n, 2e-5));
        // Flat region: a -> 0, so q = a*I + b = mean.
        expect(s.meanA * n + s.meanB, closeTo(n, 3e-3));
        expect(s.dark, closeTo(128 / 255, 1 / 255));
      }
    });

    test('guided base preserves a hard edge (overshoot <= 5 %)', () {
      final aux = AuxMaps.compute(_split(128, 64, 30, 220));
      double iOf(int byte) {
        final l = srgbToLinear(byte / 255);
        return normalizedLogLuma(relativeLuminance(l, l, l));
      }

      final lo = iOf(30), hi = iOf(220);
      // Pixel just left / right of the edge.
      final left = aux.sample(62.5 / 128, 0.5);
      final right = aux.sample(65.5 / 128, 0.5);
      final qL = left.meanA * lo + left.meanB;
      final qR = right.meanA * hi + right.meanB;
      final range = hi - lo;
      expect((qL - lo).abs() / range, lessThan(0.25));
      expect((qR - hi).abs() / range, lessThan(0.25));
      // No overshoot far from the edge.
      final far = aux.sample(10 / 128, 0.5);
      expect(far.meanA * lo + far.meanB, closeTo(lo, 0.05 * range));
      // A Gaussian blur (baseMid) would smear the edge much more than the
      // guided base does.
      expect((left.baseMid - lo).abs(), greaterThan((qL - lo).abs()));
    });

    test('dark channel min-filter spreads a single dark dot', () {
      final src = RgbaBuffer.filled(64, 64, 200, 200, 200)
        ..setPixel(32, 32, 0, 0, 0);
      final aux = AuxMaps.compute(src);
      // Within the 15x15 patch the min is 0 before smoothing; after the
      // smoothing blur it stays clearly darker than far away.
      expect(aux.sample(32.5 / 64, 32.5 / 64).dark, lessThan(0.5));
      expect(aux.sample(5 / 64, 5 / 64).dark, closeTo(200 / 255, 1 / 255));
    });

    test('airlight is the color of the haziest region', () {
      final src = RgbaBuffer.filled(64, 64, 20, 30, 40);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 64; x++) {
          src.setPixel(x, y, 230, 235, 240);
        }
      }
      final aux = AuxMaps.compute(src);
      expect(aux.airlight.r, closeTo(srgbToLinear(230 / 255), 0.02));
      expect(aux.airlight.b, closeTo(srgbToLinear(240 / 255), 0.02));
    });

    test('packed planes are opaque RGBA of width*height texels', () {
      final aux = AuxMaps.compute(RgbaBuffer.filled(10, 6, 50, 60, 70));
      expect(aux.auxA.length, 10 * 6 * 4);
      expect(aux.auxB.length, 10 * 6 * 4);
      for (var i = 3; i < aux.auxA.length; i += 4) {
        expect(aux.auxA[i], 255);
        expect(aux.auxB[i], 255);
      }
    });

    test('neutral aux is usable without an image', () {
      final aux = AuxMaps.neutral();
      expect(aux.width, 1);
      expect(aux.sample(0.3, 0.3).dark, 0);
      expect(aux.airlight.r, 1);
    });

    test('computes a 512 px proxy quickly', () {
      final rnd = math.Random(1);
      final src = RgbaBuffer(512, 384);
      for (var i = 0; i < src.data.length; i++) {
        src.data[i] = i % 4 == 3 ? 255 : rnd.nextInt(256);
      }
      final sw = Stopwatch()..start();
      AuxMaps.compute(src);
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });
}
