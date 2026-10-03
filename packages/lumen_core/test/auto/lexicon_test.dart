import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

const _d = DevelopSettings.defaults;

class _Case {
  const _Case(
    this.phrase,
    this.expect, {
    this.current = const {},
    this.locked = const {},
    this.treatment,
  });

  final String phrase;
  final Map<ParamId, Object> expect;
  final Map<ParamId, double> current;
  final Set<ParamId> locked;
  final Treatment? treatment;
}

Matcher _near(double v) => closeTo(v, 1e-6);

final _cases = <_Case>[
  // Intensity × atoms.
  _Case('a bit warmer', {P.temp: closeTo(7.5, 0.5)}),
  _Case('warmer', {P.temp: _near(15), P.tint: _near(3)}),
  _Case('a touch warmer', {P.temp: _near(3.75)}),
  _Case('much warmer', {P.temp: _near(26.25)}),
  _Case('way warmer', {P.temp: _near(30)}), // 37.5 capped at ±30
  _Case('slightly cooler', {P.temp: _near(-7.5)}),
  _Case('make it colder', {P.temp: _near(-15)}),
  _Case('cozier please', {P.temp: _near(15)}),
  _Case('make it moodier and lift the shadows', {
    P.shadows: greaterThan(0),
    P.exposure: _near(-0.3),
    P.vignetteAmount: _near(-15),
  }),
  _Case('more dramatic', {P.highlights: _near(-25)}),
  _Case('punchy', {P.contrast: _near(20), P.clarity: _near(8)}),
  _Case('softer', {P.contrast: _near(-15), P.shadows: _near(15)}),
  _Case('airy', {P.exposure: _near(0.4), P.shadows: _near(25)}),
  _Case('light and bright', {P.exposure: _near(0.4)}),
  _Case('cinematic', {'grade.shadows.hue': _near(200)}),
  _Case('teal and orange', {'grade.highlights.hue': _near(40)}),
  _Case('vintage film look', {P.grainAmount: _near(20)}),
  _Case('sunset warmth', {
    P.temp: _near(20),
    'grade.highlights.hue': _near(40),
  }),
  _Case('golden hour', {P.temp: _near(20)}),
  _Case('make the sky pop', {'hsl.blue.sat': _near(15), P.dehaze: _near(8)}),
  _Case('more vivid', {P.vibrance: _near(25)}),
  _Case('really colorful', {P.vibrance: _near(40)}), // 43.75 capped at 40
  _Case('muted colors', {P.vibrance: _near(-25)}),
  _Case('less colorful', {P.vibrance: _near(-25)}),
  // Treatment.
  _Case('black and white', {P.contrast: _near(15)}, treatment: Treatment.bw),
  _Case('make it b&w', {}, treatment: Treatment.bw),
  _Case('monochrome', {}, treatment: Treatment.bw),
  // Direct slider phrases.
  _Case('lift the shadows', {P.shadows: _near(20)}),
  _Case('brighten the shadows a bit', {P.shadows: _near(10)}),
  _Case('darken the shadows', {P.shadows: _near(-20)}),
  _Case('recover the highlights', {P.highlights: _near(-20)}),
  _Case('tame highlights a lot', {P.highlights: _near(-35)}),
  _Case('more contrast', {P.contrast: _near(15)}),
  _Case('reduce contrast slightly', {P.contrast: _near(-7.5)}),
  _Case('way more contrast', {P.contrast: _near(37.5)}),
  _Case('deeper blacks', {P.blacks: _near(-10)}),
  _Case('whites up a bit', {P.whites: _near(5)}),
  _Case('more saturation', {P.saturation: _near(10)}),
  _Case('add some clarity', {P.clarity: _near(15)}),
  _Case('remove the haze', {P.dehaze: _near(15)}),
  _Case('less haze', {P.dehaze: _near(15)}),
  _Case('add a vignette', {P.vignetteAmount: _near(-15)}),
  _Case('more grain', {P.grainAmount: _near(20)}),
  _Case('sharper', {P.sharpenAmount: _near(25)}),
  _Case('reduce noise', {P.noiseLuminance: _near(20)}),
  _Case('brighter', {P.exposure: _near(0.3)}),
  _Case('a little darker', {P.exposure: _near(-0.15)}),
  _Case('increase exposure dramatically', {P.exposure: _near(0.75)}),
  // Explicit numbers.
  _Case('exposure +0.5', {P.exposure: _near(0.5)}),
  _Case('+0.5 exposure', {P.exposure: _near(0.5)}),
  _Case('exposure −1.5', {P.exposure: _near(-1.5)}), // explicit: no cap
  _Case('+0.7 ev', {P.exposure: _near(0.7)}),
  _Case('shadows to 40', {P.shadows: _near(40)}),
  _Case('set contrast to 20', {P.contrast: _near(20)}),
  _Case('shadows 40', {P.shadows: _near(40)}, current: {P.shadows: 10}),
  _Case('raise shadows by 25', {P.shadows: _near(25)}),
  _Case('lower highlights by 30', {P.highlights: _near(-30)}),
  _Case('temperature to 500', {P.temp: _near(100)}), // registry clamp
  _Case('clarity +30 and tint -10', {P.clarity: _near(30), P.tint: _near(-10)}),
  // Conflicts: the later clause wins.
  _Case('brighter but moodier', {P.exposure: _near(-0.3)}),
  _Case('moodier but brighter', {
    P.exposure: _near(0.3),
    P.vignetteAmount: _near(-15),
  }),
  _Case('warmer, more contrast and lift shadows a little', {
    P.temp: _near(15),
    P.contrast: _near(15),
    P.shadows: _near(10),
  }),
  // "Less X" against the baseline.
  _Case('less contrast', {P.contrast: _near(15)}, current: {P.contrast: 30}),
  _Case(
    'much less contrast',
    {P.contrast: _near(3.75)},
    current: {P.contrast: 30},
  ),
  _Case('less contrast', {P.contrast: _near(0)}),
  _Case('not so warm', {P.temp: _near(10)}, current: {P.temp: 20}),
  _Case(
    'less saturated',
    {P.saturation: _near(10)},
    current: {P.saturation: 20},
  ),
  _Case(
    'less vignette',
    {P.vignetteAmount: _near(-15)},
    current: {P.vignetteAmount: -30},
  ),
  // Locks.
  _Case(
    'warmer',
    {P.temp: _near(5), P.tint: _near(3)},
    current: {P.temp: 5},
    locked: {P.temp},
  ),
  _Case(
    'temp +10',
    {P.temp: _near(15)},
    current: {P.temp: 5},
    locked: {P.temp},
  ),
  _Case(
    'lift the shadows',
    {P.shadows: _near(30)},
    current: {P.shadows: 10},
    locked: {P.shadows},
  ),
];

void main() {
  group('Lexicon phrase table (AC-25)', () {
    test('has at least 40 phrases', () {
      expect(_cases.length, greaterThanOrEqualTo(40));
    });

    for (final c in _cases) {
      test('"${c.phrase}" ${c.current.isEmpty ? '' : 'from ${c.current} '}'
          '${c.locked.isEmpty ? '' : 'locked ${c.locked}'}', () {
        final current = _d.withValues(c.current);
        final result = Lexicon.parse(c.phrase);
        expect(result.isRecognized, isTrue, reason: c.phrase);
        final out = result.apply(current, baseline: _d, locked: c.locked);
        for (final e in c.expect.entries) {
          expect(out.settings.value(e.key), e.value, reason: e.key);
        }
        if (c.treatment != null) {
          expect(out.settings.treatment, c.treatment);
        }
      });
    }
  });

  group('AC-25 named checks', () {
    test('"a bit warmer" → temp +7.5 ±0.5', () {
      final s = Lexicon.parse('a bit warmer').apply(_d).settings;
      expect(s.value(P.temp), closeTo(7.5, 0.5));
    });

    test(
      '"make it moodier and lift the shadows" → moody atom + shadows > 0',
      () {
        final r = Lexicon.parse('make it moodier and lift the shadows');
        expect(r.clauses.first.atoms, contains(StyleAtom.moody));
        expect(r.apply(_d).settings.value(P.shadows), greaterThan(0));
      },
    );

    test('"less contrast" never goes below the pre-instruction baseline', () {
      final baseline = _d.withValue(P.contrast, 10);
      for (final start in [-20.0, 0.0, 10.0, 15.0, 40.0, 100.0]) {
        for (final phrase in [
          'less contrast',
          'much less contrast',
          'way less contrast',
        ]) {
          final out = Lexicon.parse(phrase)
              .apply(_d.withValue(P.contrast, start), baseline: baseline);
          final v = out.settings.value(P.contrast);
          expect(v, greaterThanOrEqualTo(start < 10 ? start : 10));
          expect(v, lessThanOrEqualTo(start));
        }
      }
    });

    test('"exposure +0.5" → +0.5 exactly', () {
      final s = Lexicon.parse('exposure +0.5')
          .apply(_d.withValue(P.exposure, 0.25))
          .settings;
      expect(s.value(P.exposure), 0.75);
    });
  });

  group('Lexicon results', () {
    test('unrecognized text returns suggestions and no change', () {
      final r = Lexicon.parse('xyzzy plugh');
      expect(r.isRecognized, isFalse);
      expect(r.suggestions, isNotEmpty);
      final out = r.apply(_d);
      expect(out.settings, _d);
      expect(out.changes, isEmpty);
    });

    test('typos get a did-you-mean suggestion', () {
      final r = Lexicon.parse('wamer');
      expect(r.isRecognized, isFalse);
      expect(r.suggestions.first, 'warmer');
      expect(Lexicon.parse('more contrsat').suggestions, contains('contrast'));
    });

    test('empty instruction is unrecognized', () {
      expect(Lexicon.parse('   ').isRecognized, isFalse);
    });

    test('changes carry instruction reasons', () {
      final out = Lexicon.parse('a bit warmer').apply(_d);
      final temp = out.changes.firstWhere((c) => c.param == P.temp);
      expect(temp.reason, 'Temp +7.5 for “a bit warmer”');
    });

    test('"less X" at the baseline explains why nothing changed', () {
      final out = Lexicon.parse('less contrast').apply(_d);
      expect(out.changes, isEmpty);
      expect(out.notes.single, contains('Contrast'));
    });

    test('partially understood instructions keep the recognized clauses', () {
      final r = Lexicon.parse('warmer and frobnicate it');
      expect(r.isRecognized, isTrue);
      expect(r.unrecognizedClauses, ['frobnicate it']);
      expect(r.apply(_d).settings.value(P.temp), 15);
    });
  });
}
