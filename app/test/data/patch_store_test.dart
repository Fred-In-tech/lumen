import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/data/file_patch_store_io.dart';
import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen_core/lumen_core.dart';

/// A 5×3 patch with distinct colours and a soft alpha ramp.
RgbaBuffer _patch({int seed = 0}) {
  final b = RgbaBuffer(5, 3);
  for (var i = 0; i < 15; i++) {
    b.data.setRange(i * 4, i * 4 + 4, [
      (i * 17 + seed) % 256,
      (i * 31) % 256,
      (200 - i * 7 + seed) % 256,
      i * 18,
    ]);
  }
  return b;
}

HealOp _op(String id) => HealOp.forPatch(
  id: id,
  bbox: const PixelBox(10, 10, 5, 3),
  srcWidth: 100,
  srcHeight: 80,
  engine: 'pushpull@1',
  ai: false,
  strokes: const [],
);

void _contract(String name, Future<PatchStore> Function() make) {
  group(name, () {
    test('save then load returns the exact RGBA, alpha included', () async {
      final store = await make();
      await store.save('a', 'retouch/h1.png', _patch());
      final back = await store.load('a', 'retouch/h1.png');
      expect(back, isNotNull);
      expect(back!.width, 5);
      expect(back.height, 3);
      expect(back.data, _patch().data);
      expect(await store.list('a'), {'retouch/h1.png'});
      expect(await store.list('b'), isEmpty);
    });

    test('missing patches load as null; delete is idempotent', () async {
      final store = await make();
      expect(await store.load('a', 'retouch/nope.png'), isNull);
      await store.save('a', 'retouch/h1.png', _patch());
      await store.delete('a', 'retouch/h1.png');
      await store.delete('a', 'retouch/h1.png');
      expect(await store.load('a', 'retouch/h1.png'), isNull);
      expect(await store.list('a'), isEmpty);
    });

    test('refuses refs and ids that could leave the asset folder', () async {
      final store = await make();
      const bad = [
        '../h1.png',
        'retouch/../../edit.png',
        '/etc/h1.png',
        r'retouch\h1.png',
        'C:/h1.png',
        'cache/face.png',
        'retouch/h1.jpg',
        'retouch/sub/h1.png',
        '',
      ];
      for (final ref in bad) {
        await expectLater(
          store.save('a', ref, _patch()),
          throwsArgumentError,
          reason: ref,
        );
        expect(await store.load('a', ref), isNull, reason: ref);
      }
      await expectLater(
        store.save('../a', 'retouch/h1.png', _patch()),
        throwsArgumentError,
      );
    });
  });
}

void main() {
  test('PNG codec round-trips RGBA and rejects garbage', () async {
    final png = encodePatchPng(_patch(seed: 9));
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    expect(decodePatchPng(png).data, _patch(seed: 9).data);
    expect(
      () => decodePatchPng(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(await decodePatchPngInBackground(Uint8List(8)), isNull);
  });

  _contract('MemoryPatchStore', () async => MemoryPatchStore());

  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('lumen_patch'));
  tearDown(() async => tmp.delete(recursive: true));

  _contract('FilePatchStore', () async => FilePatchStore(tmp.path));

  test('files live at assets/<id>/retouch/ and go with the photo', () async {
    final store = FilePatchStore(tmp.path);
    await store.save('a', 'retouch/h1.png', _patch());
    final file = File('${tmp.path}/assets/a/retouch/h1.png');
    expect(file.existsSync(), isTrue);
    expect(
      Directory('${tmp.path}/assets/a/retouch')
          .listSync()
          .map((e) => e.path.split('/').last),
      ['h1.png'],
      reason: 'atomic write leaves no .tmp behind',
    );
    // A stray non-patch file is never listed (so never collected).
    File('${tmp.path}/assets/a/retouch/notes.txt').writeAsStringSync('x');
    expect(await store.list('a'), {'retouch/h1.png'});

    final catalog = FileCatalogRepository(tmp.path);
    await catalog.add(
      CatalogEntry(
        assetId: 'a',
        fileName: 'a.jpg',
        originalPath: 'originals/a.jpg',
        format: 'jpeg',
        width: 10,
        height: 10,
        bytes: 1,
        importedAt: DateTime.utc(2026),
      ),
      Uint8List(1),
    );
    await catalog.delete('a');
    expect(file.existsSync(), isFalse);
  });

  group('referencedPatchRefs / collectPatchGarbage', () {
    // s0 → s1 (+h1) → s2 (+h2), then undo: h2 lives only in the redo tail.
    EditDocument doc() {
      final s0 = DevelopSettings.defaults;
      final s1 = s0.copyWith(heal: [_op('h1')]);
      final s2 = s1.copyWith(heal: [_op('h1'), _op('h2')]);
      final history = HistoryStack.empty
          .push(
            HistoryEntry.diff(
              label: 'Remove',
              kind: HistoryKind.slider,
              before: s0,
              after: s1,
            ),
          )
          .push(
            HistoryEntry.diff(
              label: 'Remove',
              kind: HistoryKind.slider,
              before: s1,
              after: s2,
            ),
          );
      final undone = history.undo(s2);
      return EditDocument.create('a').copyWith(
        settings: undone.settings,
        history: undone.stack,
        snapshots: [
          Snapshot(
            name: 'before sky',
            settings: s0.copyWith(heal: [_op('h4')]),
            at: DateTime.utc(2026),
          ),
        ],
        ai: AiRecord(
          engine: 'local',
          style: 'natural',
          preAi: s0.copyWith(heal: [_op('h5').copyWith(hidden: true)]),
        ),
      );
    }

    test('lists current, undo and redo history, snapshots and AI', () {
      final d = doc();
      expect(d.settings.heal.map((o) => o.id), ['h1']);
      expect(referencedPatchRefs(d), {
        'retouch/h1.png',
        'retouch/h2.png',
        'retouch/h4.png',
        'retouch/h5.png',
      });
    });

    test('deletes only unreferenced, unprotected patches', () async {
      final store = MemoryPatchStore();
      for (final id in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']) {
        await store.save('a', 'retouch/$id.png', _patch());
      }
      final dead = await collectPatchGarbage(
        store,
        doc(),
        protect: {'retouch/h6.png'},
      );
      expect(dead, {'retouch/h3.png'});
      expect(await store.list('a'), {
        'retouch/h1.png',
        'retouch/h2.png',
        'retouch/h4.png',
        'retouch/h5.png',
        'retouch/h6.png',
      });
      // Once the history is gone, everything but the current op goes.
      final cleared = doc().copyWith(
        history: HistoryStack.empty,
        snapshots: const [],
        clearAi: true,
      );
      expect(await collectPatchGarbage(store, cleared), {
        'retouch/h2.png',
        'retouch/h4.png',
        'retouch/h5.png',
        'retouch/h6.png',
      });
      expect(await store.list('a'), {'retouch/h1.png'});
    });

    test('keeps background-swap images from settings, history, snapshots', () {
      const a = BackdropChange(
        mode: BackdropMode.image,
        imageRef: 'retouch/bg-a.png',
      );
      const b = BackdropChange(
        mode: BackdropMode.image,
        imageRef: 'retouch/bg-b.png',
      );
      final s0 = DevelopSettings.defaults;
      final s1 = s0.copyWith(backdrop: a);
      final s2 = s0.copyWith(backdrop: b);
      final history = HistoryStack.empty
          .push(
            HistoryEntry.diff(
              label: 'Background',
              kind: HistoryKind.slider,
              before: s0,
              after: s1,
            ),
          )
          .push(
            HistoryEntry.diff(
              label: 'Background',
              kind: HistoryKind.slider,
              before: s1,
              after: s2,
            ),
          );
      final d = EditDocument.create('a').copyWith(
        settings: s2,
        history: history,
        snapshots: [
          Snapshot(
            name: 'studio',
            settings: s0.copyWith(
              backdrop: const BackdropChange(
                mode: BackdropMode.image,
                imageRef: 'retouch/bg-c.png',
              ),
            ),
            at: DateTime.utc(2026),
          ),
        ],
      );
      expect(referencedPatchRefs(d), {
        'retouch/bg-a.png',
        'retouch/bg-b.png',
        'retouch/bg-c.png',
      });
    });
  });
}
