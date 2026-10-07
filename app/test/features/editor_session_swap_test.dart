import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/fixtures.dart';

/// A RAW opened on its rendition gets its float preview later
/// (docs/HIGH_BIT_DEPTH.md, "Preview cache"): the session drops what it
/// derived from the old source and tells the editor.

class _Swapping implements PhotoRenderer, ProgressiveSource {
  final CpuPhotoRenderer inner = CpuPhotoRenderer();
  final ValueNotifier<int> version = ValueNotifier(0);
  RgbaBuffer? proxy;

  @override
  ValueListenable<int> get sourceVersion => version;
  @override
  Future<void> whenSourceSettled() async {}
  @override
  ValueListenable<ui.Image?> get output => inner.output;
  @override
  ui.Image? get before => inner.before;
  @override
  RgbaBuffer? get analysisProxy => proxy ?? inner.analysisProxy;
  @override
  Future<void> open(Uint8List original) => inner.open(original);
  @override
  void update(DevelopSettings settings, {bool interactive = false}) =>
      inner.update(settings, interactive: interactive);
  @override
  Future<Uint8List> renderThumbnail(
    DevelopSettings settings, {
    int longEdge = 384,
  }) => inner.renderThumbnail(settings, longEdge: longEdge);
  @override
  void dispose() => inner.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a source swap refreshes stats and notifies the editor', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repo = MemoryCatalogRepository();
      final r = await ImportService(repo).importOne(
        ImportFile(name: 'a.jpg', bytes: Fixtures.jpeg(w: 64, h: 48)),
      );
      final renderer = _Swapping();
      final session = EditorSession(
        assetId: (r as Imported).entry.assetId,
        renderer: renderer,
        repo: repo,
      );
      await session.open();
      final first = await session.stats();
      expect(identical(await session.stats(), first), isTrue, reason: 'cached');
      var told = 0;
      session.sourceVersion.addListener(() => told++);
      renderer.proxy = RgbaBuffer.filled(32, 24, 250, 250, 250);
      renderer.version.value++;
      expect(told, 1);
      final second = await session.stats();
      expect(identical(second, first), isFalse);
      session.dispose();
      // Disposed: later swaps are ignored.
      renderer.version.value++;
      expect(told, 1);
    });
  });
}
