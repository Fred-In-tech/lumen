import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

const _eps16 = 1 / 65535;

void _expectMonotone(ToneLut lut, int row) {
  for (var i = 1; i < kToneLutSize; i++) {
    expect(
      lut.entry(row, i),
      greaterThanOrEqualTo(lut.entry(row, i - 1)),
      reason: 'row $row entry $i',
    );
  }
}

void main() {
  group('tone curve building blocks', () {
    test('contrast 0 is identity', () {
      for (var x = 0.0; x <= 1; x += 0.05) {
        expect(contrastCurve(x, 0), closeTo(x, 1e-12));
      }
    });

    test('contrast +50 is an S-curve through mid-gray', () {
      expect(contrastCurve(kContrastPivot, 50), closeTo(kContrastPivot, 1e-12));
      expect(contrastCurve(0.2, 50), lessThan(0.2));
      expect(contrastCurve(0.8, 50), greaterThan(0.8));
      expect(contrastCurve(0, 50), 0);
      expect(contrastCurve(1, 50), closeTo(1, 1e-12));
    });

    test('contrast -50 flattens around mid-gray', () {
      expect(contrastCurve(0.2, -50), greaterThan(0.2));
      expect(contrastCurve(0.8, -50), lessThan(0.8));
    });

    test('whites/blacks follow the reference levels model', () {
      // whites +100: input white point 0.75 is stretched to 1.
      expect(levelsCurve(0.75, 100, 0), closeTo(1, 1e-12));
      // whites -100: output white compressed to 0.75.
      expect(levelsCurve(1, -100, 0), closeTo(0.75, 1e-12));
      // blacks -100: input black point 0.25 is crushed to 0.
      expect(levelsCurve(0.25, 0, -100), closeTo(0, 1e-12));
      // blacks +100: output black lifted to 0.25.
      expect(levelsCurve(0, 0, 100), closeTo(0.25, 1e-12));
      // whites +40 (W_in = 0.9).
      expect(levelsCurve(0.45, 40, 0), closeTo(0.5, 1e-12));
      expect(levelsCurve(0.5, 0, 0), 0.5);
    });

    test('parametric zones move their own region, end points stay fixed', () {
      double p(
        double x, {
        double s = 0,
        double d = 0,
        double l = 0,
        double h = 0,
      }) => parametricCurve(
        x,
        shadows: s,
        darks: d,
        lights: l,
        highlights: h,
        splitShadow: 25,
        splitMidtone: 50,
        splitHighlight: 75,
      );
      expect(p(0.12, s: 100), greaterThan(0.12));
      expect(p(0.88, h: -100), lessThan(0.88));
      expect(p(0.37, d: 100), greaterThan(0.37));
      expect(p(0.62, l: 100), greaterThan(0.62));
      expect(p(0, s: 100), 0);
      expect(p(1, h: 100), 1);
      // Shadows barely touches the highlights.
      expect(p(0.9, s: 100), closeTo(0.9, 1e-9));
    });
  });

  group('ToneLut.bake', () {
    test('identity settings give identity rows (±1/65535)', () {
      final lut = ToneLut.bake(DevelopSettings.defaults);
      for (var row = 0; row < kToneLutRows; row++) {
        for (var i = 0; i < kToneLutSize; i++) {
          expect(lut.entry(row, i), closeTo(i / (kToneLutSize - 1), _eps16));
        }
      }
      expect(lut.curvesActive, isFalse);
    });

    test('contrast +50 composite row is an S-curve through mid-gray', () {
      final lut = ToneLut.bake(
        DevelopSettings.defaults.withValue(P.contrast, 50),
      );
      expect(lut.lookup(0, kContrastPivot), closeTo(kContrastPivot, 1e-3));
      expect(lut.lookup(0, 0.2), lessThan(0.2 - 0.01));
      expect(lut.lookup(0, 0.8), greaterThan(0.8 + 0.01));
      _expectMonotone(lut, 0);
    });

    test('per-channel curve rows are independent', () {
      final curves = CurveSet.identity.withChannel(
        CurveChannel.red,
        const ToneCurve([
          CurvePoint(0, 0),
          CurvePoint(128, 170),
          CurvePoint(255, 255),
        ]),
      );
      final lut = ToneLut.bake(
        DevelopSettings.defaults.copyWith(curves: curves),
      );
      expect(lut.curvesActive, isTrue);
      expect(lut.lookup(1, 128 / 255), closeTo(170 / 255, 2e-3));
      for (final row in [0, 2, 3]) {
        expect(lut.lookup(row, 0.5), closeTo(0.5, 1e-4), reason: 'row $row');
      }
    });

    test('master curve lands in the composite row only', () {
      final curves = CurveSet.identity.withChannel(
        CurveChannel.master,
        const ToneCurve([CurvePoint(0, 30), CurvePoint(255, 255)]),
      );
      final lut = ToneLut.bake(
        DevelopSettings.defaults.copyWith(curves: curves),
      );
      expect(lut.curvesActive, isFalse);
      expect(lut.lookup(0, 0), closeTo(30 / 255, 1e-4));
      expect(lut.lookup(1, 0), 0);
    });

    test('random settings always give monotone rows in 0..1', () {
      final rnd = math.Random(7);
      for (var k = 0; k < 20; k++) {
        double r() => rnd.nextDouble() * 200 - 100;
        final s = DevelopSettings.defaults.withValues({
          P.contrast: r(),
          P.whites: r(),
          P.blacks: r(),
          P.curveShadows: r(),
          P.curveDarks: r(),
          P.curveLights: r(),
          P.curveHighlights: r(),
        });
        final lut = ToneLut.bake(s);
        _expectMonotone(lut, 0);
        expect(lut.entry(0, 0), greaterThanOrEqualTo(0));
        expect(lut.entry(0, kToneLutSize - 1), lessThanOrEqualTo(1));
      }
    });

    test('lookup interpolates linearly between entries like the shader', () {
      final lut = ToneLut.bake(
        DevelopSettings.defaults.withValue(P.contrast, 80),
      );
      const x = 0.30001;
      final p = x * (kToneLutSize - 1);
      final i0 = p.floor();
      final f = p - i0;
      final expected = lut.entry(0, i0) * (1 - f) + lut.entry(0, i0 + 1) * f;
      expect(lut.lookup(0, x), closeTo(expected, 1e-12));
      expect(lut.lookup(0, -1), lut.entry(0, 0));
      expect(lut.lookup(0, 2), lut.entry(0, kToneLutSize - 1));
    });

    test('toRgba packs 1024x4 texels, opaque, decodable', () {
      final lut = ToneLut.bake(
        DevelopSettings.defaults.withValue(P.blacks, -30),
      );
      final rgba = lut.toRgba();
      expect(rgba.length, kToneLutSize * kToneLutRows * 4);
      for (var row = 0; row < kToneLutRows; row++) {
        for (var i = 0; i < kToneLutSize; i += 97) {
          final o = (row * kToneLutSize + i) * 4;
          expect(rgba[o + 3], 255);
          expect(unpackNormalized(rgba[o], rgba[o + 1]), lut.entry(row, i));
        }
      }
    });

    test('cache key tracks tone params only', () {
      final a = DevelopSettings.defaults.withValue(P.contrast, 20);
      final b = a.withValue(P.exposure, 1.2);
      final c = a.withValue(P.whites, 5);
      expect(ToneLut.keyFor(a), ToneLut.keyFor(b));
      expect(ToneLut.keyFor(a), isNot(ToneLut.keyFor(c)));
    });
  });
}
