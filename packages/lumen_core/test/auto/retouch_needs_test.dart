import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import '../retouch/support/synthetic_portrait.dart';

FaceNeeds _needs(SynthFace face) {
  final p = renderSynthPortrait(320, 320, [face]);
  final maps = computeRetouchMaps(p.image, p.analysis);
  return measureRetouchNeeds(maps, p.image, p.analysis).faces.single;
}

const _clean = SynthFace(
  id: 'f',
  cx: 160,
  cy: 130,
  iod: 90,
  spots: [],
  poreAmp: 0.003,
);

void main() {
  group('measureRetouchNeeds on the synthetic portrait', () {
    final clean = _needs(_clean);
    final acne = _needs(
      const SynthFace(
        id: 'f',
        cx: 160,
        cy: 130,
        iod: 90,
        spots: kAcneSpots,
        poreAmp: 0.003,
      ),
    );
    final rough = _needs(
      const SynthFace(
        id: 'f',
        cx: 160,
        cy: 130,
        iod: 90,
        spots: [],
        poreAmp: 0.03,
      ),
    );

    test('more acne measures a higher blemish need', () {
      expect(clean.blemish, 0);
      expect(acne.blemish, greaterThan(0.5));
    });

    test('pores raise roughness; clean skin stays low', () {
      expect(clean.roughness, lessThan(0.3));
      expect(rough.roughness, greaterThan(0.8));
    });

    test('dull teeth, shine and red veins are seen', () {
      final dull = _needs(
        const SynthFace(id: 'f', cx: 160, cy: 130, iod: 90, teethL: 0.62),
      );
      expect(dull.teethDark, greaterThan(clean.teethDark + 0.5));
      final shine = _needs(
        const SynthFace(id: 'f', cx: 160, cy: 130, iod: 90, clippedShine: true),
      );
      expect(shine.shine, greaterThan(clean.shine + 0.3));
      final veins = _needs(
        const SynthFace(id: 'f', cx: 160, cy: 130, iod: 90, veins: true),
      );
      expect(veins.scleraRed, greaterThan(clean.scleraRed + 0.2));
      for (final z in WrinkleZone.values) {
        expect(clean.wrinkle(z), inInclusiveRange(0, 1), reason: z.name);
      }
    });

    test('clean skin gets light values, problem skin stronger', () {
      final light = PortraitPresets.valuesFor(clean);
      final strong = PortraitPresets.valuesFor(
        FaceNeeds(
          faceId: 'x',
          blemish: acne.blemish,
          roughness: rough.roughness,
        ),
      );
      expect(light[PortraitIds.skinSoftening], lessThan(30));
      expect(light[PortraitIds.acne], lessThan(40));
      expect(
        strong[PortraitIds.skinSoftening],
        greaterThan(light[PortraitIds.skinSoftening]!),
      );
      expect(strong[PortraitIds.acne], greaterThan(light[PortraitIds.acne]!));
    });

    test('a photo without retouchable faces has no needs', () {
      expect(
        measureRetouchNeeds(
          RetouchMaps.empty(),
          RgbaBuffer(8, 8),
          const FaceAnalysis(imageWidth: 8, imageHeight: 8, modelVersion: ''),
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('autoRetouchFor', () {
    const worst = FaceNeeds(
      faceId: 'w',
      blemish: 1,
      roughness: 1,
      unevenness: 1,
      underEye: 1,
      shine: 1,
      wrinkles: {
        WrinkleZone.forehead: 1,
        WrinkleZone.frown: 1,
        WrinkleZone.crowsFeet: 1,
        WrinkleZone.smile: 1,
        WrinkleZone.marionette: 1,
      },
      teethDark: 1,
      teethYellow: 1,
      scleraRed: 1,
    );

    test('caps: even the worst face stays below "plastic"', () {
      final p = PortraitPresets.autoRetouchFor(
        PortraitSettings.empty,
        const RetouchNeeds([worst]),
      );
      double v(String id, [FaceGroup g = FaceGroup.all]) => p.groupValue(g, id);
      expect(v(PortraitIds.skinSoftening), lessThanOrEqualTo(55));
      expect(v(PortraitIds.eyeWhites), lessThanOrEqualTo(40));
      for (final e in PortraitPresets.needRanges.entries) {
        expect(v(e.key), lessThanOrEqualTo(e.value.$2), reason: e.key);
      }
      // Children and seniors keep texture and character.
      expect(v(PortraitIds.skinSoftening, FaceGroup.child), 15);
      expect(v(PortraitIds.eyeBags, FaceGroup.child), 0);
      expect(v(PortraitIds.wrinkleCrowsFeet, FaceGroup.senior), 10);
    });

    test('faces that differ a lot get their own group values', () {
      const cleanMale = FaceNeeds(faceId: 'm', group: FaceGroup.male);
      const roughFemale = FaceNeeds(
        faceId: 'f',
        group: FaceGroup.female,
        roughness: 1,
        blemish: 1,
      );
      final p = PortraitPresets.autoRetouchFor(
        PortraitSettings.empty,
        const RetouchNeeds([cleanMale, roughFemale]),
      );
      expect(
        p.groupValue(FaceGroup.female, PortraitIds.skinSoftening),
        greaterThan(p.groupValue(FaceGroup.male, PortraitIds.skinSoftening)),
      );
      expect(p.groupOverrides(FaceGroup.female, PortraitIds.acne), isTrue);
      // Similar faces share the All values (no overrides).
      final same = PortraitPresets.autoRetouchFor(
        PortraitSettings.empty,
        const RetouchNeeds([
          FaceNeeds(faceId: 'a', group: FaceGroup.male, roughness: 0.4),
          FaceNeeds(faceId: 'b', group: FaceGroup.female, roughness: 0.45),
        ]),
      );
      expect(same.groups[FaceGroup.male], isNull);
      expect(same.groups[FaceGroup.female], isNull);
    });

    test('unknown needs fall back to the static recipe', () {
      final p = PortraitPresets.autoRetouchFor(PortraitSettings.empty, null);
      expect(
        p.groupValue(FaceGroup.all, PortraitIds.skinSoftening),
        PortraitPresets.natural[PortraitIds.skinSoftening],
      );
      expect(p.groupValue(FaceGroup.child, PortraitIds.skinSoftening), 15);
    });

    test('hand-set values, individuals, image values and spots survive', () {
      final current = PortraitSettings.empty
          .withGroupValue(FaceGroup.all, PortraitIds.skinSoftening, 5)
          .withGroupValue(FaceGroup.female, PortraitIds.acne, 12)
          .withIndividualValue('p1', PortraitIds.iris, 77)
          .withImageValue(PortraitIds.bgClean, 40)
          .withSpots(const PortraitSpots(remove: [SpotAnchor(0.5, 0.5, 0.02)]));
      final p = PortraitPresets.autoRetouchFor(
        current,
        const RetouchNeeds([worst]),
        locked: {
          PortraitPresets.lockKey(FaceGroup.all, PortraitIds.skinSoftening),
          PortraitPresets.lockKey(FaceGroup.female, PortraitIds.acne),
        },
      );
      expect(p.groupValue(FaceGroup.all, PortraitIds.skinSoftening), 5);
      expect(p.groupValue(FaceGroup.female, PortraitIds.acne), 12);
      expect(p.individuals['p1']?[PortraitIds.iris], 77);
      expect(p.imageValue(PortraitIds.bgClean), 40);
      expect(p.spots.remove, hasLength(1));
      expect(p.groupValue(FaceGroup.all, PortraitIds.acne), 90);
    });
  });

  group('manualPortraitLocks', () {
    HistoryEntry entry(
      PortraitSettings a,
      PortraitSettings b,
      HistoryKind kind,
    ) => HistoryEntry.diff(
      label: kind.name,
      kind: kind,
      before: DevelopSettings.defaults.copyWith(portrait: a),
      after: DevelopSettings.defaults.copyWith(portrait: b),
    );

    test('slider edits lock; later presets, AI and undo release', () {
      final p0 = PortraitSettings.empty;
      final p1 = p0.withGroupValue(FaceGroup.all, PortraitIds.iris, 60);
      final p2 = PortraitPresets.autoRetouch(p1);
      var h = HistoryStack.empty.push(entry(p0, p1, HistoryKind.slider));
      expect(manualPortraitLocks(h), {'all/${PortraitIds.iris}'});
      h = h.push(entry(p1, p2, HistoryKind.preset));
      expect(manualPortraitLocks(h), isEmpty, reason: 'preset replaced it');
      final undone = HistoryStack(h.entries, 1);
      expect(manualPortraitLocks(undone), {'all/${PortraitIds.iris}'});
      expect(manualPortraitLocks(HistoryStack(h.entries, 0)), isEmpty);
    });
  });

  group('portrait presets', () {
    test('each applies per group and carries no spots or individuals', () {
      expect(kPortraitPresets, hasLength(6));
      for (final p in kPortraitPresets) {
        final portrait = p.portrait!;
        expect(portrait.individuals, isEmpty, reason: p.name);
        expect(portrait.spots.isEmpty, isTrue, reason: p.name);
        final applied = p.apply(DevelopSettings.defaults).portrait;
        expect(applied.hasFaceEdits, isTrue, reason: p.name);
        // Children never get more smoothing than the All group.
        expect(
          applied.groupValue(FaceGroup.child, PortraitIds.skinSoftening),
          lessThanOrEqualTo(
            applied.groupValue(FaceGroup.all, PortraitIds.skinSoftening),
          ),
          reason: p.name,
        );
      }
      final glam = kPortraitPresets.firstWhere((p) => p.name == 'Glam');
      final g = glam.apply(DevelopSettings.defaults).portrait;
      expect(g.groupValue(FaceGroup.female, PortraitIds.lips), 40);
      expect(g.groupValue(FaceGroup.male, PortraitIds.lips), 0);
      expect(g.groupValue(FaceGroup.child, PortraitIds.blush), 0);
    });
  });
}
