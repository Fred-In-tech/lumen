// Real camera RAW on the real app (macOS / iOS): import a RAW file → it is
// developed by the system decoder → thumbnail → open in the editor → the
// frame is a real photo → an edit changes it → export carries the camera EXIF.
//
// Needs a real RAW sample, so it is skipped unless LUMEN_RAW_SAMPLE points at
// one the app can read (the macOS app is sandboxed: put the file inside its
// container first). No RAW file is stored in the repository.
//
//   flutter test integration_test/raw_import_test.dart -d macos \
//     --dart-define=LUMEN_RAW_SAMPLE=<path inside the app container>
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/data/file_preference_repositories_io.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/photo_canvas.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/library/library_actions.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_sources.dart';
import 'package:lumen/import/photo_decoder.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

const _samplePath = String.fromEnvironment('LUMEN_RAW_SAMPLE');

class _FakeImportSource implements ImportSource {
  _FakeImportSource(this.files);
  final List<ImportFile> files;

  @override
  Future<List<ImportFile>> pick({required bool mobile}) async => files;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 120),
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

Future<void> _settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Mean and spread of the editor's current frame luminance (0–255).
Future<({double mean, double spread})> _frameStats(WidgetTester tester) async {
  final canvas = tester.widget<PhotoCanvas>(find.byType(PhotoCanvas));
  final image = canvas.after.value!;
  late Uint8List px;
  await tester.runAsync(() async {
    final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    px = bd!.buffer.asUint8List();
  });
  var sum = 0.0, min = 255.0, max = 0.0;
  for (var i = 0; i < px.length; i += 4) {
    final l = (px[i] + px[i + 1] + px[i + 2]) / 3;
    sum += l;
    if (l < min) min = l;
    if (l > max) max = l;
  }
  return (mean: sum / (px.length ~/ 4), spread: max - min);
}

/// Runs [body] with panel layout overflows logged instead of failing the
/// test: those belong to the UI tests, and here they must not hide whether
/// the RAW pixels made it through.
Future<void> _ignoringLayoutOverflow(Future<void> Function() body) async {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
      debugPrint('IGNORED layout overflow: ${details.context}');
      return;
    }
    previous?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'camera RAW: import → thumbnail → editor frame → edit → export',
    (tester) => _ignoringLayoutOverflow(() async {
      final name = p.basename(_samplePath);
      final raw = File(_samplePath).readAsBytesSync();
      final format = sniffFormat(raw, fileName: name);
      expect(format.isRaw, isTrue, reason: '$name is not a RAW file');

      final root = Directory.systemTemp.createTempSync('lumen_raw_flow');
      addTearDown(() => root.deleteSync(recursive: true));
      final catalog = FileCatalogRepository(root.path);
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
            importSourceProvider.overrideWithValue(
              _FakeImportSource([ImportFile(name: name, bytes: raw)]),
            ),
          ],
          child: const LumenApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LumenApp)),
      );

      // Import: the real `lumen/raw` channel develops the file.
      final watch = Stopwatch()..start();
      await tester.tap(find.text('Import'));
      await _pumpUntil(
        tester,
        () => (container.read(libraryProvider).value?.length ?? 0) == 1,
      );
      final entry = container.read(libraryProvider).value!.single;
      final id = entry.assetId;
      debugPrint(
        'RESULT raw import ${watch.elapsedMilliseconds} ms: ${entry.format} '
        '${entry.width}x${entry.height} exif ${entry.exif.toJson()}',
      );
      expect(entry.format, format.name);
      expect(entry.originalPath, 'originals/$id.${format.extension}');
      expect(entry.bytes, raw.length);
      expect(entry.width, greaterThan(1000));
      expect(entry.height, greaterThan(1000));
      expect(entry.exif.camera, isNotNull);
      expect(entry.exif.capturedAt, isNotNull);
      expect(entry.exif.exposureSeconds, isNotNull);

      // The RAW is stored untouched; pixels come from a JPEG rendition whose
      // upright size is what the catalog recorded.
      final stored = (await tester.runAsync(() async {
        final original = File(p.join(root.path, entry.originalPath));
        final source = await catalog.readPixelSource(id);
        final thumb = await catalog.readThumb(id);
        final size = await probeSize(source);
        final thumbSize = await probeSize(thumb!);
        return (
          originalBytes: original.lengthSync(),
          source: sniffFormat(source),
          sourceBytes: source.length,
          size: size,
          thumb: thumbSize,
        );
      }))!;
      debugPrint(
        'RESULT rendition ${stored.sourceBytes} bytes, thumb ${stored.thumb}',
      );
      expect(stored.originalBytes, raw.length);
      expect(stored.source, PhotoFormat.jpeg);
      expect(
        (stored.size.width, stored.size.height),
        (entry.width, entry.height),
      );
      expect(
        stored.thumb.width > stored.thumb.height,
        entry.width > entry.height,
      );
      await _settle(tester, 3000);

      // Open it: the editor renders a real photo, not a blank frame.
      await tester.tap(
        find.bySemanticsLabel(RegExp(RegExp.escape(name))).first,
      );
      await _pumpUntil(
        tester,
        () => container.read(editorProvider(id)).value != null,
      );
      await _pumpUntil(
        tester,
        () =>
            tester
                .widgetList<PhotoCanvas>(find.byType(PhotoCanvas))
                .isNotEmpty &&
            tester.widget<PhotoCanvas>(find.byType(PhotoCanvas)).after.value !=
                null,
      );
      await _settle(tester, 3000);
      final before = await _frameStats(tester);
      debugPrint('RESULT frame mean ${before.mean} spread ${before.spread}');
      expect(before.mean, inInclusiveRange(8, 247), reason: 'blank frame');
      expect(before.spread, greaterThan(40), reason: 'flat frame');

      // Edits apply like on any other photo.
      final ctl = container.read(editorProvider(id).notifier);
      final base = container.read(editorProvider(id)).value!.settings;
      ctl.setParam(P.exposure, base.value(P.exposure) - 1.5);
      await _settle(tester, 3000);
      final darker = await _frameStats(tester);
      debugPrint('RESULT darker mean ${darker.mean}');
      expect(darker.mean, lessThan(before.mean - 5));
      await tester.runAsync(ctl.flush);

      // Export renders from the rendition and carries the camera EXIF.
      final service = container.read(exportServiceProvider);
      final out = (await tester.runAsync(
        () => service.exportOne(
          id,
          const ExportOptions(format: ExportFormat.jpeg, longEdge: 1600),
        ),
      ))!;
      final tags = (await tester.runAsync(() => readExifFromBytes(out.bytes)))!;
      debugPrint(
        'RESULT export ${out.fileName} ${out.width}x${out.height} '
        '${out.bytes.length} bytes, model ${tags['Image Model']?.printable}',
      );
      expect(out.fileName, endsWith('.jpg'));
      expect(out.width > out.height ? out.width : out.height, 1600);
      expect(sniffFormat(out.bytes), PhotoFormat.jpeg);
      expect(tags['Image Model']?.printable, isNotEmpty);
      expect(tags.keys.where((k) => k.startsWith('GPS')), isEmpty);
    }),
    skip: _samplePath.isEmpty,
  );
}
