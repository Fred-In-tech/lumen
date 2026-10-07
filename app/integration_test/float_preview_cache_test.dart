// Opening RAW photos fast (docs/HIGH_BIT_DEPTH.md, "Preview cache"), on
// the real app stack with a real camera RAW. Skipped unless
// LUMEN_RAW_SAMPLE points at one the app can read (the macOS app is
// sandboxed: put the file inside its container first). No RAW file is
// stored in the repository.
//
//   flutter test integration_test/float_preview_cache_test.dart -d macos \
//     --dart-define=LUMEN_RAW_SAMPLE=<path inside the app container>
//
// Measures the cold first open (rendition first, float preview swapped
// in), the cached open, the filmstrip step with prefetch, the cache entry
// size, the background build after import and the cache's precision.
// Every measurement is printed as a line starting with "RESULT ".
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/renderer_factory.dart';
import 'package:lumen/import/float_decoder.dart';
import 'package:lumen/import/float_preview_cache_io.dart';
import 'package:lumen/import/float_preview_store.dart';
import 'package:lumen/import/float_sources.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen/import/photo_decoder.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

const _samplePath = String.fromEnvironment('LUMEN_RAW_SAMPLE');

void _r(String line) => debugPrint('RESULT $line');

bool get _apple =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Waits until the GPU has finished [image] (a 1-pixel readback).
Future<void> _finish(ui.Image image) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    const ui.Rect.fromLTWH(0, 0, 1, 1),
    ui.Paint(),
  );
  final picture = recorder.endRecording();
  final one = await picture.toImage(1, 1);
  await one.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  one.dispose();
}

/// The first frame [r] publishes after [s], on the GPU.
Future<ui.Image> _nextFrame(GpuPhotoRenderer r, DevelopSettings s) async {
  final previous = r.output.value;
  final done = Completer<ui.Image>();
  void listener() {
    final v = r.output.value;
    if (v != null && !identical(v, previous) && !done.isCompleted) {
      done.complete(v);
    }
  }

  r.output.addListener(listener);
  r.update(s);
  final image = await done.future.timeout(const Duration(seconds: 60));
  r.output.removeListener(listener);
  await _finish(image);
  return image;
}

/// Open → first frame on screen, and → float frame on screen.
Future<({int first, int float, bool floatAtOnce, GpuPhotoRenderer r})> _open(
  ProviderContainer c,
  String id,
  Uint8List bytes,
) async {
  final sw = Stopwatch()..start();
  final r = c.read(photoRendererFactoryProvider)(id) as GpuPhotoRenderer;
  await r.open(bytes);
  final atOnce = r.usingFloat;
  await _nextFrame(r, DevelopSettings.defaults);
  final first = sw.elapsedMilliseconds;
  if (atOnce) return (first: first, float: first, floatAtOnce: true, r: r);
  await r.whenSourceSettled();
  expect(r.usingFloat, isTrue, reason: 'the float preview never arrived');
  await _nextFrame(r, DevelopSettings.defaults);
  return (
    first: first,
    float: sw.elapsedMilliseconds,
    floatAtOnce: false,
    r: r,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'RAW opens from the float preview cache: rendition first, float '
    'without a jump, instant when cached or prefetched',
    () async {
      final name = p.basename(_samplePath);
      final raw = File(_samplePath).readAsBytesSync();
      final root = Directory.systemTemp.createTempSync('lumen_fpc_raw');
      addTearDown(() => root.deleteSync(recursive: true));
      final catalog = FileCatalogRepository(p.join(root.path, 'catalog'));
      final cacheDir = p.join(root.path, 'float_previews');
      final cache = FileFloatPreviewCache(() async => cacheDir);
      final c = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(catalog),
          floatPreviewCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(c.dispose);
      final store = c.read(floatPreviewStoreProvider);
      final longEdge = c.read(previewLongEdgeProvider);

      // ---- Import: unchanged, then the background build of the preview ----
      var sw = Stopwatch()..start();
      final imported = await c
          .read(importServiceProvider)
          .importOne(ImportFile(name: name, bytes: raw));
      final entry = (imported as Imported).entry;
      final id = entry.assetId;
      final importMs = sw.elapsedMilliseconds;
      final preview = decodedSizeFor(entry.width, entry.height, longEdge);
      _r(
        'import $importMs ms (${entry.width}x${entry.height}, preview '
        '${preview.width}x${preview.height})',
      );
      final bytes = await catalog.readPixelSource(id);
      final probe = GpuPhotoRenderer(assetId: id);
      await probe.open(bytes);
      expect(await HbdCapability.available(), isTrue);
      probe.dispose();

      // ---- Cold first open: nothing cached ----
      await Future<void>.delayed(const Duration(seconds: 5)); // import settles
      final cold = await _open(c, id, bytes);
      expect(cold.floatAtOnce, isFalse);
      _r(
        'cold first open: first frame (rendition) ${cold.first} ms, float '
        'frame ${cold.float} ms (swap ${cold.r.floatSwapDelay?.inMilliseconds} '
        'ms after open)',
      );
      // No visible jump: the rendition's default frame against the float
      // preview's (also what `before` shows).
      final b8 = await rgbaFromImage(
        await (() async {
          final r8 = GpuPhotoRenderer(assetId: id);
          await r8.open(bytes);
          final f = await _nextFrame(r8, DevelopSettings.defaults);
          final copy = f.clone();
          r8.dispose();
          return copy;
        })(),
      );
      final bf = await rgbaFromImage(cold.r.before!);
      var sum = 0, big = 0;
      for (var i = 0; i < bf.data.length; i += 4) {
        for (var k = 0; k < 3; k++) {
          final d = (bf.data[i + k] - b8.data[i + k]).abs();
          sum += d;
          if (d > 8) big++;
        }
      }
      final channels = bf.data.length * 3 ~/ 4;
      _r(
        'tone at the swap: mean |d| '
        '${(sum / channels).toStringAsFixed(2)}/255, '
        '${(100 * big / channels).toStringAsFixed(2)} % of channels > 8',
      );
      expect(sum / channels, lessThan(2.5));
      cold.r.dispose();

      // ---- The cache entry ----
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final entryPath = (await cache.pathFor(
        id,
        preview.width,
        preview.height,
      ))!;
      expect(File(entryPath).existsSync(), isTrue);
      final entryBytes = File(entryPath).lengthSync();
      _r(
        'cache entry ${(entryBytes / (1 << 20)).toStringAsFixed(1)} MB per '
        'photo (${preview.width}x${preview.height} half-float RGB, LZ4); '
        '2 GB cap ≈ ${(2 * 1024 * (1 << 20) / entryBytes).floor()} photos',
      );

      // Precision of the cache against a fresh decode at the same size.
      const decoder = PlatformFloatDecoder();
      final origPath = (await catalog.originalFilePath(id))!;
      sw = Stopwatch()..start();
      final read = (await decoder.readPreview(
        entryPath,
        width: preview.width,
        height: preview.height,
      ))!;
      final readMs = sw.elapsedMilliseconds;
      final fresh = await decoder.render(
        origPath,
        fullWidth: preview.width,
        fullHeight: preview.height,
        x: 0,
        y: 0,
        width: preview.width,
        height: preview.height,
      );
      await decoder.release(origPath);
      var worst = 0.0, worstRel = 0.0;
      for (var i = 0; i < fresh.rgba.length; i++) {
        final d = (fresh.rgba[i] - read.pixels.rgba[i]).abs();
        worst = math.max(worst, d);
        worstRel = math.max(worstRel, d / math.max(1e-3, fresh.rgba[i].abs()));
      }
      _r(
        'cache read (native: file, LZ4, half → float) ${read.pixels.decodeMs} '
        'ms, with the hand-over $readMs ms; max error vs a fresh decode '
        '${worst.toStringAsFixed(5)} (${(worst * 255).toStringAsFixed(2)}/255),'
        ' relative ${(worstRel * 100).toStringAsFixed(3)} %',
      );
      expect(worst * 255, lessThan(0.6));

      // ---- Cached open: a new session, memory dropped ----
      final cachedRuns = <int>[];
      for (var i = 0; i < 3; i++) {
        store.clearMemory();
        final o = await _open(c, id, bytes);
        expect(o.floatAtOnce, isTrue);
        cachedRuns.add(o.float);
        o.r.dispose();
      }
      _r('cached open (disk), float frame on screen: $cachedRuns ms');
      expect(cachedRuns.reduce(math.min), lessThan(300));

      // ---- Filmstrip step with prefetch (the neighbour is in memory) ----
      store.clearMemory();
      sw = Stopwatch()..start();
      await c.read(floatSourcesProvider).prefetch([
        id,
      ], previewLongEdge: longEdge);
      await store.idle();
      final prefetchMs = sw.elapsedMilliseconds;
      final stepRuns = <int>[];
      for (var i = 0; i < 3; i++) {
        final o = await _open(c, id, bytes);
        expect(o.floatAtOnce, isTrue);
        stepRuns.add(o.float);
        o.r.dispose();
      }
      _r(
        'filmstrip step, neighbour prefetched ($prefetchMs ms in the '
        'background): float frame on screen $stepRuns ms',
      );

      // ---- Background build (after import / idle), and its variance ----
      final builds = <int>[];
      for (var i = 0; i < 3; i++) {
        await cache.remove(id);
        store.clearMemory();
        sw = Stopwatch()..start();
        await c.read(floatSourcesProvider).warm([
          id,
        ], previewLongEdge: longEdge);
        await store.idle();
        builds.add(sw.elapsedMilliseconds);
        expect(File(entryPath).existsSync(), isTrue);
      }
      _r('background build of one preview (utility priority): $builds ms');

      // ---- Fresh decodes in a row (the variance the doc reported) ----
      final decodes = <String>[];
      for (var i = 0; i < 4; i++) {
        final px = await decoder.render(
          origPath,
          fullWidth: preview.width,
          fullHeight: preview.height,
          x: 0,
          y: 0,
          width: preview.width,
          height: preview.height,
        );
        await decoder.release(origPath);
        decodes.add('${px.decodeMs}');
      }
      _r('fresh preview decodes in a row (decoder ms): $decodes');
      _r(
        'cache folder ${(await cache.sizeInBytes() / (1 << 20)).toStringAsFixed(1)} MB',
      );
    },
    skip: !_apple || _samplePath.isEmpty
        ? 'needs macOS / iOS and --dart-define=LUMEN_RAW_SAMPLE=<raw file>'
        : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test('a store without a cache folder still opens (no-op cache)', () async {
    final store = FloatPreviewStore(
      decoder: const PlatformFloatDecoder(),
      cache: FileFloatPreviewCache(
        () async => throw const FileSystemException('none'),
      ),
    );
    addTearDown(store.dispose);
    expect(await store.cached('a', 1, 1), isNull);
  }, skip: !_apple);
}
