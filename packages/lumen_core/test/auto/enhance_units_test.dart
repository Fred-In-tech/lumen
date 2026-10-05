// Unit tests of the Auto Enhance building blocks: measurements on linear
// floats (values above 1.0 included), skin sampling, tone-adaptive bands,
// the white-balance vote and the exposure plan.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'enhance_scenes.dart';

typedef _C = EnhanceConstants;

LinearPixels _flat(int w, int h, double r, double g, double b) {
  final d = Float32List(w * h * 3);
  for (var i = 0; i < d.length; i += 3) {
    d[i] = r;
    d[i + 1] = g;
    d[i + 2] = b;
  }
  return LinearPixels(w, h, d);
}

FaceRead _face({
  required double litY,
  required SkinTarget target,
  double weight = 1,
  double area = 0.05,
}) {
  final px = _flat(8, 8, litY * 1.65, litY, litY * 0.66);
  final region = SkinRegion(
    pixels: Int32List.fromList(List.generate(64, (i) => i)),
    areaFraction: area,
    widthFraction: 0.2,
    weight: weight,
  );
  return FaceRead(region, SkinReading.of(px, region), target);
}

EnhanceScene _scene(
  FrameMeasure frame, [
  List<FaceRead> faces = const [],
  ExifSummary? exif,
  SceneInfo? hints,
]) =>
    EnhanceScene.classify(frame: frame, faces: faces, exif: exif, hints: hints);

void main() {
  group('LinearPixels', () {
    test('decodes 8-bit sRGB and checks its length', () {
      final px = LinearPixels.fromRgba(RgbaBuffer.filled(4, 2, 255, 128, 0));
      expect(px.pixelCount, 8);
      expect(px.rgb[0], closeTo(1, 1e-6));
      expect(px.rgb[1], closeTo(0.2158, 1e-3));
      expect(px.rgb[2], 0);
      expect(() => LinearPixels(2, 2, Float32List(5)), throwsArgumentError);
      expect(luminanceOf(1, 1, 1), closeTo(1, 1e-9));
      expect(encodeClamped(4), 1);
    });
  });

  group('FrameMeasure', () {
    test('float pixels above 1.0 are measured as clipped, not rejected', () {
      final d = Float32List(100 * 3);
      for (var i = 0; i < 100; i++) {
        final v = i < 10 ? 3.5 : 0.18;
        d[i * 3] = v;
        d[i * 3 + 1] = v;
        d[i * 3 + 2] = v;
      }
      final m = FrameMeasure.of(LinearPixels(10, 10, d));
      expect(m.clipFraction, closeTo(0.10, 1e-9));
      expect(m.hiClip, closeTo(0.10, 1e-9));
      expect(m.maxP99_9, 1);
      expect(m.p50, closeTo(0.46, 0.01));
      expect(m.medianY, closeTo(0.18, 0.005));
      expect(m.sceneWhiteY, closeTo(0.18, 0.005), reason: 'clipped excluded');
    });

    test('matches the 8-bit measurement on the same picture', () {
      final img = SyntheticScenes.wellExposedChart(longEdge: 128).image;
      final m = FrameMeasure.of(LinearPixels.fromRgba(img));
      expect(m.p50, closeTo(SceneMetrics.medianLuma(img), 0.005));
      expect(m.clipFraction, closeTo(SceneMetrics.clipFraction(img), 1e-9));
      expect(m.sigmaLStar, closeTo(SceneMetrics.sigmaLStar(img), 0.3));
      expect(m.p0_1, lessThanOrEqualTo(m.p0_5));
      expect(m.p5, lessThanOrEqualTo(m.p95));
      expect(m.p99_5, lessThanOrEqualTo(1));
      expect(m.maxP99_5, lessThanOrEqualTo(m.maxP99_9));
      expect(m.hiMean, greaterThan(m.loMean));
      expect(m.lAvg, inInclusiveRange(m.yP1, m.yP99));
      expect(m.medianLStar, inInclusiveRange(30, 70));
    });

    test('black and empty frames do not divide by zero', () {
      final black = FrameMeasure.of(_flat(4, 4, 0, 0, 0));
      expect(black.crushFraction, 1);
      expect(black.loCrush, 1);
      expect(black.sigmaLStar, 0);
      expect(black.sceneWhiteY, 0);
      final empty = FrameMeasure.of(LinearPixels(0, 0, Float32List(0)));
      expect(empty.clipFraction, 0);
    });

    test('ChromaReading: grey is colourless, saturated colour is vivid, '
        'masked skin is left out', () {
      final grey = ChromaReading.of(_flat(4, 4, 0.2, 0.2, 0.2));
      expect(grey.meanChroma, closeTo(0, 0.5));
      expect(grey.vividShare, 0);
      final red = ChromaReading.of(_flat(4, 4, 0.6, 0.05, 0.05));
      expect(red.meanChroma, greaterThan(60));
      expect(red.highChromaShare, 1);
      expect(red.vividShare, 1);
      final masked = ChromaReading.of(
        _flat(4, 4, 0.6, 0.05, 0.05),
        skin: Uint8List(16)..fillRange(0, 16, 1),
      );
      expect(masked.skinShare, 1);
      expect(masked.meanChroma, 0);
    });
  });

  group('SkinRegions / SkinReading', () {
    final scene = paintPeople([const PaintedFace(Skin.tan)]);
    final px = LinearPixels.fromRgba(makeProxy(scene.image, longEdge: 256));

    test('finds the skin of the face oval and nothing else', () {
      final region = SkinRegions.locate(px, scene.faces).single;
      expect(region.weight, 1);
      expect(region.areaFraction, closeTo(0.17 * 0.28, 1e-9));
      final reading = SkinReading.of(px, region);
      // Painted tan reflectance, lit side: Y ≈ 0.29.
      expect(reading.litY, closeTo(0.287, 0.03));
      expect(reading.a, closeTo(1.30, 0.08));
      expect(reading.m, closeTo(-0.04, 0.05));
      expect(reading.hue, inInclusiveRange(_C.skinHueLow, _C.skinHueHigh));
      expect(reading.contrast, inInclusiveRange(2, 20));
      expect(reading.hot, lessThan(0.8));
      expect(reading.chroma, inInclusiveRange(15, 35));
      final mask = SkinRegions.mask(px.pixelCount, [region]);
      expect(mask.where((v) => v == 1).length, region.pixels.length);
    });

    test('skips faces that are too small, off-frame or not skin-coherent', () {
      expect(
        SkinRegions.locate(px, const [FaceBox(0.5, 0.4, 0.01, 0.02)]),
        isEmpty,
      );
      expect(
        SkinRegions.locate(px, const [FaceBox(1.5, 1.5, 0.2, 0.2)]),
        isEmpty,
      );
      expect(SkinRegions.locate(px, const []), isEmpty);
      final black = _flat(64, 64, 0, 0, 0);
      expect(
        SkinRegions.locate(black, const [FaceBox(0.2, 0.2, 0.5, 0.5)]),
        isEmpty,
      );
    });

    test('several faces: largest first, weights sum to 1', () {
      final group = paintPeople(const [
        PaintedFace(Skin.deep, u: 0.25, size: 0.7),
        PaintedFace(Skin.light, u: 0.7),
      ]);
      final gp = LinearPixels.fromRgba(makeProxy(group.image, longEdge: 256));
      final regions = SkinRegions.locate(gp, group.faces);
      expect(regions, hasLength(2));
      expect(regions.first.weight, greaterThan(regions.last.weight));
      expect(regions.fold(0.0, (s, r) => s + r.weight), closeTo(1, 1e-9));
      expect(
        SkinReading.of(gp, regions.first).litY,
        greaterThan(SkinReading.of(gp, regions.last).litY),
      );
    });
  });

  group('SkinTarget', () {
    test('tone index follows skin luminance relative to the scene white', () {
      final dark = SkinTarget.of(litY: 0.085, sceneWhiteY: 0.85);
      final light = SkinTarget.of(litY: 0.43, sceneWhiteY: 0.85);
      expect(dark.toneIndex, closeTo(0, 0.05));
      expect(light.toneIndex, closeTo(1, 0.05));
      expect(dark.centre, closeTo(_C.centreDark, 2));
      expect(light.centre, closeTo(_C.centreLight, 2));
      expect(dark.high, lessThan(light.low));
      expect(dark.chromaMax, lessThan(light.chromaMax));
      expect(dark.confidence, greaterThan(0));
    });

    test('the index does not change with exposure', () {
      final a = SkinTarget.of(litY: 0.2, sceneWhiteY: 0.8);
      final b = SkinTarget.of(litY: 0.05, sceneWhiteY: 0.2);
      expect(a.toneIndex, closeTo(b.toneIndex, 1e-9));
      expect(a.low, closeTo(b.low, 1e-9));
    });

    test('no white reference: the band is the union of every class', () {
      final t = SkinTarget.of(litY: 0.2, sceneWhiteY: 0.21);
      expect(t.confidence, 0);
      expect(t.low, _C.lowDark);
      expect(t.high, _C.highLight);
      expect(t.accepts(40), isTrue);
      expect(t.accepts(72), isTrue);
      expect(SkinTarget.of(litY: 0, sceneWhiteY: 0.5).confidence, 0);
    });

    test('a white at the clip ceiling, or a blown frame, widens the band '
        'downwards only', () {
      final sure = SkinTarget.of(litY: 0.2, sceneWhiteY: 0.6);
      final ceiling = SkinTarget.of(litY: 0.3, sceneWhiteY: 0.95);
      expect(ceiling.confidence, lessThan(sure.confidence));
      final blown = SkinTarget.of(
        litY: 0.2,
        sceneWhiteY: 0.6,
        clipFraction: 0.1,
      );
      expect(blown.toneIndex, lessThan(sure.toneIndex));
      expect(blown.low, lessThan(sure.low));
    });

    test('error is signed and zero inside; a style shift is clamped', () {
      final t = SkinTarget.of(litY: 0.2, sceneWhiteY: 0.6);
      expect(t.error(t.low - 5), 5);
      expect(t.error(t.high + 3), -3);
      expect(t.error(t.centre), 0);
      final shifted = SkinTarget.of(litY: 0.2, sceneWhiteY: 0.6, shift: 40);
      expect(shifted.centre - t.centre, _C.styleSkinShiftMax);
    });
  });

  group('white balance', () {
    test('Cast: neutral is zero; angle grows with the difference', () {
      expect(Cast.ofRgb(1, 1, 1).a, closeTo(0, 1e-9));
      expect(Cast.ofRgb(2, 1, 0.5).a, closeTo(2, 1e-9));
      expect(Cast.ofRgb(1, 2, 1).m, closeTo(1, 1e-9));
      expect(Cast.none.angleTo(Cast.none), closeTo(0, 1e-6));
      expect(
        Cast.none.angleTo(const Cast(0.3, 0)),
        lessThan(Cast.none.angleTo(const Cast(0.9, 0))),
      );
    });

    test('candidates agree on a cast grey-world scene', () {
      final s = SyntheticScenes.daylightCoolCast(longEdge: 128);
      final c = WbCandidates.of(LinearPixels.fromRgba(s.image));
      expect(c.monochrome, isFalse);
      expect(c.statistical.length, greaterThanOrEqualTo(2));
      for (final cast in c.statistical) {
        expect(cast.a, closeTo(-0.64, 0.25));
      }
    });

    test('a frame of one saturated hue disables the grey-world family', () {
      final c = WbCandidates.of(_flat(32, 32, 0.05, 0.45, 0.08));
      expect(c.monochrome, isTrue);
      expect(c.statistical, isEmpty);
      final w = EnhanceWb.solve(candidates: c, faces: const []);
      expect(w.temp, 0);
      expect(w.tint, 0);
      expect(w.verdict, WbVerdict.leftAlone);
    });

    test('too few usable pixels: no candidates, nothing changes', () {
      final c = WbCandidates.of(_flat(2, 2, 0.2, 0.2, 0.2));
      expect(c.statistical, isEmpty);
      expect(c.neutral, isNull);
    });

    test('near-neutral objects pin a neutral scene to "leave alone"', () {
      final c = WbCandidates.of(
        LinearPixels.fromRgba(
          SyntheticScenes.wellExposedChart(longEdge: 128).image,
        ),
      );
      expect(c.neutralQ, greaterThan(0.3));
      final w = EnhanceWb.solve(candidates: c, faces: const []);
      expect(w.temp, 0);
      expect(w.tint, 0);
    });

    test('strength: golden hour < warm interior < warm empty room < cool', () {
      const warm = WbCandidates(
        shadesOfGrey: Cast(0.6, 0),
        greyEdge: Cast(0.6, 0),
        whitePatch: Cast(0.6, 0),
      );
      final ok = SkinTarget.of(litY: 0.2, sceneWhiteY: 0.6);
      final skinInWindow = [_face(litY: 0.2, target: ok)];
      expect(
        skinInWindow.single.skin.a,
        inInclusiveRange(_C.skinALow, _C.skinAHigh),
      );
      final golden = EnhanceWb.solve(
        candidates: warm,
        faces: skinInWindow,
        warmIntent: true,
      );
      final interior = EnhanceWb.solve(candidates: warm, faces: skinInWindow);
      final empty = EnhanceWb.solve(candidates: warm, faces: const []);
      const cool = WbCandidates(
        shadesOfGrey: Cast(-0.6, 0),
        greyEdge: Cast(-0.6, 0),
        whitePatch: Cast(-0.6, 0),
      );
      final cooled = EnhanceWb.solve(candidates: cool, faces: const []);
      expect(golden.temp, lessThan(0));
      expect(golden.temp, greaterThan(interior.temp));
      expect(interior.temp, greaterThan(empty.temp));
      expect(cooled.temp, greaterThan(empty.temp.abs()));
      expect(golden.verdict, WbVerdict.keptWarmth);
      expect(cooled.verdict, WbVerdict.corrected);
      final styled = EnhanceWb.solve(
        candidates: cool,
        faces: const [],
        styleStrength: 0.2,
      );
      expect(styled.temp, lessThan(cooled.temp));
    });

    test('disagreeing candidates lower the confidence and the correction', () {
      const split = WbCandidates(
        shadesOfGrey: Cast(0.9, 0),
        greyEdge: Cast(-0.2, 0),
      );
      const agreed = WbCandidates(
        shadesOfGrey: Cast(0.35, 0),
        greyEdge: Cast(0.35, 0),
      );
      final a = EnhanceWb.solve(candidates: split, faces: const []);
      final b = EnhanceWb.solve(candidates: agreed, faces: const []);
      expect(a.confidence, lessThan(b.confidence));
      expect(a.temp.abs(), lessThan(b.temp.abs()));
    });

    test('small corrections on good skin are dropped (do nothing)', () {
      const slight = WbCandidates(
        shadesOfGrey: Cast(0.2, 0.02),
        greyEdge: Cast(0.2, 0.02),
      );
      final ok = SkinTarget.of(litY: 0.2, sceneWhiteY: 0.6);
      final w = EnhanceWb.solve(
        candidates: slight,
        faces: [_face(litY: 0.2, target: ok)],
      );
      expect(w.temp, 0);
      expect(w.tint, 0);
      expect(w.verdict, WbVerdict.skinLooksRight);
    });

    test('an already edited file: no white balance unless skin is off', () {
      const warm = WbCandidates(
        shadesOfGrey: Cast(0.6, 0),
        greyEdge: Cast(0.6, 0),
      );
      final w = EnhanceWb.solve(
        candidates: warm,
        faces: const [],
        alreadyEdited: true,
      );
      expect(w.temp, 0);
    });
  });

  group('exposure plan', () {
    final normal = FrameMeasure.of(
      LinearPixels.fromRgba(
        SyntheticScenes.wellExposedChart(longEdge: 128).image,
      ),
    );

    test('faces inside their band: nothing is asked for', () {
      final t = SkinTarget.of(litY: 0.25, sceneWhiteY: 0.75);
      final faces = [_face(litY: 0.25, target: t)];
      final plan = EnhanceExposure.plan(
        frame: normal,
        faces: faces,
        scene: _scene(normal, faces),
      );
      expect(plan.facesInBand, isTrue);
      expect(plan.faceEv, 0);
      expect(plan.ev.abs(), lessThanOrEqualTo(_C.inBandEvMax));
      expect(plan.underStops, 0);
    });

    test('a face below its band is lifted to just inside it, not to the '
        'centre', () {
      final t = SkinTarget.of(litY: 0.25, sceneWhiteY: 0.75);
      final faces = [_face(litY: 0.25 / 4, target: t)];
      final plan = EnhanceExposure.plan(
        frame: normal,
        faces: faces,
        scene: _scene(normal, faces),
      );
      expect(plan.faceDriven, isTrue);
      final landed = faces.single.lStarAt(plan.faceEv);
      expect(landed, greaterThanOrEqualTo(t.low));
      expect(landed, lessThan(t.centre));
    });

    test('group rule: the lightest face caps the lift; the rest goes to '
        'shadows', () {
      final light = SkinTarget.of(litY: 0.40, sceneWhiteY: 0.85);
      final dark = SkinTarget.of(litY: 0.09, sceneWhiteY: 0.85);
      final faces = [
        _face(litY: 0.40, target: light, weight: 0.5),
        _face(litY: 0.02, target: dark, weight: 0.5),
      ];
      final plan = EnhanceExposure.plan(
        frame: normal,
        faces: faces,
        scene: _scene(normal, faces),
      );
      expect(
        faces.first.lStarAt(plan.ev),
        lessThanOrEqualTo(light.high + 0.01),
      );
      expect(plan.underStops, greaterThan(0));
    });

    test('faces of unknown tone are never brightened past the dark band', () {
      final unknown = SkinTarget.of(litY: 0.1, sceneWhiteY: 0.1);
      final faces = [_face(litY: 0.1, target: unknown)];
      final dark = FrameMeasure.of(_flat(16, 16, 0.01, 0.01, 0.01));
      final plan = EnhanceExposure.plan(
        frame: dark,
        faces: faces,
        scene: _scene(dark, faces),
      );
      expect(plan.globalEv, greaterThan(2));
      expect(plan.ev, lessThanOrEqualTo(_C.unknownToneEvMax));
      expect(
        faces.single.lStarAt(plan.ev),
        lessThanOrEqualTo(_C.highDark + 0.5),
      );
    });

    test('no faces: the damped histogram opinion, inside the limits', () {
      final dark = FrameMeasure.of(
        LinearPixels.fromRgba(
          SyntheticScenes.darkInterior(longEdge: 128).image,
        ),
      );
      final plan = EnhanceExposure.plan(
        frame: dark,
        faces: const [],
        scene: _scene(dark),
      );
      expect(plan.faceWeight, 0);
      expect(plan.ev, _C.evMaxOther);
      expect(plan.globalEv, greaterThan(plan.ev));
      final keyed = EnhanceExposure.plan(
        frame: dark,
        faces: const [],
        scene: _scene(dark),
        keyScale: 0.7,
      );
      expect(keyed.globalEv, lessThan(plan.globalEv));
    });

    test('sceneKey: flat frames get the base key; ranges are clamped', () {
      final flat = FrameMeasure.of(_flat(16, 16, 0.1, 0.1, 0.1));
      expect(EnhanceExposure.sceneKey(flat), closeTo(_C.keyBase, 1e-9));
      final bright = FrameMeasure.of(
        LinearPixels.fromRgba(
          SyntheticScenes.overexposedBeach(longEdge: 128).image,
        ),
      );
      expect(EnhanceExposure.sceneKey(bright), greaterThan(_C.keyBase));
      expect(EnhanceExposure.sceneKey(bright), lessThanOrEqualTo(_C.keyMax));
    });

    test('guardClipping holds back a push that would blow the frame', () {
      final px = _flat(10, 10, 0.5, 0.5, 0.5);
      expect(EnhanceExposure.guardClipping(px, -1, 0.005), -1);
      expect(EnhanceExposure.guardClipping(px, 0.5, 0.005), 0.5);
      final held = EnhanceExposure.guardClipping(px, 2, 0.005);
      expect(held, lessThanOrEqualTo(1));
      expect(0.5 * math.pow(2, held), lessThanOrEqualTo(1));
    });
  });

  group('scene flags', () {
    test('high key needs real whites; haze is not high key', () {
      final hazy = FrameMeasure.of(
        LinearPixels.fromRgba(
          SyntheticScenes.hazyLandscape(longEdge: 128).image,
        ),
      );
      expect(_scene(hazy).highKey, isFalse);
      final airy = paintPeople(
        [const PaintedFace(Skin.light)],
        wall: 0.8,
        shirt: 0.92,
        hair: 0.25,
      );
      final m = FrameMeasure.of(LinearPixels.fromRgba(airy.image));
      expect(_scene(m).highKey, isTrue);
      expect(
        _scene(
          hazy,
          const [],
          null,
          const SceneInfo(keyIntent: 'high_key'),
        ).highKey,
        isTrue,
      );
    });

    test('low key: dark median with bright accents, or a hint', () {
      final d = Float32List(100 * 3);
      for (var i = 0; i < 100; i++) {
        d.fillRange(i * 3, i * 3 + 3, i < 12 ? 0.6 : 0.01);
      }
      final m = FrameMeasure.of(LinearPixels(10, 10, d));
      expect(_scene(m).lowKey, isTrue);
      final dark = FrameMeasure.of(_flat(8, 8, 0.01, 0.01, 0.01));
      expect(_scene(dark).lowKey, isFalse);
      expect(
        _scene(
          dark,
          const [],
          null,
          const SceneInfo(keyIntent: 'low_key'),
        ).lowKey,
        isTrue,
      );
    });

    test('portrait, group and backlit from the faces', () {
      final m = FrameMeasure.of(_flat(8, 8, 0.5, 0.5, 0.5));
      final t = SkinTarget.of(litY: 0.2, sceneWhiteY: 0.6);
      final one = [_face(litY: 0.05, target: t)];
      final s = _scene(m, one);
      expect(s.kind, SceneKind.portrait);
      expect(s.backlit, isTrue);
      expect(s.hasFaces, isTrue);
      expect(s.isPeople, isTrue);
      final three = [
        for (var i = 0; i < 3; i++)
          _face(litY: 0.3, target: t, weight: 1 / 3, area: 0.01),
      ];
      expect(_scene(m, three).kind, SceneKind.group);
      final tiny = [_face(litY: 0.3, target: t, area: 0.001)];
      expect(_scene(m, tiny).smallFaces, isTrue);
      expect(_scene(m).kind, SceneKind.other);
    });

    test('warm light intent: EXIF time windows and scene hints', () {
      ExifSummary at(int h, int m) =>
          ExifSummary(capturedAt: DateTime(2026, 6, 1, h, m));
      expect(EnhanceScene.warmLightIntended(at(18, 42), null), isTrue);
      expect(EnhanceScene.warmLightIntended(at(6, 10), null), isTrue);
      expect(EnhanceScene.warmLightIntended(at(13, 0), null), isFalse);
      expect(EnhanceScene.warmLightIntended(null, null), isFalse);
      expect(
        EnhanceScene.warmLightIntended(
          null,
          const SceneInfo(timeOfDay: 'indoor_tungsten'),
        ),
        isTrue,
      );
    });

    test('already edited: editor software tags, not camera firmware', () {
      bool edited(String? s) =>
          EnhanceScene.editedBefore(ExifSummary(software: s));
      expect(edited('Adobe Photoshop Lightroom Classic 13.2'), isTrue);
      expect(edited('Capture One 23 Macintosh'), isTrue);
      expect(edited('Firmware Version 1.8.1'), isFalse);
      expect(edited(null), isFalse);
      expect(EnhanceScene.editedBefore(null), isFalse);
    });
  });

  group('tone stages', () {
    final chart = FrameMeasure.of(
      LinearPixels.fromRgba(
        SyntheticScenes.wellExposedChart(longEdge: 128).image,
      ),
    );
    final plain = _scene(chart);

    test(
      'highlights: hot skin and bright fabric each pull, within the cap',
      () {
        final (none, _) = EnhanceTone.highlights(
          chart,
          skinHot: 0,
          sourceClip: chart.hiClip,
          scene: plain,
        );
        final (skin, why) = EnhanceTone.highlights(
          chart,
          skinHot: 0.99,
          sourceClip: chart.hiClip,
          scene: plain,
        );
        expect(skin, lessThan(none));
        expect(why, HighlightNeed.skin);
        expect(skin, greaterThanOrEqualTo(-_C.highlightsCap));
        final blown = FrameMeasure.of(_flat(8, 8, 2, 2, 2));
        final (hard, cause) = EnhanceTone.highlights(
          blown,
          skinHot: 0,
          sourceClip: 0,
          scene: plain,
        );
        expect(hard, -_C.highlightsCap);
        expect(cause, HighlightNeed.general);
      },
    );

    test('shadows: crushed frames are opened, less at high ISO and in low '
        'key', () {
      final dark = FrameMeasure.of(_flat(8, 8, 0.0005, 0.0005, 0.0005));
      final open = EnhanceTone.shadows(dark, underStops: 0, scene: plain);
      expect(open, _C.shadowsCap);
      final noisy = EnhanceTone.shadows(
        dark,
        underStops: 0,
        scene: plain,
        iso: 12800,
      );
      expect(noisy, lessThan(open));
      expect(EnhanceTone.shadows(chart, underStops: 0, scene: plain), 0);
      expect(
        EnhanceTone.shadows(chart, underStops: 0.5, scene: plain),
        closeTo(30, 1e-9),
      );
    });

    test('whites: no stretch into hot skin, none after a strong highlight '
        'pull, source whites keep their white', () {
      final dull = FrameMeasure.of(_flat(8, 8, 0.75, 0.75, 0.75));
      double w({double hl = 0, double hot = 0, bool white = false}) =>
          EnhanceTone.whites(
            dull,
            highlights: hl,
            skinHot: hot,
            extraClip: 0,
            sourceHasWhite: white,
            kind: SceneKind.other,
          );
      expect(w(), inInclusiveRange(20, _C.whitesMax));
      expect(w(hl: -45), 0);
      expect(w(hl: -20), w());
      expect(w(hot: 0.93), lessThan(6));
      expect(w(hot: 0.99), 0);
      final bright = FrameMeasure.of(_flat(8, 8, 0.86, 0.86, 0.86));
      expect(
        EnhanceTone.whites(
          bright,
          highlights: 0,
          skinHot: 0,
          extraClip: 0,
          sourceHasWhite: false,
          kind: SceneKind.other,
        ),
        0,
        reason: 'already has a white',
      );
      final blown = FrameMeasure.of(_flat(8, 8, 2, 2, 2));
      double pulled(double extra) => EnhanceTone.whites(
        blown,
        highlights: 0,
        skinHot: 0,
        extraClip: extra,
        sourceHasWhite: true,
        kind: SceneKind.other,
      );
      expect(pulled(0), 0, reason: 'blown as shot stays white');
      expect(pulled(0.05), lessThan(0));
    });

    test('blacks: a lifted black point is set, crushed shadows are lifted, '
        'airy scenes keep a soft black', () {
      final lifted = FrameMeasure.of(_flat(8, 8, 0.01, 0.01, 0.01));
      expect(EnhanceTone.blacks(lifted, scene: plain), lessThan(-10));
      final crushed = FrameMeasure.of(_flat(8, 8, 0.0002, 0.0002, 0.0002));
      expect(EnhanceTone.blacks(crushed, scene: plain), _C.blacksMax);
      expect(
        EnhanceTone.blacks(lifted, scene: plain, targetShift: 0.03),
        greaterThan(EnhanceTone.blacks(lifted, scene: plain)),
      );
    });

    test('contrast: positive when flat, never negative unless harsh', () {
      final flat = FrameMeasure.of(_flat(8, 8, 0.2, 0.2, 0.2));
      expect(
        EnhanceTone.contrast(flat, scene: plain, harsh: false),
        _C.contrastMax,
      );
      final d = Float32List(100 * 3);
      for (var i = 0; i < 100; i++) {
        d.fillRange(i * 3, i * 3 + 3, i.isEven ? 0.9 : 0.004);
      }
      final wide = FrameMeasure.of(LinearPixels(10, 10, d));
      expect(EnhanceTone.contrast(wide, scene: plain, harsh: false), 0);
      expect(
        EnhanceTone.contrast(wide, scene: plain, harsh: true),
        _C.contrastMin,
      );
      expect(EnhanceTone.dynamicRange(wide), greaterThan(7));
      expect(EnhanceTone.harshFrame(chart, plain), isFalse);
    });

    test('colour: muted frames get vibrance up to the scene cap; vivid '
        'ones are left; style caps apply', () {
      final grey = ChromaReading.of(_flat(8, 8, 0.2, 0.21, 0.19));
      final (vib, sat) = EnhanceTone.colour(
        grey,
        scene: plain,
        skinSaturated: false,
      );
      expect(vib, _C.vibranceMax);
      expect(sat, greaterThan(0));
      final (capped, noSat) = EnhanceTone.colour(
        grey,
        scene: plain,
        skinSaturated: false,
        vibranceCap: 10,
        skinProtect: true,
      );
      expect(capped, 10);
      expect(noSat, 0);
      final (held, _) = EnhanceTone.colour(
        grey,
        scene: plain,
        skinSaturated: true,
      );
      expect(held, 0);
      final loud = ChromaReading.of(_flat(8, 8, 0.6, 0.05, 0.05));
      final (down, _) = EnhanceTone.colour(
        loud,
        scene: plain,
        skinSaturated: false,
      );
      expect(down, lessThan(0));
      expect(down, greaterThanOrEqualTo(_C.vibranceMin));
    });
  });
}
