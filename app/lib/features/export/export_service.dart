import 'package:lumen/platform/background.dart';

import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/import/photo_decoder.dart';

/// Options chosen in the export dialog.
class ExportOptions {
  const ExportOptions({
    this.format = ExportFormat.jpeg,
    this.quality = 90,
    this.longEdge,
    this.keepMetadata = true,
  });

  final ExportFormat format;
  final int quality;
  final int? longEdge;
  final bool keepMetadata;
}

/// One finished export.
class ExportedFile {
  const ExportedFile({
    required this.fileName,
    required this.bytes,
    required this.width,
    required this.height,
  });
  final String fileName;
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Full-resolution render function: original bytes + settings → pixels.
typedef FullResRenderer = Future<RgbaBuffer> Function(
  Uint8List original,
  DevelopSettings settings,
  int? longEdge,
);

/// Reference-pipeline full-res render (CPU, isolate). Correct on every platform.
Future<RgbaBuffer> cpuFullResRender(
  Uint8List original,
  DevelopSettings settings,
  int? longEdge,
) async {
  final decoded = await decodePhoto(original, maxLongEdge: longEdge);
  final src = await rgbaFromImage(decoded);
  decoded.dispose();
  return runInBackground(() => renderReference(src, settings));
}

/// Renders and encodes catalog photos for export.
class ExportService {
  ExportService(this._catalog, {FullResRenderer? renderer})
    : _render = renderer ?? cpuFullResRender;

  final CatalogRepository _catalog;
  final FullResRenderer _render;

  Future<ExportedFile> exportOne(String assetId, ExportOptions o) async {
    final entry = await _catalog.get(assetId);
    if (entry == null) throw const CatalogException('Photo not found');
    final original = await _catalog.readOriginal(assetId);
    final doc = await _catalog.loadEdit(assetId);
    final pixels = await _render(original, doc.settings, o.longEdge);
    final bytes = await encodeExport(
      pixels,
      format: o.format,
      quality: o.quality,
      sourceJpeg: entry.format == 'jpeg' ? original : null,
      keepMetadata: o.keepMetadata,
    );
    return ExportedFile(
      fileName: exportFileName(entry.fileName, o.format),
      bytes: bytes,
      width: pixels.width,
      height: pixels.height,
    );
  }
}
