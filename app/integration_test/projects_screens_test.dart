// Home, Projects and a project page on the real app at 1440×900, with
// generated photos only (drawn portraits and synthetic scenes). Saves
// screenshots for docs/verification/projects/ and checks the editor's
// filmstrip walks one project.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/data/file_preference_repositories_io.dart';
import 'package:lumen/features/cull/cull_providers.dart';
import 'package:lumen/features/cull/cull_store.dart';
import 'package:lumen/features/editor/editor_screen.dart';
import 'package:lumen/features/library/library_actions.dart';
import 'package:lumen/features/projects/project_page.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen/import/import_sources.dart';
import 'package:lumen_core/lumen_core.dart';

import 'support/import_flow.dart';
import 'support/sample_photos.dart';

class _FakeImportSource implements ImportSource {
  _FakeImportSource(this.files);
  final List<ImportFile> files;

  @override
  Future<List<ImportFile>> pick({required bool mobile}) async => files;
}

final _shotKey = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  // With semantics on (as in this test) snack bars wait for a tap.
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
    final dir = Directory('${Directory.systemTemp.path}/lumen_shots/projects')
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

CullRecord _faces(int n) => CullRecord(
  signalsKey: 'fixture',
  signals: CullSignals(
    sharpness: 0.4,
    highlightClip: 0,
    shadowClip: 0,
    meanLuma: 0.5,
    dHash: '0000000000000000',
    faces: [
      for (var i = 0; i < n; i++)
        FaceCullSignal(faceId: 'f$i', area: 0.05, sharpness: 0.5),
    ],
  ),
);

/// Imports [photos] into a new project and sets flags, edits, retouch and
/// exports so its progress reads like a real shoot.
Future<void> _shoot(
  FileCatalogRepository repo,
  MemoryCullStore cull, {
  required String name,
  required String prefix,
  required DateTime date,
  required List<Uint8List> photos,
  Set<int> picks = const {},
  Set<int> rejects = const {},
  Set<int> edited = const {},
  Set<int> retouched = const {},
  Set<int> exported = const {},
  Map<int, int> faces = const {},
}) async {
  final project = await repo.createProject(name: name, shootDate: date);
  final service = ImportService(repo);
  for (var i = 0; i < photos.length; i++) {
    final r = await service.importOne(
      ImportFile(name: '$prefix${4000 + i}.jpg', bytes: photos[i]),
      projectId: project.id,
    );
    final e = (r as Imported).entry;
    await repo.update(
      e.copyWith(
        flag: picks.contains(i)
            ? PhotoFlag.pick
            : rejects.contains(i)
            ? PhotoFlag.reject
            : PhotoFlag.none,
        hasEdits: edited.contains(i),
        retouched: retouched.contains(i),
        editedAt: edited.contains(i) ? date.add(const Duration(days: 1)) : null,
      ),
    );
    if (exported.contains(i)) {
      await repo.markExported([e.assetId], date.add(const Duration(days: 2)));
    }
    final n = faces[i];
    if (n != null) await cull.write(e.assetId, _faces(n));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home, Projects and a project page (screenshots)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = Directory.systemTemp.createTempSync('lumen_projects');
    addTearDown(() => root.deleteSync(recursive: true));
    final repo = FileCatalogRepository(root.path);
    final settings = FileSettingsRepository(root.path);
    // A display name, so Home greets by name; auto-edit off keeps the
    // fixture's edit state as set below.
    await tester.runAsync(
      () async => settings.save(
        (await settings.load()).copyWith(
          displayName: 'Ama',
          autoEditOnImport: false,
        ),
      ),
    );
    final cull = MemoryCullStore();
    final first = [
      samplePortraitJpeg(),
      groupPortraitJpeg(2),
      sceneJpeg(SceneId.goldenHourPortrait),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          presetRepositoryProvider.overrideWithValue(
            FilePresetRepository(root.path),
          ),
          settingsRepositoryProvider.overrideWithValue(settings),
          cullStoreProvider.overrideWith((ref) async => cull),
          importSourceProvider.overrideWithValue(
            _FakeImportSource([
              for (final (i, b) in first.indexed)
                ImportFile(name: 'DSC_01${i + 20}.jpg', bytes: b),
            ]),
          ),
        ],
        child: RepaintBoundary(key: _shotKey, child: const LumenApp()),
      ),
    );
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LumenApp)),
    );

    // 1. A brand-new library: one welcoming import card.
    expect(find.textContaining('developed.'), findsOneWidget);
    await _shot(tester, 'home_empty');

    // 2. Import asks where the photos go (name prefilled), then opens the
    //    new project.
    await tester.tap(find.text('Import').first);
    await pumpUntilFound(tester, find.text('Where should these go?'));
    await tester.pumpAndSettle();
    await _shot(tester, 'import_destination');
    await confirmImportDestination(tester, projectName: 'Headshots: Kojo');
    await pumpUntilFound(tester, find.byType(ProjectPage));
    final end = DateTime.now().add(const Duration(seconds: 60));
    while ((container.read(libraryProvider).value?.length ?? 0) < 3 ||
        container.read(importProgressProvider) != null) {
      if (DateTime.now().isAfter(end)) fail('import timed out');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    final kojo = container.read(libraryProvider).value!;
    expect(kojo.map((e) => e.projectId).toSet(), hasLength(1));
    expect(kojo.first.projectId, isNotNull);

    // 3. Two more shoots at different stages, plus Unsorted photos.
    await tester.runAsync(() async {
      await _shoot(
        repo,
        cull,
        name: 'Ama & Kofi wedding',
        prefix: 'AK_',
        date: DateTime(2026, 9, 27),
        photos: [
          groupPortraitJpeg(2, width: 1208),
          sceneJpeg(SceneId.goldenHourPortrait, longEdge: 1216),
          groupPortraitJpeg(1, width: 1000, height: 1250),
          sceneJpeg(SceneId.tungstenCast, longEdge: 1224),
          groupPortraitJpeg(3, width: 1232),
          sceneJpeg(SceneId.hazyLandscape, longEdge: 1240),
          sceneJpeg(SceneId.darkInterior, longEdge: 1248),
          groupPortraitJpeg(1, width: 1256),
        ],
        picks: {0, 1, 2, 4, 7},
        rejects: {3, 6},
        edited: {0, 1, 2, 4, 7},
        retouched: {0, 2},
        exported: {0},
        faces: {0: 2, 2: 1, 4: 3, 7: 1},
      );
      await _shoot(
        repo,
        cull,
        name: 'Mensah family',
        prefix: 'MF_',
        date: DateTime(2026, 10, 4),
        photos: [
          groupPortraitJpeg(3, width: 1264),
          sceneJpeg(SceneId.daylightCoolCast, longEdge: 1272),
          groupPortraitJpeg(2, width: 1280),
          sceneJpeg(SceneId.overexposedBeach, longEdge: 1288),
          groupPortraitJpeg(1, width: 1296),
        ],
        picks: {0, 2},
      );
      final service = ImportService(repo);
      await service.importOne(
        ImportFile(name: 'IMG_0001.jpg', bytes: sceneJpeg(SceneId.greenCast)),
      );
    });
    container.invalidate(cullRecordsProvider);
    container.read(shellLocationProvider.notifier).go(const HomeLocation());
    // Thumbnails decode, the import toast times out.
    await _settle(tester, 4500);
    expect(find.text('Welcome back, Ama'), findsOneWidget);
    expect(find.text('Active projects'), findsOneWidget);
    expect(find.text('Ama & Kofi wedding'), findsWidgets);
    await _shot(tester, 'home_projects');

    // 4. Projects page.
    await tester.tap(find.text('View all').first);
    await _settle(tester, 2000);
    expect(find.text('Search projects'), findsOneWidget);
    await _shot(tester, 'projects');

    // 5. A project page: breadcrumb, progress and the scoped grid.
    await tester.tap(find.text('Ama & Kofi wedding').first);
    await _settle(tester, 2500);
    expect(find.text('Export picks'), findsOneWidget);
    await _shot(tester, 'project_page');

    // 6. The editor walks only this project's photos.
    final wedding = container
        .read(libraryProvider)
        .value!
        .where((e) => e.fileName.startsWith('AK_'))
        .toList();
    final tile = find.bySemanticsLabel(RegExp(wedding.first.fileName)).first;
    await tester.tap(tile);
    await pumpUntilFound(tester, find.byType(EditorScreen));
    final editor = tester.widget<EditorScreen>(find.byType(EditorScreen));
    expect(editor.assetIds.toSet(), wedding.map((e) => e.assetId).toSet());
    await _settle(tester, 2000);
    await _shot(tester, 'editor_from_project');

    // 7. Tablet and phone layouts of Home and a project.
    Navigator.of(tester.element(find.byType(EditorScreen))).pop();
    await _settle(tester);
    for (final size in const [Size(768, 1024), Size(375, 812)]) {
      tester.view.physicalSize = size;
      container.read(shellLocationProvider.notifier).go(const HomeLocation());
      await _settle(tester, 1500);
      await _shot(tester, 'home_${size.width.toInt()}');
      container
          .read(shellLocationProvider.notifier)
          .go(ProjectLocation(wedding.first.projectId));
      await _settle(tester, 1500);
      await _shot(tester, 'project_page_${size.width.toInt()}');
    }
  });
}
