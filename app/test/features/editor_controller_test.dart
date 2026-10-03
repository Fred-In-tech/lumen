import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen_core/lumen_core.dart';

import 'dart:typed_data';

Future<(ProviderContainer, MemoryCatalogRepository)> _setup() async {
  final repo = MemoryCatalogRepository();
  await repo.add(
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
  final c = ProviderContainer(
    overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  await c.read(editorProvider('a').future);
  return (c, repo);
}

void main() {
  test('a drag gesture creates exactly one history entry', () async {
    final (c, _) = await _setup();
    final ctl = c.read(editorProvider('a').notifier);
    ctl.beginGesture('Exposure');
    for (final v in [0.1, 0.2, 0.35]) {
      ctl.preview(
        c.read(editorProvider('a')).value!.settings.withValue(P.exposure, v),
      );
    }
    ctl.commitGesture();
    final s = c.read(editorProvider('a')).value!;
    expect(s.settings.value(P.exposure), 0.35);
    expect(s.history.entries.length, 1);
    expect(s.lockedByUser, contains(P.exposure));
    ctl.undo();
    expect(c.read(editorProvider('a')).value!.settings.value(P.exposure), 0);
    ctl.redo();
    expect(c.read(editorProvider('a')).value!.settings.value(P.exposure), 0.35);
  });

  test(
    'flush persists the document and marks the catalog entry edited',
    () async {
      final (c, repo) = await _setup();
      final ctl = c.read(editorProvider('a').notifier);
      ctl.setParam(P.shadows, 25);
      await ctl.flush();
      expect((await repo.loadEdit('a')).settings.value(P.shadows), 25);
      expect((await repo.get('a'))!.hasEdits, isTrue);
    },
  );

  test('presets, paste and reset are single undoable steps', () async {
    final (c, _) = await _setup();
    final ctl = c.read(editorProvider('a').notifier);
    ctl.applyPreset(kBuiltinPresets.firstWhere((p) => p.name == 'Moody'));
    expect(
      c.read(editorProvider('a')).value!.history.entries.single.kind,
      HistoryKind.preset,
    );
    ctl.resetAll();
    expect(c.read(editorProvider('a')).value!.settings.isDefault, isTrue);
    ctl.undo();
    expect(c.read(editorProvider('a')).value!.settings.isDefault, isFalse);
    ctl.paste(DevelopSettings.defaults.withValue(P.temp, 12), {
      SettingsGroup.color,
    });
    expect(c.read(editorProvider('a')).value!.settings.value(P.temp), 12);
  });

  test('AI amount interpolates between pre-AI and AI values', () {
    final pre = DevelopSettings.defaults.withValue(P.exposure, 0.2);
    final post = pre.withValues({P.exposure: 1.2, P.shadows: 40});
    final half = interpolateSettings(pre, post, 0.5, base: post);
    expect(half.value(P.exposure), closeTo(0.7, 1e-9));
    expect(half.value(P.shadows), closeTo(20, 1e-9));
    final over = interpolateSettings(pre, post, 1.5, base: post);
    expect(over.value(P.shadows), closeTo(60, 1e-9));
  });
}
