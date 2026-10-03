import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

const _provider = LocalAutoEditProvider();

AutoEditInput _input(SyntheticScene s, {AiStyle style = AiStyle.natural}) =>
    AutoEditInput(
      stats: ImageStats.compute(s.image),
      exif: s.exif,
      style: style,
      proxy: s.image,
    );

void main() {
  final dark = SyntheticScenes.darkInterior();

  group('AC-24: AI Styles on darkInterior', () {
    final outcomes = <AiStyle, AutoEditOutcome>{};
    setUpAll(() async {
      for (final style in AiStyle.values) {
        outcomes[style] = await _provider.autoEdit(_input(dark, style: style));
      }
    });

    double median(AiStyle s) => SceneMetrics.medianLuma(
      renderReference(dark.image, outcomes[s]!.settings),
    );

    test('median luma: Moody < Natural < Clean & Bright', () {
      final moody = median(AiStyle.moody);
      final natural = median(AiStyle.natural);
      final bright = median(AiStyle.cleanBright);
      expect(moody, lessThan(natural));
      expect(natural, lessThan(bright));
    });

    test('B&W sets treatment = bw', () {
      expect(outcomes[AiStyle.bw]!.settings.treatment, Treatment.bw);
      expect(
        outcomes[AiStyle.bw]!.changes.map((c) => c.param),
        contains(ChangeIds.treatment),
      );
    });

    test('all 9 styles produce pairwise-different settings', () {
      final settings = [for (final s in AiStyle.values) outcomes[s]!.settings];
      expect(settings.length, 9);
      for (var i = 0; i < settings.length; i++) {
        for (var j = i + 1; j < settings.length; j++) {
          expect(
            settings[i],
            isNot(settings[j]),
            reason: '${AiStyle.values[i].id} vs ${AiStyle.values[j].id}',
          );
        }
      }
    });

    test('each style differs from Natural and explains its look', () {
      final natural = outcomes[AiStyle.natural]!.settings;
      for (final s in AiStyle.values.skip(1)) {
        final o = outcomes[s]!;
        expect(o.settings, isNot(natural), reason: s.id);
        expect(o.changes.every((c) => c.reason.isNotEmpty), isTrue);
        expect(o.intent, contains(s.label));
        expect(o.engineUsed, AutoEditEngine.local);
        expect(o.degraded, isFalse);
      }
      final moodyVignette = outcomes[AiStyle.moody]!.changes.firstWhere(
        (c) => c.param == P.vignetteAmount,
      );
      expect(moodyVignette.reason, startsWith('Moody look: vignette'));
    });

    test('Portrait Soft caps vibrance at 10', () {
      expect(
        outcomes[AiStyle.portraitSoft]!.settings.value(P.vibrance),
        lessThanOrEqualTo(10),
      );
    });
  });

  group('LocalAutoEditProvider', () {
    test('is the always-available local engine', () async {
      expect(_provider.engine, AutoEditEngine.local);
      expect((await _provider.status()).available, isTrue);
    });

    test('without pixels it degrades to a stats-only estimate', () async {
      final s = SyntheticScenes.tungstenCast();
      final o = await _provider.autoEdit(
        AutoEditInput(stats: ImageStats.compute(s.image)),
      );
      expect(o.degraded, isTrue);
      expect(o.degradedReason, isNotEmpty);
      expect(o.settings.value(P.temp), lessThan(0));
      expect(o.changes, isNotEmpty);
      final d = await _provider.autoEdit(
        AutoEditInput(stats: ImageStats.compute(dark.image)),
      );
      expect(d.settings.value(P.exposure), greaterThan(1));
    });

    test('instruct applies the lexicon with reasons, one outcome', () async {
      final o = await _provider.instruct(
        InstructInput(
          instruction: 'warmer and brighten the shadows a bit',
          stats: ImageStats.compute(dark.image),
          proxy: dark.image,
        ),
      );
      expect(o.settings.value(P.temp), greaterThan(0));
      expect(o.settings.value(P.shadows), greaterThan(0));
      expect(o.suggestions, isEmpty);
      expect(o.confidence, 1);
      final temp = o.changes.firstWhere((c) => c.param == P.temp);
      expect(temp.reason, contains('warmer and brighten the shadows a bit'));
    });

    test('instruct guards brightness words but not explicit numbers', () async {
      final chart = SyntheticScenes.wellExposedChart();
      final stats = ImageStats.compute(chart.image);
      final brighter = await _provider.instruct(
        InstructInput(
          instruction: 'way brighter',
          stats: stats,
          proxy: chart.image,
          current: DevelopSettings.defaults.withValue(P.exposure, 0.5),
        ),
      );
      expect(brighter.settings.value(P.exposure), lessThan(1.25));
      final explicit = await _provider.instruct(
        InstructInput(
          instruction: 'exposure +0.75',
          stats: stats,
          proxy: chart.image,
          current: DevelopSettings.defaults.withValue(P.exposure, 0.5),
        ),
      );
      expect(explicit.settings.value(P.exposure), 1.25);
    });

    test('unrecognized instructions change nothing and offer chips', () async {
      final current = DevelopSettings.defaults.withValue(P.contrast, 10);
      final o = await _provider.instruct(
        InstructInput(
          instruction: 'make it pop like a wamer sunrise llama',
          stats: ImageStats.compute(dark.image),
          current: current,
        ),
      );
      expect(o.settings.value(P.contrast), greaterThan(10));
      final none = await _provider.instruct(
        InstructInput(
          instruction: 'qwerty',
          stats: ImageStats.compute(dark.image),
          current: current,
        ),
      );
      expect(none.settings, current);
      expect(none.hasChanges, isFalse);
      expect(none.suggestions, isNotEmpty);
      expect(none.confidence, 0);
    });

    test('locked params survive styles and instructions', () async {
      final current = DevelopSettings.defaults.withValue(P.vibrance, -5);
      final o = await _provider.autoEdit(
        AutoEditInput(
          stats: ImageStats.compute(dark.image),
          proxy: dark.image,
          style: AiStyle.vibrant,
          current: current,
          locked: const {P.vibrance},
        ),
      );
      expect(o.settings.value(P.vibrance), -5);
      final i = await _provider.instruct(
        InstructInput(
          instruction: 'more vivid',
          stats: ImageStats.compute(dark.image),
          current: current,
          locked: const {P.vibrance},
        ),
      );
      expect(i.settings.value(P.vibrance), -5);
      expect(i.settings.value(P.saturation), 5);
    });
  });
}
