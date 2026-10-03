import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('sRGB transfer', () {
    test('known values', () {
      expect(srgbToLinear(0), 0);
      expect(srgbToLinear(1), closeTo(1, 1e-12));
      expect(srgbToLinear(128 / 255), closeTo(0.2158605, 1e-6));
      expect(linearToSrgb(0.18), closeTo(0.4613561, 1e-6));
    });

    test('round trip within 1e-9', () {
      for (var i = 0; i <= 1000; i++) {
        final v = i / 1000;
        expect(linearToSrgb(srgbToLinear(v)), closeTo(v, 1e-9));
      }
    });

    test('linearToSrgb clamps out-of-range input', () {
      expect(linearToSrgb(-0.5), 0);
      expect(linearToSrgb(4), 1);
    });

    test('byte lookup table matches function', () {
      for (var b = 0; b < 256; b++) {
        expect(kSrgbByteToLinear[b], closeTo(srgbToLinear(b / 255), 1e-12));
      }
    });
  });

  group('luminance', () {
    test('Rec.709 weights sum to 1', () {
      expect(relativeLuminance(1, 1, 1), closeTo(1, 1e-12));
      expect(relativeLuminance(1, 0, 0), closeTo(0.2126, 1e-12));
    });
  });

  group('CIELAB', () {
    test('white is L=100, a=b=0', () {
      final lab = linearSrgbToLab(1, 1, 1);
      expect(lab.l, closeTo(100, 1e-3));
      expect(lab.a, closeTo(0, 1e-3));
      expect(lab.b, closeTo(0, 1e-3));
    });

    test('18% gray is L about 49.5', () {
      expect(linearSrgbToLab(0.18, 0.18, 0.18).l, closeTo(49.496, 0.01));
    });

    test('pure sRGB red reference', () {
      final lab = linearSrgbToLab(1, 0, 0);
      expect(lab.l, closeTo(53.24, 0.05));
      expect(lab.a, closeTo(80.09, 0.1));
      expect(lab.b, closeTo(67.20, 0.1));
    });

    test('round trip', () {
      final rnd = math.Random(7);
      for (var i = 0; i < 200; i++) {
        final r = rnd.nextDouble(), g = rnd.nextDouble(), b = rnd.nextDouble();
        final back = labToLinearSrgb(linearSrgbToLab(r, g, b));
        expect(back.r, closeTo(r, 1e-6));
        expect(back.g, closeTo(g, 1e-6));
        expect(back.b, closeTo(b, 1e-6));
      }
    });

    test('lStarFromY matches Lab L', () {
      expect(lStarFromY(0.18), closeTo(49.496, 0.01));
      expect(yFromLStar(lStarFromY(0.3)), closeTo(0.3, 1e-9));
    });
  });

  group('OkLab', () {
    test('white maps to L=1, a=b=0', () {
      final o = linearSrgbToOklab(1, 1, 1);
      expect(o.l, closeTo(1, 1e-4));
      expect(o.a, closeTo(0, 1e-4));
      expect(o.b, closeTo(0, 1e-4));
    });

    test('reference red', () {
      final o = linearSrgbToOklab(1, 0, 0);
      expect(o.l, closeTo(0.62796, 1e-4));
      expect(o.a, closeTo(0.22486, 1e-4));
      expect(o.b, closeTo(0.12585, 1e-4));
    });

    test('round trip and LCh', () {
      final rnd = math.Random(11);
      for (var i = 0; i < 200; i++) {
        final r = rnd.nextDouble(), g = rnd.nextDouble(), b = rnd.nextDouble();
        final o = linearSrgbToOklab(r, g, b);
        final back = oklabToLinearSrgb(o);
        expect(back.r, closeTo(r, 1e-6));
        expect(back.g, closeTo(g, 1e-6));
        expect(back.b, closeTo(b, 1e-6));
        final lch = o.toLch();
        expect(lch.toLab().a, closeTo(o.a, 1e-9));
        expect(lch.h, inInclusiveRange(0, 360));
      }
    });
  });
}
