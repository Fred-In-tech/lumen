import 'dart:convert';
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
      await repo.add(
        _entry('a', at: DateTime.utc(2026, 1, 1)),
        Uint8List.fromList([1, 2, 3]),
      );
      await repo.add(
        _entry('b', at: DateTime.utc(2026, 5, 1)),
        Uint8List.fromList([4]),
      );
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
      final doc = EditDocument.create(
        'a',
      ).copyWith(settings: DevelopSettings.defaults.withValue(P.exposure, 0.7));
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

    test(
      'pixel source is the original unless a rendition was stored',
      () async {
        final repo = await make();
        await repo.add(_entry('a'), Uint8List.fromList([1, 2, 3]));
        expect(await repo.readPixelSource('a'), [1, 2, 3]);

        // Camera RAW: the untouched file stays the original, pixels come from
        // the developed rendition.
        await repo.add(
          _entry('r'),
          Uint8List.fromList([9, 9]),
          rendition: Uint8List.fromList([4, 5, 6]),
        );
        expect(await repo.readOriginal('r'), [9, 9]);
        expect(await repo.readPixelSource('r'), [4, 5, 6]);
        // A duplicate add never replaces the stored rendition.
        await repo.add(_entry('r'), Uint8List(1), rendition: Uint8List(1));
        expect(await repo.readPixelSource('r'), [4, 5, 6]);

        await repo.delete('r');
        expect(
          () => repo.readPixelSource('r'),
          throwsA(isA<CatalogException>()),
        );
        expect(
          () => repo.readPixelSource('nope'),
          throwsA(isA<CatalogException>()),
        );
      },
    );

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

    test('create, rename, list and watch projects', () async {
      final repo = await make();
      final names = <List<String>>[];
      final sub = repo.watchProjects().listen(
        (l) => names.add([for (final p in l) p.name]),
      );
      await Future<void>.delayed(Duration.zero);
      final p = await repo.createProject(
        name: '  Smith wedding ',
        shootDate: DateTime.utc(2026, 9, 1),
      );
      expect(p.name, 'Smith wedding');
      await repo.updateProject(p.copyWith(name: 'Smith & Lee wedding'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      final listed = await repo.listProjects();
      expect(listed.single.name, 'Smith & Lee wedding');
      expect(listed.single.shootDate, DateTime.utc(2026, 9, 1));
      expect(names.first, isEmpty);
      expect(names.last, ['Smith & Lee wedding']);
      expect(
        () => repo.createProject(name: '   '),
        throwsA(isA<CatalogException>()),
      );
      expect(
        () => repo.updateProject(p.copyWith(name: '')),
        throwsA(isA<CatalogException>()),
      );
    });

    test('photos join projects on import and move between them', () async {
      final repo = await make();
      final a = await repo.createProject(name: 'A');
      final b = await repo.createProject(name: 'B');
      await repo.add(_entry('x').withProject(a.id), Uint8List(1));
      await repo.add(_entry('y'), Uint8List(1));
      expect((await repo.get('x'))!.projectId, a.id);
      expect((await repo.get('y'))!.projectId, isNull);
      await repo.movePhotos(['x', 'y'], b.id);
      expect((await repo.get('x'))!.projectId, b.id);
      expect((await repo.get('y'))!.projectId, b.id);
      await repo.movePhotos(['y'], null);
      expect((await repo.get('y'))!.projectId, isNull);
      expect(
        () => repo.movePhotos(['x'], 'nope'),
        throwsA(isA<CatalogException>()),
      );
      // A stale copy of the entry cannot undo the move.
      await repo.update(_entry('x').copyWith(flag: 'pick'));
      expect((await repo.get('x'))!.projectId, b.id);
      expect((await repo.get('x'))!.flag, 'pick');
    });

    test('set cover: only a photo of the project', () async {
      final repo = await make();
      final p = await repo.createProject(name: 'P');
      await repo.add(_entry('x').withProject(p.id), Uint8List(1));
      await repo.add(_entry('y'), Uint8List(1));
      await repo.updateProject(p.copyWith(coverAssetId: 'x'));
      expect((await repo.listProjects()).single.coverAssetId, 'x');
      expect(
        () => repo.updateProject(p.copyWith(coverAssetId: 'y')),
        throwsA(isA<CatalogException>()),
      );
      await repo.updateProject(p.copyWith(clearCover: true));
      expect((await repo.listProjects()).single.coverAssetId, isNull);
    });

    test('delete a project keeping its photos as Unsorted', () async {
      final repo = await make();
      final p = await repo.createProject(name: 'P');
      await repo.add(_entry('x').withProject(p.id), Uint8List.fromList([1]));
      await repo.deleteProject(p.id);
      expect(await repo.listProjects(), isEmpty);
      expect((await repo.get('x'))!.projectId, isNull);
      expect(await repo.readOriginal('x'), [1]);
    });

    test('delete a project with its photos', () async {
      final repo = await make();
      final p = await repo.createProject(name: 'P');
      await repo.add(_entry('x').withProject(p.id), Uint8List.fromList([1]));
      await repo.add(_entry('y'), Uint8List.fromList([2]));
      await repo.writeThumb('x', Uint8List.fromList([7]));
      await repo.deleteProject(p.id, deletePhotos: true);
      expect(await repo.get('x'), isNull);
      expect(await repo.readThumb('x'), isNull);
      expect(() => repo.readOriginal('x'), throwsA(isA<CatalogException>()));
      expect(await repo.readOriginal('y'), [2]);
    });

    test('markExported stamps the photos', () async {
      final repo = await make();
      await repo.add(_entry('x'), Uint8List(1));
      final at = DateTime.utc(2026, 10, 6);
      await repo.markExported(['x'], at);
      expect((await repo.get('x'))!.exportedAt, at);
    });
  });
}

void main() {
  _contract('MemoryCatalogRepository', () async => MemoryCatalogRepository());

  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('lumen_test'));
  tearDown(() async => tmp.delete(recursive: true));

  _contract(
    'FileCatalogRepository',
    () async => FileCatalogRepository(tmp.path),
  );

  test(
    'file catalog survives a reopen and recovers from a corrupt index',
    () async {
      final repo = FileCatalogRepository(tmp.path);
      await repo.add(_entry('a'), Uint8List.fromList([1]));
      expect(
        (await FileCatalogRepository(tmp.path).list()).single.assetId,
        'a',
      );
      await File('${tmp.path}/catalog.json').writeAsString('{not json');
      expect(await FileCatalogRepository(tmp.path).list(), isEmpty);
      expect(
        tmp.listSync().any((f) => f.path.contains('catalog.json.corrupt')),
        isTrue,
      );
    },
  );

  test('a v1 catalog.json opens unchanged and is rewritten as v2', () async {
    final v1 = {
      'schemaVersion': 1,
      'entries': [
        {..._entry('a').toJson(), 'flag': 'pick', 'hasEdits': true},
      ],
    };
    await File('${tmp.path}/catalog.json').writeAsString(jsonEncode(v1));
    final repo = FileCatalogRepository(tmp.path);
    final a = (await repo.list()).single;
    expect((a.assetId, a.flag, a.hasEdits), ('a', 'pick', true));
    expect(a.projectId, isNull);
    expect(await repo.listProjects(), isEmpty);
    final p = await repo.createProject(name: 'Shoot');
    await repo.movePhotos(['a'], p.id);
    final json = jsonDecode(
      File('${tmp.path}/catalog.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(json['schemaVersion'], kCatalogSchemaVersion);
    expect((json['projects']! as List).single['name'], 'Shoot');
    final reopened = FileCatalogRepository(tmp.path);
    expect((await reopened.get('a'))!.projectId, p.id);
    expect((await reopened.listProjects()).single.id, p.id);
  });

  test('renditions live in renditions/ and go away with the photo', () async {
    final repo = FileCatalogRepository(tmp.path);
    await repo.add(_entry('a'), Uint8List.fromList([1]));
    await repo.add(
      _entry('r'),
      Uint8List.fromList([9]),
      rendition: Uint8List.fromList([4, 5]),
    );
    final rendition = File('${tmp.path}/renditions/r.jpg');
    expect(rendition.readAsBytesSync(), [4, 5]);
    expect(File('${tmp.path}/renditions/a.jpg').existsSync(), isFalse);
    // A reopened catalog (and so any catalog from before RAW support, which
    // has no renditions folder) resolves pixel sources the same way.
    final reopened = FileCatalogRepository(tmp.path);
    expect(await reopened.readPixelSource('r'), [4, 5]);
    expect(await reopened.readPixelSource('a'), [1]);
    await reopened.delete('r');
    expect(rendition.existsSync(), isFalse);
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
    await presets.save(
      Preset(id: 'u/1', name: 'Mine', values: const {P.temp: 5}),
    );
    expect(
      (await FilePresetRepository(tmp.path).list()).single.values[P.temp],
      5,
    );
    await presets.delete('u/1');
    expect(await presets.list(), isEmpty);

    final settings = FileSettingsRepository(tmp.path);
    expect((await settings.load()).autoEditOnImport, isTrue);
    await settings.save(
      const AppSettings(defaultStyle: 'moody', exportQuality: 80),
    );
    final back = await FileSettingsRepository(tmp.path).load();
    expect(back.defaultStyle, 'moody');
    expect(back.exportQuality, 80);
  });
}
