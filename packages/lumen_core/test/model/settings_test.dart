import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('ToneCurve', () {
    test('identity evaluates to x', () {
      const c = ToneCurve.identity;
      expect(c.isIdentity, isTrue);
      for (var x = 0; x <= 255; x += 15) {
        expect(c.evaluate(x.toDouble()), closeTo(x, 1e-9));
      }
    });

    test('monotone through points, endpoints exact', () {
      final c = const ToneCurve([
        CurvePoint(0, 20),
        CurvePoint(64, 60),
        CurvePoint(192, 200),
        CurvePoint(255, 245),
      ]);
      expect(c.evaluate(0), closeTo(20, 1e-9));
      expect(c.evaluate(255), closeTo(245, 1e-9));
      expect(c.evaluate(64), closeTo(60, 1e-9));
      var prev = -1.0;
      for (var x = 0; x <= 255; x++) {
        final y = c.evaluate(x.toDouble());
        expect(y >= prev - 1e-9, isTrue, reason: 'x=$x');
        prev = y;
      }
      expect(c.isIdentity, isFalse);
    });

    test('validation sorts, dedupes, clamps and limits to 16 points', () {
      final c = ToneCurve.normalized([
        const CurvePoint(300, -5),
        const CurvePoint(0, 0),
        const CurvePoint(0, 10),
        const CurvePoint(128, 128),
      ]);
      expect(c.points.first.x, 0);
      expect(c.points.last.x, 255);
      expect(c.points.last.y, 0);
      expect(c.points.length, 3);
      final many = ToneCurve.normalized([
        for (var i = 0; i < 30; i++) CurvePoint(i * 8.0, i * 8.0),
      ]);
      expect(many.points.length, lessThanOrEqualTo(16));
    });

    test('json round trip', () {
      final c = const ToneCurve([CurvePoint(0, 10), CurvePoint(255, 250)]);
      expect(ToneCurve.fromJson(c.toJson()), c);
    });
  });

  group('Geometry', () {
    test('defaults and json', () {
      const g = Geometry.none;
      expect(g.isIdentity, isTrue);
      final g2 = g.copyWith(
        angle: 3.5,
        rotate90: 1,
        flipH: true,
        crop: const CropRect(0.1, 0.1, 0.9, 0.8),
      );
      expect(Geometry.fromJson(g2.toJson()), g2);
      expect(g2.isIdentity, isFalse);
    });

    test('rotate90 wraps and angle clamps', () {
      expect(Geometry.none.copyWith(rotate90: 5).rotate90, 1);
      expect(Geometry.none.copyWith(angle: 90).angle, 45);
    });

    test('crop rect normalizes', () {
      final r = CropRect.normalized(0.9, -0.2, 0.1, 1.4);
      expect(r.left, closeTo(0.1, 1e-12));
      expect(r.right, closeTo(0.9, 1e-12));
      expect(r.top, 0);
      expect(r.bottom, 1);
    });
  });

  group('DevelopSettings', () {
    test('default values are omitted from json', () {
      const s = DevelopSettings.defaults;
      expect(s.toJson()['values'], isEmpty);
      final s2 = s.withValue(P.exposure, 0.5).withValue(P.contrast, 0);
      expect((s2.toJson()['values'] as Map).keys, [P.exposure]);
    });

    test('get returns registry default; set clamps', () {
      const s = DevelopSettings.defaults;
      expect(s.value(P.splitMidtone), 50);
      expect(s.withValue(P.exposure, 99).value(P.exposure), 5);
      expect(() => s.withValue('bogus', 1), throwsArgumentError);
    });

    test('immutability: withValue returns a new object', () {
      const s = DevelopSettings.defaults;
      final s2 = s.withValue(P.shadows, 20);
      expect(s.value(P.shadows), 0);
      expect(s2.value(P.shadows), 20);
      expect(identical(s, s2), isFalse);
    });

    test('equality and hashCode are value based', () {
      final a = DevelopSettings.defaults.withValues({
        P.exposure: 0.3,
        'hsl.blue.sat': 10,
      });
      final b = DevelopSettings.defaults
          .withValue('hsl.blue.sat', 10)
          .withValue(P.exposure, 0.3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('json round trip with curves, treatment, geometry', () {
      final s = DevelopSettings.defaults
          .withValues({P.exposure: 0.62, P.shadows: 31, 'hsl.orange.sat': -8})
          .copyWith(
            curves: CurveSet.identity.withChannel(
              CurveChannel.master,
              const ToneCurve([CurvePoint(0, 20), CurvePoint(255, 240)]),
            ),
            treatment: Treatment.bw,
            geometry: Geometry.none.copyWith(flipV: true),
          );
      final back = DevelopSettings.fromJson(s.toJson());
      expect(back, s);
      expect(back.curves.master.points.first.y, 20);
      expect(back.curves.red.isIdentity, isTrue);
    });

    test('fromJson drops unknown params and clamps values', () {
      final s = DevelopSettings.fromJson({
        'values': {'exposure': 12, 'unknown.x': 3, 'shadows': 'bad'},
      });
      expect(s.value(P.exposure), 5);
      expect(s.nonDefaultValues.keys, [P.exposure]);
    });

    test('isDefault and diffParams', () {
      expect(DevelopSettings.defaults.isDefault, isTrue);
      final s = DevelopSettings.defaults.withValue(P.temp, 10);
      expect(s.isDefault, isFalse);
      expect(DevelopSettings.defaults.changedParams(s), {P.temp});
    });

    test('masks list serializes (reserved for phase 2)', () {
      final s = DevelopSettings.defaults.copyWith(
        masks: [
          const LocalMask(
            id: 'm1',
            name: 'Sky',
            kind: MaskKind.linear,
            shape: {'x0': 0.5, 'y0': 0.0, 'x1': 0.5, 'y1': 0.6},
            adjustments: {'exposure': -0.5},
          ),
        ],
      );
      final back = DevelopSettings.fromJson(s.toJson());
      expect(back.masks.single.kind, MaskKind.linear);
      expect(back.masks.single.adjustments['exposure'], -0.5);
    });
  });
}
