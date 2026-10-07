import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/data/app_settings.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/export/export_batch.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

Uint8List _jpeg(int seed) {
  final im = img.Image(width: 32, height: 24);
  img.fill(im, color: img.ColorRgb8(20 * seed, 255 - 20 * seed, 90));
  return Uint8List.fromList(img.encodeJpg(im));
}

Future<(MemoryCatalogRepository, List<String>)> _photos(int n) async {
  final repo = MemoryCatalogRepository();
  final ids = <String>[];
  for (var i = 0; i < n; i++) {
    final r = await ImportService(repo)
        .importOne(ImportFile(name: 'IMG_${100 + i}.jpg', bytes: _jpeg(i)));
    ids.add((r as Imported).entry.assetId);
  }
  return (repo, ids);
}

/// Counts renders in flight (the memory rule: never more than one).
class _Tracking {
  int inFlight = 0;
  int maxInFlight = 0;
  int calls = 0;

  FullResRenderer get render =>
      (original, settings, longEdge, {String assetId = ''}) async {
        calls++;
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return RgbaBuffer(8, 6);
      };
}

void main() {
  test('exports N photos in order with progress, unique names and one '
      'render in flight', () async {
    final (repo, ids) = await _photos(5);
    final track = _Tracking();
    final service = ExportService(repo, renderer: track.render);
    final written = <String>[];
    final progress = <(int, String?)>[];
    final result =
        await ExportBatch(service, (f) async {
          written.add(f.fileName);
          return '/out/${f.fileName}';
        }, catalog: repo).run(
          ids,
          const ExportOptions(naming: 'shoot'),
          onProgress: (done, total, current) {
            expect(total, 5);
            progress.add((done, current));
          },
        );
    expect(result.failures, isEmpty);
    expect(result.cancelled, isFalse);
    expect(written, [
      'shoot.jpg',
      'shoot (2).jpg',
      'shoot (3).jpg',
      'shoot (4).jpg',
      'shoot (5).jpg',
    ]);
    expect(result.written.first, '/out/shoot.jpg');
    expect(progress.first, (0, 'IMG_100.jpg'));
    expect(progress.last, (5, null));
    expect(track.maxInFlight, 1);
  });

  test('two batches at once still render one photo at a time', () async {
    final (repo, ids) = await _photos(4);
    final track = _Tracking();
    final service = ExportService(repo, renderer: track.render);
    final batch = ExportBatch(service, (f) async => null);
    final results = await Future.wait([
      batch.run(ids.sublist(0, 2), const ExportOptions()),
      batch.run(ids.sublist(2), const ExportOptions()),
    ]);
    expect(results.every((r) => r.written.length == 2), isTrue);
    expect(track.calls, 4);
    expect(track.maxInFlight, 1);
  });

  test('a failing photo is reported and the batch goes on', () async {
    final (repo, ids) = await _photos(2);
    final service = ExportService(repo, renderer: _Tracking().render);
    final result = await ExportBatch(
      service,
      (f) async => null,
      catalog: repo,
    ).run([ids.first, 'missing-id', ids.last], const ExportOptions());
    expect(result.written, hasLength(2));
    expect(result.failures.single.assetId, 'missing-id');
    expect(result.failures.single.name, 'missing-id');
    expect(result.failures.single.reason, 'Photo not found');
    expect(exportSummary(result, null), contains('2 photos exported'));
    // Exported photos are stamped (project progress); the failed one is not.
    for (final id in ids) {
      expect((await repo.get(id))!.exportedAt, isNotNull);
    }
  });

  test('without a catalog nothing is stamped', () async {
    final (repo, ids) = await _photos(1);
    final service = ExportService(repo, renderer: _Tracking().render);
    await ExportBatch(
      service,
      (f) async => null,
    ).run(ids, const ExportOptions());
    expect((await repo.get(ids.single))!.exportedAt, isNull);
  });

  test('cancel stops before the next photo', () async {
    final (repo, ids) = await _photos(4);
    final service = ExportService(repo, renderer: _Tracking().render);
    var n = 0;
    final result = await ExportBatch(
      service,
      (f) async => null,
    ).run(ids, const ExportOptions(), isCancelled: () => n++ >= 2);
    expect(result.cancelled, isTrue);
    expect(result.written, hasLength(2));
    expect(exportSummary(result, '/x'), '2 of 4 exported (cancelled).');
  });

  test('errors read as sentences', () {
    expect(
      describeExportError(const CatalogException('Disk full')),
      'Disk full',
    );
    expect(describeExportError(const FormatException('bad\nmore')), 'bad');
    expect(describeExportError(Exception('')), 'Unknown error');
  });

  test('serialExport keeps going after a failure', () async {
    await expectLater(
      serialExport<void>(() async => throw StateError('x')),
      throwsStateError,
    );
    expect(await serialExport(() async => 7), 7);
  });

  group('presets in settings', () {
    test('user presets, the picked one and the last settings persist', () {
      const mine = ExportPreset(
        id: 'user-1',
        name: 'Proofs',
        format: ExportFileFormat.tiff16,
      );
      final s = const AppSettings().copyWith(
        exportPresets: [mine],
        exportPresetId: 'user-1',
        exportLast: mine.copyWith(quality: 50),
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.exportPresets, [mine]);
      expect(back.exportPresetId, 'user-1');
      expect(back.exportLast!.quality, 50);
      expect(initialExportPreset(back).preset, mine);
      expect(allExportPresets(back), hasLength(5));
      final cleared = back.copyWith(clearExportPresetId: true);
      final init = initialExportPreset(cleared);
      expect(init.presetId, isNull);
      expect(init.preset.quality, 50);
      expect(
        AppSettings.fromJson({
          'exportPresets': [
            {'id': ''},
            'junk',
            {'id': 'a', 'name': 'A'},
          ],
        }).exportPresets.single.name,
        'A',
      );
    });

    test('without presets the old export preferences are the start', () {
      final s = const AppSettings().copyWith(
        exportFormat: 'png',
        exportQuality: 70,
        exportLongEdge: 1080,
      );
      final p = initialExportPreset(s).preset;
      expect(p.format, ExportFileFormat.png);
      expect(p.quality, 70);
      expect(p.size, const ExportSizeLimit.longEdge(1080));
      expect(initialExportPreset(null).preset.format, ExportFileFormat.jpeg);
    });

    test('depth hint', () {
      CatalogEntry e(String format, int? depth) => CatalogEntry(
        assetId: format,
        fileName: 'a',
        originalPath: 'a',
        format: format,
        width: 1,
        height: 1,
        bytes: 1,
        importedAt: DateTime(2026),
        bitDepth: depth,
      );
      expect(
        depthHintFor([e('jpeg', 8)]),
        'This photo is 8-bit; 16-bit adds no detail.',
      );
      expect(depthHintFor([e('cr3', null)]), startsWith('High-bit-depth'));
      expect(
        depthHintFor([e('jpeg', 8), e('cr3', null), e('png', 16)]),
        '1 of 3 photos are 8-bit; 16-bit adds no detail to those.',
      );
      expect(depthHintFor([e('cr3', null), e('dng', 16)]), startsWith('All'));
    });
  });
}
