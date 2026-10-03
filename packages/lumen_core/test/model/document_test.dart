import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('EditDocument', () {
    test('new document defaults', () {
      final d = EditDocument.create('abc', now: DateTime.utc(2026, 10, 3));
      expect(d.schemaVersion, EditDocument.currentSchemaVersion);
      expect(d.engineVersion, 'lumen-1');
      expect(d.settings.isDefault, isTrue);
      expect(d.history.entries, isEmpty);
      expect(d.ai, isNull);
    });

    test('json round trip including ai record and snapshots', () {
      final s = DevelopSettings.defaults.withValue(P.exposure, 0.62);
      final d = EditDocument.create('abc', now: DateTime.utc(2026, 10, 3))
          .copyWith(
            settings: s,
            history: HistoryStack.empty.push(
              HistoryEntry.diff(
                label: 'AI Auto',
                kind: HistoryKind.ai,
                before: DevelopSettings.defaults,
                after: s,
              ),
            ),
            ai: const AiRecord(
              engine: 'local',
              style: 'natural',
              intent: 'Brighter, balanced',
              preAi: DevelopSettings.defaults,
              changes: [
                AiChange(
                  param: P.exposure,
                  from: 0,
                  to: 0.62,
                  reason: 'Underexposed',
                ),
              ],
            ),
            snapshots: [
              Snapshot(name: 'v1', settings: s, at: DateTime.utc(2026, 10, 3)),
            ],
          );
      final back = EditDocument.fromJson(d.toJson());
      expect(back.settings, s);
      expect(back.ai!.changes.single.reason, 'Underexposed');
      expect(back.ai!.preAi.isDefault, isTrue);
      expect(back.snapshots.single.name, 'v1');
      expect(back.history.entries.single.kind, HistoryKind.ai);
    });

    test('future schema versions open read only; v0 migrates', () {
      final future = EditDocument.fromJson({
        'schema': 'lumen.edit',
        'schemaVersion': 99,
        'assetId': 'x',
      });
      expect(future.readOnly, isTrue);
      final v0 = EditDocument.fromJson({
        'schemaVersion': 0,
        'assetId': 'x',
        'settings': {'exposure': 0.5},
      });
      expect(v0.readOnly, isFalse);
      expect(v0.settings.value(P.exposure), 0.5);
      expect(v0.schemaVersion, 1);
    });

    test('garbage input yields an empty document rather than throwing', () {
      final d = EditDocument.fromJson({
        'assetId': 'x',
        'settings': 'nope',
        'history': 3,
      });
      expect(d.settings.isDefault, isTrue);
    });
  });

  group('CatalogEntry', () {
    test('json round trip, no GPS fields', () {
      final e = CatalogEntry(
        assetId: '9f2c',
        fileName: 'IMG_1.HEIC',
        originalPath: 'originals/9f2c.heic',
        format: 'heic',
        width: 4032,
        height: 3024,
        bytes: 1000,
        importedAt: DateTime.utc(2026, 10, 3),
        exif: const ExifSummary(camera: 'iPhone', iso: 80),
      );
      final back = CatalogEntry.fromJson(e.toJson());
      expect(back.assetId, '9f2c');
      expect(back.exif.camera, 'iPhone');
      expect(back.hasEdits, isFalse);
      expect(e.toJson().toString().toLowerCase(), isNot(contains('gps')));
      final edited = back.copyWith(
        hasEdits: true,
        aiEngine: 'vision',
        aiStyle: 'moody',
        thumbVersion: 2,
      );
      expect(CatalogEntry.fromJson(edited.toJson()).aiStyle, 'moody');
    });
  });

  group('Presets', () {
    test('sparse merge at full amount', () {
      final p = Preset(
        id: 'p',
        name: 'Warm',
        values: const {P.temp: 12, P.contrast: 0},
      );
      final base = DevelopSettings.defaults.withValues({
        P.contrast: 30,
        P.shadows: 20,
      });
      final out = p.apply(base);
      expect(out.value(P.temp), 12);
      expect(out.value(P.contrast), 0, reason: 'explicit 0 resets');
      expect(out.value(P.shadows), 20, reason: 'omitted keys untouched');
    });

    test('amount interpolates', () {
      final p = Preset(id: 'p', name: 'Warm', values: const {P.temp: 20});
      final base = DevelopSettings.defaults.withValue(P.temp, 10);
      expect(p.apply(base, amount: 0).value(P.temp), 10);
      expect(p.apply(base, amount: 0.5).value(P.temp), 15);
      expect(p.apply(base, amount: 1).value(P.temp), 20);
    });

    test('geometry is never applied; treatment and curves are', () {
      final p = Preset(
        id: 'p',
        name: 'BW',
        values: const {},
        treatment: Treatment.bw,
        curves: CurveSet.identity.withChannel(
          CurveChannel.master,
          const ToneCurve([CurvePoint(0, 20), CurvePoint(255, 245)]),
        ),
      );
      final base = DevelopSettings.defaults.copyWith(
        geometry: Geometry.none.copyWith(angle: 4),
      );
      final out = p.apply(base);
      expect(out.treatment, Treatment.bw);
      expect(out.geometry.angle, 4);
      expect(out.curves.master.points.first.y, 20);
    });

    test('from settings captures only selected groups; json round trip', () {
      final s = DevelopSettings.defaults.withValues({
        P.exposure: 1,
        P.temp: 10,
        P.vignetteAmount: -20,
      });
      final p = Preset.fromSettings(
        id: 'u1',
        name: 'Mine',
        settings: s,
        groups: {SettingsGroup.color, SettingsGroup.effects},
      );
      expect(p.values.containsKey(P.exposure), isFalse);
      expect(p.values[P.temp], 10);
      final back = Preset.fromJson(p.toJson());
      expect(back.name, 'Mine');
      expect(back.values, p.values);
    });

    test('12 built-ins use only valid ids and differ from defaults', () {
      expect(kBuiltinPresets.length, 12);
      expect(kBuiltinPresets.map((p) => p.id).toSet().length, 12);
      for (final p in kBuiltinPresets) {
        for (final id in p.values.keys) {
          expect(ParamRegistry.contains(id), isTrue, reason: '${p.name}: $id');
        }
        expect(
          p.apply(DevelopSettings.defaults).isDefault,
          isFalse,
          reason: p.name,
        );
        expect(p.builtIn, isTrue);
      }
    });
  });

  group('SettingsGroup copy/paste', () {
    test('every param belongs to exactly one group', () {
      for (final spec in ParamRegistry.all) {
        expect(
          SettingsGroup.values.where((g) => g.contains(spec.id)).length,
          1,
          reason: spec.id,
        );
      }
    });

    test('paste only selected groups', () {
      final src = DevelopSettings.defaults
          .withValues({P.exposure: 1, P.temp: 10, 'hsl.blue.sat': 20})
          .copyWith(
            treatment: Treatment.bw,
            geometry: Geometry.none.copyWith(angle: 3),
          );
      final dst = DevelopSettings.defaults.withValues({P.exposure: -1});
      final out = pasteSettings(
        source: src,
        target: dst,
        groups: {SettingsGroup.color, SettingsGroup.hsl},
      );
      expect(out.value(P.exposure), -1);
      expect(out.value(P.temp), 10);
      expect(out.value('hsl.blue.sat'), 20);
      expect(out.treatment, Treatment.color);
      expect(out.geometry.angle, 0);
      final all = pasteSettings(
        source: src,
        target: dst,
        groups: SettingsGroup.defaultCopy,
      );
      expect(all.value(P.exposure), 1);
      expect(all.treatment, Treatment.bw);
      expect(all.geometry.angle, 0, reason: 'geometry excluded by default');
    });
  });
}
