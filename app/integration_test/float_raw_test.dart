// High-bit-depth sources on the real app stack (macOS / iOS): import →
// native float decode (`lumen/raw` floatInfo / floatRender) → the editor's
// renderer on the float path → export from source windows.
//
// 1. A generated 16-bit PNG (always runs on Apple platforms).
// 2. A real camera RAW, skipped unless LUMEN_RAW_SAMPLE points at one the
//    app can read (the macOS app is sandboxed: put the file inside its
//    container first). It proves highlight recovery on real data against
//    the 8-bit rendition path, and times open, frames and a full export.
//    No RAW file is stored in the repository.
//
//   flutter test integration_test/float_raw_test.dart -d macos \
//     --dart-define=LUMEN_RAW_SAMPLE=<path inside the app container>
//
// Every measurement is printed as a line starting with "RESULT ".
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/features/editor/renderer/gpu_float_export.dart';
import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/renderer_factory.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/info/photo_info.dart';
import 'package:lumen/import/float_sources.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

const _samplePath = String.fromEnvironment('LUMEN_RAW_SAMPLE');

void _r(String line) => debugPrint('RESULT $line');

bool get _apple =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

String _ms(Stopwatch sw) => '${sw.elapsedMilliseconds} ms';

String _mb(num bytes) => '${(bytes / (1 << 20)).round()} MB';

/// The next frame the renderer publishes after [update], fully rendered
/// (a 1-pixel readback waits for the GPU), as RGBA bytes when [read].
Future<({RgbaBuffer? pixels, double ms})> _frame(
  GpuPhotoRenderer r,
  DevelopSettings s, {
  bool interactive = false,
  bool read = true,
}) async {
  final done = Completer<ui.Image>();
  void listener() {
    final v = r.output.value;
    if (v != null && !done.isCompleted) done.complete(v);
  }

  final sw = Stopwatch()..start();
  r.output.addListener(listener);
  r.update(s, interactive: interactive);
  final image = await done.future.timeout(const Duration(seconds: 60));
  r.output.removeListener(listener);
  // Force the GPU to finish the frame.
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
  final ms = sw.elapsedMicroseconds / 1000;
  if (!read) return (pixels: null, ms: ms);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return (
    pixels: RgbaBuffer(
      image.width,
      image.height,
      Uint8List.fromList(data!.buffer.asUint8List()),
    ),
    ms: ms,
  );
}

double _luma(RgbaBuffer b, int x, int y) =>
    0.2126 * b.r(x, y) + 0.7152 * b.g(x, y) + 0.0722 * b.b(x, y);

/// Detail of a block: distinct luma levels (rounded to 8 bits), standard
/// deviation and mean absolute neighbour difference, in 8-bit units.
({int levels, double sd, double gradient, double mean}) _detail(
  RgbaBuffer b,
  int x0,
  int y0,
  int size,
) {
  final levels = <int>{};
  var sum = 0.0, sum2 = 0.0, grad = 0.0;
  var n = 0, g = 0;
  for (var y = y0; y < y0 + size; y++) {
    for (var x = x0; x < x0 + size; x++) {
      final l = _luma(b, x, y);
      levels.add(l.round());
      sum += l;
      sum2 += l * l;
      n++;
      if (x + 1 < x0 + size) {
        grad += (l - _luma(b, x + 1, y)).abs();
        g++;
      }
    }
  }
  final mean = sum / n;
  return (
    levels: levels.length,
    sd: math.sqrt(math.max(0, sum2 / n - mean * mean)),
    gradient: grad / g,
    mean: mean,
  );
}

/// Top-left corners of the [count] brightest non-overlapping [size] blocks.
List<(int, int)> _brightestBlocks(RgbaBuffer b, int size, int count) {
  final scored = <(double, int, int)>[];
  for (var y = 0; y + size <= b.height; y += size) {
    for (var x = 0; x + size <= b.width; x += size) {
      var s = 0.0;
      for (var yy = y; yy < y + size; yy += 4) {
        for (var xx = x; xx < x + size; xx += 4) {
          s += _luma(b, xx, yy);
        }
      }
      scored.add((s, x, y));
    }
  }
  scored.sort((a, c) => c.$1.compareTo(a.$1));
  return [for (final e in scored.take(count)) (e.$2, e.$3)];
}

/// Top-left corner of the [size] block with the most pixels at white.
(int, int) _mostClippedBlock(RgbaBuffer b, int size) {
  var best = (0, 0), most = -1;
  for (var y = 0; y + size <= b.height; y += size ~/ 2) {
    for (var x = 0; x + size <= b.width; x += size ~/ 2) {
      var n = 0;
      for (var yy = y; yy < y + size; yy += 2) {
        for (var xx = x; xx < x + size; xx += 2) {
          if (b.r(xx, yy) >= 254 && b.g(xx, yy) >= 254 && b.b(xx, yy) >= 254) {
            n++;
          }
        }
      }
      if (n > most) {
        most = n;
        best = (x, y);
      }
    }
  }
  return best;
}

ProviderContainer _container(FileCatalogRepository catalog) =>
    ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(catalog)],
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('16-bit PNG: imported with its depth, edited in float, keeps the '
      'levels 8 bits lose', () async {
    final root = Directory.systemTemp.createTempSync('lumen_float_png');
    addTearDown(() => root.deleteSync(recursive: true));
    final catalog = FileCatalogRepository(root.path);
    final container = _container(catalog);
    addTearDown(container.dispose);

    // The darkest 2 % of the range as a 16-bit ramp (1024 x 64).
    const w = 1024, h = 64;
    final image = img.Image(
      width: w,
      height: h,
      numChannels: 3,
      format: img.Format.uint16,
    );
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = (65535 * 0.02 * x / (w - 1)).round();
        image.setPixelRgb(x, y, v, v, v);
      }
    }
    final png = Uint8List.fromList(img.encodePng(image));
    final result = await ImportService(catalog)
        .importOne(ImportFile(name: 'ramp16.png', bytes: png));
    final entry = (result as Imported).entry;
    expect(entry.bitDepth, 16);
    expect(bitDepthLabel(entry), '16-bit');

    final float = await container.read(
      floatEditingProvider(entry.assetId).future,
    );
    _r('16-bit PNG: float editing available: $float');
    expect(float, _apple && await HbdCapability.available());
    if (!float) {
      markTestSkipped('no float path on this device');
      return;
    }
    final source = await catalog.readPixelSource(entry.assetId);
    final onFloat = container.read(photoRendererFactoryProvider)(
      entry.assetId,
    ) as GpuPhotoRenderer;
    final onBytes = GpuPhotoRenderer(assetId: entry.assetId);
    await onFloat.open(source);
    await onBytes.open(source);
    expect(onFloat.usingFloat, isTrue);
    expect(onBytes.usingFloat, isFalse);
    final s = DevelopSettings.defaults.withValue(P.exposure, 3);
    final a = (await _frame(onFloat, s)).pixels!;
    final b = (await _frame(onBytes, s)).pixels!;
    final lf = {for (var x = 0; x < w; x++) a.g(x, 32)}.length;
    final lb = {for (var x = 0; x < w; x++) b.g(x, 32)}.length;
    _r(
      '16-bit PNG, darkest 2 % at +3 EV: float path $lf levels, 8-bit '
      'path $lb levels',
    );
    expect(lb, lessThanOrEqualTo(8));
    expect(lf, greaterThan(3 * lb));
    // Defaults: the float path shows the same picture as the 8-bit one.
    final d0 = (await _frame(onFloat, DevelopSettings.defaults)).pixels!;
    final d1 = (await _frame(onBytes, DevelopSettings.defaults)).pixels!;
    var worst = 0;
    for (var i = 0; i < d0.data.length; i++) {
      worst = math.max(worst, (d0.data[i] - d1.data[i]).abs());
    }
    expect(worst, lessThanOrEqualTo(1));
    onFloat.dispose();
    onBytes.dispose();
  });

  test(
    'camera RAW: float path, highlight recovery against the 8-bit '
    'rendition, frame times, windowed export',
    () async {
      expect(_apple, isTrue, reason: 'RAW needs the Apple decoder');
      final name = p.basename(_samplePath);
      final raw = File(_samplePath).readAsBytesSync();
      final root = Directory.systemTemp.createTempSync('lumen_float_raw');
      addTearDown(() => root.deleteSync(recursive: true));
      final catalog = FileCatalogRepository(root.path);
      final container = _container(catalog);
      addTearDown(container.dispose);

      // ---- Import (JPEG rendition as before, plus the recorded depth) ----
      var sw = Stopwatch()..start();
      final imported = await container
          .read(importServiceProvider)
          .importOne(ImportFile(name: name, bytes: raw));
      final entry = (imported as Imported).entry;
      final id = entry.assetId;
      _r(
        'import ${_ms(sw)}: ${entry.format} ${entry.width}x${entry.height}, '
        'bit depth ${entry.bitDepth ?? 'not declared'} → '
        '"${bitDepthLabel(entry)}"',
      );
      final info = photoInfo(entry, floatEditing: true).first.rows;
      expect(info, contains(('Editing', '32-bit float')));

      // ---- The float source itself: headroom ----
      final source = await container.read(floatSourcesProvider).open(id);
      expect(source, isNotNull, reason: 'no float source for $name');
      _r(
        'float source ${source!.width}x${source.height}, profile '
        '${source.profile}',
      );
      expect((source.width, source.height), (entry.width, entry.height));
      sw = Stopwatch()..start();
      final small = await source.render(
        fullWidth: (entry.width / 4).round(),
        fullHeight: (entry.height / 4).round(),
      );
      final decodeMs = sw.elapsedMilliseconds;
      var peak = 0.0, above = 0, negative = 0;
      for (var i = 0; i < small.rgba.length; i += 4) {
        final m = math.max(
          small.rgba[i],
          math.max(small.rgba[i + 1], small.rgba[i + 2]),
        );
        if (m > peak) peak = m;
        if (m > 1) above++;
        if (math.min(small.rgba[i], small.rgba[i + 2]) < 0) negative++;
      }
      final pixels = small.width * small.height;
      final stops = math.log(srgbToLinear(peak)) / math.ln2;
      _r(
        'headroom: peak encoded ${peak.toStringAsFixed(3)} = '
        '${srgbToLinear(peak).toStringAsFixed(2)}x display white = '
        '${stops.toStringAsFixed(2)} stops; '
        '${(100 * above / pixels).toStringAsFixed(2)} % of pixels above '
        'white, ${(100 * negative / pixels).toStringAsFixed(2)} % out of '
        'gamut; quarter-size decode $decodeMs ms',
      );
      if (!source.profile.isNone) expect(peak, greaterThan(1.2));
      // A decode at a new size is a fresh RAW decode; the same size again
      // comes from the decoder's cache. (Right after the 45 MP import the
      // system is still busy for a few seconds, so let it settle first.)
      await Future<void>.delayed(const Duration(seconds: 8));
      sw = Stopwatch()..start();
      final fresh = await source.render(
        fullWidth: (entry.width / 5).round(),
        fullHeight: (entry.height / 5).round(),
      );
      final freshMs = sw.elapsedMilliseconds;
      sw = Stopwatch()..start();
      final again = await source.render(
        fullWidth: (entry.width / 5).round(),
        fullHeight: (entry.height / 5).round(),
      );
      _r(
        'native decode at 1/5 size: fresh $freshMs ms (decoder '
        '${fresh.decodeMs} ms), cached ${_ms(sw)} (decoder '
        '${again.decodeMs} ms)',
      );

      // ---- Open in the editor's renderer, and on the 8-bit path ----
      final bytes = await catalog.readPixelSource(id);
      final onFloat =
          container.read(photoRendererFactoryProvider)(id) as GpuPhotoRenderer;
      final onBytes = GpuPhotoRenderer(assetId: id);
      sw = Stopwatch()..start();
      await onBytes.open(bytes);
      final open8 = sw.elapsedMilliseconds;
      sw = Stopwatch()..start();
      await onFloat.open(bytes);
      final openF = sw.elapsedMilliseconds;
      expect(
        onFloat.usingFloat,
        isTrue,
        reason: 'editor not on the float path',
      );
      expect(onBytes.usingFloat, isFalse);
      expect(await container.read(floatEditingProvider(id).future), isTrue);
      _r('open: float path $openF ms, 8-bit path $open8 ms');

      // ---- Default look: the float path must show the rendition's picture
      const defaults = DevelopSettings.defaults;
      final f0 = (await _frame(onFloat, defaults)).pixels!;
      final b0 = (await _frame(onBytes, defaults)).pixels!;
      expect((f0.width, f0.height), (b0.width, b0.height));
      // Before / after: the float path's "before" is its own default frame.
      final before = await rgbaFromImage(onFloat.before!);
      var beforeWorst = 0;
      for (var i = 0; i < f0.data.length; i++) {
        beforeWorst = math.max(
          beforeWorst,
          (f0.data[i] - before.data[i]).abs(),
        );
      }
      _r(
        'before image vs the default frame on the float path: max '
        '$beforeWorst/255',
      );
      expect(beforeWorst, lessThanOrEqualTo(1));
      var sum = 0, worst = 0, big = 0;
      for (var i = 0; i < f0.data.length; i++) {
        final d = (f0.data[i] - b0.data[i]).abs();
        sum += d;
        if (d > worst) worst = d;
        if (d > 8) big++;
      }
      _r(
        'default look, float path vs 8-bit rendition (${f0.width}x'
        '${f0.height}): mean |d| '
        '${(sum / f0.data.length).toStringAsFixed(3)}/255, max $worst/255, '
        '${(100 * big / f0.data.length).toStringAsFixed(3)} % of channels '
        'differ by more than 8',
      );
      expect(sum / f0.data.length, lessThan(2.5));
      // Where they differ: tone classes of the rendition (clipped, inside
      // Apple's highlight roll-off, below it), edges apart (the two decodes
      // are downscaled by different resamplers).
      final total = <String, int>{}, off = <String, int>{};
      for (var y = 1; y < f0.height - 1; y += 2) {
        for (var x = 1; x < f0.width - 1; x += 2) {
          final o = f0.offset(x, y);
          final m8 = math.max(
            b0.data[o],
            math.max(b0.data[o + 1], b0.data[o + 2]),
          );
          final edge =
              (_luma(b0, x + 1, y) - _luma(b0, x - 1, y)).abs() +
              (_luma(b0, x, y + 1) - _luma(b0, x, y - 1)).abs();
          final tone = m8 >= 250
              ? 'clipped'
              : (m8 >= 215 ? 'roll-off' : 'below');
          final cls = edge > 24 ? 'edges' : tone;
          var d = 0;
          for (var c = 0; c < 3; c++) {
            d = math.max(d, (f0.data[o + c] - b0.data[o + c]).abs());
          }
          total[cls] = (total[cls] ?? 0) + 1;
          if (d > 8) off[cls] = (off[cls] ?? 0) + 1;
        }
      }
      final perClass = [
        for (final k in total.keys)
          '$k ${(100 * (off[k] ?? 0) / total[k]!).toStringAsFixed(2)} % of '
              '${total[k]}',
      ].join(', ');
      _r('default look, pixels differing by more than 8/255: $perClass');
      expect((off['below'] ?? 0) / total['below']!, lessThan(0.02));

      // ---- Recovery in the brightest regions ----
      const block = 96;
      final blocks = [
        // The most clipped area of the 8-bit rendition (the light source),
        // then the brightest ones by mean.
        _mostClippedBlock(b0, block),
        ..._brightestBlocks(b0, block, 2),
      ];
      final edits = {
        'exposure -2': defaults.withValue(P.exposure, -2),
        'highlights -100': defaults.withValue(P.highlights, -100),
      };
      for (final e in edits.entries) {
        final f = (await _frame(onFloat, e.value)).pixels!;
        final b = (await _frame(onBytes, e.value)).pixels!;
        var better = 0;
        for (final (x, y) in blocks) {
          final df = _detail(f, x, y, block), db = _detail(b, x, y, block);
          _r(
            '${e.key}, block at $x,$y (default mean '
            '${_detail(b0, x, y, block).mean.toStringAsFixed(0)}/255): float '
            '${df.levels} levels, sd ${df.sd.toStringAsFixed(2)}, gradient '
            '${df.gradient.toStringAsFixed(3)} | 8-bit rendition '
            '${db.levels} levels, sd ${db.sd.toStringAsFixed(2)}, gradient '
            '${db.gradient.toStringAsFixed(3)}',
          );
          if (df.levels > db.levels && df.sd > db.sd) better++;
        }
        if (!source.profile.isNone) {
          expect(better, greaterThan(0), reason: '${e.key}: nothing recovered');
        }
      }

      // ---- Slider drag: frames at preview size ----
      Future<double> drag(
        GpuPhotoRenderer r, {
        required bool interactive,
      }) async {
        var total = 0.0;
        const n = 20;
        for (var i = 0; i < n; i++) {
          final s = defaults
              .withValue(P.exposure, -2 + 0.1 * i)
              .withValue(P.highlights, -5.0 * i);
          total += (await _frame(
            r,
            s,
            interactive: interactive,
            read: false,
          )).ms;
        }
        return total / n;
      }

      await drag(onFloat, interactive: true); // warm-up
      final dragF = await drag(onFloat, interactive: true);
      final fullF = await drag(onFloat, interactive: false);
      final dragB = await drag(onBytes, interactive: true);
      final fullB = await drag(onBytes, interactive: false);
      _r(
        'frame (exposure + highlights drag, ${f0.width}x${f0.height} '
        'preview): float path ${dragF.toStringAsFixed(1)} ms interactive, '
        '${fullF.toStringAsFixed(1)} ms full quality | 8-bit path '
        '${dragB.toStringAsFixed(1)} ms interactive, '
        '${fullB.toStringAsFixed(1)} ms full quality',
      );
      expect(
        dragF,
        lessThan(50),
        reason: 'float drag frames are not interactive',
      );
      onFloat.dispose();
      onBytes.dispose();

      // ---- Full-resolution export from source windows ----
      final doc = await catalog.loadEdit(id);
      final edit = defaults.withValues({P.exposure: -1.5, P.highlights: -60});
      await catalog.saveEdit(doc.copyWith(settings: edit));
      final rss0 = ProcessInfo.currentRss;
      sw = Stopwatch()..start();
      final floatFile =
          await ExportService(
            catalog,
            floatExport: gpuFloatExport(
              container.read(floatSourcesProvider).open,
            ),
          ).exportOne(
            id,
            const ExportOptions(format: ExportFormat.jpeg, quality: 90),
          );
      final exportF = sw.elapsedMilliseconds;
      final stats = lastFloatExportStats!;
      _r(
        'export float path: ${floatFile.width}x${floatFile.height} JPEG '
        '${_mb(floatFile.bytes.length)} in $exportF ms; $stats; process RSS '
        '${_mb(rss0)} → ${_mb(ProcessInfo.currentRss)} (max '
        '${_mb(ProcessInfo.maxRss)})',
      );
      expect((floatFile.width, floatFile.height), (entry.width, entry.height));
      expect(stats.largestWindow, lessThan(entry.width * entry.height ~/ 4));

      sw = Stopwatch()..start();
      final byteFile = await ExportService(catalog, renderer: gpuFullResRender)
          .exportOne(
            id,
            const ExportOptions(format: ExportFormat.jpeg, quality: 90),
          );
      _r(
        'export 8-bit path: ${byteFile.width}x${byteFile.height} JPEG '
        '${_mb(byteFile.bytes.length)} in ${_ms(sw)}',
      );

      // The exported files: the brightest block of the photo, at full size.
      final scale = entry.width / b0.width;
      final (bx, by) = blocks.first;
      final fx = (bx * scale).round(), fy = (by * scale).round();
      final size = (block * scale).round();
      RgbaBuffer crop(Uint8List jpeg) {
        final decoded = img.decodeJpg(jpeg)!;
        final part = img.copyCrop(
          decoded,
          x: fx,
          y: fy,
          width: size,
          height: size,
        );
        final out = RgbaBuffer(size, size);
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            final px = part.getPixel(x, y);
            out.setPixel(x, y, px.r.toInt(), px.g.toInt(), px.b.toInt());
          }
        }
        return out;
      }

      final ef = _detail(crop(floatFile.bytes), 0, 0, size);
      final eb = _detail(crop(byteFile.bytes), 0, 0, size);
      _r(
        'exported file, brightest block ($size px at $fx,$fy), exposure -1.5 '
        'highlights -60: float ${ef.levels} levels, sd '
        '${ef.sd.toStringAsFixed(2)}, mean ${ef.mean.toStringAsFixed(0)} | '
        '8-bit ${eb.levels} levels, sd ${eb.sd.toStringAsFixed(2)}, mean '
        '${eb.mean.toStringAsFixed(0)}',
      );
      if (!source.profile.isNone) {
        expect(ef.sd, greaterThan(eb.sd));
      }
      await source.release();
      expect(EngineImages.live, lessThanOrEqualTo(2));
    },
    skip: _samplePath.isEmpty,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
