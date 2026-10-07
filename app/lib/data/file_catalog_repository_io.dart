import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/data/atomic_file_io_impl_io.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/project_catalog_ops.dart';

final _log = Logger('FileCatalogRepository');

/// JSON-file catalog under `<root>/`:
/// `catalog.json` (photos and projects, [kCatalogSchemaVersion]),
/// `originals/<id>.<ext>`, `assets/<id>/{edit.json,thumb.jpg}` and, for
/// camera RAW only, the developed `renditions/<id>.jpg`.
class FileCatalogRepository
    with ProjectCatalogOps
    implements CatalogRepository, OriginalFileLocator {
  FileCatalogRepository(this.root, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String root;
  final DateTime Function() _clock;
  CatalogIndex? _cache;
  final StreamController<List<CatalogEntry>> _changes =
      StreamController.broadcast();
  final StreamController<List<Project>> _projectChanges =
      StreamController.broadcast();
  Future<void> _writeChain = Future.value();

  String get _indexPath => p.join(root, 'catalog.json');
  String _assetDir(String id) => p.join(root, 'assets', id);
  String _renditionPath(String id) => p.join(root, 'renditions', '$id.jpg');

  @override
  DateTime now() => _clock().toUtc();

  /// Reads `catalog.json` once; v1 catalogs (no projects) load as-is with
  /// every photo Unsorted and are written back as v2 on the next change.
  @override
  Future<CatalogIndex> loadIndex() async {
    final cached = _cache;
    if (cached != null) return cached;
    final file = File(_indexPath);
    var index = CatalogIndex.empty;
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) index = CatalogIndex.fromJson(json.cast());
      } on FormatException catch (e) {
        _log.warning('catalog.json unreadable, backing up: $e');
        await file.copy(
          '$_indexPath.corrupt-${DateTime.now().millisecondsSinceEpoch}',
        );
      }
    }
    return _cache ??= index;
  }

  @override
  Future<void> commitIndex(CatalogIndex next) {
    final before = _cache;
    _cache = next;
    final entries = sortEntries(next.entries.values);
    final bytes = utf8.encode(jsonEncode(next.toJson(ordered: entries)));
    _writeChain = _writeChain.then(
      (_) => atomicWrite(_indexPath, Uint8List.fromList(bytes)),
    );
    _changes.add(entries);
    if (!identical(before?.projects, next.projects)) {
      _projectChanges.add(next.sortedProjects);
    }
    return _writeChain;
  }

  @override
  Future<void> dropAssetFiles(List<CatalogEntry> removed) async {
    for (final e in removed) {
      await _deleteFiles(e);
    }
  }

  /// Removes every stored file of [entry]: the original, the RAW rendition
  /// and the asset folder (edit, thumbnail, caches).
  Future<void> _deleteFiles(CatalogEntry entry) async {
    final original = File(p.join(root, entry.originalPath));
    if (await original.exists()) await original.delete();
    final rendition = File(_renditionPath(entry.assetId));
    if (await rendition.exists()) await rendition.delete();
    final dir = Directory(_assetDir(entry.assetId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Stream<List<CatalogEntry>> watch() async* {
    yield sortEntries((await loadIndex()).entries.values);
    yield* _changes.stream;
  }

  @override
  Stream<List<Project>> watchProjects() async* {
    yield (await loadIndex()).sortedProjects;
    yield* _projectChanges.stream;
  }

  @override
  Future<List<CatalogEntry>> list() async =>
      sortEntries((await loadIndex()).entries.values);

  @override
  Future<CatalogEntry?> get(String assetId) async =>
      (await loadIndex()).entries[assetId];

  @override
  Future<CatalogEntry> add(
    CatalogEntry entry,
    Uint8List originalBytes, {
    Uint8List? rendition,
  }) async {
    final index = await loadIndex();
    final existing = index.entries[entry.assetId];
    if (existing != null) return existing;
    await atomicWrite(p.join(root, entry.originalPath), originalBytes);
    if (rendition != null) {
      await atomicWrite(_renditionPath(entry.assetId), rendition);
    }
    final next = (await loadIndex()).withEntry(entry, at: now());
    await commitIndex(next);
    return next.entries[entry.assetId]!;
  }

  @override
  Future<void> update(CatalogEntry entry) async {
    final index = await loadIndex();
    if (!index.entries.containsKey(entry.assetId)) {
      throw CatalogException('Unknown asset ${entry.assetId}');
    }
    await commitIndex(index.withUpdatedEntry(entry));
  }

  @override
  Future<void> delete(String assetId) async {
    final index = await loadIndex();
    final entry = index.entries[assetId];
    if (entry == null) return;
    await commitIndex(index.withoutEntry(assetId));
    await _deleteFiles(entry);
  }

  @override
  Future<Uint8List> readOriginal(String assetId) async {
    final entry = (await loadIndex()).entries[assetId];
    if (entry == null) throw CatalogException('Unknown asset $assetId');
    final file = File(p.join(root, entry.originalPath));
    if (!await file.exists()) {
      throw CatalogException('Original file missing for ${entry.fileName}');
    }
    return file.readAsBytes();
  }

  @override
  Future<String?> originalFilePath(String assetId) async {
    final entry = (await loadIndex()).entries[assetId];
    if (entry == null) return null;
    final file = File(p.join(root, entry.originalPath));
    return await file.exists() ? file.path : null;
  }

  @override
  Future<Uint8List> readPixelSource(String assetId) async {
    // Only RAW imports have a rendition; every other photo (and every
    // catalog from before RAW support) decodes its original.
    final rendition = File(_renditionPath(assetId));
    if (await rendition.exists()) return rendition.readAsBytes();
    return readOriginal(assetId);
  }

  @override
  Future<EditDocument> loadEdit(String assetId) async {
    final file = File(p.join(_assetDir(assetId), 'edit.json'));
    if (!await file.exists()) return EditDocument.create(assetId);
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map) return EditDocument.fromJson(json.cast());
    } on FormatException catch (e) {
      _log.warning('edit.json for $assetId unreadable, starting fresh: $e');
      await file.copy(
        '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
      );
    }
    return EditDocument.create(assetId);
  }

  @override
  Future<void> saveEdit(EditDocument doc) async {
    if (doc.readOnly) return;
    final bytes = utf8.encode(jsonEncode(doc.toJson()));
    await atomicWrite(
      p.join(_assetDir(doc.assetId), 'edit.json'),
      Uint8List.fromList(bytes),
    );
  }

  @override
  Future<Uint8List?> readThumb(String assetId) async {
    final file = File(p.join(_assetDir(assetId), 'thumb.png'));
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> writeThumb(String assetId, Uint8List bytes) =>
      atomicWrite(p.join(_assetDir(assetId), 'thumb.png'), bytes);
}
