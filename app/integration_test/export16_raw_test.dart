// 16-bit export and batch export on the real app stack (macOS / iOS):
// import a camera RAW → float export from source windows → TIFF / PNG
// 16-bit files; then a 20-photo batch with one preset.
//
// Skipped unless LUMEN_RAW_SAMPLE points at a RAW the app can read (the
// macOS app is sandboxed: copy the file into its container first). The
// exported files are left in `<container tmp>/lumen_export16/` for an
// independent reader (sips, Python); delete them afterwards. No RAW file
// is stored in the repository.
//
//   flutter test integration_test/export16_raw_test.dart -d macos \
//     --dart-define=LUMEN_RAW_SAMPLE=<path inside the app container>
//
// Every measurement is printed as a line starting with "RESULT ".
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/features/editor/renderer/gpu_float_export.dart';
import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/export/export_batch.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/export/export_targets_io.dart';
import 'package:lumen/import/float_sources.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

const _samplePath = String.fromEnvironment('LUMEN_RAW_SAMPLE');

void _r(String line) => debugPrint('RESULT $line');

String _mb(num bytes) => '${(bytes / (1 << 20)).round()} MB';

/// Distinct levels of channel [c] in a 16-bit RGB frame, and how many of
/// them are off the 8-bit grid (not a multiple of 257).
({int levels, int off8}) _levels(Uint16List rgb, int c) {
  final seen = Uint8List(65536);
  for (var i = c; i < rgb.length; i += 3) {
    seen[rgb[i]] = 1;
  }
  var levels = 0, off8 = 0;
  for (var v = 0; v < 65536; v++) {
    if (seen[v] == 0) continue;
    levels++;
    if (v % 257 != 0) off8++;
  }
  return (levels: levels, off8: off8);
}

/// The 16-bit samples of a TIFF this app wrote (uncompressed, contiguous
/// strips; the offset is read from the file).
Uint16List _tiffSamples(Uint8List file) {
  final bd = ByteData.sublistView(file);
  final ifd = bd.getUint32(4, Endian.little);
  final n = bd.getUint16(ifd, Endian.little);
  for (var i = 0; i < n; i++) {
    final e = ifd + 2 + i * 12;
    if (bd.getUint16(e, Endian.little) != 273) continue;
    final count = bd.getUint32(e + 4, Endian.little);
    final v = bd.getUint32(e + 8, Endian.little);
    final first = count == 1 ? v : bd.getUint32(v, Endian.little);
    return file.buffer.asUint16List(
      file.offsetInBytes + first,
      (file.length - first) ~/ 2,
    );
  }
  throw StateError('no StripOffsets');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'camera RAW: 16-bit TIFF / PNG from the float path, a 20-photo batch',
    () async {
      final name = p.basename(_samplePath);
      final raw = File(_samplePath).readAsBytesSync();
      final root = Directory.systemTemp.createTempSync('lumen_export16');
      addTearDown(() => root.deleteSync(recursive: true));
      final out = Directory(p.join(Directory.systemTemp.path, 'lumen_export16'))
        ..createSync(recursive: true);
      final catalog = FileCatalogRepository(root.path);
      final container = ProviderContainer(
        overrides: [catalogRepositoryProvider.overrideWithValue(catalog)],
      );
      addTearDown(container.dispose);

      final imported = await container
          .read(importServiceProvider)
          .importOne(ImportFile(name: name, bytes: raw));
      final entry = (imported as Imported).entry;
      final id = entry.assetId;
      _r('import: ${entry.format} ${entry.width}x${entry.height}');
      expect(await HbdCapability.available(), isTrue);

      // A typical edit: pull the highlights, lift the shadows.
      final doc = await catalog.loadEdit(id);
      await catalog.saveEdit(
        doc.copyWith(
          settings: DevelopSettings.defaults.withValues({
            P.exposure: -0.7,
            P.highlights: -60,
            P.shadows: 30,
          }),
        ),
      );
      final service = ExportService(
        catalog,
        renderer: gpuFullResRender,
        sourceRenderer: const GpuSourceRenderer(),
        floatExport: gpuFloatExport(container.read(floatSourcesProvider).open),
      );

      // ---- Full-size 16-bit TIFF ----
      final rss0 = ProcessInfo.currentRss;
      var sw = Stopwatch()..start();
      final tiff = await service.exportOne(
        id,
        const ExportOptions(
          format: ExportFormat.tiff16,
          sharpen: OutputSharpen.printStandard,
        ),
      );
      final tiffMs = sw.elapsedMilliseconds;
      final rssTiff = ProcessInfo.currentRss;
      final stats = lastFloatExportStats!;
      sw = Stopwatch()..start();
      final tiffPath = (await writeExports(out.path, [tiff])).single;
      final writeMs = sw.elapsedMilliseconds;
      _r(
        'TIFF 16-bit ${tiff.width}x${tiff.height}: ${_mb(tiff.length)}, '
        'render + finish $tiffMs ms, write $writeMs ms, float detail '
        '${tiff.sixteenBitDetail}; $stats; RSS ${_mb(rss0)} → '
        '${_mb(rssTiff)} (max ${_mb(ProcessInfo.maxRss)}); file $tiffPath',
      );
      expect((tiff.width, tiff.height), (entry.width, entry.height));
      expect(tiff.sixteenBitDetail, isTrue);
      final samples = _tiffSamples(File(tiffPath).readAsBytesSync());
      expect(samples.length, tiff.width * tiff.height * 3);
      for (var c = 0; c < 3; c++) {
        final l = _levels(samples, c);
        _r(
          'TIFF channel $c: ${l.levels} distinct levels, ${l.off8} off the '
          '8-bit grid',
        );
        expect(l.levels, greaterThan(256));
        expect(l.off8, greaterThan(0));
      }

      // ---- 16-bit PNG (long edge 2048) and an 8-bit dithered JPEG ----
      sw = Stopwatch()..start();
      final png = await service.exportOne(
        id,
        const ExportOptions(
          format: ExportFormat.png16,
          size: ExportSizeLimit.longEdge(2048),
        ),
      );
      final pngPath = (await writeExports(out.path, [png])).single;
      _r(
        'PNG 16-bit ${png.width}x${png.height}: ${_mb(png.length)} in '
        '${sw.elapsedMilliseconds} ms; file $pngPath',
      );
      sw = Stopwatch()..start();
      final jpg = await service.exportOne(
        id,
        ExportOptions.fromPreset(kBuiltinExportPresets[1]),
      );
      final jpgPath = (await writeExports(out.path, [jpg])).single;
      _r(
        'JPEG full size (float, dithered) ${jpg.width}x${jpg.height}: '
        '${_mb(jpg.length)} in ${sw.elapsedMilliseconds} ms; file $jpgPath',
      );

      // ---- Batch: 20 photos with the Web preset, then 3 full-size TIFFs ----
      final batchDir = Directory(p.join(out.path, 'batch'))..createSync();
      final rssB = ProcessInfo.currentRss;
      sw = Stopwatch()..start();
      var maxRss = 0;
      final web =
          await ExportBatch(service, (f) async {
            maxRss = ProcessInfo.currentRss > maxRss
                ? ProcessInfo.currentRss
                : maxRss;
            return (await writeExports(batchDir.path, [f])).single;
          }, catalog: catalog).run(
            List.filled(20, id),
            ExportOptions.fromPreset(kBuiltinExportPresets.first),
          );
      _r(
        'batch 20 x Web preset: ${web.written.length} written, '
        '${web.failures.length} failed in ${sw.elapsedMilliseconds} ms; RSS '
        '${_mb(rssB)} → max ${_mb(maxRss)} during the batch',
      );
      expect(web.written, hasLength(20));
      expect(web.failures, isEmpty);
      for (final f in web.written) {
        File(f).deleteSync();
      }
      sw = Stopwatch()..start();
      maxRss = 0;
      final print =
          await ExportBatch(service, (f) async {
            maxRss = ProcessInfo.currentRss > maxRss
                ? ProcessInfo.currentRss
                : maxRss;
            final path = (await writeExports(batchDir.path, [f])).single;
            File(path).deleteSync(); // disk: keep one TIFF only
            return path;
          }).run(
            List.filled(3, id),
            ExportOptions.fromPreset(kBuiltinExportPresets[2]),
          );
      _r(
        'batch 3 x Print TIFF 16-bit preset: ${print.written.length} in '
        '${sw.elapsedMilliseconds} ms; RSS max ${_mb(maxRss)} during the '
        'batch (process max ${_mb(ProcessInfo.maxRss)})',
      );
      expect(print.written, hasLength(3));
    },
    skip: _samplePath.isEmpty,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
