import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/remove/heal_transfer.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/features/sync/settings_clipboard.dart';
import 'package:lumen_core/lumen_core.dart';

CatalogEntry _entry(String id) => CatalogEntry(
  assetId: id,
  fileName: '$id.jpg',
  originalPath: 'originals/$id.jpg',
  format: 'jpeg',
  width: 100,
  height: 80,
  bytes: 1,
  importedAt: DateTime.utc(2026),
);

HealOp _op(String id) => HealOp.forPatch(
  id: id,
  bbox: const PixelBox(10, 10, 4, 4),
  srcWidth: 100,
  srcHeight: 80,
  engine: 'pushpull@1',
  ai: false,
  strokes: const [],
);

typedef _Harness = ({
  WidgetRef ref,
  BuildContext context,
  MemoryCatalogRepository repo,
  MemoryPatchStore store,
});

Future<_Harness> _harness(WidgetTester tester) async {
  final repo = MemoryCatalogRepository();
  final store = MemoryPatchStore();
  late WidgetRef ref;
  late BuildContext ctx;
  await tester.runAsync(() async {
    for (final id in ['a', 'b', 'c']) {
      await repo.add(_entry(id), Uint8List(1));
    }
    // 'a' has h1's patch; h2's patch is missing.
    await store.save('a', 'retouch/h1.png', RgbaBuffer.filled(4, 4, 9, 8, 7));
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        patchStoreProvider.overrideWith((ref) async => store),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, r, _) {
              ref = r;
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    ),
  );
  return (ref: ref, context: ctx, repo: repo, store: store);
}

final _source = DevelopSettings.defaults.copyWith(heal: [_op('h1'), _op('h2')]);

void main() {
  testWidgets('sync copies heal patches under fresh ids and counts missing '
      'ones', (tester) async {
    final h = await _harness(tester);
    await tester.runAsync(() async {
      var skipped = 0;
      final n = await syncSettingsToAssets(
        h.ref,
        _source,
        {SettingsGroup.heal},
        ['b', 'c'],
        sourceAssetId: 'a',
        onHealsSkipped: (k) => skipped = k,
      );
      expect(n, 2);
      expect(skipped, 2, reason: 'h2 is missing, once per target');
      final ids = <String>{};
      for (final id in ['b', 'c']) {
        final doc = await h.repo.loadEdit(id);
        final op = doc.settings.heal.single;
        ids.add(op.id);
        expect(op.id, isNot('h1'));
        expect(op.patch, 'retouch/${op.id}.png');
        expect(op.bbox, _op('h1').bbox);
        expect(doc.history.entries.single.kind, HistoryKind.paste);
        expect(await h.store.list(id), {op.patch});
        expect(
          (await h.store.load(id, op.patch))!.data,
          RgbaBuffer.filled(4, 4, 9, 8, 7).data,
        );
      }
      // The source photo keeps its own patch untouched.
      expect(await h.store.list('a'), {'retouch/h1.png'});
    });
  });

  testWidgets('pasting into the open photo is one history entry; the same '
      'photo keeps its ids', (tester) async {
    final h = await _harness(tester);
    await tester.runAsync(() async {
      await h.ref.read(editorProvider('b').future);
      await h.ref.read(editorProvider('a').future);
      h.ref
          .read(settingsClipboardProvider.notifier)
          .set(
            SettingsClipboard(
              settings: _source,
              groups: {SettingsGroup.heal, SettingsGroup.light},
              sourceAssetId: 'a',
            ),
          );
      await pasteSettingsInto(h.context, h.ref, 'b');
      final b = h.ref.read(editorProvider('b')).value!;
      expect(b.history.entries, hasLength(1));
      expect(b.settings.heal.single.id, isNot('h1'));
      expect(await h.store.list('b'), {b.settings.heal.single.patch});

      await pasteSettingsInto(h.context, h.ref, 'a');
      final a = h.ref.read(editorProvider('a')).value!;
      expect(a.settings.heal.map((o) => o.id), ['h1', 'h2']);
      await h.ref.read(editorProvider('a').notifier).flush();
      await h.ref.read(editorProvider('b').notifier).flush();
    });
    await tester.pump(const Duration(seconds: 5)); // toast timers
  });

  test('transfer avoids every ref the target document knows', () async {
    final store = MemoryPatchStore();
    await store.save('a', 'retouch/h1.png', RgbaBuffer.filled(4, 4, 1, 2, 3));
    final taken = {for (var i = 0; i < 50; i++) 'retouch/x$i.png'};
    final moved = await transferHealOps(
      store,
      fromAsset: 'a',
      toAsset: 'b',
      ops: [_op('h1')],
      takenRefs: taken,
    );
    expect(moved.skipped, 0);
    expect(taken.contains(moved.ops.single.patch), isFalse);
    expect(
      newHealOpIds({'retouch/${moved.ops.single.id}.png'}, 3).toSet(),
      hasLength(3),
    );
    // Copy refuses unsafe refs on both sides.
    expect(await store.copy('a', '../h1.png', 'b', 'retouch/z.png'), isFalse);
    await expectLater(
      store.copy('a', 'retouch/h1.png', 'b', '../z.png'),
      throwsArgumentError,
    );
  });
}
