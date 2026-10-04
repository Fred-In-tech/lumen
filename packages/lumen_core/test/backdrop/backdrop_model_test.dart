import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

const _green = BackdropChange(
  mode: BackdropMode.gradient,
  color: 0xFF20A040,
  color2: 0xFF102030,
  angle: 30,
  blur: 70,
  fit: BackdropFit.fit,
  edgeShift: -20,
  feather: 60,
  spill: 80,
  match: 40,
);

void main() {
  group('BackdropChange', () {
    test('defaults are off and round-trip', () {
      expect(BackdropChange.none.isNone, isTrue);
      expect(
        BackdropChange.fromJson(BackdropChange.none.toJson()),
        BackdropChange.none,
      );
      expect(BackdropChange.fromJson(_green.toJson()), _green);
      expect(_green.isNone, isFalse);
    });

    test(
      'parsing is lenient: clamps, unknown enums fall back, junk is none',
      () {
        final b = BackdropChange.fromJson({
          'mode': 'image',
          'imageRef': 'retouch/bg-1.png',
          'blur': 900,
          'edgeShift': -300,
          'feather': 'x',
          'spill': -5,
          'fit': 'tile',
          'color': 'red',
        });
        expect(b.mode, BackdropMode.image);
        expect(b.imageRef, 'retouch/bg-1.png');
        expect(b.blur, 100);
        expect(b.edgeShift, -100);
        expect(b.feather, BackdropChange.none.feather);
        expect(b.spill, 0);
        expect(b.fit, BackdropFit.fill);
        expect(b.color, BackdropChange.none.color);
        expect(BackdropChange.fromJson('junk'), BackdropChange.none);
        expect(
          BackdropChange.fromJson({'mode': 'hologram'}).mode,
          BackdropMode.none,
        );
      },
    );

    test('an image backdrop without a ref is off', () {
      expect(const BackdropChange(mode: BackdropMode.image).isNone, isTrue);
    });
  });

  group('DevelopSettings.backdrop', () {
    final s = DevelopSettings.defaults.copyWith(backdrop: _green);

    test('serializes only when set and round-trips', () {
      expect(
        DevelopSettings.defaults.toJson().containsKey('backdrop'),
        isFalse,
      );
      final back = DevelopSettings.fromJson(s.toJson());
      expect(back.backdrop, _green);
      expect(back, s);
      expect(s.isDefault, isFalse);
    });

    test('history records one backdrop op', () {
      final e = HistoryEntry.diff(
        label: 'Background',
        kind: HistoryKind.backdrop,
        before: DevelopSettings.defaults,
        after: s,
      );
      expect(e.ops.single.path, 'backdrop');
      expect(e.applyForward(DevelopSettings.defaults), s);
      expect(e.applyBackward(s), DevelopSettings.defaults);
      expect(
        HistoryEntry.fromJson(e.toJson())
            .applyForward(DevelopSettings.defaults)
            .backdrop,
        _green,
      );
    });

    test('paste group "Background swap", not in the default copy', () {
      expect(SettingsGroup.backdrop.label, 'Background swap');
      expect(
        SettingsGroup.defaultCopy,
        isNot(contains(SettingsGroup.backdrop)),
      );
      expect(
        pasteSettings(
          source: s,
          target: DevelopSettings.defaults,
          groups: SettingsGroup.defaultCopy,
        ).backdrop,
        BackdropChange.none,
      );
      expect(
        pasteSettings(
          source: s,
          target: DevelopSettings.defaults,
          groups: {SettingsGroup.backdrop},
        ).backdrop,
        _green,
      );
    });

    test('never part of presets, even with every group selected', () {
      final p = Preset.fromSettings(
        id: 'p',
        name: 'P',
        settings: s,
        groups: SettingsGroup.values.toSet(),
      );
      expect(p.toJson().toString(), isNot(contains('backdrop')));
      const kept = BackdropChange(mode: BackdropMode.blur, blur: 30);
      final target = DevelopSettings.defaults.copyWith(backdrop: kept);
      expect(p.apply(target).backdrop, kept);
    });
  });
}
