import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/remove/remove_service.dart';
import 'package:lumen/features/remove/remove_status.dart';
import 'package:lumen_core/lumen_core.dart';

import 'remove_fixtures.dart';

/// A fake MI-GAN: paints every hole pixel mid-grey.
class _GreyModel implements InpaintModel {
  int calls = 0;

  @override
  String get id => 'fake-migan@1';

  @override
  Future<RgbaBuffer> inpaint(RgbaBuffer crop, Uint8List keep) async {
    calls++;
    final out = crop.copy();
    for (var i = 0; i < keep.length; i++) {
      if (keep[i] == 0) out.data.setRange(i * 4, i * 4 + 3, [128, 128, 128]);
    }
    return out;
  }
}

void main() {
  test('remove: strokes become one history entry with stored patches; '
      'undo and redo move the ops', () async {
    final h = await RemoveHarness.create();
    final service = h.container.read(removeServiceProvider);
    expect(meanLuma(syntheticPhoto(), kObject), lessThan(20));

    final ops = await service.remove('a', kObjectStroke);

    expect(ops, isNotEmpty);
    final s = h.editor;
    expect(s.history.entries, hasLength(1));
    expect(s.history.entries.single.label, 'Remove');
    expect(s.history.entries.single.kind, HistoryKind.slider);
    expect(s.settings.heal, ops);
    for (final op in ops) {
      expect(op.kind, HealKind.remove);
      expect(op.ai, isFalse);
      expect(op.engine, 'patchmatch@1');
      expect(op.patch, 'retouch/${op.id}.png');
      expect((op.srcWidth, op.srcHeight), (kW, kH));
      expect(op.strokes, kObjectStroke);
    }
    expect(await h.store.list('a'), {for (final op in ops) op.patch});
    expect(meanLuma(await h.healed(), kObject), greaterThan(110));
    // The commit flushed the document, so the ops are already on disk.
    expect((await h.catalog.loadEdit('a')).settings.heal, ops);

    expect(h.statuses.first, isA<RemoveRunning>());
    expect(
      h.statuses.whereType<RemoveRunning>().map((r) => r.method),
      contains(InpaintMethod.patchMatch),
    );
    final done = h.status as RemoveDone;
    expect(done.ops, ops);
    expect(done.method, InpaintMethod.patchMatch);

    final ctl = h.container.read(editorProvider('a').notifier);
    ctl.undo();
    expect(h.editor.settings.heal, isEmpty);
    // Undone ops stay restorable: GC keeps patches the redo tail needs.
    expect(await service.collectGarbage('a'), isEmpty);
    expect(await h.store.list('a'), hasLength(ops.length));
    ctl.redo();
    expect(h.editor.settings.heal, ops);
    expect(meanLuma(await h.healed(), kObject), greaterThan(110));
  });

  test('a new removal after undo drops the abandoned patches', () async {
    final h = await RemoveHarness.create();
    final service = h.container.read(removeServiceProvider);
    final first = await service.remove(
      'a',
      kObjectStroke,
      method: InpaintMethod.pushPull,
    );
    h.container.read(editorProvider('a').notifier).undo();
    final second = await service.remove(
      'a',
      kObjectStroke,
      method: InpaintMethod.telea,
    );
    expect(h.editor.history.entries, hasLength(1));
    expect(h.editor.settings.heal, second);
    expect(second.first.engine, 'telea@1');
    expect(await h.store.list('a'), {for (final op in second) op.patch});
    expect(first.first.id, isNot(second.first.id));
  });

  test('the hole touching a detected face flags the op', () async {
    final h = await RemoveHarness.create(
      overrides: [
        portraitFacesProvider('a').overrideWithValue(
          const FaceAnalysis(
            imageWidth: kW,
            imageHeight: kH,
            modelVersion: 'test',
            faces: [DetectedFace(id: 'f1', box: FaceBox(0.5, 0.4, 0.2, 0.3))],
          ),
        ),
      ],
    );
    final ops = await h.container
        .read(removeServiceProvider)
        .remove('a', kObjectStroke, method: InpaintMethod.pushPull);
    expect(ops.every((o) => o.faceIntersect), isTrue);
    expect((h.status as RemoveDone).faceIntersect, isTrue);
  });

  test('model seam: an AI fill is labelled ai and kind ai', () async {
    final model = _GreyModel();
    final h = await RemoveHarness.create(model: model);
    final ops = await h.container
        .read(removeServiceProvider)
        .remove('a', kObjectStroke);
    expect(model.calls, greaterThan(0));
    expect(ops.every((o) => o.ai && o.engine == 'fake-migan@1'), isTrue);
    expect(h.editor.history.entries.single.kind, HistoryKind.ai);
    expect((h.status as RemoveDone).ai, isTrue);
  });

  test('clone and heal brushes commit their own kinds', () async {
    final h = await RemoveHarness.create();
    final service = h.container.read(removeServiceProvider);
    final stroke = [
      const BrushStroke(points: [(0.25, 0.5)], radius: 0.04, hardness: 1),
    ];
    final cloned = await service.cloneAt('a', stroke, (0.25, 0));
    expect(cloned.single.kind, HealKind.clone);
    expect(cloned.single.cloneOffset, (0.25, 0));
    expect(cloned.single.engine, 'clone@1');
    // Inside the stroke, the clone copies the pixels 40 px to the right.
    final healed = await h.healed();
    final src = syntheticPhoto();
    expect(
      healed.data.sublist(healed.offset(40, 60), healed.offset(40, 60) + 3),
      src.data.sublist(src.offset(80, 60), src.offset(80, 60) + 3),
    );

    final healedOps = await service.healAt('a', kObjectStroke);
    expect(healedOps.single.kind, HealKind.heal);
    expect(healedOps.single.engine, 'heal@1');
    expect(h.editor.history.entries.map((e) => e.label), ['Clone', 'Heal']);
    expect(meanLuma(await h.healed(), kObject), greaterThan(100));
  });

  test('cancel kills the running job: nothing committed or stored', () async {
    final runner = InlineRunner()..hang.add(1); // plan runs, the fill hangs
    final h = await RemoveHarness.create(runner: runner.call);
    final service = h.container.read(removeServiceProvider);

    final pending = service.remove('a', kObjectStroke);
    await h.until(
      () => switch (h.status) {
        RemoveRunning(method: InpaintMethod.patchMatch) => true,
        _ => false,
      },
    );
    expect(service.isRunning('a'), isTrue);
    expect(
      () => service.remove('a', kObjectStroke),
      throwsStateError,
      reason: 'one run per photo',
    );
    service.cancel('a');

    expect(await pending, isEmpty);
    expect(runner.tasks[1].isCancelled, isTrue);
    expect(h.status, isA<RemoveIdle>());
    expect(h.editor.history.entries, isEmpty);
    expect(await h.store.list('a'), isEmpty);
    expect(service.isRunning('a'), isFalse);
  });

  test('errors end in a failed status with a readable message', () async {
    final h = await RemoveHarness.create(
      loader: (_) async =>
          throw const CatalogException('Original file missing for a.jpg'),
    );
    final service = h.container.read(removeServiceProvider);
    expect(await service.remove('a', kObjectStroke), isEmpty);
    expect(
      h.status,
      isA<RemoveFailed>().having(
        (f) => f.message,
        'message',
        'Original file missing for a.jpg',
      ),
    );
    expect(h.editor.history.entries, isEmpty);
    expect(await h.store.list('a'), isEmpty);

    // Forcing the AI engine without a model fails before any work.
    await service.remove('a', kObjectStroke, method: InpaintMethod.model);
    expect((h.status as RemoveFailed).message, contains('not available'));
    h.container.read(removeStatusProvider('a').notifier).dismiss();
    expect(h.status, isA<RemoveIdle>());
  });

  test('strokes outside the photo commit nothing and go idle', () async {
    final h = await RemoveHarness.create();
    final ops = await h.container.read(removeServiceProvider).remove('a', [
      const BrushStroke(points: [(3, 3)], radius: 0.01, hardness: 1),
    ]);
    expect(ops, isEmpty);
    expect(h.status, isA<RemoveIdle>());
    expect(h.editor.history.entries, isEmpty);
  });
}
