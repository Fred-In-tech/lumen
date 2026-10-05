// Auto Enhance v2 on people (research 09 §2, §5.1): each rule is encoded as
// a painted scene and judged on the CPU reference render, not only on the
// slider values.
import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'enhance_scenes.dart';

typedef _C = EnhanceConstants;

/// The solver's own view of [s] (targets, flags, verdicts).
EnhanceOutcome _detail(PeopleScene s) =>
    LocalAutoTone.run(proxy: s.image, faces: s.faces, exif: s.exif).detail;

void main() {
  group('face-aware exposure', () {
    for (final e in Skin.all.entries) {
      test(
        '${e.key} skin, well exposed: exposure and skin are left alone',
        () async {
          final r = await enhance(paintPeople([PaintedFace(e.value)]));
          final target = _detail(r.scene).faces.single.target;
          // Deep skin sits a touch under its band as painted: a small lift.
          expect(r.v(P.exposure).abs(), lessThanOrEqualTo(0.35));
          expect(
            (r.after.single.lStar - r.before.single.lStar).abs(),
            lessThanOrEqualTo(4),
          );
          expect(r.after.single.lStar, greaterThanOrEqualTo(target.low - 1));
          expect(r.after.single.lStar, lessThanOrEqualTo(target.high + 1));
        },
      );

      test(
        '${e.key} skin, 1.5 stops under: lifted into its own band',
        () async {
          final r = await enhance(
            paintPeople([PaintedFace(e.value)], stops: -1.5),
          );
          final target = _detail(r.scene).faces.single.target;
          expect(r.v(P.exposure), greaterThan(0.6));
          expect(r.v(P.exposure), lessThanOrEqualTo(_C.evMaxPortrait));
          expect(r.after.single.lStar, greaterThanOrEqualTo(target.low - 1.5));
          expect(r.after.single.lStar, lessThanOrEqualTo(target.high));
          expect(r.after.single.hot, lessThanOrEqualTo(_C.skinHotMax));
        },
      );
    }

    test('deeper skin gets a lower target than lighter skin', () {
      double centre(Lin skin) =>
          _detail(paintPeople([PaintedFace(skin)])).faces.single.target.centre;
      expect(centre(Skin.deep), lessThan(centre(Skin.brown)));
      expect(centre(Skin.brown), lessThan(centre(Skin.tan)));
      expect(centre(Skin.tan), lessThan(centre(Skin.light)));
      expect(centre(Skin.deep), closeTo(_C.centreDark, 3));
      expect(centre(Skin.light), closeTo(_C.centreLight, 3));
    });

    test('under-exposed deep skin is never pushed towards a light-skin '
        'target', () async {
      final r = await enhance(
        paintPeople([const PaintedFace(Skin.deep)], stops: -1.5),
      );
      expect(r.after.single.lStar, lessThanOrEqualTo(_C.highDark));
    });

    for (final e in {
      'deep': Skin.deep,
      'brown': Skin.brown,
      'tan': Skin.tan,
    }.entries) {
      test('${e.key} skin, 1 stop over with a blown shirt: brought down, '
          'never below its band', () async {
        final r = await enhance(paintPeople([PaintedFace(e.value)], stops: 1));
        final target = _detail(r.scene).faces.single.target;
        expect(r.v(P.exposure), lessThan(-0.3));
        expect(r.v(P.exposure), greaterThanOrEqualTo(_C.evMinPortrait));
        expect(r.after.single.lStar, lessThan(r.before.single.lStar - 4));
        expect(r.after.single.lStar, greaterThanOrEqualTo(target.low - 1));
        expect(r.after.single.hot, lessThanOrEqualTo(_C.skinHotMax));
      });
    }

    test('deep skin on a dark background, no white in frame: the dark '
        'background does not drive a big push', () async {
      final r = await enhance(
        paintPeople([const PaintedFace(Skin.deep)], wall: 0.04, shirt: 0.05),
      );
      final d = _detail(r.scene);
      expect(d.faces.single.target.confidence, 0, reason: 'tone unknown');
      expect(d.exposure.globalEv, greaterThan(1.5), reason: 'histogram');
      expect(r.v(P.exposure), lessThanOrEqualTo(_C.unknownToneEvMax));
      expect(r.after.single.lStar, lessThanOrEqualTo(_C.highDark));
    });

    test('a face in its band on a bright wall is not darkened with the '
        'wall', () async {
      final r = await enhance(
        paintPeople([const PaintedFace(Skin.brown)], wall: 0.8),
      );
      expect(r.v(P.exposure), greaterThanOrEqualTo(-_C.inBandEvMax));
      expect(
        r.after.single.lStar,
        greaterThanOrEqualTo(r.before.single.lStar - 4),
      );
    });

    test('group with mixed skin tones: the lightest face stays in its band, '
        'the darkest is lifted', () async {
      final scene = paintPeople(const [
        PaintedFace(Skin.deep, u: 0.25),
        PaintedFace(Skin.light, u: 0.5),
        PaintedFace(Skin.tan, u: 0.75),
      ], stops: -0.8);
      final r = await enhance(scene);
      final d = _detail(scene);
      expect(d.scene.kind, SceneKind.group);
      final before = r.before, after = r.after;
      for (var i = 0; i < 3; i++) {
        expect(
          after[i].lStar,
          lessThanOrEqualTo(d.faces[i].target.high),
          reason: 'face $i over its band',
        );
        expect(after[i].lStar, greaterThan(before[i].lStar + 4));
        expect(
          after[i].lStar,
          greaterThanOrEqualTo(d.faces[i].target.low - 2.5),
        );
      }
      expect(r.v(P.shadows), greaterThan(0), reason: 'darker faces → shadows');
    });

    test('well-exposed group: exposure is left alone', () async {
      final r = await enhance(
        paintPeople(const [
          PaintedFace(Skin.deep, u: 0.25),
          PaintedFace(Skin.light, u: 0.5),
          PaintedFace(Skin.tan, u: 0.75),
        ]),
      );
      expect(r.v(P.exposure).abs(), lessThanOrEqualTo(0.15));
    });

    test('faces too small to measure fall back to the histogram', () {
      final scene = paintPeople([const PaintedFace(Skin.tan, size: 0.1)]);
      final d = _detail(scene);
      expect(d.faces, isEmpty);
      expect(d.scene.kind, SceneKind.other);
    });
  });

  group('white balance', () {
    for (final e in {'tan': Skin.tan, 'deep': Skin.deep}.entries) {
      test('warm tungsten portrait (${e.key}): the warmth is kept', () async {
        final r = await enhance(
          paintPeople([PaintedFace(e.value)], light: (1.35, 1.0, 0.7)),
        );
        final cast = SceneMetrics.castA(r.scene.image, [r.scene.neutral]);
        final left = SceneMetrics.castA(r.rendered, [r.scene.neutral]);
        expect(cast, closeTo(0.95, 0.05));
        expect(r.v(P.temp), lessThanOrEqualTo(0));
        expect(r.v(P.temp), greaterThanOrEqualTo(-_C.tempMax));
        expect(left, greaterThanOrEqualTo(0.7 * cast), reason: 'mood kept');
        final skin = r.after.single;
        expect(skin.a, inInclusiveRange(_C.skinALow, _C.skinAHigh));
        expect(skin.hue, inInclusiveRange(_C.skinHueLow, _C.skinHueHigh));
        expect(_detail(r.scene).wb.verdict, WbVerdict.keptWarmth);
      });
    }

    for (final e in {'light': Skin.light, 'brown': Skin.brown}.entries) {
      test('blue-cast daylight portrait (${e.key}): corrected', () async {
        final r = await enhance(
          paintPeople([PaintedFace(e.value)], light: (0.8, 1.0, 1.25)),
        );
        final cast = SceneMetrics.castA(r.scene.image, [r.scene.neutral]);
        final left = SceneMetrics.castA(r.rendered, [r.scene.neutral]);
        expect(cast, closeTo(-0.64, 0.05));
        expect(r.v(P.temp), greaterThan(25));
        expect(left.abs(), lessThanOrEqualTo(0.55 * cast.abs()));
        expect(left, lessThanOrEqualTo(0.05), reason: 'not over-corrected');
        final skin = r.after.single;
        expect(skin.a, greaterThanOrEqualTo(_C.skinALow));
        expect(skin.hue, inInclusiveRange(_C.skinHueLow, _C.skinHueHigh));
      });
    }

    test(
      'green cast on skin: tint moves skin back to its hue window',
      () async {
        final r = await enhance(
          paintPeople([const PaintedFace(Skin.tan)], light: (1.0, 1.2, 1.0)),
        );
        expect(r.before.single.m, greaterThan(_C.skinMHigh));
        expect(r.v(P.tint), greaterThan(15));
        expect(r.after.single.m, lessThan(r.before.single.m - 0.1));
        expect(r.after.single.hue, lessThanOrEqualTo(_C.skinHueHigh + 1));
      },
    );

    test(
      'neutral light, skin in its window: white balance is not touched',
      () async {
        for (final skin in Skin.all.values) {
          final r = await enhance(paintPeople([PaintedFace(skin)]));
          expect(r.v(P.temp), 0);
          expect(r.v(P.tint), 0);
        }
      },
    );

    test('golden hour (capture time) keeps more warmth than the same light '
        'at noon', () async {
      PeopleScene at(int hour) => paintPeople(
        [const PaintedFace(Skin.tan)],
        light: (1.3, 1.0, 0.72),
        exif: ExifSummary(capturedAt: DateTime(2026, 7, 12, hour, 40)),
      );
      final golden = await enhance(at(18));
      final noon = await enhance(at(12));
      expect(golden.v(P.temp), lessThanOrEqualTo(0));
      expect(golden.v(P.temp), greaterThanOrEqualTo(noon.v(P.temp)));
      final cast = SceneMetrics.castA(golden.scene.image, [
        golden.scene.neutral,
      ]);
      expect(
        SceneMetrics.castA(golden.rendered, [golden.scene.neutral]),
        greaterThanOrEqualTo(0.75 * cast),
      );
    });

    test('skin-coloured surroundings do not read as a warm cast', () async {
      // Dark room, no neutrals: only skin and near-black.
      final r = await enhance(
        paintPeople([const PaintedFace(Skin.light)], wall: 0.04, shirt: 0.05),
      );
      expect(r.v(P.temp), 0);
    });
  });

  group('tone', () {
    test('high-key white dress: whites stay white, nothing clips, the key '
        'is kept', () async {
      final scene = paintPeople(
        [const PaintedFace(Skin.light)],
        wall: 0.8,
        shirt: 0.92,
        hair: 0.25,
      );
      final r = await enhance(scene);
      expect(_detail(scene).scene.highKey, isTrue);
      expect(r.v(P.exposure).abs(), lessThanOrEqualTo(0.1));
      expect(r.v(P.whites), greaterThanOrEqualTo(0), reason: 'no grey whites');
      expect(r.v(P.highlights), greaterThanOrEqualTo(-10));
      expect(r.v(P.blacks), greaterThanOrEqualTo(_C.blacksMinAiry));
      final before = SceneMetrics.percentileLuma(scene.image, 0.99);
      final after = SceneMetrics.percentileLuma(r.rendered, 0.99);
      expect(after, greaterThanOrEqualTo(before - 0.02));
      expect(SceneMetrics.clipFraction(r.rendered), lessThanOrEqualTo(0.001));
      expect(
        SceneMetrics.medianLuma(r.rendered),
        greaterThanOrEqualTo(SceneMetrics.medianLuma(scene.image) - 0.04),
      );
    });

    test('low-key portrait stays low-key', () async {
      final scene = paintPeople(
        [const PaintedFace(Skin.tan)],
        wall: 0.012,
        shirt: 0.03,
      );
      final r = await enhance(scene);
      expect(r.v(P.exposure).abs(), lessThanOrEqualTo(0.15));
      expect(r.v(P.shadows), lessThanOrEqualTo(15));
      expect(
        SceneMetrics.medianLuma(r.rendered),
        lessThanOrEqualTo(SceneMetrics.medianLuma(scene.image) + 0.04),
      );
      expect(
        (r.after.single.lStar - r.before.single.lStar).abs(),
        lessThanOrEqualTo(4),
      );
    });

    test('contrast is never lowered on soft light', () async {
      for (final wall in [0.35, 0.8, 0.05]) {
        final r = await enhance(
          paintPeople([const PaintedFace(Skin.brown)], wall: wall),
        );
        expect(r.v(P.contrast), greaterThanOrEqualTo(0), reason: 'wall $wall');
        expect(r.v(P.contrast), lessThanOrEqualTo(_C.contrastMaxPortrait));
      }
    });

    test('a true white (a blown lamp) is never left grey', () async {
      // The shirt is blown as shot: after Auto it is still white.
      final r = await enhance(
        paintPeople([const PaintedFace(Skin.brown)], shirt: 1.4),
      );
      expect(SceneMetrics.percentileLuma(r.rendered, 0.995), greaterThan(0.95));
    });
  });

  group('colour', () {
    test('portrait vibrance is capped and saturation stays tiny', () async {
      for (final skin in Skin.all.values) {
        final r = await enhance(paintPeople([PaintedFace(skin)]));
        expect(r.v(P.vibrance), inInclusiveRange(0, _C.vibranceMaxPortrait));
        expect(r.v(P.saturation), inInclusiveRange(_C.saturationMin, 3));
      }
    });

    test('skin that is already rich gets no colour boost', () async {
      final r = await enhance(
        paintPeople([const PaintedFace(Skin.tan)], light: (1.35, 1.0, 0.7)),
      );
      expect(r.before.single.chroma, greaterThan(_C.skinChromaMaxLight));
      expect(r.v(P.vibrance), lessThanOrEqualTo(0));
      expect(r.v(P.saturation), lessThanOrEqualTo(0));
      expect(r.outcome.intent, contains('Skin is already rich'));
    });

    test('skin chroma does not grow by more than a few C*', () async {
      for (final skin in Skin.all.values) {
        final r = await enhance(paintPeople([PaintedFace(skin)]));
        expect(
          r.after.single.chroma,
          lessThanOrEqualTo(r.before.single.chroma + 6),
        );
      }
    });

    test('without face boxes, skin-coloured frames still get the people '
        'cap', () async {
      final scene = paintPeople([const PaintedFace(Skin.tan, size: 2.6)]);
      final r = await enhance(scene, withFaces: false);
      expect(r.v(P.vibrance), lessThanOrEqualTo(_C.vibranceMaxGroup));
    });
  });
}
