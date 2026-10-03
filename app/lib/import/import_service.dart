import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/import/exif_reader.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/photo_decoder.dart';

final _log = Logger('ImportService');

/// Outcome of importing one file.
sealed class ImportResult {
  const ImportResult(this.fileName);
  final String fileName;
}

final class Imported extends ImportResult {
  const Imported(super.fileName, this.entry);
  final CatalogEntry entry;
}

final class Duplicate extends ImportResult {
  const Duplicate(super.fileName, this.entry);
  final CatalogEntry entry;
}

final class ImportFailed extends ImportResult {
  const ImportFailed(super.fileName, this.reason);
  final String reason;
}

/// Hash → dedupe → probe → EXIF → store → thumbnail.
class ImportService {
  ImportService(this._catalog, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final CatalogRepository _catalog;
  final DateTime Function() _clock;

  static const int thumbLongEdge = 384;

  static String assetIdFor(List<int> bytes) => sha256.convert(bytes).toString().substring(0, 32);

  Future<List<ImportResult>> importAll(List<ImportFile> files, {void Function(int done, int total)? onProgress}) async {
    final results = <ImportResult>[];
    for (var i = 0; i < files.length; i++) {
      results.add(await importOne(files[i]));
      onProgress?.call(i + 1, files.length);
    }
    return results;
  }

  Future<ImportResult> importOne(ImportFile file) async {
    final format = sniffFormat(file.bytes);
    if (!format.isSupported) {
      return ImportFailed(file.name, 'Not a supported photo (JPEG, PNG, WebP or HEIC).');
    }
    final id = assetIdFor(file.bytes);
    final existing = await _catalog.get(id);
    if (existing != null) return Duplicate(file.name, existing);
    try {
      final size = await probeSize(file.bytes);
      final exif = await readExifSummary(file.bytes);
      final entry = CatalogEntry(
        assetId: id,
        fileName: file.name,
        originalPath: 'originals/$id.${format.extension}',
        format: format.name,
        width: size.width,
        height: size.height,
        bytes: file.bytes.length,
        importedAt: _clock().toUtc(),
        exif: exif,
      );
      final stored = await _catalog.add(entry, file.bytes);
      await _writeThumb(stored, file);
      return Imported(file.name, stored);
    } on DecodeException catch (e) {
      final hint = format == PhotoFormat.heic
          ? ' HEIC needs the system HEIF codec (on Windows: install "HEIF Image Extensions").'
          : '';
      return ImportFailed(file.name, '${e.message}$hint');
    } on CatalogException catch (e) {
      _log.warning('Import of ${file.name} failed: $e');
      return ImportFailed(file.name, e.message);
    }
  }

  Future<void> _writeThumb(CatalogEntry entry, ImportFile file) async {
    final img = await decodePhoto(file.bytes, maxLongEdge: thumbLongEdge);
    try {
      await _catalog.writeThumb(entry.assetId, await encodePng(img));
    } finally {
      img.dispose();
    }
  }
}
