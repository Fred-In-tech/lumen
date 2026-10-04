import 'package:lumen/platform/background.dart';

import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/masks/ai_mask_rasters.dart' show aiMaskRefsKey;
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/import/photo_decoder.dart';

final _log = Logger('ExportService');

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

/// Develops already-decoded source pixels (a healed source) with
/// [settings], drawing AI masks from [maskRasters] (`maskRef` → raster).
typedef SourceRenderer = Future<RgbaBuffer> Function(
  RgbaBuffer source,
  DevelopSettings settings,
  Map<String, MaskRaster> maskRasters,
);

/// Reference-pipeline render of decoded pixels (CPU, isolate).
Future<RgbaBuffer> cpuSourceRender(
  RgbaBuffer source,
  DevelopSettings settings,
  Map<String, MaskRaster> maskRasters,
) => runInBackground(
  () => renderReference(source, settings, maskRasters: maskRasters),
);

/// Decoded rasters of [masks]' AI masks for stored photo [assetId], by
/// `maskRef` (a raster that cannot be produced is left out: that mask then
/// covers nothing, as in the editor).
Future<Map<String, MaskRaster>> loadAiMaskRasters(
  AiMaskRasterLoader? loader,
  String assetId,
  List<LocalMask> masks,
) async {
  final key = aiMaskRefsKey(masks);
  if (loader == null || key.isEmpty) return const {};
  final out = <String, MaskRaster>{};
  for (final maskRef in key.split('\n')) {
    try {
      final raster = await loader.load(assetId, maskRef);
      if (raster != null) out[maskRef] = raster;
    } on Exception catch (e) {
      _log.warning('AI mask $maskRef for $assetId unavailable: $e');
    }
  }
  return out;
}

/// Renders and encodes catalog photos for export.
///
/// Photos with visible heal ops or AI masks are decoded, healed from
/// [patches] (the patch PNGs) and developed by [sourceRenderer] with their
/// AI mask rasters (from [maskLoader]); the rest go through [renderer]
/// straight from the original bytes.
class ExportService {
  ExportService(
    this._catalog, {
    FullResRenderer? renderer,
    this.patches,
    this.maskLoader,
    SourceRenderer? sourceRenderer,
  }) : _render = renderer ?? cpuFullResRender,
       _renderSource = sourceRenderer ?? cpuSourceRender;

  final CatalogRepository _catalog;
  final FullResRenderer _render;

  /// Opens the heal patch store (null: heal ops are ignored).
  final PatchStoreGetter? patches;

  /// Loads AI mask rasters (null: AI masks cover nothing, as before).
  final AiMaskRasterLoader? maskLoader;
  final SourceRenderer _renderSource;

  Future<ExportedFile> exportOne(String assetId, ExportOptions o) async {
    final entry = await _catalog.get(assetId);
    if (entry == null) throw const CatalogException('Photo not found');
    final original = await _catalog.readOriginal(assetId);
    final doc = await _catalog.loadEdit(assetId);
    final rasters = await loadAiMaskRasters(
      maskLoader,
      assetId,
      doc.settings.masks,
    );
    final heal = patches != null && hasVisibleHeals(doc.settings);
    final pixels = heal || rasters.isNotEmpty
        ? await _renderSource(
            await decodeHealedSource(
              original,
              assetId: assetId,
              ops: doc.settings.heal,
              patches: patches,
              maxLongEdge: o.longEdge,
            ),
            doc.settings,
            rasters,
          )
        : await _render(original, doc.settings, o.longEdge);
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
