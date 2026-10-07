// Screenshots of Looks & presets rendered by the headless tester, for when
// no display is available to the on-device run
// (integration_test/looks_screens_test.dart is the real-window version).
// Uses the bundled CC0 samples and generated preset files only; the Mac's
// Arial / Georgia stand in for the app fonts.
//
//   flutter test test/screenshots/looks_screenshots_test.dart \
//     --dart-define=LUMEN_SHOTS=<output folder>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/lut_repository.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/features/cull/cull_providers.dart';
import 'package:lumen/features/cull/cull_store.dart';
import 'package:lumen/features/home/looks_page.dart';
import 'package:lumen/features/looks/look_import_flow.dart';
import 'package:lumen/features/looks/look_import_service.dart';
import 'package:lumen/features/looks/look_previews.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/look_files.dart';

const _out = String.fromEnvironment('LUMEN_SHOTS');
final _key = GlobalKey();

class _Looks implements LookImportSource {
  @override
  Future<List<LookImportFile>> pick() async => fixtureLookFiles();
}

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Future<void> _wait(WidgetTester tester, LookPreviewService s, int n) async {
  for (var i = 0; i < 400 && s.renders < n; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  // Let Image.memory decode what arrived.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _frames(tester);
  await tester.runAsync(() async {
    final b = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await b.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('Looks & presets screenshots', (tester) async {
    await tester.runAsync(() async {
      const sup = '/System/Library/Fonts/Supplemental';
      await _font('Geist', ['$sup/Arial.ttf', '$sup/Arial Bold.ttf']);
      await _font('InstrumentSerif', ['$sup/Georgia.ttf']);
      final lucide = await rootBundle.load(
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      );
      await (FontLoader(
        'packages/lucide_icons_flutter/Lucide',
      )..addFont(Future.value(lucide))).load();
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(CreativeLuts.reset);
    final repo = MemoryCatalogRepository();
    final previews = LookPreviewService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          presetRepositoryProvider.overrideWithValue(MemoryPresetRepository()),
          lutRepositoryProvider.overrideWithValue(MemoryLutRepository()),
          settingsRepositoryProvider.overrideWithValue(
            MemorySettingsRepository(),
          ),
          cullStoreProvider.overrideWith((ref) async => MemoryCullStore()),
          lookImportSourceProvider.overrideWithValue(_Looks()),
          lookPreviewServiceProvider.overrideWithValue(previews),
        ],
        child: RepaintBoundary(key: _key, child: const LumenApp()),
      ),
    );
    await tester.pump();
    final c = ProviderScope.containerOf(tester.element(find.byType(LumenApp)));

    // 1. Home, empty library: the looks row on the bundled samples.
    await tester.ensureVisible(find.text('Looks & presets'));
    await _wait(tester, previews, 6);
    await _shot(tester, 'home_looks_samples');

    // 2. Import: the summary.
    await tester.tap(find.text('Import presets & LUTs'));
    for (var i = 0; i < 100 && c.read(lastLookImportProvider) == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, 'import_summary');
    await tester.tap(find.text('Done'));
    // Let the "Reading…" toast time out.
    await _frames(tester);
    await tester.pump(const Duration(seconds: 6));
    await _frames(tester);

    // 3. The Looks page.
    c.read(shellLocationProvider.notifier).go(const LooksLocation());
    await _frames(tester);
    expect(find.byType(LooksPage), findsOneWidget);
    await _wait(tester, previews, 14);
    await _shot(tester, 'looks_page');

    // 4. A project: every card shows its cover.
    await tester.runAsync(() async {
      final project = await repo.createProject(name: 'Ama & Kofi wedding');
      final service = ImportService(repo);
      for (final s in [SamplePhoto.weddingCouple, SamplePhoto.portraitPink]) {
        final bytes = (await rootBundle.load(s.asset)).buffer.asUint8List();
        await service.importOne(
          ImportFile(name: s.file, bytes: bytes),
          projectId: project.id,
        );
      }
      final cover = (await repo.list()).firstWhere(
        (e) => e.fileName == SamplePhoto.portraitPink.file,
      );
      await repo.updateProject(project.copyWith(coverAssetId: cover.assetId));
    });
    c.read(shellLocationProvider.notifier).go(const HomeLocation());
    await _frames(tester);
    await tester.ensureVisible(find.text('Looks & presets'));
    await _wait(tester, previews, 26);
    await _shot(tester, 'home_looks_project_cover');
  }, skip: _out.isEmpty);
}
