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
  ///
  /// [rendition] is the developed image of a camera RAW original (encoded,
  /// engine-decodable); see [readPixelSource].
  Future<CatalogEntry> add(
    CatalogEntry entry,
    Uint8List originalBytes, {
    Uint8List? rendition,
  });

  Future<void> update(CatalogEntry entry);

  /// Removes an entry and its files.
  Future<void> delete(String assetId);

  /// The untouched imported file (for RAW: the RAW itself, which the engine
  /// codec cannot decode).
  Future<Uint8List> readOriginal(String assetId);

  /// The encoded bytes the pixel pipeline decodes: the developed rendition
  /// for camera RAW, the original for everything else.
  Future<Uint8List> readPixelSource(String assetId);

  Future<EditDocument> loadEdit(String assetId);

  Future<void> saveEdit(EditDocument doc);

  Future<Uint8List?> readThumb(String assetId);

  Future<void> writeThumb(String assetId, Uint8List bytes);
}

/// Optional catalog capability: originals that are files on disk. The
/// float decoder reads RAW (and other high-bit-depth) originals by path,
/// so the 30–80 MB file never crosses a platform channel. Check with
/// `catalog is OriginalFileLocator`; catalogs without it (web, tests) keep
/// every photo on the 8-bit path.
abstract interface class OriginalFileLocator {
  /// Absolute path of the untouched original of [assetId], or null when
  /// the photo or its file is missing.
  Future<String?> originalFilePath(String assetId);
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
