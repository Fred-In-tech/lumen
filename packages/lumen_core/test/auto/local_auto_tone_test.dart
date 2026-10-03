// Acceptance checks PLAN.md §9 items 17–23 on 512-px synthetic scenes,
// measured on the CPU reference render (`renderReference`).
import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

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

Future<_Run> _auto(SceneId id) => _autoOn(SyntheticScenes.build(id));

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
      runs[id] = await _auto(id);
    }
  });

  test('AC-17: darkInterior → median luma in [0.38, 0.55], clip ≤ 0.5 %', () {
    final r = runs[SceneId.darkInterior]!;
    expect(SceneMetrics.medianLuma(r.scene.image), closeTo(0.10, 0.01));
    expect(SceneMetrics.medianLuma(r.rendered), inInclusiveRange(0.38, 0.55));
    expect(SceneMetrics.clipFraction(r.rendered), lessThanOrEqualTo(0.005));
    expect(r.v(P.exposure), greaterThan(1));
  });

  test('AC-18: overexposedBeach → median in [0.50, 0.72], highlights < 0, '
      'clip ≤ 1 %', () {
    final r = runs[SceneId.overexposedBeach]!;
    expect(SceneMetrics.clipFraction(r.scene.image), closeTo(0.04, 0.005));
    expect(SceneMetrics.medianLuma(r.rendered), inInclusiveRange(0.50, 0.72));
    expect(r.v(P.highlights), lessThan(0));
    expect(SceneMetrics.clipFraction(r.rendered), lessThanOrEqualTo(0.01));
  });

  group('AC-19: white balance', () {
    test('tungstenCast → temp < 0, neutral-patch cast reduced ≥ 50 %', () {
      final r = runs[SceneId.tungstenCast]!;
      final p = r.scene.neutralPatches;
      expect(r.v(P.temp), lessThan(0));
      final before = SceneMetrics.castA(r.scene.image, p).abs();
      final after = SceneMetrics.castA(r.rendered, p).abs();
      expect(after, lessThanOrEqualTo(0.5 * before));
    });

    test('daylightCoolCast → temp > 0', () {
      expect(runs[SceneId.daylightCoolCast]!.v(P.temp), greaterThan(0));
    });

    test('greenCast → tint > 0 (toward magenta)', () {
      expect(runs[SceneId.greenCast]!.v(P.tint), greaterThan(0));
    });
  });

  test('AC-20: hazyLandscape → blacks < 0, contrast > 0, dehaze > 0, '
      'σ(L*) ≥ 1.4× before', () {
    final r = runs[SceneId.hazyLandscape]!;
    expect(r.v(P.blacks), lessThan(0));
    expect(r.v(P.contrast), greaterThan(0));
    expect(r.v(P.dehaze), greaterThan(0));
    final before = SceneMetrics.sigmaLStar(r.scene.image);
    expect(
      SceneMetrics.sigmaLStar(r.rendered),
      greaterThanOrEqualTo(1.4 * before),
    );
  });

  test('AC-21: wellExposedChart → |exposure| ≤ 0.15 EV, |temp| ≤ 5, '
      '|tint| ≤ 5', () {
    final r = runs[SceneId.wellExposedChart]!;
    expect(r.v(P.exposure).abs(), lessThanOrEqualTo(0.15));
    expect(r.v(P.temp).abs(), lessThanOrEqualTo(5));
    expect(r.v(P.tint).abs(), lessThanOrEqualTo(5));
  });

  group('AC-22: idempotence (Auto on an already-auto-edited render)', () {
    for (final id in [
      SceneId.darkInterior,
      SceneId.overexposedBeach,
      SceneId.tungstenCast,
      SceneId.daylightCoolCast,
      SceneId.greenCast,
      SceneId.hazyLandscape,
      SceneId.wellExposedChart,
    ]) {
      test('${id.name}: |Δexposure| ≤ 0.10 EV and |Δtemp| ≤ 3', () async {
        final first = runs[id]!;
        final again = await _autoOn(
          SyntheticScene(name: id.name, image: first.rendered),
        );
        expect(again.v(P.exposure).abs(), lessThanOrEqualTo(0.10));
        expect(again.v(P.temp).abs(), lessThanOrEqualTo(3));
      });
    }
  });

  group('AC-23: goldenHourPortrait keeps the warm cast', () {
    test('temp correction ≤ 50 % of full neutralization; vibrance ≤ 20', () {
      final r = runs[SceneId.goldenHourPortrait]!;
      final estimate = ImageStats.compute(r.scene.image).wb.a;
      final trueCast = SceneMetrics.castA(
        r.scene.image,
        r.scene.neutralPatches,
      );
      final full = -100 * math.max(estimate, trueCast) / 1.0;
      expect(r.v(P.temp), lessThanOrEqualTo(0));
      expect(r.v(P.temp).abs(), lessThanOrEqualTo(0.5 * full.abs()));
      expect(r.v(P.vibrance), lessThanOrEqualTo(20));
      expect(
        SceneMetrics.castA(r.rendered, r.scene.neutralPatches),
        greaterThan(0.5 * trueCast),
      );
    });

    test('WB strength is reduced to the intentional-cast value', () {
      final s = SyntheticScenes.goldenHourPortrait();
      final tone = LocalAutoTone.run(proxy: s.image, exif: s.exif);
      expect(tone.wbStrength, AutoToneConstants.wbStrengthIntentional);
      final neutral = LocalAutoTone.run(
        proxy: SyntheticScenes.tungstenCast().image,
      );
      expect(neutral.wbStrength, AutoToneConstants.wbStrength);
    });
  });

  group('LocalAutoTone', () {
    test('every change has a short human reason', () {
      for (final r in runs.values) {
        expect(r.outcome.changes, isNotEmpty);
        for (final c in r.outcome.changes) {
          expect(c.reason, isNotEmpty, reason: c.param);
          expect(c.reason.length, lessThan(90), reason: c.reason);
        }
      }
      final shadows = runs[SceneId.darkInterior]!.outcome.changes.firstWhere(
        (c) => c.param == P.exposure,
      );
      expect(shadows.reason, startsWith('Raised exposure +'));
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

    test('managed params are recomputed; others are kept', () {
      final s = SyntheticScenes.wellExposedChart();
      final base = DevelopSettings.defaults.withValues({
        P.exposure: 2,
        P.clarity: 25,
      });
      final r = LocalAutoTone.run(proxy: s.image, base: base);
      expect(r.settings.value(P.exposure).abs(), lessThanOrEqualTo(0.15));
      expect(r.settings.value(P.clarity), 25);
      expect(r.renders, greaterThan(3));
      expect(r.changesFrom(base), isNotEmpty);
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

    test('sceneKey: flat images get the base key; ranges are clamped', () {
      final flat = ImageStats.compute(RgbaBuffer.filled(32, 32, 90, 90, 90));
      expect(LocalAutoTone.sceneKey(flat), closeTo(0.18, 1e-9));
      final bright = ImageStats.compute(
        SyntheticScenes.overexposedBeach().image,
      );
      expect(LocalAutoTone.sceneKey(bright), greaterThan(0.18));
      expect(LocalAutoTone.sceneKey(bright), lessThanOrEqualTo(0.36));
    });

    test('sunsetLike: EXIF time windows and scene hints', () {
      ExifSummary at(int h, int m) =>
          ExifSummary(capturedAt: DateTime(2026, 6, 1, h, m));
      expect(LocalAutoTone.sunsetLike(at(18, 42), null), isTrue);
      expect(LocalAutoTone.sunsetLike(at(6, 10), null), isTrue);
      expect(LocalAutoTone.sunsetLike(at(13, 0), null), isFalse);
      expect(LocalAutoTone.sunsetLike(null, null), isFalse);
      expect(
        LocalAutoTone.sunsetLike(
          null,
          const SceneInfo(timeOfDay: 'indoor_tungsten'),
        ),
        isTrue,
      );
    });

    test('night EXIF caps the exposure push', () {
      final s = SyntheticScenes.darkInterior();
      final r = LocalAutoTone.run(
        proxy: s.image,
        exif: const ExifSummary(exposureSeconds: 0.5, iso: 3200),
      );
      expect(
        r.settings.value(P.exposure),
        lessThanOrEqualTo(AutoToneConstants.nightEvCap),
      );
    });
  });
}
