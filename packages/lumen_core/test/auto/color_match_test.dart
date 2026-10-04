import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

RgbaBuffer _scene(SceneId id) => SyntheticScenes.build(id, longEdge: 512).image;

/// The look of [img] rendered with [settings].
LookStats _look(RgbaBuffer img, DevelopSettings settings) =>
    ColorMatch.lookOf(img, settings: settings);

ColorMatchResult _match(
  RgbaBuffer target,
  LookStats reference, {
  DevelopSettings base = DevelopSettings.defaults,
}) => ColorMatch.run(target: target, reference: reference, base: base);

void main() {
  final chart = _scene(SceneId.wellExposedChart);
  final portrait = _scene(SceneId.goldenHourPortrait);

  test('a warm reference makes the target warmer', () {
    final ref = _look(chart, DevelopSettings.defaults.withValue(P.temp, 35));
    final r = _match(chart, ref);
    expect(r.settings.value(P.temp), greaterThan(12));
    expect(
      _look(chart, r.settings).neutral.b,
      greaterThan(_look(chart, DevelopSettings.defaults).neutral.b),
    );
  });

  test('a high-contrast reference raises contrast', () {
    final ref = _look(
      chart,
      DevelopSettings.defaults.withValues({P.contrast: 60, P.clarity: 0}),
    );
    final r = _match(chart, ref);
    final out = _look(chart, r.settings);
    final before = _look(chart, DevelopSettings.defaults);
    expect(out.sigmaL, greaterThan(before.sigmaL));
    expect(
      r.settings.value(P.contrast) +
          r.settings.value(P.whites) -
          r.settings.value(P.blacks),
      greaterThan(10),
    );
  });

  test('a desaturated reference lowers saturation', () {
    final ref = _look(
      chart,
      DevelopSettings.defaults.withValue(P.saturation, -60),
    );
    final r = _match(chart, ref);
    expect(r.settings.value(P.saturation), lessThan(-15));
    expect(
      _look(chart, r.settings).chroma,
      lessThan(_look(chart, DevelopSettings.defaults).chroma),
    );
  });

  test('matching a photo to itself is (almost) identity', () {
    for (final img in [chart, portrait]) {
      final base = DevelopSettings.defaults.withValue(P.exposure, 0.2);
      final r = _match(img, _look(img, base), base: base);
      for (final p in ColorMatch.managedParams) {
        final tol = p == P.exposure ? 0.05 : 3.0;
        expect(
          (r.settings.value(p) - base.value(p)).abs(),
          lessThanOrEqualTo(tol),
          reason: p,
        );
      }
    }
  });

  test('moves stay bounded even for an extreme reference', () {
    final ref = _look(
      chart,
      DevelopSettings.defaults.withValues({
        P.temp: 100,
        P.tint: 100,
        P.exposure: 4,
        P.contrast: 100,
        P.saturation: 100,
      }),
    );
    final r = _match(chart, ref);
    final s = r.settings;
    expect(s.value(P.exposure).abs(), lessThanOrEqualTo(1.5));
    expect(s.value(P.temp).abs(), lessThanOrEqualTo(40));
    expect(s.value(P.tint).abs(), lessThanOrEqualTo(25));
    for (final p in [P.contrast, P.highlights, P.shadows, P.whites]) {
      expect(s.value(p).abs(), lessThanOrEqualTo(40), reason: p);
    }
    expect(s.value(P.vibrance).abs(), lessThanOrEqualTo(40));
    expect(s.value(P.saturation).abs(), lessThanOrEqualTo(40));
    for (final z in [GradeZone.shadows, GradeZone.highlights]) {
      expect(s.value(P.grade(z, 'sat')), lessThanOrEqualTo(30));
    }
  });

  test('skin hue stays within a few degrees', () {
    final before = _look(portrait, DevelopSettings.defaults);
    expect(before.skinHue, isNotNull, reason: 'the scene has skin');
    // A cold, green reference would push skin far off its hue.
    final ref = _look(
      chart,
      DevelopSettings.defaults.withValues({P.temp: -80, P.tint: -60}),
    );
    final r = _match(portrait, ref);
    final after = _look(portrait, r.settings);
    var d = (after.skinHue! - before.skinHue!).abs();
    if (d > 180) d = 360 - d;
    expect(d, lessThanOrEqualTo(ColorMatchBounds.skinHueDeg + 0.5));
    expect(r.settings.value(P.temp), lessThan(0), reason: 'still cooler');
  });

  test('split toning follows tinted shadows and highlights', () {
    final ref = _look(
      chart,
      DevelopSettings.defaults.withValues({
        P.grade(GradeZone.shadows, 'hue'): 230,
        P.grade(GradeZone.shadows, 'sat'): 40,
        P.grade(GradeZone.highlights, 'hue'): 60,
        P.grade(GradeZone.highlights, 'sat'): 30,
      }),
    );
    final r = _match(chart, ref);
    final sh = r.settings.value(P.grade(GradeZone.shadows, 'sat'));
    expect(sh, greaterThan(5));
    var dh = (r.settings.value(P.grade(GradeZone.shadows, 'hue')) - 230).abs();
    if (dh > 180) dh = 360 - dh;
    expect(dh, lessThan(45), reason: 'a blue shadow tint');
  });

  test('only colour/tone sliders move: portrait and others are kept', () {
    final base = DevelopSettings.defaults
        .withValues({P.clarity: 12, P.sharpenAmount: 30})
        .copyWith(
          portrait: PortraitSettings.empty.withGroupValue(
            FaceGroup.all,
            PortraitIds.skinSoftening,
            40,
          ),
        );
    final ref = _look(chart, DevelopSettings.defaults.withValue(P.temp, 30));
    final r = _match(chart, ref, base: base);
    expect(r.settings.portrait, base.portrait);
    expect(r.settings.value(P.clarity), 12);
    expect(r.settings.value(P.sharpenAmount), 30);
    for (final c in r.changes) {
      expect(ColorMatch.managedParams, contains(c.param));
    }
  });
}
