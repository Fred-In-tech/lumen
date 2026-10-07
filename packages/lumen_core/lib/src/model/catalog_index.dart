import 'catalog_entry.dart';
import 'project.dart';

/// Schema of `catalog.json`.
///
/// - v1: `{schemaVersion: 1, entries: [...]}` (no projects).
/// - v2: adds `projects: [...]`; entries may carry `project`, `exportedAt`
///   and `retouched`. A v1 file loads as v2 with every photo Unsorted.
const kCatalogSchemaVersion = 2;

/// What [CatalogIndex.withoutProject] did.
typedef ProjectRemoval = ({CatalogIndex index, List<String> removedAssetIds});

/// The library index: photos and projects. Immutable: every change returns
/// a new index, so a repository swaps one value and persists it.
class CatalogIndex {
  CatalogIndex({
    Map<String, CatalogEntry> entries = const {},
    Map<String, Project> projects = const {},
  }) : entries = Map.unmodifiable(entries),
       projects = Map.unmodifiable(projects);

  /// Reads any known schema version. Unreadable items are dropped; photos
  /// pointing at a project that does not exist become Unsorted, and covers
  /// pointing at photos outside their project are cleared.
  factory CatalogIndex.fromJson(Map<String, Object?> json) {
    final projects = <String, Project>{};
    for (final raw in (json['projects'] as List? ?? const [])) {
      final p = Project.tryFromJson(raw);
      if (p != null) projects[p.id] = p;
    }
    final entries = <String, CatalogEntry>{};
    for (final raw in (json['entries'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final e = CatalogEntry.fromJson(raw.cast());
      if (e.assetId.isEmpty) continue;
      final orphan = e.projectId != null && !projects.containsKey(e.projectId);
      entries[e.assetId] = orphan ? e.withProject(null) : e;
    }
    for (final p in projects.values.toList()) {
      final cover = p.coverAssetId;
      if (cover != null && entries[cover]?.projectId != p.id) {
        projects[p.id] = p.copyWith(clearCover: true);
      }
    }
    return CatalogIndex(entries: entries, projects: projects);
  }

  static final empty = CatalogIndex();

  final Map<String, CatalogEntry> entries;
  final Map<String, Project> projects;

  /// Photos of [projectId] (null: Unsorted), in no particular order.
  Iterable<CatalogEntry> photosOf(String? projectId) =>
      entries.values.where((e) => e.projectId == projectId);

  /// Projects, most recently changed first.
  List<Project> get sortedProjects => List.unmodifiable(
    projects.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
  );

  /// Adds or replaces [entry]. An entry for an unknown project is stored as
  /// Unsorted; adding a photo to a project counts as a project change.
  CatalogIndex withEntry(CatalogEntry entry, {DateTime? at}) {
    final pid = entry.projectId;
    final known = pid == null || projects.containsKey(pid);
    final stored = known ? entry : entry.withProject(null);
    final before = entries[entry.assetId];
    final joined = known && pid != null && before?.projectId != pid;
    return CatalogIndex(
      entries: {...entries, entry.assetId: stored},
      projects: joined && at != null
          ? {...projects, pid: projects[pid]!.copyWith(updatedAt: at)}
          : projects,
    );
  }

  /// Replaces a stored photo's own fields (flags, edits, thumbnails).
  /// Project membership and the export stamp are kept from the stored
  /// entry: [movePhotos] and [markExported] own them, so an update built
  /// from an older copy of the entry cannot undo a move or an export.
  /// Unknown photos are left out.
  CatalogIndex withUpdatedEntry(CatalogEntry entry) {
    final stored = entries[entry.assetId];
    if (stored == null) return this;
    final exported = stored.exportedAt;
    final merged = entry.withProject(stored.projectId);
    final keepStamp =
        exported != null &&
        (merged.exportedAt == null || merged.exportedAt!.isBefore(exported));
    return CatalogIndex(
      entries: {
        ...entries,
        entry.assetId: keepStamp
            ? merged.copyWith(exportedAt: exported)
            : merged,
      },
      projects: projects,
    );
  }

  /// Removes a photo (and any project cover pointing at it).
  CatalogIndex withoutEntry(String assetId) {
    if (!entries.containsKey(assetId)) return this;
    return CatalogIndex(
      entries: {
        for (final e in entries.entries)
          if (e.key != assetId) e.key: e.value,
      },
      projects: {
        for (final p in projects.values)
          p.id: p.coverAssetId == assetId ? p.copyWith(clearCover: true) : p,
      },
    );
  }

  /// Adds or replaces [project].
  CatalogIndex withProject(Project project) => CatalogIndex(
    entries: entries,
    projects: {...projects, project.id: project},
  );

  /// Removes project [id]. Its photos become Unsorted, or, with
  /// [deletePhotos], leave the index too (their ids are returned so the
  /// caller can delete their files).
  ProjectRemoval withoutProject(String id, {required bool deletePhotos}) {
    if (!projects.containsKey(id)) {
      return (index: this, removedAssetIds: const <String>[]);
    }
    final removed = <String>[];
    final kept = <String, CatalogEntry>{};
    for (final e in entries.values) {
      if (e.projectId != id) {
        kept[e.assetId] = e;
      } else if (deletePhotos) {
        removed.add(e.assetId);
      } else {
        kept[e.assetId] = e.withProject(null);
      }
    }
    return (
      index: CatalogIndex(
        entries: kept,
        projects: {
          for (final p in projects.values)
            if (p.id != id) p.id: p,
        },
      ),
      removedAssetIds: List.unmodifiable(removed),
    );
  }

  /// Moves [assetIds] into [projectId] (null: Unsorted). Unknown ids are
  /// skipped; an unknown project throws [ArgumentError]. Covers that leave
  /// their project are cleared; the target project's [Project.updatedAt]
  /// becomes [at].
  CatalogIndex movePhotos(
    Iterable<String> assetIds,
    String? projectId, {
    required DateTime at,
  }) {
    if (projectId != null && !projects.containsKey(projectId)) {
      throw ArgumentError.value(projectId, 'projectId', 'unknown project');
    }
    final ids = assetIds.where(entries.containsKey).toSet();
    if (ids.isEmpty) return this;
    final next = {
      for (final e in entries.values)
        e.assetId: ids.contains(e.assetId) ? e.withProject(projectId) : e,
    };
    return CatalogIndex(
      entries: next,
      projects: {
        for (final p in projects.values)
          p.id: _afterMove(p, next, projectId, at),
      },
    );
  }

  static Project _afterMove(
    Project p,
    Map<String, CatalogEntry> entries,
    String? target,
    DateTime at,
  ) {
    final cover = p.coverAssetId;
    final coverLeft = cover != null && entries[cover]?.projectId != p.id;
    if (p.id == target) {
      return p.copyWith(updatedAt: at, clearCover: coverLeft);
    }
    return coverLeft ? p.copyWith(clearCover: true) : p;
  }

  /// Stamps [assetIds] as exported at [at].
  CatalogIndex markExported(Iterable<String> assetIds, DateTime at) {
    final ids = assetIds.toSet();
    return CatalogIndex(
      entries: {
        for (final e in entries.values)
          e.assetId: ids.contains(e.assetId) ? e.copyWith(exportedAt: at) : e,
      },
      projects: projects,
    );
  }

  /// The `catalog.json` document. [ordered] fixes the entry order (default:
  /// insertion order).
  Map<String, Object?> toJson({Iterable<CatalogEntry>? ordered}) => {
    'schemaVersion': kCatalogSchemaVersion,
    'projects': [for (final p in sortedProjects) p.toJson()],
    'entries': [for (final e in ordered ?? entries.values) e.toJson()],
  };
}
