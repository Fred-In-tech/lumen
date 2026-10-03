import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';

import 'dart:convert';

import '../support/fixtures.dart';
import '../support/format_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sniffs formats from magic bytes', () {
    expect(sniffFormat(Fixtures.jpeg()), PhotoFormat.jpeg);
    expect(sniffFormat(Fixtures.png()), PhotoFormat.png);
    final webp = Uint8List.fromList([
      0x52,
      0x49,
      0x46,
      0x46,
      0,
      0,
      0,
      0,
      0x57,
      0x45,
      0x42,
      0x50,
    ]);
    expect(sniffFormat(webp), PhotoFormat.webp);
    final heic = Uint8List.fromList([
      0,
      0,
      0,
      0x18,
      0x66,
      0x74,
      0x79,
      0x70,
      0x68,
      0x65,
      0x69,
      0x63,
    ]);
    expect(sniffFormat(heic), PhotoFormat.heic);
    expect(sniffFormat(Uint8List.fromList([1, 2, 3])), PhotoFormat.unknown);
  });

  test('imports JPEG and PNG, dedupes, writes thumbs, rejects junk', () async {
    final repo = MemoryCatalogRepository();
    final service = ImportService(repo, clock: () => DateTime.utc(2026, 10, 3));
    final results = await service.importAll([
      ImportFile(name: 'a.jpg', bytes: Fixtures.jpeg(w: 800, h: 600)),
      ImportFile(name: 'b.png', bytes: Fixtures.png(seed: 9)),
      ImportFile(name: 'a-copy.jpg', bytes: Fixtures.jpeg(w: 800, h: 600)),
      ImportFile(
        name: 'notes.txt',
        bytes: Uint8List.fromList('hello'.codeUnits),
      ),
    ]);
    expect(results[0], isA<Imported>());
    expect(results[1], isA<Imported>());
    expect(results[2], isA<Duplicate>());
    expect(results[3], isA<ImportFailed>());
    final entries = await repo.list();
    expect(entries.length, 2);
    final a = entries.firstWhere((e) => e.fileName == 'a.jpg');
    expect(a.width, 800);
    expect(a.height, 600);
    expect(a.originalPath, endsWith('.jpg'));
    expect(await repo.readThumb(a.assetId), isNotNull);
  });

  test('imports WebP (engine codec)', () async {
    final repo = MemoryCatalogRepository();
    final r = await ImportService(repo).importOne(
      ImportFile(name: 'g.webp', bytes: base64Decode(kWebpFixtureB64)),
    );
    expect(r, isA<Imported>());
    final e = (r as Imported).entry;
    expect(e.format, 'webp');
    expect(e.width, 320);
    expect(e.height, 214);
  });
}
