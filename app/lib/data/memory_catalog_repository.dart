import 'dart:async';
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';

/// Session-only catalog used on the web and in tests.
class MemoryCatalogRepository implements CatalogRepository {
  final Map<String, CatalogEntry> _entries = {};
  final Map<String, Uint8List> _originals = {};
  final Map<String, EditDocument> _edits = {};
  final Map<String, Uint8List> _thumbs = {};
  final StreamController<List<CatalogEntry>> _changes = StreamController.broadcast();

  void _emit() => _changes.add(sortEntries(_entries.values));

  @override
  Stream<List<CatalogEntry>> watch() async* {
    yield sortEntries(_entries.values);
    yield* _changes.stream;
  }

  @override
  Future<List<CatalogEntry>> list() async => sortEntries(_entries.values);

  @override
  Future<CatalogEntry?> get(String assetId) async => _entries[assetId];

  @override
  Future<CatalogEntry> add(CatalogEntry entry, Uint8List originalBytes) async {
    final existing = _entries[entry.assetId];
    if (existing != null) return existing;
    _entries[entry.assetId] = entry;
    _originals[entry.assetId] = originalBytes;
    _emit();
    return entry;
  }

  @override
  Future<void> update(CatalogEntry entry) async {
    if (!_entries.containsKey(entry.assetId)) throw CatalogException('Unknown asset ${entry.assetId}');
    _entries[entry.assetId] = entry;
    _emit();
  }

  @override
  Future<void> delete(String assetId) async {
    _entries.remove(assetId);
    _originals.remove(assetId);
    _edits.remove(assetId);
    _thumbs.remove(assetId);
    _emit();
  }

  @override
  Future<Uint8List> readOriginal(String assetId) async {
    final bytes = _originals[assetId];
    if (bytes == null) throw CatalogException('Original missing for $assetId');
    return bytes;
  }

  @override
  Future<EditDocument> loadEdit(String assetId) async => _edits[assetId] ?? EditDocument.create(assetId);

  @override
  Future<void> saveEdit(EditDocument doc) async => _edits[doc.assetId] = doc;

  @override
  Future<Uint8List?> readThumb(String assetId) async => _thumbs[assetId];

  @override
  Future<void> writeThumb(String assetId, Uint8List bytes) async => _thumbs[assetId] = bytes;
}
