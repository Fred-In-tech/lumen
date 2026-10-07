import 'dart:async';
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/project_catalog_ops.dart';

/// Session-only catalog used on the web and in tests.
class MemoryCatalogRepository
    with ProjectCatalogOps
    implements CatalogRepository {
  MemoryCatalogRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  CatalogIndex _index = CatalogIndex.empty;
  final Map<String, Uint8List> _originals = {};
  final Map<String, Uint8List> _renditions = {};
  final Map<String, EditDocument> _edits = {};
  final Map<String, Uint8List> _thumbs = {};
  final StreamController<List<CatalogEntry>> _changes =
      StreamController.broadcast();
  final StreamController<List<Project>> _projectChanges =
      StreamController.broadcast();

  @override
  DateTime now() => _clock().toUtc();

  @override
  Future<CatalogIndex> loadIndex() async => _index;

  @override
  Future<void> commitIndex(CatalogIndex next) async {
    final projectsChanged = !identical(next.projects, _index.projects);
    _index = next;
    _changes.add(sortEntries(next.entries.values));
    if (projectsChanged) _projectChanges.add(next.sortedProjects);
  }

  @override
  Future<void> dropAssetFiles(List<CatalogEntry> removed) async {
    for (final id in removed.map((e) => e.assetId)) {
      _originals.remove(id);
      _renditions.remove(id);
      _edits.remove(id);
      _thumbs.remove(id);
    }
  }

  @override
  Stream<List<CatalogEntry>> watch() async* {
    yield sortEntries(_index.entries.values);
    yield* _changes.stream;
  }

  @override
  Stream<List<Project>> watchProjects() async* {
    yield _index.sortedProjects;
    yield* _projectChanges.stream;
  }

  @override
  Future<List<CatalogEntry>> list() async => sortEntries(_index.entries.values);

  @override
  Future<CatalogEntry?> get(String assetId) async => _index.entries[assetId];

  @override
  Future<CatalogEntry> add(
    CatalogEntry entry,
    Uint8List originalBytes, {
    Uint8List? rendition,
  }) async {
    final existing = _index.entries[entry.assetId];
    if (existing != null) return existing;
    _originals[entry.assetId] = originalBytes;
    if (rendition != null) _renditions[entry.assetId] = rendition;
    await commitIndex(_index.withEntry(entry, at: now()));
    return _index.entries[entry.assetId]!;
  }

  @override
  Future<void> update(CatalogEntry entry) async {
    if (!_index.entries.containsKey(entry.assetId)) {
      throw CatalogException('Unknown asset ${entry.assetId}');
    }
    await commitIndex(_index.withUpdatedEntry(entry));
  }

  @override
  Future<void> delete(String assetId) async {
    final entry = _index.entries[assetId];
    if (entry == null) return;
    await commitIndex(_index.withoutEntry(assetId));
    await dropAssetFiles([entry]);
  }

  @override
  Future<Uint8List> readOriginal(String assetId) async {
    final bytes = _originals[assetId];
    if (bytes == null) throw CatalogException('Original missing for $assetId');
    return bytes;
  }

  @override
  Future<Uint8List> readPixelSource(String assetId) async =>
      _renditions[assetId] ?? await readOriginal(assetId);

  @override
  Future<EditDocument> loadEdit(String assetId) async =>
      _edits[assetId] ?? EditDocument.create(assetId);

  @override
  Future<void> saveEdit(EditDocument doc) async => _edits[doc.assetId] = doc;

  @override
  Future<Uint8List?> readThumb(String assetId) async => _thumbs[assetId];

  @override
  Future<void> writeThumb(String assetId, Uint8List bytes) async =>
      _thumbs[assetId] = bytes;
}
