import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

CatalogEntry _e(String id, {String? project}) => CatalogEntry(
  assetId: id,
  fileName: '$id.jpg',
  originalPath: 'originals/$id.jpg',
  format: 'jpeg',
  width: 4,
  height: 3,
  bytes: 1,
  importedAt: DateTime.utc(2026, 10, 1),
  projectId: project,
);

Project _p(String id, {String? cover}) => Project(
  id: id,
  name: 'Shoot $id',
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: DateTime.utc(2026, 10, 1),
  coverAssetId: cover,
);

final _later = DateTime.utc(2026, 10, 5);

void main() {
  group('Project', () {
    test('json round trip keeps every field', () {
      final p = Project(
        id: 'p1',
        name: 'Wedding',
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 2),
        coverAssetId: 'a',
        shootDate: DateTime.utc(2026, 8, 30),
        notes: 'Church at 2pm',
      );
      final back = Project.tryFromJson(p.toJson())!;
      expect(back.toJson(), p.toJson());
      expect(back.displayDate, DateTime.utc(2026, 8, 30));
    });

    test('rejects documents without an id; blank names get a default', () {
      expect(Project.tryFromJson({'name': 'x'}), isNull);
      expect(Project.tryFromJson('nope'), isNull);
      final p = Project.tryFromJson({'id': 'p', 'name': '  '})!;
      expect(p.name, 'Untitled shoot');
      expect(p.updatedAt, p.createdAt);
      expect(p.displayDate, p.createdAt);
    });

    test('copyWith clears the cover only when asked', () {
      final p = _p('p', cover: 'a');
      expect(p.copyWith(name: 'B').coverAssetId, 'a');
      expect(p.copyWith(clearCover: true).coverAssetId, isNull);
    });
  });

  group('CatalogEntry project fields', () {
    test('round trip project, exportedAt, retouched', () {
      final e = _e(
        'a',
        project: 'p',
      ).copyWith(exportedAt: DateTime.utc(2026, 10, 2), retouched: true);
      final back = CatalogEntry.fromJson(e.toJson());
      expect(back.projectId, 'p');
      expect(back.exportedAt, DateTime.utc(2026, 10, 2));
      expect(back.retouched, isTrue);
    });

    test('copyWith keeps the project; withProject changes it', () {
      final e = _e('a', project: 'p');
      expect(e.copyWith(rating: 3).projectId, 'p');
      expect(e.withProject(null).projectId, isNull);
      expect(e.withProject('q').rating, e.rating);
    });

    test('an export is current until the photo is edited again', () {
      final out = DateTime.utc(2026, 10, 2);
      final e = _e('a').copyWith(exportedAt: out);
      expect(e.exportIsCurrent, isTrue);
      expect(e.copyWith(editedAt: out).exportIsCurrent, isTrue);
      expect(
        e.copyWith(editedAt: DateTime.utc(2026, 10, 3)).exportIsCurrent,
        isFalse,
      );
      expect(_e('b').exportIsCurrent, isFalse);
    });

    test('withEditState follows the settings', () {
      final at = DateTime.utc(2026, 10, 3);
      final plain = _e('a').withEditState(DevelopSettings.defaults, at);
      expect(plain.hasEdits, isFalse);
      expect(plain.retouched, isFalse);
      expect(plain.editedAt, at);
      final edited = _e(
        'a',
      ).withEditState(DevelopSettings.defaults.withValue(P.exposure, 0.4), at);
      expect(edited.hasEdits, isTrue);
      expect(edited.retouched, isFalse);
    });
  });

  group('CatalogIndex migration', () {
    test('a v1 catalog loads unchanged with every photo Unsorted', () {
      final v1 = {
        'schemaVersion': 1,
        'entries': [
          {
            'assetId': 'a',
            'fileName': 'a.jpg',
            'original': 'originals/a.jpg',
            'format': 'jpeg',
            'width': 10,
            'height': 8,
            'bytes': 3,
            'importedAt': '2026-10-03T00:00:00.000Z',
            'hasEdits': true,
            'flag': 'pick',
            'rating': 4,
          },
          {'fileName': 'no id is dropped'},
          'garbage',
        ],
      };
      final index = CatalogIndex.fromJson(v1);
      expect(index.projects, isEmpty);
      final a = index.entries['a']!;
      expect(a.projectId, isNull);
      expect(a.exportedAt, isNull);
      expect(a.retouched, isFalse);
      expect((a.hasEdits, a.flag, a.rating), (true, 'pick', 4));
      expect(index.entries, hasLength(1));
      final out = index.toJson();
      expect(out['schemaVersion'], kCatalogSchemaVersion);
      expect(out['projects'], isEmpty);
    });

    test('v2 round trip keeps projects and memberships', () {
      final index = CatalogIndex(
        entries: {
          'a': _e('a', project: 'p'),
          'b': _e('b'),
        },
        projects: {'p': _p('p', cover: 'a')},
      );
      final back = CatalogIndex.fromJson(index.toJson());
      expect(back.projects['p']!.coverAssetId, 'a');
      expect(back.entries['a']!.projectId, 'p');
      expect(back.photosOf(null).map((e) => e.assetId), ['b']);
    });

    test('dangling project ids and covers are repaired on load', () {
      final json = {
        'schemaVersion': 2,
        'projects': [
          _p('p', cover: 'b').toJson(),
          {'name': 'no id'},
        ],
        'entries': [_e('a', project: 'gone').toJson(), _e('b').toJson()],
      };
      final index = CatalogIndex.fromJson(json);
      expect(index.projects.keys, ['p']);
      expect(index.entries['a']!.projectId, isNull);
      expect(index.projects['p']!.coverAssetId, isNull);
    });
  });

  group('CatalogIndex operations', () {
    final base = CatalogIndex(
      entries: {
        'a': _e('a', project: 'p'),
        'b': _e('b', project: 'p'),
        'c': _e('c'),
      },
      projects: {
        'p': _p('p', cover: 'a'),
        'q': _p('q'),
      },
    );

    test('withEntry stores unknown projects as Unsorted', () {
      final next = base.withEntry(_e('d', project: 'nope'), at: _later);
      expect(next.entries['d']!.projectId, isNull);
      expect(base.entries.containsKey('d'), isFalse, reason: 'immutable');
    });

    test('adding a photo to a project bumps its updatedAt', () {
      final next = base.withEntry(_e('d', project: 'q'), at: _later);
      expect(next.projects['q']!.updatedAt, _later);
      expect(next.sortedProjects.first.id, 'q');
      final same = base.withEntry(base.entries['a']!.copyWith(rating: 2));
      expect(same.projects['p']!.updatedAt, DateTime.utc(2026, 10, 1));
    });

    test('withUpdatedEntry keeps the stored project and export stamp', () {
      final moved = base.movePhotos(['a'], 'q', at: _later).markExported([
        'a',
      ], _later);
      // An update built from a copy read before the move and the export.
      final stale = base.entries['a']!.copyWith(rating: 5);
      final next = moved.withUpdatedEntry(stale);
      expect(next.entries['a']!.rating, 5);
      expect(next.entries['a']!.projectId, 'q');
      expect(next.entries['a']!.exportedAt, _later);
      final newer = DateTime.utc(2026, 10, 9);
      final stamped = moved.withUpdatedEntry(stale.copyWith(exportedAt: newer));
      expect(stamped.entries['a']!.exportedAt, newer);
      expect(identical(base.withUpdatedEntry(_e('zz')), base), isTrue);
    });

    test('withoutEntry clears a cover pointing at the photo', () {
      final next = base.withoutEntry('a');
      expect(next.entries.containsKey('a'), isFalse);
      expect(next.projects['p']!.coverAssetId, isNull);
      expect(identical(base.withoutEntry('zz'), base), isTrue);
    });

    test('deleting a project keeps its photos as Unsorted', () {
      final r = base.withoutProject('p', deletePhotos: false);
      expect(r.removedAssetIds, isEmpty);
      expect(r.index.projects.keys, ['q']);
      expect(r.index.photosOf(null).map((e) => e.assetId).toSet(), {
        'a',
        'b',
        'c',
      });
    });

    test('deleting a project with its photos removes them', () {
      final r = base.withoutProject('p', deletePhotos: true);
      expect(r.removedAssetIds.toSet(), {'a', 'b'});
      expect(r.index.entries.keys, ['c']);
      final none = base.withoutProject('nope', deletePhotos: true);
      expect(none.removedAssetIds, isEmpty);
    });

    test('movePhotos moves, bumps the target and clears stale covers', () {
      final next = base.movePhotos(['a', 'c', 'missing'], 'q', at: _later);
      expect(next.entries['a']!.projectId, 'q');
      expect(next.entries['c']!.projectId, 'q');
      expect(next.entries['b']!.projectId, 'p');
      expect(next.projects['p']!.coverAssetId, isNull);
      expect(next.projects['q']!.updatedAt, _later);
      final out = next.movePhotos(['a'], null, at: _later);
      expect(out.entries['a']!.projectId, isNull);
      expect(
        () => base.movePhotos(['a'], 'nope', at: _later),
        throwsArgumentError,
      );
      expect(identical(base.movePhotos(['zz'], 'q', at: _later), base), isTrue);
    });

    test('markExported stamps only the given photos', () {
      final next = base.markExported(['a'], _later);
      expect(next.entries['a']!.exportedAt, _later);
      expect(next.entries['b']!.exportedAt, isNull);
    });
  });
}
