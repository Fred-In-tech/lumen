import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('AiStyle', () {
    test('nine styles with unique ids that round-trip', () {
      expect(AiStyle.values.length, 9);
      expect(AiStyle.values.map((s) => s.label), [
        'Natural',
        'Vibrant',
        'Moody',
        'Cinematic',
        'Film',
        'Golden Hour',
        'Clean & Bright',
        'B&W',
        'Portrait Soft',
      ]);
      for (final s in AiStyle.values) {
        expect(AiStyle.fromId(s.id), s);
      }
      expect(AiStyle.fromId('sepia'), isNull);
    });

    test('Natural has no look; every other style has one', () {
      expect(AiStyle.natural.ops(), isEmpty);
      for (final s in AiStyle.values.skip(1)) {
        expect(s.ops(), isNotEmpty, reason: s.id);
      }
    });

    test('target shifts follow the PLAN table', () {
      expect(AiStyle.moody.targets.keyScale, 0.7);
      expect(AiStyle.moody.targets.wbStrength, 0.4);
      expect(AiStyle.cleanBright.targets.keyScale, 1.3);
      expect(AiStyle.cleanBright.targets.blackTargetShift, 0.03);
      expect(AiStyle.goldenHour.targets.wbStrength, 0.2);
      expect(AiStyle.vibrant.targets.chromaShift, 8);
      expect(AiStyle.portraitSoft.targets.vibranceCap, 10);
      expect(AiStyle.portraitSoft.targets.skinProtect, isTrue);
    });

    test('looks applied to defaults are pairwise different', () {
      final looks = [
        for (final s in AiStyle.values)
          applyOps(DevelopSettings.defaults, s.ops()).settings,
      ];
      expect(looks.toSet().length, AiStyle.values.length);
    });

    test('B&W look sets the bw treatment; Portrait Soft softens', () {
      final bw = applyOps(DevelopSettings.defaults, AiStyle.bw.ops()).settings;
      expect(bw.treatment, Treatment.bw);
      final soft = applyOps(
        DevelopSettings.defaults,
        AiStyle.portraitSoft.ops(),
      ).settings;
      expect(soft.value(P.clarity), -14);
      expect(soft.value(P.texture), -15);
    });
  });
}
