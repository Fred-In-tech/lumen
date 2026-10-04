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

    test('Auto Retouch starts eyes at 80/80 with full lid protection', () {
      final s = autoRetouchSettings();
      final v = s.valueFor(PortraitIds.eyeWhites, group: FaceGroup.all);
      expect(v, 80);
      expect(s.valueFor(PortraitIds.iris, group: FaceGroup.male), 80);
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

    test('any effect slider breaks identity; shape and backdrop do not', () {
      for (final id in [
        PortraitIds.skinSoftening,
        PortraitIds.skinTexture,
        PortraitIds.acne,
        PortraitIds.darkCircles,
        PortraitIds.teethBrightness,
        PortraitIds.redVein,
      ]) {
        final s = PortraitSettings.empty.withGroupValue(FaceGroup.all, id, 20);
        expect(
          RetouchUniforms.fromSettings(s, one).isIdentity,
          isFalse,
          reason: id,
        );
      }
      final shape = PortraitSettings.empty
          .withGroupValue(FaceGroup.all, PortraitIds.faceWidth, 30)
          .withImageValue(PortraitIds.bgClean, 50);
      expect(RetouchUniforms.fromSettings(shape, one).isIdentity, isTrue);
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
        .withGroupValue(FaceGroup.all, PortraitIds.mole, 25);
    final u = RetouchUniforms.fromSettings(settings, analysis);
    final f = u.pack();

    test('has the documented size and header', () {
      expect(f, hasLength(kRetouchUniformFloats));
      expect(kRetouchUniformFloats, 164);
      expect(f[0], 2);
      expect(f[1], 1);
      expect(f[2], closeTo(kSpotRamp, 1e-7));
    });

    test('rows sit at 4 + 20·slot in the documented order', () {
      const b = kRetouchHeaderFloats + kFaceRowFloats;
      expect(f[b + 0], 1, reason: 'slot 1 smooth');
      expect(f[b + 1], 1, reason: 'texture gain');
      expect(f[b + 3], closeTo(kAmpThresholdStrong, 1e-7));
      expect(f[b + 6], 1, reason: 'lid protect default');
      expect(f[b + 13], closeTo(0.5, 1e-7), reason: 'teeth desaturate');
      expect(f[b + 16], closeTo(0.25, 1e-7), reason: 'mole');
      expect(f[kRetouchHeaderFloats + 0], 0, reason: 'slot 0 smooth');
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
