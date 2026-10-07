import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/file_lut_repository_io.dart';
import 'package:lumen/data/lut_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/features/looks/inflate_io.dart';
import 'package:lumen/features/looks/look_import_service.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../support/look_files.dart';
import '../../support/lut_fixtures.dart';

/// Runs [body] with a live WidgetRef (the import API takes one).
Future<T> _withRef<T>(
  WidgetTester tester,
  List<Override> overrides,
  Future<T> Function(WidgetRef ref) body,
) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return const SizedBox();
        },
      ),
    ),
  );
  final out = await tester.runAsync(() => body(captured));
  return out as T;
}

void main() {
  tearDown(CreativeLuts.reset);

  group('LUT library', () {
    test('memory: save, load, hashes', () async {
      final repo = MemoryLutRepository();
      final lut = tealOrangeLut(size: 5);
      await repo.save(lut);
      expect(await repo.load(lut.contentHash), same(lut));
      expect(await repo.hashes(), {lut.contentHash});
      expect(await repo.load('0000000000000000'), isNull);
    });

    test('files: stored once per hash, round trip, bad data', () async {
      final dir = await Directory.systemTemp.createTemp('luts');
      addTearDown(() => dir.delete(recursive: true));
      final repo = FileLutRepository(dir.path);
      final lut = tealOrangeLut(size: 7);
      await repo.save(lut);
      await repo.save(lut.renamed('Same table'));
      final files = Directory('${dir.path}/luts').listSync();
      expect(files, hasLength(1));
      final back = await repo.load(lut.contentHash);
      expect(back!.contentHash, lut.contentHash);
      expect(back.title, 'Teal & Orange');
      expect(await repo.hashes(), {lut.contentHash});
      expect(await repo.load('../../etc/passwd'), isNull);
      expect(await repo.load('0123456789abcdef'), isNull);
      File('${dir.path}/luts/0123456789abcdef.lut').writeAsBytesSync([1, 2]);
      expect(await repo.load('0123456789abcdef'), isNull);
      expect(await FileLutRepository('${dir.path}/none').hashes(), isEmpty);
    });
  });

  group('capped inflate', () {
    test('inflates, and stops a bomb at the declared size', () {
      final data = Uint8List(200000); // zeros: ~1000:1
      final packed = Uint8List.fromList(ZLibEncoder(raw: true).convert(data));
      expect(inflateCapped(packed, data.length), data);
      expect(
        () => inflateCapped(packed, 1000),
        throwsA(isA<FormatException>()),
      );
    });
  });

  testWidgets('import saves presets and LUTs, reports, skips duplicates', (
    tester,
  ) async {
    final presets = MemoryPresetRepository();
    final luts = MemoryLutRepository();
    final overrides = [
      presetRepositoryProvider.overrideWithValue(presets),
      lutRepositoryProvider.overrideWithValue(luts),
    ];
    final outcome = await _withRef(
      tester,
      overrides,
      (ref) => importLooksInto(ref, sampleLookFiles()),
    );
    expect(outcome.saved.map((p) => p.name), [
      'Airy Wedding',
      'Moody Film',
      'Teal & Orange',
    ]);
    expect(outcome.result.failures.single.fileName, 'notes.cube');
    expect(
      outcome.headline,
      '2 presets imported · 1 LUT imported · 1 file not imported',
    );
    final stored = await presets.list();
    expect(stored, hasLength(3));
    final lut = stored.firstWhere((p) => p.isLutOnly).lut!;
    expect(await luts.load(lut.hash), isNotNull);
    expect(CreativeLuts.cached(lut.hash), isNotNull);
    final airy = stored.firstWhere((p) => p.name == 'Airy Wedding');
    expect(
      airy.importReport!.skipped,
      containsAll(['Calibration', 'Lens profile']),
    );
    expect(airy.values[P.exposure], 0.6);

    // The same files again: nothing new.
    final again = await _withRef(
      tester,
      overrides,
      (ref) => importLooksInto(ref, sampleLookFiles().take(3).toList()),
    );
    expect(again.saved, isEmpty);
    expect(again.duplicates, 3);
    expect(again.headline, '3 already in your looks');
    expect(await presets.list(), hasLength(3));
  });

  test('reading dropped files keeps looks only and folders', () async {
    final dir = await Directory.systemTemp.createTemp('drop');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/a.xmp').writeAsStringSync(kAiryXmp);
    File('${dir.path}/b.jpg').writeAsBytesSync([1, 2, 3]);
    Directory('${dir.path}/pack').createSync();
    File('${dir.path}/pack/c.lrtemplate').writeAsStringSync(kFilmLrTemplate);
    final files = await readLookXFiles([
      XFile('${dir.path}/a.xmp'),
      XFile('${dir.path}/b.jpg'),
      XFile('${dir.path}/pack'),
    ]);
    expect(files.map((f) => f.name).toSet(), {'a.xmp', 'c.lrtemplate'});
  });
}
