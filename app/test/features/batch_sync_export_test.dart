import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/ai/auto_edit_service.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/features/export/export_targets_io.dart';
import 'package:lumen/features/sync/settings_clipboard.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

Uint8List _jpeg(SceneId id, int seed, {bool gps = false}) {
  final s = SyntheticScenes.build(id, longEdge: 240).image;
  final im = img.Image.fromBytes(
    width: s.width,
    height: s.height,
    bytes: s.data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  ).convert(numChannels: 3);
  im.setPixelRgb(
    seed % im.width,
    0,
    seed % 255,
    0,
    0,
  ); // make every file unique
  if (gps) {
    im.exif.imageIfd['Make'] = 'TestCam';
    im.exif.gpsIfd['GPSLatitudeRef'] = 'N';
    im.exif.gpsIfd['GPSLatitude'] = [51.0, 30.0, 0.0];
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

/// Pumps a ProviderScope and returns a WidgetRef from inside it.
Future<(WidgetRef, MemoryCatalogRepository)> _harness(
  WidgetTester tester,
) async {
  final repo = MemoryCatalogRepository();
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        autoEditServiceProvider.overrideWithValue(
          AutoEditService(local: const LocalAutoEditProvider()),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return const SizedBox();
        },
      ),
    ),
  );
  return (captured, repo);
}

Future<List<String>> _import(MemoryCatalogRepository repo, int n) async {
  final service = ImportService(repo);
  final files = [
    for (var i = 0; i < n; i++)
      ImportFile(
        name: 'p$i.jpg',
        bytes: _jpeg(
          SceneId.values[i % 3 == 0 ? 0 : (i % 3 == 1 ? 2 : 5)],
          i + 1,
        ),
      ),
  ];
  final results = await service.importAll(files);
  return [
    for (final r in results)
      if (r is Imported) r.entry.assetId,
  ];
}

void main() {
  testWidgets(
    'batch auto-edit of 20 photos stops when cancelled; untouched photos stay unedited',
    (tester) async {
      final (ref, repo) = await _harness(tester);
      await tester.runAsync(() async {
        final ids = await _import(repo, 20);
        expect(ids.length, 20);
        final run = batchAutoEdit(ref, ids, concurrency: 2);
        while ((ref.read(batchProvider)?.done ?? 0) < 6) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        ref.read(batchProvider.notifier).cancel();
        final (ok, failed) = await run;
        expect(failed, 0);
        expect(ok, inInclusiveRange(6, 9));
        final edited = [
          for (final id in ids)
            if ((await repo.get(id))!.aiEngine != null) id,
        ];
        expect(edited.length, ok);
        for (final id in ids.where((x) => !edited.contains(x))) {
          expect((await repo.loadEdit(id)).settings.isDefault, isTrue);
        }
        expect(ref.read(batchProvider), isNull);
      });
    },
  );

  testWidgets(
    'each of the 9 AI styles applies as one undoable step and they differ',
    (tester) async {
      final (ref, repo) = await _harness(tester);
      await tester.runAsync(() async {
        final ids = await _import(repo, 1);
        final service = ref.read(autoEditServiceProvider);
        final results = <AiStyle, DevelopSettings>{};
        for (final style in AiStyle.values) {
          // Reset to an unedited document before each style.
          await repo.saveEdit(EditDocument.create(ids.single));
          expect(
            await autoEditStoredAsset(
              repo: repo,
              service: service,
              assetId: ids.single,
              style: style,
            ),
            isTrue,
          );
          final doc = await repo.loadEdit(ids.single);
          expect(doc.ai!.style, style.id);
          expect(doc.history.entries.single.kind, HistoryKind.ai);
          expect(
            doc.history.undo(doc.settings).settings.isDefault,
            isTrue,
            reason: 'one undo reverts ${style.label}',
          );
          results[style] = doc.settings;
        }
        expect(results.values.toSet().length, AiStyle.values.length);
        expect(results[AiStyle.bw]!.treatment, Treatment.bw);
      });
    },
  );

  testWidgets(
    'sync settings to 5 photos: groups respected, one entry per photo',
    (tester) async {
      final (ref, repo) = await _harness(tester);
      await tester.runAsync(() async {
        final ids = await _import(repo, 5);
        final source = DevelopSettings.defaults.withValues({
          P.temp: 15,
          P.exposure: 1,
        });
        final n = await syncSettingsToAssets(ref, source, {
          SettingsGroup.color,
        }, ids);
        expect(n, 5);
        for (final id in ids) {
          final doc = await repo.loadEdit(id);
          expect(doc.settings.value(P.temp), 15);
          expect(
            doc.settings.value(P.exposure),
            0,
            reason: 'light group not selected',
          );
          expect(doc.history.entries.single.kind, HistoryKind.paste);
        }
      });
    },
  );

  test(
    'export writes JPEG/PNG to a folder with location removed and no overwrite',
    () async {
      final repo = MemoryCatalogRepository();
      final ids = await _importGps(repo);
      await repo.saveEdit(
        EditDocument.create(ids.single).copyWith(
          settings: DevelopSettings.defaults.withValue(P.exposure, 0.5),
        ),
      );
      final service = ExportService(repo);
      final jpg = await service.exportOne(
        ids.single,
        const ExportOptions(
          format: ExportFormat.jpeg,
          quality: 85,
          longEdge: 120,
        ),
      );
      expect(jpg.width, 120);
      final tags = await readExifFromBytes(jpg.bytes);
      expect(tags.keys.where((k) => k.startsWith('GPS')), isEmpty);
      expect(tags['Image Make']?.printable, 'TestCam');
      final png = await service.exportOne(
        ids.single,
        const ExportOptions(format: ExportFormat.png),
      );
      expect(img.decodePng(png.bytes)!.width, 240);

      final dir = await Directory.systemTemp.createTemp('lumen_export');
      addTearDown(() => dir.delete(recursive: true));
      final first = await writeExports(dir.path, [jpg]);
      final second = await writeExports(dir.path, [jpg]);
      expect(File(first.single).existsSync(), isTrue);
      expect(second.single, isNot(first.single), reason: 'never overwrites');
      expect(second.single, endsWith('gps_edit (2).jpg'));
    },
  );
}

Future<List<String>> _importGps(MemoryCatalogRepository repo) async {
  final r = await ImportService(repo).importOne(
    ImportFile(
      name: 'gps.jpg',
      bytes: _jpeg(SceneId.darkInterior, 7, gps: true),
    ),
  );
  return [(r as Imported).entry.assetId];
}
