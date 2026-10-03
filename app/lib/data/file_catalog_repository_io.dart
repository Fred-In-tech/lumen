import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/data/atomic_file_io_impl_io.dart';
import 'package:lumen/data/catalog_repository.dart';

final _log = Logger('FileCatalogRepository');

/// JSON-file catalog under `<root>/`:
/// `catalog.json`, `originals/<id>.<ext>`, `assets/<id>/{edit.json,thumb.jpg}`.
class FileCatalogRepository implements CatalogRepository {
  FileCatalogRepository(this.root);

  final String root;
  Map<String, CatalogEntry>? _cache;
  final StreamController<List<CatalogEntry>> _changes = StreamController.broadcast();
  Future<void> _writeChain = Future.value();

  String get _indexPath => p.join(root, 'catalog.json');
  String _assetDir(String id) => p.join(root, 'assets', id);

  Future<Map<String, CatalogEntry>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final file = File(_indexPath);
    final map = <String, CatalogEntry>{};
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
        for (final e in (json['entries'] as List? ?? const [])) {
          if (e is Map) {
            final entry = CatalogEntry.fromJson(e.cast());
            if (entry.assetId.isNotEmpty) map[entry.assetId] = entry;
          }
        }
      } on FormatException catch (e) {
        _log.warning('catalog.json unreadable, backing up: $e');
        await file.copy('$_indexPath.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      }
    }
    return _cache = map;
  }

  Future<void> _persist() {
    final entries = sortEntries(_cache!.values);
    final bytes = utf8.encode(jsonEncode({
      'schemaVersion': 1,
      'entries': [for (final e in entries) e.toJson()],
    }));
    _writeChain = _writeChain.then((_) => atomicWrite(_indexPath, Uint8List.fromList(bytes)));
    _changes.add(entries);
    return _writeChain;
  }

  @override
  Stream<List<CatalogEntry>> watch() async* {
    yield sortEntries((await _load()).values);
    yield* _changes.stream;
  }

  @override
  Future<List<CatalogEntry>> list() async => sortEntries((await _load()).values);

  @override
  Future<CatalogEntry?> get(String assetId) async => (await _load())[assetId];

  @override
  Future<CatalogEntry> add(CatalogEntry entry, Uint8List originalBytes) async {
    final map = await _load();
    final existing = map[entry.assetId];
    if (existing != null) return existing;
    await atomicWrite(p.join(root, entry.originalPath), originalBytes);
    map[entry.assetId] = entry;
    await _persist();
    return entry;
  }

  @override
  Future<void> update(CatalogEntry entry) async {
    final map = await _load();
    if (!map.containsKey(entry.assetId)) throw CatalogException('Unknown asset ${entry.assetId}');
    map[entry.assetId] = entry;
    await _persist();
  }

  @override
  Future<void> delete(String assetId) async {
    final map = await _load();
    final entry = map.remove(assetId);
    if (entry == null) return;
    await _persist();
    final original = File(p.join(root, entry.originalPath));
    if (await original.exists()) await original.delete();
    final dir = Directory(_assetDir(assetId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<Uint8List> readOriginal(String assetId) async {
    final entry = (await _load())[assetId];
    if (entry == null) throw CatalogException('Unknown asset $assetId');
    final file = File(p.join(root, entry.originalPath));
    if (!await file.exists()) throw CatalogException('Original file missing for ${entry.fileName}');
    return file.readAsBytes();
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
      await file.copy('${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
    }
    return EditDocument.create(assetId);
  }

  @override
  Future<void> saveEdit(EditDocument doc) async {
    if (doc.readOnly) return;
    final bytes = utf8.encode(jsonEncode(doc.toJson()));
    await atomicWrite(p.join(_assetDir(doc.assetId), 'edit.json'), Uint8List.fromList(bytes));
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
