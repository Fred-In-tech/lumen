import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// Thrown when a catalog read or write fails in a way the user should see.
class CatalogException implements Exception {
  const CatalogException(this.message);
  final String message;

  @override
  String toString() => 'CatalogException: $message';
}

/// The photo library: index entries, original bytes, edit documents, thumbnails.
///
/// Implementations: [MemoryCatalogRepository] (web, tests) and
/// `FileCatalogRepository` (JSON files on disk, all native platforms).
abstract interface class CatalogRepository {
  /// Emits the full sorted entry list after every change.
  Stream<List<CatalogEntry>> watch();

  Future<List<CatalogEntry>> list();

  Future<CatalogEntry?> get(String assetId);

  /// Adds a new photo with its original bytes. Returns the existing entry if
  /// the asset id is already present (dedupe).
  Future<CatalogEntry> add(CatalogEntry entry, Uint8List originalBytes);

  Future<void> update(CatalogEntry entry);

  /// Removes an entry and its files.
  Future<void> delete(String assetId);

  Future<Uint8List> readOriginal(String assetId);

  Future<EditDocument> loadEdit(String assetId);

  Future<void> saveEdit(EditDocument doc);

  Future<Uint8List?> readThumb(String assetId);

  Future<void> writeThumb(String assetId, Uint8List bytes);
}

/// Sorts newest capture first, then by file name.
List<CatalogEntry> sortEntries(Iterable<CatalogEntry> entries) {
  final list = entries.toList()
    ..sort((a, b) {
      final c = b.sortDate.compareTo(a.sortDate);
      return c != 0 ? c : a.fileName.compareTo(b.fileName);
    });
  return List.unmodifiable(list);
}
