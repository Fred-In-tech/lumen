import 'dart:convert';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

final _created = DateTime.utc(2026, 10, 3, 12, 30);

HealOp _remove(String id, {bool hidden = false}) => HealOp(
  id: id,
  kind: HealKind.remove,
  engine: 'migan@fp16-1',
  ai: true,
  strokes: const [
    BrushStroke(points: [(0.61, 0.2), (0.63, 0.22)], radius: 0.004),
  ],
  bbox: const PixelBox(3120, 1004, 812, 812),
  srcWidth: 6000,
  srcHeight: 4000,
  patch: 'retouch/$id.png',
  hidden: hidden,
  createdAt: _created,
  faceIntersect: true,
);

void main() {
  group('HealOp JSON', () {
    test('round-trips every field (through a JSON string)', () {
      final ops = [
        _remove('h3'),
        const HealOp(
          id: 'h4',
          kind: HealKind.clone,
          engine: 'copy',
          strokes: [
            BrushStroke(points: [(0.3, 0.71)], radius: 0.006, erase: false),
          ],
          bbox: PixelBox(1764, 2804, 96, 96),
          srcWidth: 6000,
          srcHeight: 4000,
          patch: 'retouch/h4.png',
          cloneOffset: (-0.05, 0.0),
          hidden: true,
        ),
      ];
      for (final op in ops) {
        final back = HealOp.fromJson(
          (jsonDecode(jsonEncode(op.toJson())) as Map).cast<String, Object?>(),
        );
        expect(back, op);
        expect(back.hashCode, op.hashCode);
      }
    });

    test('writes the §5.5 shape', () {
      final j = _remove('h3').toJson();
      expect(j['kind'], 'remove');
      expect(j['engine'], 'migan@fp16-1');
      expect(j['ai'], true);
      expect(j['bbox'], [3120, 1004, 812, 812]);
      expect(j['srcSize'], [6000, 4000]);
      expect(j['patch'], 'retouch/h3.png');
      expect((j['mask'] as Map)['strokes'], isA<List<Object?>>());
      expect(j.containsKey('hidden'), isFalse);
      expect(j.containsKey('src'), isFalse);
      expect(j['faceWarning'], true);
    });

    test('lenient parsing of junk', () {
      final op = HealOp.fromJson({
        'id': 7,
        'kind': 'teleport',
        'ai': 'yes',
        'bbox': [1, 2],
        'srcSize': 'big',
        'mask': {
          'strokes': [
            'x',
            {
              'points': [
                [0.1, 0.2],
              ],
              'radius': 0.01,
            },
          ],
        },
        'createdAt': 'yesterday',
        'src': ['a', 1],
        'hidden': 1,
      });
      expect(op.id, '');
      expect(op.kind, HealKind.remove);
      expect(op.ai, isFalse);
      expect(op.bbox.isEmpty, isTrue);
      expect(op.srcWidth, 0);
      expect(op.strokes, hasLength(1));
      expect(op.createdAt, isNull);
      expect(op.cloneOffset, isNull);
      expect(op.hidden, isFalse);
      expect(op.isRenderable, isFalse);
    });

    test('patch refs must stay relative and inside the asset folder', () {
      for (final bad in [
        '/etc/passwd',
        '../x.png',
        'retouch/../../a.png',
        r'C:\a.png',
        'a\\b.png',
      ]) {
        expect(
          HealOp.fromJson({'id': 'h', 'patch': bad}).patch,
          '',
          reason: bad,
        );
      }
      expect(
        HealOp.fromJson({'id': 'h', 'patch': 'retouch/h1.png'}).patch,
        'retouch/h1.png',
      );
    });

    test('parseHealOps skips non-maps', () {
      expect(parseHealOps(null), isEmpty);
      expect(parseHealOps('x'), isEmpty);
      expect(parseHealOps([1, _remove('a').toJson()]), [_remove('a')]);
    });

    test('copyWith toggles hidden and keeps the rest', () {
      final op = _remove('h1');
      final hidden = op.copyWith(hidden: true);
      expect(hidden.hidden, isTrue);
      expect(hidden.copyWith(hidden: false), op);
    });
  });

  group('DevelopSettings integration', () {
    test('json only when non-empty; equality; isDefault', () {
      expect(DevelopSettings.defaults.toJson().containsKey('heal'), isFalse);
      final s = DevelopSettings.defaults.copyWith(heal: [_remove('h1')]);
      expect(s.isDefault, isFalse);
      expect(s.toJson()['heal'], isA<List<Object?>>());
      final back = DevelopSettings.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>,
      );
      expect(back, s);
      expect(back.hashCode, s.hashCode);
      expect(s, isNot(DevelopSettings.defaults));
      expect(s.copyWith(heal: const []), DevelopSettings.defaults);
      // Scalar edits keep the heal list.
      expect(s.withValue(P.exposure, 1).heal, s.heal);
    });

    test('history targets heal as a whole list', () {
      final a = DevelopSettings.defaults.copyWith(heal: [_remove('h1')]);
      final b = a.copyWith(heal: [_remove('h1', hidden: true), _remove('h2')]);
      final e = HistoryEntry.diff(
        label: 'Remove',
        kind: HistoryKind.slider,
        before: a,
        after: b,
      );
      expect(e.ops.map((o) => o.path), ['heal']);
      expect(e.applyForward(a), b);
      expect(e.applyBackward(b), a);
      final back = HistoryEntry.fromJson(
        (jsonDecode(jsonEncode(e.toJson())) as Map).cast<String, Object?>(),
      );
      expect(back.applyForward(a), b);
      expect(back.applyBackward(b), a);
      // Undo to an empty list.
      final first = HistoryEntry.diff(
        label: 'Remove',
        kind: HistoryKind.slider,
        before: DevelopSettings.defaults,
        after: a,
      );
      expect(first.applyBackward(a), DevelopSettings.defaults);
    });

    test('paste: not in the default groups, copied only when asked', () {
      final src = DevelopSettings.defaults
          .withValue(P.exposure, 0.5)
          .copyWith(heal: [_remove('h1')]);
      expect(SettingsGroup.defaultCopy.contains(SettingsGroup.heal), isFalse);
      expect(SettingsGroup.heal.label, 'Heal & remove');
      final byDefault = pasteSettings(
        source: src,
        target: DevelopSettings.defaults,
        groups: SettingsGroup.defaultCopy,
      );
      expect(byDefault.value(P.exposure), 0.5);
      expect(byDefault.heal, isEmpty);
      final target = DevelopSettings.defaults.copyWith(heal: [_remove('t')]);
      expect(
        pasteSettings(
          source: src,
          target: target,
          groups: SettingsGroup.defaultCopy,
        ).heal,
        target.heal,
      );
      expect(
        pasteSettings(
          source: src,
          target: target,
          groups: {SettingsGroup.heal},
        ).heal,
        src.heal,
      );
    });
  });
}
