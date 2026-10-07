import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 10, 1);

CatalogEntry _e(
  String id, {
  String flag = PhotoFlag.none,
  bool edited = false,
  bool retouched = false,
  DateTime? exportedAt,
  DateTime? editedAt,
}) => CatalogEntry(
  assetId: id,
  fileName: '$id.jpg',
  originalPath: 'originals/$id.jpg',
  format: 'jpeg',
  width: 4,
  height: 3,
  bytes: 1,
  importedAt: _t0,
  flag: flag,
  hasEdits: edited,
  editedAt: editedAt ?? (edited ? _t0 : null),
  retouched: retouched,
  exportedAt: exportedAt,
);

List<CatalogEntry> _many(int n, {String flag = PhotoFlag.none}) => [
  for (var i = 0; i < n; i++) _e('p$i', flag: flag),
];

void main() {
  group('computeProjectProgress', () {
    test('an empty project asks for photos', () {
      final p = computeProjectProgress(const []);
      expect(p.of(ProjectStep.import).state, StepState.notStarted);
      expect(p.of(ProjectStep.import).summary, 'No photos yet');
      expect(p.next.step, ProjectStep.import);
      expect(p.next.label, 'Add photos');
      expect(p.completedSteps, 1, reason: 'retouch is optional');
    });

    test('a fresh import: next is culling every photo', () {
      final p = computeProjectProgress(_many(120));
      expect(p.of(ProjectStep.import).state, StepState.done);
      expect(p.of(ProjectStep.import).summary, '120 photos');
      expect(p.of(ProjectStep.cull).state, StepState.notStarted);
      expect(p.next.step, ProjectStep.cull);
      expect(p.next.label, 'Cull 120 photos');
      expect(p.next.assetIds, hasLength(120));
    });

    test('cull counts flags and accepted Smart Cull suggestions', () {
      final photos = [
        _e('a', flag: PhotoFlag.pick),
        _e('b', flag: PhotoFlag.reject),
        _e('c'),
        _e('d'),
      ];
      final partial = computeProjectProgress(photos, cullAccepted: {'c'});
      final cull = partial.of(ProjectStep.cull);
      expect((cull.state, cull.done, cull.total), (StepState.partial, 3, 4));
      expect(cull.summary, '3 of 4 culled');
      expect(partial.next.label, 'Cull 1 photo');
      expect(partial.next.assetIds, ['d']);
      final done = computeProjectProgress(photos, cullAccepted: {'c', 'd'});
      expect(done.of(ProjectStep.cull).state, StepState.done);
    });

    test('edit counts picks when there are picks', () {
      final photos = [
        _e('a', flag: PhotoFlag.pick, edited: true),
        _e('b', flag: PhotoFlag.pick),
        _e('c', flag: PhotoFlag.reject, edited: true),
        _e('d', flag: PhotoFlag.reject),
      ];
      final p = computeProjectProgress(photos);
      final edit = p.of(ProjectStep.edit);
      expect((edit.done, edit.total), (1, 2));
      expect(edit.summary, '1 of 2 picks edited');
      expect(p.next.step, ProjectStep.edit);
      expect(p.next.label, 'Edit 1 pick');
      expect(p.next.assetIds, ['b']);
    });

    test('without picks, edit counts every photo that is not rejected', () {
      final photos = [
        _e('a', edited: true),
        _e('b'),
        _e('c'),
        _e('x', flag: PhotoFlag.reject),
      ];
      final p = computeProjectProgress(photos, cullAccepted: {'a', 'b', 'c'});
      expect(p.of(ProjectStep.edit).summary, '1 of 3 edited');
      expect(p.next.label, 'Edit 2 photos');
    });

    test('retouch counts portraits among the edit photos', () {
      final photos = [
        _e('a', flag: PhotoFlag.pick, edited: true, retouched: true),
        _e('b', flag: PhotoFlag.pick, edited: true),
        _e('c', flag: PhotoFlag.pick, edited: true),
        _e('d', flag: PhotoFlag.reject),
      ];
      final p = computeProjectProgress(photos, faceCounts: {'b': 2, 'd': 1});
      final r = p.of(ProjectStep.retouch);
      expect((r.state, r.done, r.total), (StepState.partial, 1, 2));
      expect(r.summary, '1 of 2 portraits retouched');
      expect(p.next.step, ProjectStep.retouch);
      expect(p.next.label, 'Retouch 1 portrait');
      expect(p.next.assetIds, ['b']);
    });

    test('retouch is optional when no faces are known', () {
      final photos = [_e('a', flag: PhotoFlag.pick, edited: true)];
      final p = computeProjectProgress(photos);
      expect(p.of(ProjectStep.retouch).state, StepState.optional);
      expect(p.of(ProjectStep.retouch).summary, 'No faces found yet');
      expect(p.next.step, ProjectStep.export);
      expect(p.next.label, 'Export 1 pick');
    });

    test('export counts picks, then edited photos, then all', () {
      final out = DateTime.utc(2026, 10, 3);
      final picks = computeProjectProgress([
        _e('a', flag: PhotoFlag.pick, edited: true, exportedAt: out),
        _e('b', flag: PhotoFlag.pick, edited: true),
        _e('c', flag: PhotoFlag.reject, edited: true),
      ]);
      expect(picks.of(ProjectStep.export).summary, '1 of 2 picks exported');
      expect(picks.next.label, 'Export 1 pick');

      final edited = computeProjectProgress(
        [
          _e('a', edited: true, exportedAt: out),
          _e('b', edited: true),
          _e('c'),
        ],
        cullAccepted: {'a', 'b', 'c'},
      );
      // Edit is unfinished (c), so it comes first; export counts a and b.
      expect(edited.of(ProjectStep.export).summary, '1 of 2 exported');
      expect(edited.next.step, ProjectStep.edit);

      final none = computeProjectProgress([_e('a')], cullAccepted: {'a'});
      expect(none.of(ProjectStep.export).total, 1);
    });

    test('an edit after export makes the photo due again', () {
      final p = computeProjectProgress([
        _e(
          'a',
          flag: PhotoFlag.pick,
          edited: true,
          exportedAt: DateTime.utc(2026, 10, 2),
          editedAt: DateTime.utc(2026, 10, 4),
        ),
      ]);
      expect(p.of(ProjectStep.export).state, StepState.notStarted);
      expect(p.next.label, 'Export 1 pick');
    });

    test('everything done: all delivered', () {
      final out = DateTime.utc(2026, 10, 3);
      final p = computeProjectProgress(
        [
          _e(
            'a',
            flag: PhotoFlag.pick,
            edited: true,
            retouched: true,
            exportedAt: out,
          ),
          _e('b', flag: PhotoFlag.reject),
        ],
        faceCounts: {'a': 1},
      );
      expect(p.isComplete, isTrue);
      expect(p.completedSteps, 5);
      expect(p.next.label, 'All delivered');
      expect(p.next.assetIds, isEmpty);
    });
  });

  group('weekStats', () {
    test('counts imports, edits and exports in the last 7 days', () {
      final now = DateTime.utc(2026, 10, 10);
      final recent = DateTime.utc(2026, 10, 8);
      final old = DateTime.utc(2026, 9, 1);
      CatalogEntry at(DateTime imported) => CatalogEntry(
        assetId: imported.toIso8601String(),
        fileName: 'x.jpg',
        originalPath: 'originals/x.jpg',
        format: 'jpeg',
        width: 1,
        height: 1,
        bytes: 1,
        importedAt: imported,
      );
      final s = weekStats([
        at(recent)
            .copyWith(hasEdits: true, editedAt: recent, exportedAt: recent),
        at(old).copyWith(hasEdits: true, editedAt: recent),
        at(old).copyWith(editedAt: recent), // reset to default: not edited
        at(old).copyWith(exportedAt: old),
      ], now);
      expect((s.imported, s.edited, s.exported), (1, 2, 1));
    });
  });

  group('naming', () {
    test('formatShootDate', () {
      expect(formatShootDate(DateTime(2026, 10, 12)), '12 Oct 2026');
    });

    test('suggestProjectName uses the capture day and first file', () {
      final now = DateTime(2026, 10, 7);
      expect(
        suggestProjectName(
          now: now,
          capturedAt: DateTime(2026, 9, 30, 14),
          firstFileName: 'IMG_4021.CR3',
        ),
        '30 Sep 2026 · IMG_4021',
      );
      expect(suggestProjectName(now: now), '7 Oct 2026 shoot');
      expect(
        suggestProjectName(now: now, firstFileName: '.hidden'),
        '7 Oct 2026 · .hidden',
      );
      expect(
        suggestProjectName(now: now, firstFileName: '  '),
        '7 Oct 2026 shoot',
      );
    });
  });
}
