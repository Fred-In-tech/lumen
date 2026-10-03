import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

DevelopSettings _randomEdit(DevelopSettings s, math.Random rnd) {
  switch (rnd.nextInt(4)) {
    case 0:
      final p = ParamRegistry.all[rnd.nextInt(ParamRegistry.all.length)];
      return s.withValue(p.id, p.min + rnd.nextDouble() * (p.max - p.min));
    case 1:
      return s.copyWith(
        treatment: s.treatment == Treatment.bw ? Treatment.color : Treatment.bw,
      );
    case 2:
      return s.copyWith(
        geometry: s.geometry.copyWith(
          angle: rnd.nextDouble() * 10 - 5,
          flipH: rnd.nextBool(),
        ),
      );
    default:
      return s.copyWith(
        curves: s.curves.withChannel(
          CurveChannel.values[rnd.nextInt(4)],
          ToneCurve([
            const CurvePoint(0, 0),
            CurvePoint(128, 100 + rnd.nextDouble() * 50),
            const CurvePoint(255, 255),
          ]),
        ),
      );
  }
}

void main() {
  test('diff produces ops that reproduce the change both ways', () {
    final a = DevelopSettings.defaults.withValue(P.exposure, 0.3);
    final b = a
        .withValue(P.exposure, 0.8)
        .withValue(P.shadows, 20)
        .copyWith(treatment: Treatment.bw);
    final e = HistoryEntry.diff(
      label: 'x',
      kind: HistoryKind.slider,
      before: a,
      after: b,
    );
    expect(e.ops.length, 3);
    expect(e.applyForward(a), b);
    expect(e.applyBackward(b), a);
  });

  test('empty diff yields null', () {
    const a = DevelopSettings.defaults;
    expect(
      HistoryEntry.tryDiff(
        label: 'x',
        kind: HistoryKind.slider,
        before: a,
        after: a,
      ),
      isNull,
    );
  });

  test('50 random edits: undo all equals initial, redo all equals final', () {
    final rnd = math.Random(42);
    var s = DevelopSettings.defaults;
    var stack = HistoryStack.empty;
    final initial = s;
    for (var i = 0; i < 50; i++) {
      final next = _randomEdit(s, rnd);
      final e = HistoryEntry.tryDiff(
        label: 'edit $i',
        kind: HistoryKind.slider,
        before: s,
        after: next,
      );
      if (e != null) stack = stack.push(e);
      s = next;
    }
    final finalState = s;
    while (stack.canUndo) {
      final r = stack.undo(s);
      stack = r.stack;
      s = r.settings;
    }
    expect(s, initial);
    while (stack.canRedo) {
      final r = stack.redo(s);
      stack = r.stack;
      s = r.settings;
    }
    expect(s, finalState);
  });

  test('push after undo truncates redo tail', () {
    var s = DevelopSettings.defaults;
    var stack = HistoryStack.empty;
    for (final v in [0.1, 0.2, 0.3]) {
      final n = s.withValue(P.exposure, v);
      stack = stack.push(
        HistoryEntry.diff(
          label: '$v',
          kind: HistoryKind.slider,
          before: s,
          after: n,
        ),
      );
      s = n;
    }
    final r = stack.undo(s);
    expect(r.settings.value(P.exposure), closeTo(0.2, 1e-9));
    final n = r.settings.withValue(P.contrast, 10);
    stack = r.stack.push(
      HistoryEntry.diff(
        label: 'c',
        kind: HistoryKind.slider,
        before: r.settings,
        after: n,
      ),
    );
    expect(stack.canRedo, isFalse);
    expect(stack.entries.length, 3);
  });

  test('cap drops oldest entries', () {
    var stack = HistoryStack.empty;
    var s = DevelopSettings.defaults;
    for (var i = 0; i < HistoryStack.maxEntries + 20; i++) {
      final n = s.withValue(P.exposure, (i % 100) / 100 + 0.001);
      stack = stack.push(
        HistoryEntry.diff(
          label: '$i',
          kind: HistoryKind.slider,
          before: s,
          after: n,
        ),
      );
      s = n;
    }
    expect(stack.entries.length, HistoryStack.maxEntries);
    expect(stack.cursor, HistoryStack.maxEntries);
  });

  test('coalesce merges consecutive edits of the same key', () {
    var s = DevelopSettings.defaults;
    var stack = HistoryStack.empty;
    for (final v in [10.0, 20.0, 30.0]) {
      final n = s.withValue(P.shadows, v);
      stack = stack.push(
        HistoryEntry.diff(
          label: 'Shadows',
          kind: HistoryKind.slider,
          before: s,
          after: n,
          coalesceKey: 'shadows',
        ),
        coalesce: true,
      );
      s = n;
    }
    expect(stack.entries.length, 1);
    final r = stack.undo(s);
    expect(r.settings.value(P.shadows), 0);
  });

  test('json round trip', () {
    var s = DevelopSettings.defaults;
    var stack = HistoryStack.empty;
    final n = s
        .withValue(P.exposure, 0.62)
        .copyWith(geometry: Geometry.none.copyWith(rotate90: 1));
    stack = stack.push(
      HistoryEntry.diff(
        label: 'Exposure +0.62',
        kind: HistoryKind.ai,
        before: s,
        after: n,
      ),
    );
    s = n;
    final back = HistoryStack.fromJson(stack.toJson());
    expect(back.entries.single.label, 'Exposure +0.62');
    expect(back.entries.single.kind, HistoryKind.ai);
    expect(back.undo(s).settings, DevelopSettings.defaults);
  });
}
