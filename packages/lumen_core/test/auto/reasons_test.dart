import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('Reasons', () {
    test('formatDelta uses units and signs', () {
      expect(Reasons.formatDelta(P.shadows, 35), '+35');
      expect(Reasons.formatDelta(P.exposure, -0.5), '−0.50 EV');
      expect(Reasons.formatDelta(P.temp, 7.5), '+7.5');
      expect(Reasons.formatDelta(P.temp, -12.02), '−12');
    });

    test('auto templates read like a photographer', () {
      expect(
        Reasons.auto(P.shadows, 0, 35),
        'Lifted shadows +35 to open up dark areas',
      );
      expect(
        Reasons.auto(P.temp, 0, -30),
        'Cooled temp −30 to neutralize a warm cast',
      );
      expect(
        Reasons.auto(P.exposure, 0, 1.2),
        'Raised exposure +1.20 EV to brighten the midtones',
      );
      expect(Reasons.auto(P.clarity, 0, 5), 'Raised clarity +5');
    });

    test('every local-engine param has both templates and a short text', () {
      for (final id in [
        P.exposure,
        P.temp,
        P.tint,
        P.whites,
        P.blacks,
        P.highlights,
        P.shadows,
        P.contrast,
        P.vibrance,
        P.saturation,
        P.dehaze,
      ]) {
        for (final to in [-10.0, 10.0]) {
          final r = Reasons.auto(id, 0, to);
          expect(r.length, lessThan(70), reason: r);
          expect(r, contains(Reasons.formatDelta(id, to)));
        }
      }
    });

    test('style and instruction reasons', () {
      expect(
        Reasons.style('Moody', P.vignetteAmount, 0, -12),
        'Moody look: vignette −12',
      );
      expect(
        Reasons.instruction('a bit warmer ', P.temp, 0, 7.5),
        'Temp +7.5 for “a bit warmer”',
      );
    });

    test('diff lists scalar, treatment and curve changes in order', () {
      final from = DevelopSettings.defaults;
      final to = applyOps(from, [
        const DeltaOp(P.shadows, 20),
        const DeltaOp(P.exposure, 0.5),
        ...StyleAtom.bwClassic.ops(1),
        ...StyleAtom.softMatte.ops(1),
      ]).settings;
      final changes = Reasons.diff(from, to, Reasons.auto);
      final ids = changes.map((c) => c.param).toList();
      expect(ids.first, P.exposure);
      expect(ids, containsAll([P.shadows, ChangeIds.treatment]));
      expect(ids.last, ChangeIds.masterCurve);
      final ex = changes.first;
      expect(ex.from, 0);
      expect(ex.to, 0.5);
      expect(ex.delta, 0.5);
      expect(changes.every((c) => c.reason.isNotEmpty), isTrue);
    });
  });

  group('DTOs', () {
    test('ParamChange JSON round-trip and equality', () {
      const c = ParamChange(param: P.temp, from: 0, to: 7.5, reason: 'r');
      expect(ParamChange.fromJson(c.toJson()), c);
      expect(c.hashCode, ParamChange.fromJson(c.toJson()).hashCode);
      expect(c.toString(), contains('temp'));
    });

    test('SceneInfo JSON round-trip omits nulls', () {
      const s = SceneInfo(timeOfDay: 'golden_hour', keyIntent: 'low_key');
      expect(s.toJson(), {'timeOfDay': 'golden_hour', 'keyIntent': 'low_key'});
      final back = SceneInfo.fromJson(s.toJson());
      expect(back.timeOfDay, 'golden_hour');
      expect(back.subject, isNull);
    });

    test('ProviderStatus', () {
      expect(const ProviderStatus.available().available, isTrue);
      const u = ProviderStatus.unavailable('no key');
      expect(u.available, isFalse);
      expect(u.reason, 'no key');
    });
  });
}
