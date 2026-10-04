import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_screen.dart';
import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/editor/renderer/renderer_factory.dart';
import 'package:lumen/features/masks/ai_mask_rasters.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/masks/mask_commands.dart';
import 'package:lumen_core/lumen_core.dart';

const _ref = 'people.selfie_multiclass_256-1';

/// Records the rasters the editor pushes; renders a fixed image.
class _RecordingRenderer implements PhotoRenderer, MaskRasterSink {
  _RecordingRenderer(this.image);

  final ui.Image image;
  final ValueNotifier<ui.Image?> _out = ValueNotifier(null);
  final List<Map<String, MaskRaster>> pushed = [];

  @override
  void setMaskRasters(Map<String, MaskRaster> rasters) => pushed.add(rasters);

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
  }) async => throw Exception('no thumbnails here');

  @override
  void dispose() => _out.dispose();
}

class _Loader implements AiMaskRasterLoader {
  final List<String> loads = [];

  @override
  Future<MaskRaster?> load(String assetId, String maskRef) async {
    loads.add(maskRef);
    return maskRef == _ref
        ? MaskRaster(2, 1, Uint8List.fromList([0, 255]))
        : null;
  }
}

LocalMask _aiMask(String ref) => LocalMask(
  id: 'm1',
  name: 'Subject 1',
  kind: MaskKind.subject,
  shape: AiShape(maskRef: ref, model: 'x', modelVersion: '1').toJson(),
  adjustments: const {P.exposure: 2},
);

void main() {
  test('aiMaskRefsKey is sorted, unique and ignores non-AI masks', () {
    expect(aiMaskRefsKey(null), '');
    expect(
      aiMaskRefsKey([
        _aiMask('b'),
        _aiMask('a'),
        _aiMask('b'),
        const LocalMask(id: 'l', name: 'L', kind: MaskKind.linear),
      ]),
      'a\nb',
    );
  });

  testWidgets('the editor pushes AI mask rasters to the renderer', (
    tester,
  ) async {
    // Phone layout: its module tabs scroll, so the test does not depend on
    // the desktop tab row width.
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final image = (await tester.runAsync(
      () => createTestImage(width: 300, height: 200),
    ))!;
    final renderer = _RecordingRenderer(image);
    final loader = _Loader();
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
    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        presetRepositoryProvider.overrideWithValue(MemoryPresetRepository()),
        settingsRepositoryProvider.overrideWithValue(
          MemorySettingsRepository(),
        ),
        photoRendererFactoryProvider.overrideWithValue((_) => renderer),
        aiMaskRasterLoaderProvider.overrideWithValue(loader),
        gatewayStatusProvider.overrideWithValue(
          const AsyncData(
            GatewayStatus(url: '', reachable: false, visionAvailable: false),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildLumenTheme(),
          home: const EditorScreen(assetIds: ['a'], initialAssetId: 'a'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(renderer.pushed.every((m) => m.isEmpty), isTrue);

    MaskCommands(container.read, 'a').add(
      MaskKind.subject,
      sourceSize: const Size(300, 200),
      ai: const AiShape(maskRef: _ref, model: 'm', modelVersion: '1'),
    );
    await tester.pumpAndSettle();

    expect(loader.loads, [_ref]);
    expect(renderer.pushed.last.keys, [_ref]);
    expect(renderer.pushed.last[_ref]!.data, [0, 255]);

    // Undo removes the AI mask: the renderer gets an empty map again.
    container.read(editorProvider('a').notifier).undo();
    await tester.pumpAndSettle();
    expect(renderer.pushed.last, isEmpty);
    await container.read(editorProvider('a').notifier).flush();
    await tester.pumpAndSettle();
  });

  test('CpuPhotoRenderer applies AI mask rasters it is given', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final gray = img.Image(width: 32, height: 24)
      ..clear(img.ColorRgb8(90, 90, 90));
    final renderer = CpuPhotoRenderer(
      previewLongEdge: 32,
      interactiveLongEdge: 32,
    );
    addTearDown(renderer.dispose);
    await renderer.open(img.encodePng(gray));

    Future<double> nextMean() async {
      final c = Completer<ui.Image>();
      void listener() {
        final v = renderer.output.value;
        if (v != null && !c.isCompleted) c.complete(v);
      }

      renderer.output.addListener(listener);
      final frame = await c.future.timeout(const Duration(seconds: 20));
      renderer.output.removeListener(listener);
      final px = await rgbaFromImage(frame);
      var sum = 0;
      for (var i = 0; i < px.data.length; i += 4) {
        sum += px.data[i];
      }
      return sum / px.pixelCount;
    }

    final settings = DevelopSettings.defaults.copyWith(masks: [_aiMask(_ref)]);
    var frame = nextMean();
    renderer.update(settings);
    final without = await frame;
    frame = nextMean();
    renderer.setMaskRasters({
      _ref: MaskRaster(4, 3, Uint8List(12)..fillRange(0, 12, 255)),
    });
    final withMask = await frame;
    expect(withMask, greaterThan(without + 20), reason: '$without → $withMask');
  });
}
