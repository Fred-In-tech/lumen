import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('PortraitRegistry', () {
    test('ids unique, defaults in range, every param has a section', () {
      final ids = PortraitRegistry.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final p in PortraitRegistry.all) {
        expect(p.defaultValue, inInclusiveRange(p.min, p.max), reason: p.id);
        expect(p.label, isNotEmpty);
      }
      expect(PortraitRegistry.byId('skin.softening').scope, PortraitScope.face);
      expect(PortraitRegistry.byId('bg.clean').scope, PortraitScope.image);
      expect(PortraitRegistry.byId('eyes.lidProtect').defaultValue, 100);
    });
  });

  group('PortraitSettings resolution: individual → group → all → default', () {
    const female = FaceGroup.female;
    final s = PortraitSettings.empty
        .withGroupValue(FaceGroup.all, PortraitIds.skinSoftening, 30)
        .withGroupValue(female, PortraitIds.skinSoftening, 45)
        .withIndividualValue('p1', PortraitIds.skinSoftening, 10);

    test('falls back through the chain', () {
      expect(s.valueFor(PortraitIds.skinSoftening, group: FaceGroup.male), 30);
      expect(s.valueFor(PortraitIds.skinSoftening, group: female), 45);
      expect(
        s.valueFor(PortraitIds.skinSoftening, group: female, personId: 'p1'),
        10,
      );
      expect(s.valueFor(PortraitIds.teethBrightness, group: female), 0);
      expect(s.valueFor(PortraitIds.lidProtect, group: female), 100);
    });

    test('clamps and drops defaults; json round trip; equality', () {
      final t = s
          .withGroupValue(FaceGroup.all, PortraitIds.skinSoftening, 999)
          .withImageValue(PortraitIds.bgClean, 60);
      expect(
        t.valueFor(PortraitIds.skinSoftening, group: FaceGroup.child),
        100,
      );
      final back = PortraitSettings.fromJson(t.toJson());
      expect(back, t);
      expect(back.imageValue(PortraitIds.bgClean), 60);
      expect(
        PortraitSettings.empty
            .withGroupValue(FaceGroup.all, PortraitIds.skinSoftening, 0)
            .isDefault,
        isTrue,
      );
    });

    test('resetting an individual re-attaches to the group', () {
      final t = s.clearIndividual('p1');
      expect(
        t.valueFor(PortraitIds.skinSoftening, group: female, personId: 'p1'),
        45,
      );
    });

    test('clearing one individual value re-inherits only that param', () {
      final t = s
          .withIndividualValue('p1', PortraitIds.acne, 20)
          .clearIndividualValue('p1', PortraitIds.skinSoftening);
      expect(
        t.valueFor(PortraitIds.skinSoftening, group: female, personId: 'p1'),
        45,
      );
      expect(t.valueFor(PortraitIds.acne, group: female, personId: 'p1'), 20);
      expect(
        t.clearIndividualValue('p1', PortraitIds.acne).hasIndividual('p1'),
        isFalse,
      );
    });

    test('image-scope params cannot be set per face', () {
      expect(
        () => s.withGroupValue(FaceGroup.all, PortraitIds.bgClean, 10),
        throwsArgumentError,
      );
      expect(
        () => s.withImageValue(PortraitIds.skinSoftening, 10),
        throwsArgumentError,
      );
    });
  });

  group('DevelopSettings integration', () {
    test('portrait participates in json, equality, history and presets', () {
      final p = PortraitSettings.empty.withGroupValue(
        FaceGroup.all,
        PortraitIds.acne,
        80,
      );
      final s = DevelopSettings.defaults.copyWith(portrait: p);
      expect(DevelopSettings.fromJson(s.toJson()), s);
      expect(s.isDefault, isFalse);
      final e = HistoryEntry.diff(
        label: 'Acne',
        kind: HistoryKind.slider,
        before: DevelopSettings.defaults,
        after: s,
      );
      expect(e.applyBackward(s), DevelopSettings.defaults);
      expect(e.applyForward(DevelopSettings.defaults), s);
      final preset = Preset.fromSettings(
        id: 'x',
        name: 'Skin',
        settings: s,
        groups: {SettingsGroup.portrait},
      );
      expect(
        preset
            .apply(DevelopSettings.defaults)
            .portrait
            .valueFor(PortraitIds.acne, group: FaceGroup.male),
        80,
      );
      expect(
        pasteSettings(
          source: s,
          target: DevelopSettings.defaults,
          groups: {SettingsGroup.color},
        ).portrait.isDefault,
        isTrue,
      );
      expect(
        pasteSettings(
          source: s,
          target: DevelopSettings.defaults,
          groups: {SettingsGroup.portrait},
        ).portrait,
        p,
      );
    });

    test('preset amount scales portrait values', () {
      final p = PortraitSettings.empty.withGroupValue(
        FaceGroup.all,
        PortraitIds.skinSoftening,
        60,
      );
      final preset = Preset(
        id: 'p',
        name: 'Soft',
        values: const {},
        portrait: p,
      );
      final half = preset.apply(DevelopSettings.defaults, amount: 0.5);
      expect(
        half.portrait.valueFor(PortraitIds.skinSoftening, group: FaceGroup.all),
        30,
      );
    });
  });

  group('FaceAnalysis', () {
    test('json round trip; tag edit; group of face', () {
      const a = FaceAnalysis(
        imageWidth: 1000,
        imageHeight: 800,
        modelVersion: 'test',
        faces: [
          DetectedFace(
            id: 'f1',
            box: FaceBox(0.1, 0.1, 0.3, 0.4),
            landmarks: [0.2, 0.2, 0.25, 0.22],
            confidence: 0.9,
          ),
        ],
      );
      final tagged = a.withTag('f1', FaceGroup.female, personId: 'p1');
      final back = FaceAnalysis.fromJson(tagged.toJson());
      expect(back.faces.single.group, FaceGroup.female);
      expect(back.faces.single.personId, 'p1');
      expect(back.faces.single.landmarkCount, 2);
      expect(back.faces.single.tagSource, TagSource.manual);
    });
  });

  group('PortraitPresets.autoRetouch', () {
    test('sets All values, gentler child/senior overrides, keeps people', () {
      final current = PortraitSettings.empty
          .withIndividualValue('p1', PortraitIds.skinSoftening, 5)
          .withImageValue(PortraitIds.bgClean, 40);
      final r = PortraitPresets.autoRetouch(current);
      expect(r.valueFor(PortraitIds.skinSoftening, group: FaceGroup.male), 40);
      expect(r.valueFor(PortraitIds.skinSoftening, group: FaceGroup.child), 15);
      expect(r.valueFor(PortraitIds.eyeBags, group: FaceGroup.child), 0);
      expect(r.groupOverrides(FaceGroup.child, PortraitIds.eyeBags), isTrue);
      expect(
        r.valueFor(
          PortraitIds.skinSoftening,
          group: FaceGroup.female,
          personId: 'p1',
        ),
        5,
      );
      expect(r.imageValue(PortraitIds.bgClean), 40);
      for (final e in PortraitPresets.natural.entries) {
        final spec = PortraitRegistry.byId(e.key);
        expect(e.value, inInclusiveRange(spec.min, spec.max), reason: e.key);
      }
    });
  });
}
