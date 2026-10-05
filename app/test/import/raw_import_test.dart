import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_service.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen/import/photo_decoder.dart';
import 'package:lumen/import/raw_developer.dart';

import '../support/fixtures.dart';

/// Stands in for the OS RAW decoder: hands back a canned rendition or fails.
class _FakeRawDeveloper implements RawDeveloper {
  _FakeRawDeveloper({this.rendition, this.error});

  final Uint8List? rendition;
  final RawDevelopException? error;
  final List<String> developed = [];

  @override
  Future<Uint8List> develop(Uint8List raw, {required String extension}) async {
    developed.add(extension);
    if (error != null) throw error!;
    return rendition!;
  }
}

/// A developed rendition as the native side writes it: upright JPEG pixels
/// carrying the camera's EXIF.
Uint8List _rendition({int w = 600, int h = 400}) {
  final im = Fixtures.gradient(w, h, seed: 3);
  im.exif.imageIfd['Make'] = 'Canon';
  im.exif.imageIfd['Model'] = 'Canon EOS R5';
  im.exif.exifIfd[0x8827] = img.IfdValueShort(250); // ISOSpeedRatings
  im.exif.exifIfd['DateTimeOriginal'] = '2026:09:17 10:51:29';
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RAW import keeps the RAW as the original and reads pixels, size, '
      'EXIF and the thumbnail from the developed rendition', () async {
    final repo = MemoryCatalogRepository();
    final raw = _FakeRawDeveloper(rendition: _rendition());
    final service = ImportService(repo, rawDeveloper: raw);
    final cr3 = Fixtures.cr3();

    final r = await service.importOne(
      ImportFile(name: '541A4390.CR3', bytes: cr3),
    );

    expect(r, isA<Imported>());
    final e = (r as Imported).entry;
    expect(raw.developed, ['cr3']);
    expect(e.format, 'cr3');
    expect(e.originalPath, 'originals/${e.assetId}.cr3');
    expect(e.bytes, cr3.length);
    expect((e.width, e.height), (600, 400));
    expect(e.exif.camera, 'Canon EOS R5');
    expect(e.exif.iso, 250);
    expect(e.exif.capturedAt, DateTime(2026, 9, 17, 10, 51, 29));
    expect(await repo.readOriginal(e.assetId), cr3);
    expect(
      sniffFormat(await repo.readPixelSource(e.assetId)),
      PhotoFormat.jpeg,
    );
    final thumb = await decodePhoto((await repo.readThumb(e.assetId))!);
    addTearDown(thumb.dispose);
    expect(thumb.width, ImportService.thumbLongEdge);

    // The same RAW again is a duplicate and is not developed twice.
    final again = await service.importOne(
      ImportFile(name: 'copy.cr3', bytes: cr3),
    );
    expect(again, isA<Duplicate>());
    expect(raw.developed, ['cr3']);
  });

  test('CR2 goes through the developer too; JPEG never does', () async {
    final repo = MemoryCatalogRepository();
    final raw = _FakeRawDeveloper(rendition: _rendition(w: 90, h: 60));
    final service = ImportService(repo, rawDeveloper: raw);
    final results = await service.importAll([
      ImportFile(name: 'IMG_0001.CR2', bytes: Fixtures.cr2()),
      ImportFile(name: 'a.jpg', bytes: Fixtures.jpeg()),
    ]);
    expect(results, everyElement(isA<Imported>()));
    expect(raw.developed, ['cr2']);
    final jpg = (results[1] as Imported).entry;
    expect(
      await repo.readPixelSource(jpg.assetId),
      await repo.readOriginal(jpg.assetId),
    );
  });

  test('RAW on a platform without a decoder fails with a friendly message '
      'and stores nothing', () async {
    final repo = MemoryCatalogRepository();
    final service = ImportService(
      repo,
      rawDeveloper: _FakeRawDeveloper(
        error: const RawDevelopException(kRawUnsupportedMessage),
      ),
    );
    final r = await service.importOne(
      ImportFile(name: 'a.cr3', bytes: Fixtures.cr3()),
    );
    expect(r, isA<ImportFailed>());
    expect(
      (r as ImportFailed).reason,
      "RAW photos aren't supported on this device yet.",
    );
    expect(await repo.list(), isEmpty);
  });

  test('a native develop failure is reported, not thrown', () async {
    final repo = MemoryCatalogRepository();
    final service = ImportService(
      repo,
      rawDeveloper: _FakeRawDeveloper(
        error: const RawDevelopException(
          'This RAW file could not be developed.',
        ),
      ),
    );
    final results = await service.importAll([
      ImportFile(name: 'broken.cr3', bytes: Fixtures.cr3(seed: 1)),
      ImportFile(name: 'ok.jpg', bytes: Fixtures.jpeg()),
    ]);
    expect(
      (results[0] as ImportFailed).reason,
      contains('could not be developed'),
    );
    expect(results[1], isA<Imported>());
    expect((await repo.list()).single.fileName, 'ok.jpg');
  });

  test(
    'a rendition the engine cannot decode fails the import cleanly',
    () async {
      final repo = MemoryCatalogRepository();
      final service = ImportService(
        repo,
        rawDeveloper: _FakeRawDeveloper(rendition: Uint8List.fromList([1, 2])),
      );
      final r = await service.importOne(
        ImportFile(name: 'a.cr3', bytes: Fixtures.cr3()),
      );
      expect(r, isA<ImportFailed>());
      expect(await repo.list(), isEmpty);
    },
  );

  test('without the native handler (tests, unsupported embedders) the '
      'default developer reports RAW as unsupported', () async {
    final repo = MemoryCatalogRepository();
    final r = await ImportService(repo)
        .importOne(ImportFile(name: 'a.cr3', bytes: Fixtures.cr3()));
    expect((r as ImportFailed).reason, kRawUnsupportedMessage);
  });

  test(
    'exporting a RAW photo renders the rendition and carries its EXIF',
    () async {
      final repo = MemoryCatalogRepository();
      final r = await ImportService(
        repo,
        rawDeveloper: _FakeRawDeveloper(rendition: _rendition()),
      ).importOne(ImportFile(name: 'shot.cr3', bytes: Fixtures.cr3()));
      final id = (r as Imported).entry.assetId;

      final out = await ExportService(repo).exportOne(
        id,
        const ExportOptions(format: ExportFormat.jpeg, longEdge: 150),
      );

      expect(out.fileName, endsWith('.jpg'));
      expect((out.width, out.height), (150, 100));
      final tags = await readExifFromBytes(out.bytes);
      expect(tags['Image Model']?.printable, 'Canon EOS R5');
    },
  );
}
