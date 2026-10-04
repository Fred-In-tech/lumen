import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

const _push = LiquifyStroke(
  tool: LiquifyTool.push,
  points: [(0.4, 0.5), (0.45, 0.5), (0.5, 0.52)],
  radius: 0.05,
  strength: 0.8,
);

void main() {
  group('LiquifyStroke', () {
    test('JSON round-trip for every tool', () {
      for (final tool in LiquifyTool.values) {
        final s = LiquifyStroke(
          tool: tool,
          points: const [(0.1, 0.2), (0.3, 0.4)],
          radius: 0.07,
          strength: 0.5,
        );
        expect(LiquifyStroke.fromJson(s.toJson()), s);
      }
    });

    test('parsing clamps and drops bad points; unknown tools are skipped', () {
      final s = LiquifyStroke.fromJson({
        'tool': 'bloat',
        'points': [
          [0.5, 0.5],
          ['x', 1],
          [2, -1],
        ],
        'radius': 9,
        'strength': -3,
      });
      expect(s!.points, [(0.5, 0.5), (1.0, 0.0)]);
      expect(s.radius, 0.5);
      expect(s.strength, 0);
      expect(
        LiquifyStroke.fromJson({'tool': 'swirl', 'points': <Object?>[]}),
        isNull,
      );
      expect(
        parseLiquify([
          {'tool': 'swirl'},
          _push.toJson(),
        ]),
        [_push],
      );
    });
  });

  group('DevelopSettings.liquify', () {
    final s = DevelopSettings.defaults.copyWith(liquify: [_push]);

    test('serializes only when present and round-trips', () {
      expect(DevelopSettings.defaults.toJson().containsKey('liquify'), isFalse);
      final back = DevelopSettings.fromJson(s.toJson());
      expect(back.liquify, [_push]);
      expect(back, s);
      expect(s.isDefault, isFalse);
    });

    test('history records one liquify op and undoes it', () {
      final e = HistoryEntry.diff(
        label: 'Liquify',
        kind: HistoryKind.liquify,
        before: DevelopSettings.defaults,
        after: s,
      );
      expect(e.ops.single.path, 'liquify');
      expect(e.applyForward(DevelopSettings.defaults), s);
      expect(e.applyBackward(s), DevelopSettings.defaults);
      final json = HistoryEntry.fromJson(e.toJson());
      expect(json.applyForward(DevelopSettings.defaults).liquify, [_push]);
    });

    test('paste group "Liquify", not in the default copy', () {
      expect(SettingsGroup.liquify.label, 'Liquify');
      expect(SettingsGroup.defaultCopy, isNot(contains(SettingsGroup.liquify)));
      final none = pasteSettings(
        source: s,
        target: DevelopSettings.defaults,
        groups: SettingsGroup.defaultCopy,
      );
      expect(none.liquify, isEmpty);
      final pasted = pasteSettings(
        source: s,
        target: DevelopSettings.defaults,
        groups: {SettingsGroup.liquify},
      );
      expect(pasted.liquify, [_push]);
    });
  });
}
