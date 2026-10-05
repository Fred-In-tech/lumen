// Auto Enhance v2 on scenes without faces, measured on the CPU reference
// render (`renderReference`). Successor of the PLAN.md §9 checks 17–23:
// the solver now follows research 09 §2 (per-scene caps, partial white
// balance on warm light, no negative contrast on soft scenes).
import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'enhance_scenes.dart';

typedef _C = EnhanceConstants;

const _provider = LocalAutoEditProvider();

class _Run {
  const _Run(this.scene, this.outcome, this.rendered);

  final SyntheticScene scene;
  final AutoEditOutcome outcome;
  final RgbaBuffer rendered;

  double v(ParamId id) => outcome.settings.value(id);
}

Future<_Run> _autoOn(SyntheticScene scene) async {
  final outcome = await _provider.autoEdit(
    AutoEditInput(
      stats: ImageStats.compute(scene.image),
      exif: scene.exif,
      proxy: scene.image,
    ),
  );
  return _Run(scene, outcome, renderReference(scene.image, outcome.settings));
}

void main() {
  final runs = <SceneId, _Run>{};
  setUpAll(() async {
    for (final id in [
      SceneId.darkInterior,
      SceneId.overexposedBeach,
      SceneId.tungstenCast,
      SceneId.daylightCoolCast,
      SceneId.greenCast,
      SceneId.hazyLandscape,
      SceneId.wellExposedChart,
      SceneId.goldenHourPortrait,
    ]) {
      runs[id] = await _autoOn(SyntheticScenes.build(id));
    }
  });

  test('darkInterior (4 stops under): pushed to the per-click cap, clearly '
      'brighter, nothing clipped', () {
    final r = runs[SceneId.darkInterior]!;
    expect(SceneMetrics.medianLuma(r.scene.image), closeTo(0.10, 0.01));
    expect(r.v(P.exposure), greaterThan(1.5));
    expect(r.v(P.exposure), lessThanOrEqualTo(_C.evMaxOther));
    expect(SceneMetrics.medianLuma(r.rendered), greaterThan(0.24));
    expect(SceneMetrics.clipFraction(r.rendered), lessThanOrEqualTo(0.005));
  });

  test('overexposedBeach (8-bit, sun blown as shot): pulled down within '
      'the blown-frame limit, the sun stays white, clip ≤ 1 %', () {
    final r = runs[SceneId.overexposedBeach]!;
    expect(SceneMetrics.clipFraction(r.scene.image), closeTo(0.04, 0.005));
    expect(r.v(P.exposure), lessThan(-0.4));
    expect(r.v(P.exposure), greaterThanOrEqualTo(_C.evMinBlown));
    expect(
      SceneMetrics.medianLuma(r.rendered),
      lessThan(SceneMetrics.medianLuma(r.scene.image) - 0.03),
    );
    expect(r.v(P.highlights), lessThanOrEqualTo(0));
    expect(r.v(P.whites), greaterThan(0), reason: 'white given back');
    expect(SceneMetrics.clipFraction(r.rendered), lessThanOrEqualTo(0.01));
    expect(SceneMetrics.percentileLuma(r.rendered, 0.99), greaterThan(0.88));
  });

  group('white balance without faces', () {
    test('tungstenCast: cooled, most of the cast removed, some warmth '
        'kept', () {
      final r = runs[SceneId.tungstenCast]!;
      final p = r.scene.neutralPatches;
      expect(r.v(P.temp), lessThan(-20));
      expect(r.v(P.temp), greaterThanOrEqualTo(-_C.tempMaxWide));
      final before = SceneMetrics.castA(r.scene.image, p);
      final after = SceneMetrics.castA(r.rendered, p);
      expect(after, lessThanOrEqualTo(0.7 * before));
      expect(after, greaterThan(0), reason: 'never past neutral');
    });

    test('daylightCoolCast: warmed, cast reduced by ≥ 35 %', () {
      final r = runs[SceneId.daylightCoolCast]!;
      final p = r.scene.neutralPatches;
      expect(r.v(P.temp), greaterThan(20));
      final before = SceneMetrics.castA(r.scene.image, p);
      final after = SceneMetrics.castA(r.rendered, p);
      expect(after.abs(), lessThanOrEqualTo(0.65 * before.abs()));
      expect(after, lessThanOrEqualTo(0.02), reason: 'never past neutral');
    });

    test('greenCast: tint toward magenta, cast reduced by ≥ 50 %', () {
      final r = runs[SceneId.greenCast]!;
      final p = r.scene.neutralPatches;
      expect(r.v(P.tint), greaterThan(15));
      expect(
        SceneMetrics.castM(r.rendered, p).abs(),
        lessThanOrEqualTo(0.5 * SceneMetrics.castM(r.scene.image, p).abs()),
      );
    });

    test('goldenHourPortrait (sunset capture time): at most a third of the '
        'warm cast is removed', () {
      final r = runs[SceneId.goldenHourPortrait]!;
      final cast = SceneMetrics.castA(r.scene.image, r.scene.neutralPatches);
      expect(r.v(P.temp), lessThanOrEqualTo(0));
      expect(r.v(P.temp).abs(), lessThanOrEqualTo(100 * cast / 3));
      expect(r.v(P.vibrance), lessThanOrEqualTo(_C.vibranceMaxGroup));
      final tone = LocalAutoTone.run(proxy: r.scene.image, exif: r.scene.exif);
      expect(tone.detail.scene.warmIntent, isTrue);
      expect(tone.detail.wb.verdict, WbVerdict.keptWarmth);
    });
  });

  test('hazyLandscape: blacks < 0, contrast > 0, dehaze > 0, σ(L*) ≥ 1.3× '
      'before', () {
    final r = runs[SceneId.hazyLandscape]!;
    expect(r.v(P.blacks), lessThan(0));
    expect(r.v(P.contrast), greaterThan(0));
    expect(r.v(P.contrast), lessThanOrEqualTo(_C.contrastMax));
    expect(r.v(P.dehaze), greaterThan(0));
    final before = SceneMetrics.sigmaLStar(r.scene.image);
    expect(
      SceneMetrics.sigmaLStar(r.rendered),
      greaterThanOrEqualTo(1.3 * before),
    );
  });

  test('wellExposedChart: exposure, temp and tint are not touched', () {
    final r = runs[SceneId.wellExposedChart]!;
    expect(r.v(P.exposure), 0);
    expect(r.v(P.temp), 0);
    expect(r.v(P.tint), 0);
    expect(r.v(P.highlights), 0);
    expect(r.v(P.shadows), 0);
  });

  group('Auto on its own result settles (exposure and white balance)', () {
    for (final id in [
      SceneId.overexposedBeach,
      SceneId.greenCast,
      SceneId.wellExposedChart,
      SceneId.goldenHourPortrait,
    ]) {
      test('${id.name}: second pass moves less than the first', () async {
        final first = runs[id]!;
        final again = await _autoOn(
          SyntheticScene(name: id.name, image: first.rendered),
        );
        expect(
          again.v(P.exposure).abs(),
          lessThanOrEqualTo(first.v(P.exposure).abs() * 0.5 + 0.05),
        );
        expect(
          again.v(P.tint).abs(),
          lessThanOrEqualTo(first.v(P.tint).abs() * 0.5 + 0.01),
        );
      });
    }
  });

  group('LocalAutoTone', () {
    test('every change has a short human reason that states its size', () {
      for (final r in runs.values) {
        expect(r.outcome.changes, isNotEmpty);
        for (final c in r.outcome.changes) {
          expect(c.reason, isNotEmpty, reason: c.param);
          expect(c.reason.length, lessThan(90), reason: c.reason);
          if (!ParamRegistry.contains(c.param)) continue;
          expect(
            c.reason,
            contains(Reasons.formatDelta(c.param, c.delta)),
            reason: '${c.param} ${c.from} → ${c.to}: ${c.reason}',
          );
        }
      }
      final exposure = runs[SceneId.darkInterior]!.outcome.changes.firstWhere(
        (c) => c.param == P.exposure,
      );
      expect(exposure.reason, startsWith('Raised exposure +'));
      final temp = runs[SceneId.tungstenCast]!.outcome.changes.firstWhere(
        (c) => c.param == P.temp,
      );
      expect(temp.reason, contains('keep its mood'));
    });

    test('regression: a guard-limited exposure is explained by its final '
        'direction and size', () async {
      // Seen on IMG_0002: final +0.68 EV explained as "Lowered exposure".
      const strict = LocalAutoEditProvider(autoLimits: GuardLimits(maxClip: 0));
      // A deep-skinned face 2.5 stops under, in a white shirt: lifting the
      // face costs some of the shirt, which the strict guard refuses.
      final s = paintPeople(
        [const PaintedFace(Skin.deep, size: 1.6)],
        stops: -2.5,
        shirt: 1.6,
      );
      final out = await strict.autoEdit(
        AutoEditInput(
          stats: ImageStats.compute(s.image),
          proxy: s.image,
          faces: s.faces,
          // Highlights and whites may not help, so only the guard can stop the clip.
          locked: const {P.highlights, P.whites},
        ),
      );
      final ex = out.changes.firstWhere((c) => c.param == P.exposure);
      expect(ex.to, greaterThan(0));
      expect(ex.reason, startsWith('Raised exposure +'));
      expect(ex.reason, contains(Reasons.formatDelta(P.exposure, ex.delta)));
      expect(ex.reason, contains('clipping'));
    });

    test('locked params are never changed', () async {
      final s = SyntheticScenes.darkInterior();
      final current = DevelopSettings.defaults.withValues({
        P.exposure: 0.3,
        P.temp: 12,
      });
      final out = await _provider.autoEdit(
        AutoEditInput(
          stats: ImageStats.compute(s.image),
          proxy: s.image,
          current: current,
          locked: const {P.exposure, P.temp},
        ),
      );
      expect(out.settings.value(P.exposure), 0.3);
      expect(out.settings.value(P.temp), 12);
      expect(out.changes.map((c) => c.param), isNot(contains(P.exposure)));
    });

    test('managed params are solved from their defaults (never Auto on top '
        'of Auto); other settings and geometry are kept', () {
      final s = SyntheticScenes.wellExposedChart();
      final base = DevelopSettings.defaults
          .withValues({P.exposure: 2, P.clarity: 25})
          .copyWith(
            geometry: const Geometry(angle: 3),
            liquify: [
              LiquifyStroke(
                tool: LiquifyTool.values.first,
                points: const [(0.4, 0.4), (0.45, 0.4)],
                radius: 0.1,
              ),
            ],
          );
      final r = LocalAutoTone.run(proxy: s.image, base: base);
      expect(r.settings.value(P.exposure), 0);
      expect(r.settings.value(P.clarity), 25);
      expect(r.settings.geometry, base.geometry);
      expect(r.settings.liquify, base.liquify);
      expect(r.renders, greaterThan(3));
      expect(r.changesFrom(base), isNotEmpty);
      expect(LocalAutoTone.managedParams, contains(P.exposure));
    });

    test('an injected renderer is used for every solver render', () {
      var calls = 0;
      RgbaBuffer counting(RgbaBuffer src, DevelopSettings s) {
        calls++;
        return renderReference(src, s);
      }

      final r = LocalAutoTone.run(
        proxy: SyntheticScenes.greenCast().image,
        renderer: counting,
      );
      expect(calls, r.renders);
    });

    test('night EXIF caps the exposure push', () {
      final s = SyntheticScenes.darkInterior();
      final r = LocalAutoTone.run(
        proxy: s.image,
        exif: const ExifSummary(exposureSeconds: 0.5, iso: 3200),
      );
      expect(r.detail.scene.night, isTrue);
      expect(r.settings.value(P.exposure), lessThanOrEqualTo(_C.evNightMax));
    });

    test('a file an editor already wrote gets a much lighter touch and no '
        'white balance', () {
      final s = SyntheticScenes.tungstenCast();
      final fresh = LocalAutoTone.run(proxy: s.image);
      final edited = LocalAutoTone.run(
        proxy: s.image,
        exif: const ExifSummary(software: 'Adobe Lightroom Classic 14.0'),
      );
      expect(edited.detail.scene.alreadyEdited, isTrue);
      expect(edited.settings.value(P.temp), 0);
      expect(
        edited.settings.value(P.contrast),
        lessThan(0.6 * fresh.settings.value(P.contrast)),
      );
      expect(edited.confidence, lessThan(fresh.confidence));
    });
  });
}
