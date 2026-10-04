import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/memory_patch_store.dart';
import 'package:lumen/features/remove/heal_transfer.dart';
import 'package:lumen_core/lumen_core.dart';

void main() {
  final source = DevelopSettings.defaults.copyWith(
    backdrop: const BackdropChange(
      mode: BackdropMode.image,
      imageRef: 'retouch/bg-studio.png',
    ),
  );

  test('pasting a background swap copies its image into the target', () async {
    final store = MemoryPatchStore();
    final img = RgbaBuffer(4, 4);
    await store.save('src', 'retouch/bg-studio.png', img);
    final r = await prepareHealPaste(
      source: source,
      groups: {SettingsGroup.backdrop},
      sourceAssetId: 'src',
      targetAssetId: 'dst',
      targetDoc: EditDocument.create('dst'),
      store: () async => store,
    );
    expect(r.skipped, 0);
    final ref = r.settings.backdrop.imageRef;
    expect(ref, startsWith('retouch/bg'));
    expect(ref, isNot('retouch/bg-studio.png'));
    expect(await store.list('dst'), {ref});
    expect(r.settings.backdrop.mode, BackdropMode.image);
  });

  test('a missing image is dropped and counted, never left dangling', () async {
    final store = MemoryPatchStore();
    final r = await prepareHealPaste(
      source: source,
      groups: {SettingsGroup.backdrop},
      sourceAssetId: 'src',
      targetAssetId: 'dst',
      targetDoc: EditDocument.create('dst'),
      store: () async => store,
    );
    expect(r.skipped, 1);
    expect(r.settings.backdrop.imageRef, isEmpty);
  });

  test('without the backdrop group nothing is copied', () async {
    final store = MemoryPatchStore();
    await store.save('src', 'retouch/bg-studio.png', RgbaBuffer(4, 4));
    final r = await prepareHealPaste(
      source: source,
      groups: {SettingsGroup.light},
      sourceAssetId: 'src',
      targetAssetId: 'dst',
      targetDoc: EditDocument.create('dst'),
      store: () async => store,
    );
    expect(r.skipped, 0);
    expect(await store.list('dst'), isEmpty);
  });
}
