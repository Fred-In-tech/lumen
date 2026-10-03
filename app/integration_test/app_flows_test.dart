import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/data/file_preference_repositories_io.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/library/library_actions.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_sources.dart';
import 'package:lumen_core/lumen_core.dart';

import 'dart:convert' show base64Decode;

import 'format_fixtures.dart';

/// Picker replacement that returns synthetic JPEG/PNG photos.
class FakeImportSource implements ImportSource {
  FakeImportSource(this.files);
  final List<ImportFile> files;

  @override
  Future<List<ImportFile>> pick({required bool mobile}) async => files;
}

Uint8List _jpeg(SceneId id, {int longEdge = 1600}) {
  final s = SyntheticScenes.build(id, longEdge: longEdge).image;
  final im = img.Image.fromBytes(
    width: s.width,
    height: s.height,
    bytes: s.data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(
    img.encodeJpg(im.convert(numChannels: 3), quality: 92),
  );
}

Uint8List _png(SceneId id) {
  final s = SyntheticScenes.build(id, longEdge: 900).image;
  final im = img.Image.fromBytes(
    width: s.width,
    height: s.height,
    bytes: s.data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(im));
}

final _shotKey = GlobalKey();

/// Saves the app's current frame as PNG under the system temp dir (for manual review).
Future<void> _screenshot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory('${Directory.systemTemp.path}/lumen_shots')
      ..createSync(recursive: true);
    final f = File('${dir.path}/$name.png')
      ..writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('SCREENSHOT ${f.path}');
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('import → auto-edit → editor → prompt → undo → export', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('lumen_it');
    final catalog = FileCatalogRepository(root.path);
    final files = [
      ImportFile(name: 'dark_interior.jpg', bytes: _jpeg(SceneId.darkInterior)),
      ImportFile(name: 'tungsten.jpg', bytes: _jpeg(SceneId.tungstenCast)),
      ImportFile(name: 'hazy.png', bytes: _png(SceneId.hazyLandscape)),
      ImportFile(name: 'gradient.heic', bytes: base64Decode(kHeicFixtureB64)),
      ImportFile(name: 'gradient.webp', bytes: base64Decode(kWebpFixtureB64)),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(catalog),
          presetRepositoryProvider.overrideWithValue(
            FilePresetRepository(root.path),
          ),
          settingsRepositoryProvider.overrideWithValue(
            FileSettingsRepository(root.path),
          ),
          importSourceProvider.overrideWithValue(FakeImportSource(files)),
        ],
        child: RepaintBoundary(key: _shotKey, child: const LumenApp()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('developed.'), findsOneWidget);
    await _screenshot(tester, '01_library_empty');

    // Import (auto-edit on import is on by default).
    await tester.tap(find.text('Import'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LumenApp)),
    );
    await _pumpUntil(
      tester,
      () => (container.read(libraryProvider).value?.length ?? 0) == 5,
    );
    await _pumpUntil(
      tester,
      () =>
          container.read(batchProvider) == null &&
          container
              .read(libraryProvider)
              .value!
              .every((e) => e.aiEngine != null),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await _screenshot(tester, '02_library_edited');
    final entries = container.read(libraryProvider).value!;
    expect(
      entries.map((e) => e.format).toSet(),
      containsAll(['jpeg', 'png', 'heic', 'webp']),
    );
    final dark = entries.firstWhere((e) => e.fileName == 'dark_interior.jpg');
    final darkDoc = await tester.runAsync(() => catalog.loadEdit(dark.assetId));
    expect(
      darkDoc!.settings.value(P.exposure),
      greaterThan(0.3),
      reason: 'dark scene gets brightened',
    );
    expect(darkDoc.history.entries.single.kind, HistoryKind.ai);

    // Re-importing the same files does not duplicate.
    await tester.tap(find.text('Import'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump();
    expect(container.read(libraryProvider).value!.length, 5);

    // Open the editor.
    final tile = find.bySemanticsLabel(RegExp('dark_interior.jpg')).first;
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await _pumpUntil(
      tester,
      () => container.read(editorProvider(dark.assetId)).value != null,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _screenshot(tester, '03_editor');
    final ctl = container.read(editorProvider(dark.assetId).notifier);
    final before = container.read(editorProvider(dark.assetId)).value!.settings;

    // Describe-an-edit (offline lexicon).
    final field = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').startsWith('Describe an edit'),
    );
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.tap(field);
    await tester.enterText(field, 'warmer and brighten the shadows a bit');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _pumpUntil(
      tester,
      () =>
          container.read(editorProvider(dark.assetId)).value!.settings !=
          before,
    );
    final after = container.read(editorProvider(dark.assetId)).value!;
    expect(after.settings.value(P.temp), greaterThan(before.value(P.temp)));
    expect(
      after.settings.value(P.shadows),
      greaterThan(before.value(P.shadows)),
    );
    expect(
      after.history.current!.label,
      contains('warmer and brighten the shadows a bit'),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await _screenshot(tester, '04_after_prompt');

    // Single undo reverts the instruction.
    ctl.undo();
    await tester.pump();
    expect(
      container.read(editorProvider(dark.assetId)).value!.settings,
      before,
    );
    ctl.redo();

    // No gateway running: the app says so and still edits on-device (DoD 26).
    expect(find.text('Basic auto (offline)'), findsWidgets);

    // Hold-to-compare shows the unedited photo with a BEFORE chip; side by side shows both (DoD 34).
    ctl.setShowingBefore(true);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('BEFORE'), findsOneWidget);
    ctl.setShowingBefore(false);
    ctl.setCompare(CompareMode.sideBySide);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('AFTER'), findsOneWidget);
    await _screenshot(tester, '05b_side_by_side');

    // Split compare renders.
    ctl.setCompare(CompareMode.split);
    await tester.pump(const Duration(milliseconds: 500));
    await _screenshot(tester, '05_compare_split');
    ctl.setCompare(CompareMode.off);

    // Crop mode.
    ctl.setCropMode(true);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _screenshot(tester, '06_crop');
    ctl.setCropMode(false);
    await ctl.flush();

    // Export full resolution through the real (GPU) export path.
    final service = container.read(exportServiceProvider);
    final exported = await tester.runAsync(
      () => service.exportOne(
        dark.assetId,
        const ExportOptions(format: ExportFormat.jpeg, quality: 90),
      ),
    );
    expect(exported!.width, 1600);
    final decoded = img.decodeJpg(exported.bytes);
    expect(decoded, isNotNull);
    expect(exported.fileName, 'dark_interior_edit.jpg');

    // Edits persist across a "restart" (fresh repository on the same folder).
    final reopened = await tester.runAsync(
      () => FileCatalogRepository(root.path).loadEdit(dark.assetId),
    );
    expect(reopened!.history.entries.length, greaterThanOrEqualTo(2));
  });
}
