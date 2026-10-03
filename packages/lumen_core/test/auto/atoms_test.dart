import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  const base = DevelopSettings.defaults;

  group('StyleAtom', () {
    test('ids are unique snake_case and round-trip', () {
      final ids = StyleAtom.values.map((a) => a.id).toSet();
      expect(ids.length, StyleAtom.values.length);
      for (final a in StyleAtom.values) {
        expect(RegExp(r'^[a-z_]+$').hasMatch(a.id), isTrue, reason: a.id);
        expect(StyleAtom.fromId(a.id), a);
      }
      expect(StyleAtom.fromId('nope'), isNull);
    });

    test('every atom only touches registry params', () {
      for (final a in StyleAtom.values) {
        for (final op in a.ops(1)) {
          final id = switch (op) {
            DeltaOp(:final param) => param,
            SetOp(:final param) => param,
            LessOp(:final param) => param,
            CurveOp() || TreatmentOp() => null,
          };
          if (id != null) {
            expect(ParamRegistry.contains(id), isTrue, reason: '${a.id} $id');
          }
        }
      }
    });

    test('warm at 0.5 gives temp +7.5, tint +1.5, orange sat +2.5', () {
      final s = applyOps(base, StyleAtom.warm.ops(0.5)).settings;
      expect(s.value(P.temp), closeTo(7.5, 1e-9));
      expect(s.value(P.tint), closeTo(1.5, 1e-9));
      expect(
        s.value(P.hsl(HslBand.orange, HslChannel.sat)),
        closeTo(2.5, 1e-9),
      );
    });

    test('moody sets grade hue and adds grade saturation', () {
      final s = applyOps(base, StyleAtom.moody.ops(1)).settings;
      expect(s.value(P.grade(GradeZone.shadows, 'hue')), 215);
      expect(s.value(P.grade(GradeZone.shadows, 'sat')), 10);
      expect(s.value(P.exposure), closeTo(-0.3, 1e-9));
      expect(s.value(P.vignetteAmount), -15);
    });

    test('bw_classic switches treatment and mixes', () {
      final s = applyOps(base, StyleAtom.bwClassic.ops(1)).settings;
      expect(s.treatment, Treatment.bw);
      expect(s.value(P.bw(HslBand.blue)), -20);
      expect(s.value(P.contrast), 15);
    });

    test(
      'film_faded and soft_matte write a master curve blended by amount',
      () {
        final full = applyOps(base, StyleAtom.filmFaded.ops(1)).settings;
        expect(full.curves.master.evaluate(0), closeTo(20, 1e-9));
        expect(full.curves.master.evaluate(255), closeTo(245, 1e-9));
        final half = applyOps(base, StyleAtom.softMatte.ops(0.5)).settings;
        expect(half.curves.master.evaluate(0), closeTo(9, 1e-9));
      },
    );

    test('locked params are left alone; others still change', () {
      final r = applyOps(base, StyleAtom.warm.ops(1), locked: {P.temp});
      expect(r.settings.value(P.temp), 0);
      expect(r.settings.value(P.tint), 3);
      expect(r.touched, isNot(contains(P.temp)));
    });

    test('values clamp to the registry range', () {
      final hot = base.withValue(P.temp, 95);
      final s = applyOps(hot, StyleAtom.goldenHour.ops(1)).settings;
      expect(s.value(P.temp), 100);
    });
  });

  group('applyOps', () {
    test('SetOp sets absolute values', () {
      final s = applyOps(base, const [SetOp(P.shadows, 40)]).settings;
      expect(s.value(P.shadows), 40);
    });

    test('LessOp never crosses the baseline', () {
      final current = base.withValue(P.contrast, 30);
      final r = applyOps(current, const [
        LessOp(P.contrast, 0.5, 1),
      ], baseline: base);
      expect(r.settings.value(P.contrast), 15);
      final none = applyOps(base, const [
        LessOp(P.contrast, 1, 1),
      ], baseline: base);
      expect(none.settings.value(P.contrast), 0);
      expect(none.notes, isNotEmpty);
    });

    test('caps limit non-explicit deltas relative to the start', () {
      final r = applyOps(base, const [
        DeltaOp(P.exposure, 3),
        DeltaOp(P.temp, 80),
        DeltaOp(P.shadows, 90),
      ], caps: InstructionCaps.standard);
      expect(r.settings.value(P.exposure), 1);
      expect(r.settings.value(P.temp), 30);
      expect(r.settings.value(P.shadows), 40);
    });

    test('explicit ops bypass caps and locks', () {
      final r = applyOps(
        base,
        const [DeltaOp(P.exposure, 2.5, explicit: true)],
        caps: InstructionCaps.standard,
        locked: {P.exposure},
      );
      expect(r.settings.value(P.exposure), 2.5);
    });
  });
}
