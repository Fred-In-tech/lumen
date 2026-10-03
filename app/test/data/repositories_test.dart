import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/data/app_settings.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/data/file_preference_repositories_io.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen_core/lumen_core.dart';

CatalogEntry _entry(String id, {DateTime? at}) => CatalogEntry(
      assetId: id,
      fileName: '$id.jpg',
      originalPath: 'originals/$id.jpg',
      format: 'jpeg',
      width: 10,
      height: 10,
      bytes: 3,
      importedAt: at ?? DateTime.utc(2026, 10, 3),
    );

void _contract(String name, Future<CatalogRepository> Function() make) {
  group(name, () {
    test('add, dedupe, list sorted newest first', () async {
      final repo = await make();
      await repo.add(_entry('a', at: DateTime.utc(2026, 1, 1)), Uint8List.fromList([1, 2, 3]));
      await repo.add(_entry('b', at: DateTime.utc(2026, 5, 1)), Uint8List.fromList([4]));
      final again = await repo.add(_entry('a'), Uint8List.fromList([9]));
      expect(again.importedAt, DateTime.utc(2026, 1, 1));
      final all = await repo.list();
      expect(all.map((e) => e.assetId), ['b', 'a']);
      expect(await repo.readOriginal('a'), [1, 2, 3]);
    });

    test('edit documents persist; missing edit gives a fresh doc', () async {
      final repo = await make();
      await repo.add(_entry('a'), Uint8List(1));
      expect((await repo.loadEdit('a')).settings.isDefault, isTrue);
      final doc = EditDocument.create('a').copyWith(settings: DevelopSettings.defaults.withValue(P.exposure, 0.7));
      await repo.saveEdit(doc);
      expect((await repo.loadEdit('a')).settings.value(P.exposure), 0.7);
    });

    test('update, thumbs, delete', () async {
      final repo = await make();
      await repo.add(_entry('a'), Uint8List(1));
      await repo.update((await repo.get('a'))!.copyWith(hasEdits: true));
      expect((await repo.get('a'))!.hasEdits, isTrue);
      await repo.writeThumb('a', Uint8List.fromList([7, 7]));
      expect(await repo.readThumb('a'), [7, 7]);
      await repo.delete('a');
      expect(await repo.get('a'), isNull);
      expect(() => repo.readOriginal('a'), throwsA(isA<CatalogException>()));
    });

    test('watch emits after changes', () async {
      final repo = await make();
      final emitted = <int>[];
      final sub = repo.watch().listen((l) => emitted.add(l.length));
      await Future<void>.delayed(Duration.zero);
      await repo.add(_entry('a'), Uint8List(1));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(emitted, containsAllInOrder([0, 1]));
    });
  });
}

void main() {
  _contract('MemoryCatalogRepository', () async => MemoryCatalogRepository());

  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('lumen_test'));
  tearDown(() async => tmp.delete(recursive: true));

  _contract('FileCatalogRepository', () async => FileCatalogRepository(tmp.path));

  test('file catalog survives a reopen and recovers from a corrupt index', () async {
    final repo = FileCatalogRepository(tmp.path);
    await repo.add(_entry('a'), Uint8List.fromList([1]));
    expect((await FileCatalogRepository(tmp.path).list()).single.assetId, 'a');
    await File('${tmp.path}/catalog.json').writeAsString('{not json');
    expect(await FileCatalogRepository(tmp.path).list(), isEmpty);
    expect(tmp.listSync().any((f) => f.path.contains('catalog.json.corrupt')), isTrue);
  });

  test('corrupt edit.json yields a fresh document', () async {
    final repo = FileCatalogRepository(tmp.path);
    await repo.add(_entry('a'), Uint8List(1));
    await Directory('${tmp.path}/assets/a').create(recursive: true);
    await File('${tmp.path}/assets/a/edit.json').writeAsString('garbage');
    expect((await repo.loadEdit('a')).settings.isDefault, isTrue);
  });

  test('presets and settings persist', () async {
    final presets = FilePresetRepository(tmp.path);
    await presets.save(Preset(id: 'u/1', name: 'Mine', values: const {P.temp: 5}));
    expect((await FilePresetRepository(tmp.path).list()).single.values[P.temp], 5);
    await presets.delete('u/1');
    expect(await presets.list(), isEmpty);

    final settings = FileSettingsRepository(tmp.path);
    expect((await settings.load()).autoEditOnImport, isTrue);
    await settings.save(const AppSettings(defaultStyle: 'moody', exportQuality: 80));
    final back = await FileSettingsRepository(tmp.path).load();
    expect(back.defaultStyle, 'moody');
    expect(back.exportQuality, 80);
  });
}
