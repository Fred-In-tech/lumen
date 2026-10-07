import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/features/cull/cull_providers.dart';
import 'package:lumen/features/cull/cull_store.dart';

/// Every project, most recently changed first.
final projectsProvider = StreamProvider<List<Project>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchProjects(),
);

/// What progress needs from the cull cache: photos whose Smart Cull
/// suggestion was accepted, and face counts measured while culling.
typedef CullFacts = ({Set<String> accepted, Map<String, int> faces});

CullFacts cullFactsOf(Map<String, CullRecord> records) => (
  accepted: {
    for (final r in records.entries)
      if (r.value.status == SuggestionStatus.accepted) r.key,
  },
  faces: {
    for (final r in records.entries)
      if (r.value.signals.faces.isNotEmpty) r.key: r.value.signals.faces.length,
  },
);

final cullFactsProvider = Provider<CullFacts>(
  (ref) => cullFactsOf(ref.watch(cullRecordsProvider).value ?? const {}),
);

/// A project (or, with a null [project], the Unsorted photos) with its
/// photos and derived progress.
class ProjectSummary {
  ProjectSummary({
    required this.project,
    required List<CatalogEntry> photos,
    required this.progress,
  }) : photos = List.unmodifiable(photos);

  final Project? project;

  /// Newest capture first (library order).
  final List<CatalogEntry> photos;
  final ProjectProgress progress;

  bool get isUnsorted => project == null;
  String get name => project?.name ?? 'Unsorted';
  int get count => photos.length;

  /// The project's cover, else its newest photo.
  CatalogEntry? get cover {
    final id = project?.coverAssetId;
    if (id != null) {
      for (final e in photos) {
        if (e.assetId == id) return e;
      }
    }
    return photos.isEmpty ? null : photos.first;
  }

  /// Up to [n] photos for a card strip, the cover first.
  List<CatalogEntry> strip(int n) {
    final c = cover;
    if (c == null) return const [];
    return [c, ...photos.where((e) => e.assetId != c.assetId).take(n - 1)];
  }

  /// The latest thing that happened: the project changed, or a photo was
  /// imported, edited or exported.
  DateTime get lastActivity {
    var t =
        project?.updatedAt ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final e in photos) {
      for (final x in [e.importedAt, e.editedAt, e.exportedAt]) {
        if (x != null && x.isAfter(t)) t = x;
      }
    }
    return t;
  }

  /// Photos the "Export" action delivers: picks, else every photo that is
  /// not rejected.
  List<String> get deliverable {
    final picks = [
      for (final e in photos)
        if (e.flag == PhotoFlag.pick) e.assetId,
    ];
    if (picks.isNotEmpty) return picks;
    return [
      for (final e in photos)
        if (e.flag != PhotoFlag.reject) e.assetId,
    ];
  }
}

ProjectSummary summarize(
  Project? project,
  List<CatalogEntry> photos,
  CullFacts facts,
) => ProjectSummary(
  project: project,
  photos: photos,
  progress: computeProjectProgress(
    photos,
    cullAccepted: facts.accepted,
    faceCounts: facts.faces,
  ),
);

/// Every project with its photos, most recent activity first.
final projectSummariesProvider = Provider<List<ProjectSummary>>((ref) {
  final projects = ref.watch(projectsProvider).value ?? const <Project>[];
  final entries = ref.watch(libraryProvider).value ?? const <CatalogEntry>[];
  final facts = ref.watch(cullFactsProvider);
  final byProject = <String, List<CatalogEntry>>{};
  for (final e in entries) {
    final id = e.projectId;
    if (id != null) (byProject[id] ??= []).add(e);
  }
  final out = [
    for (final p in projects) summarize(p, byProject[p.id] ?? const [], facts),
  ]..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  return List.unmodifiable(out);
});

/// The Unsorted photos (no project), or null when there are none.
final unsortedSummaryProvider = Provider<ProjectSummary?>((ref) {
  final entries = ref.watch(libraryProvider).value ?? const <CatalogEntry>[];
  final photos = [
    for (final e in entries)
      if (e.projectId == null) e,
  ];
  if (photos.isEmpty) return null;
  return summarize(null, photos, ref.watch(cullFactsProvider));
});

/// One project's summary (null id: Unsorted); null when it is gone.
final projectSummaryProvider = Provider.family<ProjectSummary?, String?>((
  ref,
  projectId,
) {
  if (projectId == null) {
    return ref.watch(unsortedSummaryProvider) ??
        summarize(null, const [], ref.watch(cullFactsProvider));
  }
  for (final s in ref.watch(projectSummariesProvider)) {
    if (s.project?.id == projectId) return s;
  }
  return null;
});

/// Where the editor's back button returns to, named for the photos it
/// walks: their project ("Smith wedding"), "Unsorted", or "All photos"
/// when they span several.
String backLabelFor(
  List<String> assetIds,
  List<CatalogEntry> library,
  List<Project> projects,
) {
  final ids = assetIds.toSet();
  final owners = {
    for (final e in library)
      if (ids.contains(e.assetId)) e.projectId,
  };
  if (owners.length != 1) return 'All photos';
  final id = owners.single;
  if (id == null) return 'Unsorted';
  for (final p in projects) {
    if (p.id == id) return p.name;
  }
  return 'All photos';
}

/// [backLabelFor] over the live library and projects.
final editorBackLabelProvider = Provider.family<String, String>((ref, key) {
  return backLabelFor(
    key.split('\n'),
    ref.watch(libraryProvider).value ?? const [],
    ref.watch(projectsProvider).value ?? const [],
  );
});
