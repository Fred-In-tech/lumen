// Imported looks on a real camera RAW: three Lightroom preset fixtures
// (bright & airy, moody film, B&W) and a generated teal & orange LUT are
// applied to the file and exported through the float path at 2048 px, and
// every card sample (presets, LUT, AI styles) is rendered on it as Home
// would with the RAW as a project cover, into one contact sheet. Skipped
// unless LUMEN_RAW_SAMPLE points at a RAW the sandboxed app can read. The
// results go to <app tmp>/lumen_looks_real/ (never into the repository:
// the photo is the user's). Needs no window (runs with the display asleep).
//
//   flutter test integration_test/looks_real_photo_test.dart -d macos \
//     --dart-define=LUMEN_RAW_SAMPLE=<path inside the app container>
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/data/file_lut_repository_io.dart';
import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/features/editor/renderer/gpu_float_export.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/looks/inflate_io.dart';
import 'package:lumen/features/looks/look.dart';
import 'package:lumen/features/looks/look_previews.dart';
import 'package:lumen/import/float_preview_cache_io.dart';
import 'package:lumen/import/float_sources.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import '../test/support/look_files.dart';

const _samplePath = String.fromEnvironment('LUMEN_RAW_SAMPLE');
final _out = Directory('${Directory.systemTemp.path}/lumen_looks_real');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fixture presets and a LUT on a real RAW (exports + card samples)',
    () async {
      addTearDown(CreativeLuts.reset);
      _out.createSync(recursive: true);
      final root = Directory.systemTemp.createTempSync('lumen_looks_raw');
      addTearDown(() => root.deleteSync(recursive: true));
      final repo = FileCatalogRepository(root.path);
      final luts = FileLutRepository(root.path);
      CreativeLuts.configure(luts.load);

      final raw = File(_samplePath).readAsBytesSync();
      final project = await repo.createProject(name: 'Real RAW');
      final r = await ImportService(repo).importOne(
        ImportFile(name: p.basename(_samplePath), bytes: raw),
        projectId: project.id,
      );
      final id = (r as Imported).entry.assetId;
      var n = 0;
      final result = importLookFiles(
        fixtureLookFiles(),
        inflate: inflateCapped,
        newId: () => 'real.${n++}',
      );
      expect(result.failures, isEmpty);
      for (final l in result.luts) {
        await luts.save(l);
      }
      final looks = result.presets;

      // Exports through the float path (what the user would deliver).
      final container = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          floatPreviewCacheProvider.overrideWithValue(
            FileFloatPreviewCache(
              () async => p.join(root.path, '.float_previews'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final export = ExportService(
        repo,
        floatExport: gpuFloatExport(container.read(floatSourcesProvider).open),
      );
      Future<void> save(String name, DevelopSettings s) async {
        final doc = await repo.loadEdit(id);
        await repo.saveEdit(doc.copyWith(settings: s));
        final sw = Stopwatch()..start();
        final f = await export.exportOne(
          id,
          const ExportOptions(format: ExportFormat.jpeg, longEdge: 2048),
        );
        File('${_out.path}/$name.jpg').writeAsBytesSync(f.bytes);
        debugPrint(
          'RESULT export "$name" ${f.width}x${f.height} in '
          '${sw.elapsedMilliseconds} ms',
        );
      }

      await save('0_original', DevelopSettings.defaults);
      for (final look in looks) {
        final slug = look.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
        await save(slug, look.apply(DevelopSettings.defaults));
        debugPrint('RESULT ${look.name}: ${look.importReport?.toJson()}');
      }

      // The card samples on this RAW (what Home shows with it as cover).
      final previews = LookPreviewService();
      final photo = await loadLibraryPhoto(repo, id);
      expect(photo, isNotNull);
      final all = <Look>[
        for (final l in looks) PresetLook(l),
        for (final s in AiStyle.values) StyleLook(s),
      ];
      const e = kLookPreviewLongEdge;
      final sheet = img.Image(
        width: 4 * e,
        height: ((all.length + 1) / 4).ceil() * e,
      );
      final tiles = [(await previews.before(photo!))!];
      final sw = Stopwatch()..start();
      tiles.addAll(
        (await Future.wait([for (final l in all) previews.preview(l, photo)]))
            .map((b) => b!),
      );
      final wall = sw.elapsedMilliseconds;
      for (final (i, t) in tiles.indexed) {
        img.compositeImage(
          sheet,
          img.decodeJpg(t)!,
          dstX: (i % 4) * e,
          dstY: (i ~/ 4) * e,
        );
      }
      File('${_out.path}/card_samples.jpg')
          .writeAsBytesSync(img.encodeJpg(sheet, quality: 88));
      debugPrint(
        'RESULT card samples on the RAW: ${previews.renders} renders, '
        '${previews.renderTime.inMilliseconds ~/ previews.renders} ms each, '
        '$wall ms for all (2 at a time); order: before, '
        '${all.map((l) => l.name).join(', ')}',
      );
      debugPrint('RESULT outputs in ${_out.path}');
    },
    skip: _samplePath.isEmpty,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
