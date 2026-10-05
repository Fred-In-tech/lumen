import 'package:lumen/platform/background.dart';

import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart'
    show kNoBackdropInputs;
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/masks/ai_mask_rasters.dart' show aiMaskRefsKey;
import 'package:lumen/features/export/source_render.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/import/import_file.dart';
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
    this.note,
  });
  final String fileName;
  final Uint8List bytes;
  final int width;
  final int height;

  /// Something the export had to leave out (e.g. portrait retouch when face
  /// analysis is unavailable). The file is still complete.
  final String? note;
}

/// Full-resolution render function: original bytes + settings → pixels.
/// [assetId] seeds film grain so exports match the editor preview.
typedef FullResRenderer = Future<RgbaBuffer> Function(
  Uint8List original,
  DevelopSettings settings,
  int? longEdge, {
  String assetId,
});

/// Reference-pipeline full-res render (CPU, isolate). Correct on every platform.
Future<RgbaBuffer> cpuFullResRender(
  Uint8List original,
  DevelopSettings settings,
  int? longEdge, {
  String assetId = '',
}) async {
  final decoded = await decodePhoto(original, maxLongEdge: longEdge);
  final src = await rgbaFromImage(decoded);
  decoded.dispose();
  return runInBackground(() => renderReference(src, settings));
}

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
/// Photos with visible heal ops, AI masks or portrait retouch are decoded,
/// healed from [patches] (the patch PNGs), then retouched and developed by
/// [sourceRenderer] with their AI mask rasters (from [maskLoader]) and
/// retouch inputs (from [retouch]); the rest go through [renderer] straight
/// from the original bytes.
class ExportService {
  ExportService(
    this._catalog, {
    FullResRenderer? renderer,
    this.patches,
    this.maskLoader,
    this.retouch,
    this.backdrop,
    SourceRenderer? sourceRenderer,
  }) : _render = renderer ?? cpuFullResRender,
       _renderSource = sourceRenderer ?? const CpuSourceRenderer();

  final CatalogRepository _catalog;
  final FullResRenderer _render;

  /// Opens the heal patch store (null: heal ops are ignored).
  final PatchStoreGetter? patches;

  /// Loads AI mask rasters (null: AI masks cover nothing, as before).
  final AiMaskRasterLoader? maskLoader;

  /// Loads portrait retouch inputs (null: portrait edits are not applied).
  final RetouchLoader? retouch;

  /// Loads background-swap inputs (null: the background swap is ignored).
  final BackdropInputsLoader? backdrop;
  final SourceRenderer _renderSource;

  Future<ExportedFile> exportOne(String assetId, ExportOptions o) async {
    final entry = await _catalog.get(assetId);
    if (entry == null) throw const CatalogException('Photo not found');
    final original = await _catalog.readPixelSource(assetId);
    final doc = await _catalog.loadEdit(assetId);
    final settings = doc.settings;
    final rasters = await loadAiMaskRasters(
      maskLoader,
      assetId,
      settings.masks,
    );
    final faces = await (retouch?.call(assetId, settings) ?? kNoRetouchFuture);
    final heal = patches != null && hasVisibleHeals(settings);
    final swap = settings.backdrop.isNone || backdrop == null
        ? kNoBackdropInputs
        : await backdrop!(assetId, settings.backdrop);
    final swapped = swap.people != null || swap.hair != null;
    final RgbaBuffer pixels;
    if (heal || rasters.isNotEmpty || faces.maps != null || swapped) {
      final source = await decodeHealedSource(
        original,
        assetId: assetId,
        ops: settings.heal,
        patches: patches,
        maxLongEdge: _renderSource.decodeLongEdge(o.longEdge),
      );
      pixels = await _renderSource.render(source, settings, (
        assetId: assetId,
        maskRasters: rasters,
        retouchMaps: faces.maps,
        faces: faces.faces,
        backdrop: swap,
      ), longEdge: o.longEdge);
    } else {
      pixels = await _render(original, settings, o.longEdge, assetId: assetId);
    }
    final bytes = await encodeExport(
      pixels,
      format: o.format,
      quality: o.quality,
      // Sniffed, not entry.format: a RAW photo's pixel source is its JPEG
      // rendition, which carries the camera EXIF.
      sourceJpeg: sniffFormat(original) == PhotoFormat.jpeg ? original : null,
      keepMetadata: o.keepMetadata,
    );
    return ExportedFile(
      fileName: exportFileName(entry.fileName, o.format),
      bytes: bytes,
      width: pixels.width,
      height: pixels.height,
      note: faces.note,
    );
  }
}
