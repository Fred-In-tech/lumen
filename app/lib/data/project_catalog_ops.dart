import 'package:lumen_core/lumen_core.dart';
import 'package:uuid/uuid.dart';

import 'package:lumen/data/catalog_repository.dart';

/// Project operations shared by the catalog repositories. A repository
/// holds one immutable [CatalogIndex], and every change swaps it through
/// [commitIndex] (which persists and notifies).
mixin ProjectCatalogOps {
  /// The current index (loaded on first use).
  Future<CatalogIndex> loadIndex();

  /// Stores [next] as the current index, persists and notifies watchers.
  Future<void> commitIndex(CatalogIndex next);

  /// Deletes the stored files of photos already removed from the index.
  Future<void> dropAssetFiles(List<CatalogEntry> removed);

  /// The repository clock (UTC).
  DateTime now();

  static const _uuid = Uuid();

  Future<List<Project>> listProjects() async =>
      (await loadIndex()).sortedProjects;

  Future<Project> createProject({
    required String name,
    DateTime? shootDate,
    String? notes,
  }) async {
    final at = now();
    final project = Project(
      id: _uuid.v4(),
      name: checkProjectName(name),
      createdAt: at,
      updatedAt: at,
      shootDate: shootDate,
      notes: notes,
    );
    await commitIndex((await loadIndex()).withProject(project));
    return project;
  }

  Future<void> updateProject(Project project) async {
    final index = await loadIndex();
    final current = index.projects[project.id];
    if (current == null) {
      throw CatalogException('Unknown project ${project.id}');
    }
    final cover = project.coverAssetId;
    if (cover != null && index.entries[cover]?.projectId != project.id) {
      throw const CatalogException('The cover must be a photo of the project.');
    }
    final named = Project(
      id: project.id,
      name: checkProjectName(project.name),
      createdAt: current.createdAt,
      updatedAt: now(),
      coverAssetId: cover,
      shootDate: project.shootDate,
      notes: project.notes,
    );
    await commitIndex(index.withProject(named));
  }

  Future<void> deleteProject(
    String projectId, {
    bool deletePhotos = false,
  }) async {
    final index = await loadIndex();
    final removal = index.withoutProject(projectId, deletePhotos: deletePhotos);
    await commitIndex(removal.index);
    final removed = [
      for (final id in removal.removedAssetIds) ?index.entries[id],
    ];
    if (removed.isNotEmpty) await dropAssetFiles(removed);
  }

  Future<void> movePhotos(Iterable<String> assetIds, String? projectId) async {
    final index = await loadIndex();
    if (projectId != null && !index.projects.containsKey(projectId)) {
      throw CatalogException('Unknown project $projectId');
    }
    final next = index.movePhotos(assetIds, projectId, at: now());
    if (!identical(next, index)) await commitIndex(next);
  }

  Future<void> markExported(Iterable<String> assetIds, DateTime at) async =>
      commitIndex((await loadIndex()).markExported(assetIds, at));
}
