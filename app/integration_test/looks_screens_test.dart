// Looks & presets on the real app at 1440×900: import of Lightroom presets
// and a LUT, the summary, the Looks page, Home's looks row on the bundled
// CC0 samples (empty library) and on a project cover, and the editor's
// Presets tab with a LUT applied. Screenshots go to
// <tmp>/lumen_shots/looks/ (docs/verification/looks/). Only bundled CC0
// samples and generated files are used.
//
//   flutter test integration_test/looks_screens_test.dart -d macos
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/data/file_lut_repository_io.dart';
import 'package:lumen/data/file_preference_repositories_io.dart';
import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/features/cull/cull_providers.dart';
import 'package:lumen/features/cull/cull_store.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_mode.dart';
import 'package:lumen/features/editor/editor_screen.dart';
import 'package:lumen/features/editor/open_editor.dart';
import 'package:lumen/features/home/looks_page.dart';
import 'package:lumen/features/looks/look_import_flow.dart';
import 'package:lumen/features/looks/look_import_service.dart';
import 'package:lumen/features/looks/look_previews.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

import '../test/support/look_files.dart';
import 'support/import_flow.dart';

class _FakeLooks implements LookImportSource {
  @override
  Future<List<LookImportFile>> pick() async => fixtureLookFiles();
}

final _shotKey = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  for (final m in tester.stateList<ScaffoldMessengerState>(
    find.byType(ScaffoldMessenger),
  )) {
    m.removeCurrentSnackBar();
  }
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final dir = Directory('${Directory.systemTemp.path}/lumen_shots/looks')
      ..createSync(recursive: true);
    final f = File('${dir.path}/$name.png')
      ..writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('SCREENSHOT ${f.path}');
  });
}

Future<void> _settle(WidgetTester tester, [int ms = 800]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pumpAndSettle();
}

/// Waits until the preview service has rendered at least [n] looks.
Future<void> _previews(WidgetTester tester, LookPreviewService s, int n) async {
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (s.renders < n && DateTime.now().isBefore(end)) {
    await _settle(tester, 300);
  }
  await _settle(tester, 600);
  debugPrint(
    'RESULT previews: ${s.renders} renders, '
    '${s.renders == 0 ? 0 : s.renderTime.inMilliseconds ~/ s.renders} ms '
    'each on average (CPU twin in an isolate, two at a time)',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Looks & presets: import, summary, samples (screenshots)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(CreativeLuts.reset);
    final root = Directory.systemTemp.createTempSync('lumen_looks');
    addTearDown(() => root.deleteSync(recursive: true));
    final repo = FileCatalogRepository(root.path);
    final luts = FileLutRepository(root.path);
    CreativeLuts.configure(luts.load);
    final settings = FileSettingsRepository(root.path);
    await tester.runAsync(
      () async => settings.save(
        (await settings.load()).copyWith(
          displayName: 'Ama',
          autoEditOnImport: false,
        ),
      ),
    );
    final previews = LookPreviewService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          presetRepositoryProvider.overrideWithValue(
            FilePresetRepository(root.path),
          ),
          lutRepositoryProvider.overrideWithValue(luts),
          settingsRepositoryProvider.overrideWithValue(settings),
          cullStoreProvider.overrideWith((ref) async => MemoryCullStore()),
          lookImportSourceProvider.overrideWithValue(_FakeLooks()),
          lookPreviewServiceProvider.overrideWithValue(previews),
        ],
        child: RepaintBoundary(key: _shotKey, child: const LumenApp()),
      ),
    );
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LumenApp)),
    );

    // 1. Empty library: Home's looks row on the bundled samples.
    await tester.ensureVisible(find.text('Import presets & LUTs'));
    await _previews(tester, previews, 9);
    await _shot(tester, 'home_looks_samples');

    // 2. Import three Lightroom presets and a LUT: the summary.
    await tester.tap(find.text('Import presets & LUTs'));
    await tester.pump();
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (container.read(lastLookImportProvider) == null &&
        DateTime.now().isBefore(end)) {
      await _settle(tester, 200);
    }
    await pumpUntilFound(tester, find.byType(LookImportSummary));
    expect(find.textContaining('3 presets imported'), findsOneWidget);
    await _shot(tester, 'import_summary');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // 3. The Looks page: imported looks on samples, grouped.
    container.read(shellLocationProvider.notifier).go(const LooksLocation());
    await pumpUntilFound(tester, find.byType(LooksPage));
    await _previews(tester, previews, 13);
    expect(find.text('LUT: Teal & Orange'), findsOneWidget);
    await _shot(tester, 'looks_page');

    // 4. A shoot in the library: every card shows the project's cover.
    final photos = <String, Uint8List>{};
    await tester.runAsync(() async {
      for (final s in SamplePhoto.values) {
        photos[s.file] = (await rootBundle.load(s.asset)).buffer.asUint8List();
      }
      final project = await repo.createProject(
        name: 'Ama & Kofi wedding',
        shootDate: DateTime(2026, 9, 27),
      );
      final service = ImportService(repo);
      for (final name in [
        'portrait_moody.jpg',
        'wedding_couple.jpg',
        'portrait_pink.jpg',
      ]) {
        await service.importOne(
          ImportFile(name: name, bytes: photos[name]!),
          projectId: project.id,
        );
      }
      final cover = (await repo.list()).firstWhere(
        (e) => e.fileName == 'portrait_pink.jpg',
      );
      await repo.updateProject(project.copyWith(coverAssetId: cover.assetId));
    });
    container.read(shellLocationProvider.notifier).go(const HomeLocation());
    await _settle(tester, 2500);
    await tester.ensureVisible(find.text('Import presets & LUTs'));
    await _previews(tester, previews, 26);
    await _shot(tester, 'home_looks_project_cover');

    // Hold to compare: the before.
    final sample = find.text('LUT: Teal & Orange');
    await tester.ensureVisible(sample);
    await tester.pumpAndSettle();
    final at = tester.getCenter(sample) - const Offset(0, 90);
    final gesture = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(tester, 'home_looks_hold_to_compare');
    await gesture.up();
    await tester.pumpAndSettle();

    // 5. The editor's Presets tab on the photo, with the LUT applied.
    final entry = container
        .read(libraryProvider)
        .value!
        .firstWhere((e) => e.fileName == 'portrait_pink.jpg');
    final lutPreset = (await container.read(userPresetsProvider.future))
        .firstWhere((p) => p.isLutOnly);
    container.read(presetsOpenProvider(entry.assetId).notifier).set(true);
    unawaitedOpen(tester, container, entry.assetId);
    await pumpUntilFound(tester, find.byType(EditorScreen));
    await _settle(tester, 3000);
    container
        .read(editorProvider(entry.assetId).notifier)
        .applyPreset(lutPreset);
    await _previews(tester, previews, 30);
    await _settle(tester, 2000);
    expect(find.text('LUT: Teal & Orange'), findsWidgets);
    await _shot(tester, 'editor_presets_lut');
  });
}

/// Opens the editor on [assetId] in Manual mode (not awaited: the route
/// stays open).
void unawaitedOpen(
  WidgetTester tester,
  ProviderContainer container,
  String assetId,
) {
  container.read(editorModeProvider.notifier).select(EditorMode.manual);
  final element = tester.element(find.byType(Scaffold).first);
  // ignore: discarded_futures
  openEditor(element, [assetId], assetId);
}
