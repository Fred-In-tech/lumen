import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  final chart = SyntheticScenes.wellExposedChart();
  final overBright = DevelopSettings.defaults.withValue(P.exposure, 0.8);

  group('Guards', () {
    test('fixes an over-bright vision proposal: clip ≥ 6 % → ≤ 1 %', () {
      final g = Guards.enforce(proxy: chart.image, settings: overBright);
      expect(g.before.clipFraction, greaterThanOrEqualTo(0.06));
      expect(g.after.clipFraction, lessThanOrEqualTo(0.01));
      expect(g.changed, isTrue);
      expect(g.settings.value(P.exposure), lessThan(0.8));
      expect(g.reasons[P.exposure], contains('clipping'));
      final full = renderReference(chart.image, g.settings);
      expect(SceneMetrics.clipFraction(full), lessThanOrEqualTo(0.01));
    });

    test('only exposure, whites and blacks are ever adjusted', () {
      final proposal = overBright.withValues({
        P.whites: 30,
        P.contrast: 25,
        P.vibrance: 10,
      });
      final g = Guards.enforce(proxy: chart.image, settings: proposal);
      final touched = proposal.changedParams(g.settings);
      expect(touched, isNotEmpty);
      expect({P.exposure, P.whites, P.blacks}.containsAll(touched), isTrue);
      expect(g.reasons[P.whites], isNotNull);
    });

    test('locked params are untouched even if the guard cannot fix', () {
      final g = Guards.enforce(
        proxy: chart.image,
        settings: overBright,
        locked: const {P.exposure, P.whites},
      );
      expect(g.settings, overBright);
      expect(g.after.clipFraction, greaterThan(0.01));
      expect(g.changed, isFalse);
    });

    test('negative whites cannot hide blown pixels', () {
      final hidden = overBright.withValue(P.whites, -3);
      final g = Guards.enforce(proxy: chart.image, settings: hidden);
      expect(g.before.clipFraction, greaterThan(0.05));
    });

    test('crushed shadows get lifted blacks', () {
      final dark = SyntheticScenes.darkInterior();
      final g = Guards.enforce(
        proxy: dark.image,
        settings: DevelopSettings.defaults.withValue(P.exposure, 3.5),
      );
      expect(g.before.crushFraction, greaterThan(0.02));
      expect(g.after.crushFraction, lessThanOrEqualTo(0.02));
      expect(g.settings.value(P.blacks), greaterThan(0));
    });

    test('a too-dark proposal is brought into the key band', () {
      final g = Guards.enforce(
        proxy: chart.image,
        settings: DevelopSettings.defaults.withValue(P.exposure, -4),
      );
      expect(g.before.medianLStar, lessThan(15));
      expect(g.after.medianLStar, inInclusiveRange(15, 85));
      expect(g.reasons[P.exposure], contains('too dark'));
    });

    test('a good edit passes untouched', () {
      final g = Guards.enforce(
        proxy: chart.image,
        settings: DevelopSettings.defaults,
      );
      expect(g.changed, isFalse);
      expect(g.settings, DevelopSettings.defaults);
      expect(
        GuardReport.of(chart.image).violations(GuardLimits.proposal),
        <String>[],
      );
    });
  });
}
