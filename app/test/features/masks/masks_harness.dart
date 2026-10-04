import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/mask_commands.dart';
import 'package:lumen/features/masks/mask_ui_state.dart';
import 'package:lumen_core/lumen_core.dart';

const kAsset = 'a';
const kSource = Size(400, 300);

/// A container with photo [kAsset] open in the editor controller.
Future<ProviderContainer> openEditor({
  List<Override> overrides = const [],
}) async {
  final repo = MemoryCatalogRepository();
  await repo.add(
    CatalogEntry(
      assetId: kAsset,
      fileName: 'a.jpg',
      originalPath: 'originals/a.jpg',
      format: 'jpeg',
      width: kSource.width.toInt(),
      height: kSource.height.toInt(),
      bytes: 1,
      importedAt: DateTime.utc(2026),
    ),
    Uint8List(1),
  );
  final c = ProviderContainer(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(repo),
      ...overrides,
    ],
  );
  addTearDown(c.dispose);
  await c.read(editorProvider(kAsset).future);
  return c;
}

/// Pumps [child] in the app theme on a 1000×2400 logical surface.
Future<void> pumpIn(
  WidgetTester tester,
  ProviderContainer c,
  Widget child,
) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildLumenTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MaskCommands cmds(ProviderContainer c) => MaskCommands(c.read, kAsset);

EditorState editor(ProviderContainer c) =>
    c.read(editorProvider(kAsset)).value!;

List<LocalMask> masksOf(ProviderContainer c) => editor(c).settings.masks;

int historyLength(ProviderContainer c) => editor(c).history.entries.length;

MaskUiState maskUi(ProviderContainer c) => c.read(maskUiProvider(kAsset));

/// Lets the editor's debounced auto-save run so no timer outlives the test.
Future<void> flushSave(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 2));
