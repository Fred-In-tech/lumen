import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

DetectedFace _face(String id, FaceGroup group, {String? personId}) =>
    DetectedFace(
      id: id,
      box: const FaceBox(0.1, 0.1, 0.2, 0.2),
      group: group,
      personId: personId,
    );

FaceAnalysis _analysis(List<DetectedFace> faces) => FaceAnalysis(
  imageWidth: 100,
  imageHeight: 100,
  modelVersion: 'test',
  faces: faces,
);

void main() {
  group('slider mapping (§3.13)', () {
    test('smoothing is (v/100)^0.8 with a lower threshold above 0.6', () {
      expect(mapSmoothing(0), 0);
      expect(mapSmoothing(100), 1);
      expect(mapSmoothing(50), closeTo(math.pow(0.5, 0.8), 1e-12));
      expect(mapAmpThreshold(0.5), kAmpThreshold);
      expect(mapAmpThreshold(0.7), kAmpThresholdStrong);
    });

    test('texture is bipolar around a gain of exactly 1', () {
      expect(mapTextureGain(0), 1);
      expect(mapTextureGain(-100), closeTo(kTextureGainMin, 1e-12));
      expect(mapTextureGain(100), closeTo(kTextureGainMax, 1e-12));
      expect(mapTextureGain(-50), closeTo(0.7, 1e-12));
    });

    test('even tone and linear sliders', () {
      expect(mapEvenTone(100), closeTo(kEvenToneMax, 1e-12));
      expect(mapLinear(80), closeTo(0.8, 1e-12));
      expect(mapLinear(150), 1);
    });

    test('Auto Retouch (PortraitPresets) produces active uniforms', () {
      final s = PortraitPresets.autoRetouch(PortraitSettings.empty);
      for (final e in PortraitPresets.natural.entries) {
        expect(s.valueFor(e.key, group: FaceGroup.all), e.value);
      }
      expect(s.valueFor(PortraitIds.lidProtect, group: FaceGroup.all), 100);
      final u = RetouchUniforms.fromSettings(
        s,
        _analysis([_face('a', FaceGroup.all)]),
      );
      expect(u.isIdentity, isFalse);
    });
  });

  group('per-face resolution (individual → group → All)', () {
    final analysis = _analysis([
      _face('f', FaceGroup.female),
      _face('m', FaceGroup.male),
      _face('p', FaceGroup.male, personId: 'p1'),
      _face('c', FaceGroup.child),
    ]);
    final settings = PortraitSettings.empty
        .withGroupValue(FaceGroup.all, PortraitIds.skinSoftening, 30)
        .withGroupValue(FaceGroup.female, PortraitIds.skinSoftening, 80)
        .withGroupValue(FaceGroup.male, PortraitIds.skinSoftening, 10)
        .withIndividualValue('p1', PortraitIds.skinSoftening, 60)
        .withGroupValue(FaceGroup.child, PortraitIds.eyeWhites, 40);

    test('each face row resolves its own value', () {
      final u = RetouchUniforms.fromSettings(settings, analysis);
      expect(u.faces, hasLength(4));
      expect(u.faces[0].smooth, closeTo(mapSmoothing(80), 1e-12));
      expect(u.faces[1].smooth, closeTo(mapSmoothing(10), 1e-12));
      expect(u.faces[2].smooth, closeTo(mapSmoothing(60), 1e-12));
      expect(u.faces[3].smooth, closeTo(mapSmoothing(30), 1e-12));
      expect(u.faces[3].whites, closeTo(0.4, 1e-12));
      expect(u.faces[0].whites, 0);
    });

    test('a group drag changes only the packed uniforms of that group', () {
      final before = RetouchUniforms.fromSettings(settings, analysis).pack();
      final after = RetouchUniforms.fromSettings(
        settings.withGroupValue(
          FaceGroup.female,
          PortraitIds.skinSoftening,
          90,
        ),
        analysis,
      ).pack();
      final changed = <int>[
        for (var i = 0; i < before.length; i++)
          if (before[i] != after[i]) i,
      ];
      expect(changed, isNotEmpty);
      expect(
        changed.every(
          (i) =>
              i >= kRetouchHeaderFloats &&
              i < kRetouchHeaderFloats + kFaceRowFloats,
        ),
        isTrue,
        reason: 'only slot 0 (the female face) changes',
      );
    });
  });

  group('identity', () {
    final one = _analysis([_face('a', FaceGroup.all)]);

    test(
      'defaults, explicit defaults and lone lid protection are identity',
      () {
        expect(
          RetouchUniforms.fromSettings(PortraitSettings.empty, one).isIdentity,
          isTrue,
        );
        final s = PortraitSettings.empty
            .withGroupValue(FaceGroup.female, PortraitIds.skinTexture, 0)
            .withGroupValue(FaceGroup.female, PortraitIds.lidProtect, 30);
        expect(RetouchUniforms.fromSettings(s, one).isIdentity, isTrue);
        expect(RetouchUniforms.identity.isIdentity, isTrue);
      },
    );

    test('effect and backdrop sliders break identity; shape does not', () {
      for (final id in [
        PortraitIds.skinSoftening,
        PortraitIds.skinTexture,
        PortraitIds.acne,
        PortraitIds.darkCircles,
        PortraitIds.teethBrightness,
        PortraitIds.redVein,
        PortraitIds.redEye,
      ]) {
        final s = PortraitSettings.empty.withGroupValue(FaceGroup.all, id, 20);
        expect(
          RetouchUniforms.fromSettings(s, one).isIdentity,
          isFalse,
          reason: id,
        );
      }
      final shape = PortraitSettings.empty.withGroupValue(
        FaceGroup.all,
        PortraitIds.faceWidth,
        30,
      );
      expect(RetouchUniforms.fromSettings(shape, one).isIdentity, isTrue);
      for (final (id, v) in [
        (PortraitIds.bgClean, 50.0),
        (PortraitIds.bgUnify, 50.0),
        (PortraitIds.bgUnifyLuminance, -30.0),
        (PortraitIds.strayHairs, 10.0),
      ]) {
        final s = PortraitSettings.empty.withImageValue(id, v);
        final u = RetouchUniforms.fromSettings(s, one);
        expect(u.isIdentity, isFalse, reason: id);
        expect(u.faces.single.isIdentity, isTrue, reason: '$id is image scope');
        expect(needsBackdropMaps(s), isTrue, reason: id);
        expect(needsClothesMaps(s), isFalse, reason: id);
        expect(portraitNeedsRetouch(s), isTrue, reason: id);
      }
      for (final id in [PortraitIds.clothesWrinkles, PortraitIds.clothesLint]) {
        final s = PortraitSettings.empty.withImageValue(id, 40);
        final u = RetouchUniforms.fromSettings(s, one);
        expect(u.isIdentity, isFalse, reason: id);
        expect(u.faces.single.isIdentity, isTrue, reason: '$id is image scope');
        expect(u.backdrop.backdropIdentity, isTrue, reason: id);
        expect(u.backdrop.clothesIdentity, isFalse, reason: id);
        // Only the clothes raster is loaded (lazily, for these values).
        expect(needsClothesMaps(s), isTrue, reason: id);
        expect(needsBackdropMaps(s), isFalse, reason: id);
        expect(portraitNeedsRetouch(s), isTrue, reason: id);
      }
      expect(needsBackdropMaps(PortraitSettings.empty), isFalse);
      expect(needsClothesMaps(PortraitSettings.empty), isFalse);
    });

    test('no faces is identity', () {
      final s = PortraitSettings.empty.withGroupValue(
        FaceGroup.all,
        PortraitIds.skinSoftening,
        50,
      );
      expect(RetouchUniforms.fromSettings(s, _analysis([])).isIdentity, isTrue);
    });
  });

  group('pack() layout', () {
    final analysis = _analysis([
      _face('a', FaceGroup.all),
      _face('b', FaceGroup.male),
    ]);
    final settings = PortraitSettings.empty
        .withGroupValue(FaceGroup.male, PortraitIds.skinSoftening, 100)
        .withGroupValue(FaceGroup.all, PortraitIds.teethDesaturate, 50)
        .withGroupValue(FaceGroup.all, PortraitIds.mole, 25)
        .withGroupValue(FaceGroup.male, PortraitIds.skinShine, 70)
        .withGroupValue(FaceGroup.male, PortraitIds.lips, 30)
        .withGroupValue(FaceGroup.male, PortraitIds.blush, 40)
        .withGroupValue(FaceGroup.male, PortraitIds.wrinkleCrowsFeet, 50)
        .withGroupValue(FaceGroup.male, PortraitIds.wrinkleForehead, 60)
        .withGroupValue(FaceGroup.male, PortraitIds.wrinkleFrown, 70)
        .withGroupValue(FaceGroup.male, PortraitIds.wrinkleSmile, 80)
        .withGroupValue(FaceGroup.male, PortraitIds.wrinkleMarionette, 90)
        .withGroupValue(FaceGroup.male, PortraitIds.redEye, 40)
        .withImageValue(PortraitIds.bgClean, 60)
        .withImageValue(PortraitIds.bgUnify, 25)
        .withImageValue(PortraitIds.bgUnifyLuminance, -50)
        .withImageValue(PortraitIds.strayHairs, 80)
        .withGroupValue(FaceGroup.male, PortraitIds.glare, 45)
        .withImageValue(PortraitIds.clothesWrinkles, 70)
        .withImageValue(PortraitIds.clothesLint, 35);
    final u = RetouchUniforms.fromSettings(settings, analysis);
    final f = u.pack();

    test('has the documented size and header', () {
      expect(f, hasLength(kRetouchUniformFloats));
      expect(kRetouchUniformFloats, 204);
      expect(kFaceRowFloats, 24);
      expect(f[0], 2);
      expect(f[1], 1);
      expect(f[2], closeTo(kSpotRamp, 1e-7));
    });

    test('rows sit at 4 + 24·slot in the documented order', () {
      const b = kRetouchHeaderFloats + kFaceRowFloats;
      final expected = <int, (double, String)>{
        0: (1, 'smooth'),
        1: (1, 'texture gain'),
        3: (0.4, 'red-eye'),
        6: (1, 'lid protect default'),
        7: (0.7, 'shine'),
        11: (0.45, 'glasses glare'),
        13: (0.5, 'teeth desaturate'),
        16: (0.25, 'mole'),
        17: (0.3, 'lips'),
        18: (0.4, 'blush'),
        19: (0.5, 'crow’s feet'),
        20: (0.6, 'forehead'),
        21: (0.7, 'frown'),
        22: (0.8, 'smile'),
        23: (0.9, 'marionette'),
      };
      for (final e in expected.entries) {
        expect(f[b + e.key], closeTo(e.value.$1, 1e-6), reason: e.value.$2);
      }
      expect(f[kRetouchHeaderFloats + 0], 0, reason: 'slot 0 smooth');
      expect(f[kRetouchHeaderFloats + 20], 0, reason: 'slot 0 forehead');
      // The shine fill is derived from Shine (row slot 7), not stored.
      expect(u.row(1).shineFill, closeTo(0.5, 1e-12));
      // uBackdropParams and uClothesParams after the rows.
      expect(f.sublist(196, 200), [
        closeTo(0.6, 1e-6),
        closeTo(0.25, 1e-6),
        closeTo(-0.5 * kBackdropLumMax, 1e-6),
        closeTo(0.8, 1e-6),
      ]);
      expect(f.sublist(200), [closeTo(0.7, 1e-6), closeTo(0.35, 1e-6), 0, 0]);
    });

    test('shine fill starts above 50 % Shine', () {
      expect(mapShineFill(0.5), 0);
      expect(mapShineFill(0.7), closeTo(0.5, 1e-12));
      expect(mapShineFill(0.9), 1);
      expect(mapShineFill(1), 1);
    });

    test('unused slots hold identity rows', () {
      final row = f.sublist(
        kRetouchHeaderFloats + 7 * kFaceRowFloats,
        kRetouchHeaderFloats + 8 * kFaceRowFloats,
      );
      final identity = FaceRetouchParams.identity.toList();
      for (var i = 0; i < kFaceRowFloats; i++) {
        expect(row[i], closeTo(identity[i], 1e-7), reason: 'float $i');
      }
    });

    test('the cache key tracks the values', () {
      expect(u.key, RetouchUniforms.fromSettings(settings, analysis).key);
      final other = RetouchUniforms.fromSettings(
        settings.withGroupValue(FaceGroup.male, PortraitIds.skinSoftening, 99),
        analysis,
      );
      expect(other.key, isNot(u.key));
      expect(u.key, startsWith('retouch:v4:'));
      for (final changed in [
        settings.withGroupValue(FaceGroup.male, PortraitIds.glare, 46),
        settings.withImageValue(PortraitIds.clothesWrinkles, 71),
        settings.withImageValue(PortraitIds.clothesLint, 36),
      ]) {
        expect(
          RetouchUniforms.fromSettings(changed, analysis).key,
          isNot(u.key),
        );
      }
      expect(RetouchUniforms.identity.key, 'retouch:identity');
    });

    test('only the first eight faces get rows', () {
      final many = _analysis([
        for (var i = 0; i < 11; i++) _face('f$i', FaceGroup.all),
      ]);
      expect(
        RetouchUniforms.fromSettings(settings, many).faces,
        hasLength(kMaxRetouchFaces),
      );
    });
  });
}
