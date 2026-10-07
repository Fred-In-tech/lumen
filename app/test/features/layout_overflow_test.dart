import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/editor/editor_screen.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/editor/renderer/renderer_factory.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/features/masks/canvas/mask_canvas.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/remove/ai_remover.dart';
import 'package:lumen/features/remove/remove_canvas.dart';
import 'package:lumen/features/remove/remove_panel.dart';
import 'package:lumen/features/remove/remove_ui_state.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:lumen/features/home/home_screen.dart';
import 'package:lumen/features/shell/shell_location.dart';

import '../support/project_fixtures.dart';

List<Override> _overrides() => [
  catalogRepositoryProvider.overrideWithValue(MemoryCatalogRepository()),
  presetRepositoryProvider.overrideWithValue(MemoryPresetRepository()),
  settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()),
];

/// Shows a fixed image; renders nothing (layout only).
class _StillRenderer implements PhotoRenderer {
  _StillRenderer(this.image);

  final ui.Image image;
  final ValueNotifier<ui.Image?> _out = ValueNotifier(null);

  @override
  ValueListenable<ui.Image?> get output => _out;

  @override
  ui.Image? get before => image;

  @override
  RgbaBuffer? get analysisProxy => null;

  @override
  Future<void> open(Uint8List original) async => _out.value = image;

  @override
  void update(DevelopSettings settings, {bool interactive = false}) {}

  @override
  Future<Uint8List> renderThumbnail(
    DevelopSettings settings, {
    int longEdge = 384,
  }) async => throw Exception('no thumbnails in layout tests');

  @override
  void dispose() => _out.dispose();
}

/// The AI remover was never downloaded here.
class _NoAiRemover implements AiRemoverLoader {
  @override
  int get downloadBytes => 16312640;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<InpaintModel> load({
    required void Function(double? fraction) onProgress,
    CancelToken? cancel,
  }) => Future.error(const InferenceUnavailable('no runtime in tests'));
}

/// Opens the editor on photo 'a' and switches to the module whose phone
/// tab is [tab] (desktop/tablet: its shortcut [key]).
Future<void> _openEditor(
  WidgetTester tester,
  Size size, {
  String tab = 'Masks',
  LogicalKeyboardKey key = LogicalKeyboardKey.keyM,
}) async {
  final img = (await tester.runAsync(
    () => createTestImage(width: 300, height: 200),
  ))!;
  final repo = MemoryCatalogRepository();
  await repo.add(
    CatalogEntry(
      assetId: 'a',
      fileName: 'a.jpg',
      originalPath: 'originals/a.jpg',
      format: 'jpeg',
      width: 300,
      height: 200,
      bytes: 1,
      importedAt: DateTime.utc(2026),
    ),
    Uint8List(1),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        presetRepositoryProvider.overrideWithValue(MemoryPresetRepository()),
        settingsRepositoryProvider.overrideWithValue(
          MemorySettingsRepository(),
        ),
        photoRendererFactoryProvider.overrideWithValue(
          (_) => _StillRenderer(img),
        ),
        gatewayStatusProvider.overrideWithValue(
          const AsyncData(
            GatewayStatus(url: '', reachable: false, visionAvailable: false),
          ),
        ),
        // No face models or model store in widget tests.
        portraitFacesStatusProvider.overrideWith(
          (ref, assetId) => const AsyncData(null),
        ),
        aiRemoverLoaderProvider.overrideWithValue(_NoAiRemover()),
      ],
      child: MaterialApp(
        theme: buildLumenTheme(),
        home: const EditorScreen(assetIds: ['a'], initialAssetId: 'a'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (size.width < 600) {
    // Phone: Manual mode, then the module's tool tab.
    await tester.tap(find.bySemanticsLabel('Manual mode'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text(tab),
      // The tool tabs: the last horizontal list on the phone editor.
      find
          .byWidgetPredicate(
            (w) => w is ListView && w.scrollDirection == Axis.horizontal,
          )
          .last,
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab));
  } else {
    // Desktop/tablet: the module shortcut.
    await tester.sendKeyEvent(key);
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [Size(375, 812), Size(768, 1024), Size(1440, 900)]) {
    testWidgets(
      'no overflow at ${size.width.toInt()}×${size.height.toInt()}: editor Masks module',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _openEditor(tester, size);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(EditorScreen)),
        );
        expect(container.read(editorModuleProvider('a')), EditorModule.masks);
        expect(find.byType(MaskCanvas), findsOneWidget);
        for (final kind in ['Linear gradient', 'Radial gradient', 'Brush']) {
          await tester.ensureVisible(find.text('Add mask'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Add mask'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(kind));
          await tester.pumpAndSettle();
        }
        final masks = container.read(editorProvider('a')).value!.settings.masks;
        expect(masks, hasLength(3));
        expect(find.text('Editing: Brush 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Let the debounced save and thumbnail timers run out.
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }

  for (final size in const [Size(375, 812), Size(768, 1024), Size(1440, 900)]) {
    testWidgets(
      'no overflow at ${size.width.toInt()}×${size.height.toInt()}: editor Remove module',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _openEditor(
          tester,
          size,
          tab: 'Remove',
          key: LogicalKeyboardKey.keyQ,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(EditorScreen)),
        );
        expect(container.read(editorModuleProvider('a')), EditorModule.remove);
        expect(find.byType(RemoveCanvas), findsOneWidget);
        expect(find.byType(RemovePanel), findsOneWidget);
        expect(find.text(RemovePanel.emptyHint), findsOneWidget);
        expect(find.text('AI fill'), findsOneWidget);
        for (final tool in ['Heal', 'Clone']) {
          await tester.ensureVisible(find.text(tool).last);
          await tester.pumpAndSettle();
          await tester.tap(find.text(tool).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: tool);
        }
        expect(container.read(removeUiProvider('a')).tool, RemoveTool.clone);
        await tester.ensureVisible(find.text('Set source'));
        await tester.tap(find.text('Set source'));
        await tester.pumpAndSettle();
        expect(find.text('Tap the photo to choose the source'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }

  for (final size in const [Size(375, 812), Size(768, 1024), Size(1440, 900)]) {
    testWidgets(
      'no overflow at ${size.width.toInt()}×${size.height.toInt()}: library + export dialog',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(overrides: _overrides(), child: const LumenApp()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          ProviderScope(
            overrides: _overrides(),
            child: MaterialApp(
              theme: buildLumenTheme(),
              home: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () =>
                          showExportDialog(context, ref, ['a', 'b']),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Export 2 photos'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in const [Size(375, 812), Size(768, 1024), Size(1440, 900)]) {
    testWidgets(
      'no overflow at ${size.width.toInt()}×${size.height.toInt()}: Home, '
      'Projects, a project, All photos, Looks',
      (tester) async {
        final empty = MemoryCatalogRepository();
        await pumpApp(tester, empty, size: size);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'empty Home');

        final (repo, wedding, _) = await twoProjectLibrary();
        final c = await pumpApp(tester, repo, size: size);
        expect(find.text('Active projects'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Home');
        // Phones get a bottom tab bar and no rail.
        final phone = size.width < 600;
        expect(find.text('All photos'), phone ? findsNothing : findsWidgets);

        for (final (name, to) in <(String, ShellLocation)>[
          ('Projects', const ProjectsLocation()),
          ('project', ProjectLocation(wedding)),
          ('Unsorted', const ProjectLocation(null)),
          ('All photos', const AllPhotosLocation()),
          ('Looks', const LooksLocation()),
        ]) {
          c.read(shellLocationProvider.notifier).go(to);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: name);
        }
        c.read(shellLocationProvider.notifier).go(ProjectLocation(wedding));
        await tester.pumpAndSettle();
        c.read(selectionProvider.notifier).selectAll(['w1', 'w2']);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'batch bar');
      },
    );
  }
}
