import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/platform/background.dart';

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart'
    show BackdropInputs, kNoBackdropInputs;
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen/features/export/export_watermark.dart';
import 'package:lumen/features/masks/ai_mask_rasters.dart' show aiMaskRefsKey;
import 'package:lumen/features/export/source_render.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/photo_decoder.dart';

final _log = Logger('ExportService');

/// Options chosen in the export dialog (one preset).
class ExportOptions {
  const ExportOptions({
    this.format = ExportFormat.jpeg,
    this.quality = 90,
    this.longEdge,
    this.size = const ExportSizeLimit.none(),
    this.sharpen = OutputSharpen.none,
    this.watermark,
    this.naming = kDefaultNaming,
    this.presetName = '',
    this.keepMetadata = true,
  });

  /// The options of [preset].
  factory ExportOptions.fromPreset(ExportPreset preset) => ExportOptions(
    format: preset.format,
    quality: preset.quality,
    size: preset.size,
    sharpen: preset.sharpen,
    watermark: preset.watermark,
    naming: preset.naming,
    presetName: preset.name,
    keepMetadata: preset.keepMetadata,
  );

  final ExportFormat format;
  final int quality;

  /// Long edge cap in pixels (null: none); applied with [size].
  final int? longEdge;
  final ExportSizeLimit size;
  final OutputSharpen sharpen;
  final Watermark? watermark;

  /// File name template (see `exportBaseName`).
  final String naming;
  final String presetName;
  final bool keepMetadata;
}

/// One finished export.
class ExportedFile {
  /// A file held in one buffer.
  ExportedFile({
    required this.fileName,
    required Uint8List bytes,
    required this.width,
    required this.height,
    this.note,
    this.sixteenBitDetail,
  }) : chunks = [bytes];

  /// A file that is the concatenation of [chunks] (a 16-bit TIFF: header
  /// plus the pixel frame, never copied into one buffer).
  ExportedFile.chunked({
    required this.fileName,
    required this.chunks,
    required this.width,
    required this.height,
    this.note,
    this.sixteenBitDetail,
  });

  final String fileName;
  final List<Uint8List> chunks;
  final int width;
  final int height;

  /// For 16-bit files: true when the pixels came from a float source (more
  /// than 256 levels are real), false when an 8-bit photo was widened.
  final bool? sixteenBitDetail;

  /// This file under another name.
  ExportedFile renamed(String name) => ExportedFile.chunked(
    fileName: name,
    chunks: chunks,
    width: width,
    height: height,
    note: note,
    sixteenBitDetail: sixteenBitDetail,
  );

  /// Total file size.
  int get length => chunks.fold(0, (n, c) => n + c.length);

  /// The whole file in one buffer (copies when chunked).
  Uint8List get bytes {
    if (chunks.length == 1) return chunks.single;
    final b = BytesBuilder(copy: false);
    chunks.forEach(b.add);
    return b.toBytes();
  }

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

/// What a float (high-bit-depth) export needs to render one stored photo.
class FloatExportRequest {
  const FloatExportRequest({
    required this.assetId,
    required this.settings,
    required this.pixelSource,
    this.longEdge,
    this.maskRasters = const {},
    this.retouchMaps,
    this.faces,
    this.backdrop = kNoBackdropInputs,
    this.patches,
    this.sixteenBit = false,
    this.dither = false,
  });

  final String assetId;
  final DevelopSettings settings;

  /// The 8-bit pixel source (the RAW rendition), for what is analysed in
  /// 8 bits (backdrop matte).
  final Uint8List pixelSource;
  final int? longEdge;
  final Map<String, MaskRaster> maskRasters;
  final RetouchMaps? retouchMaps;
  final FaceAnalysis? faces;
  final BackdropInputs backdrop;
  final PatchStoreGetter? patches;

  /// Read the final pass back at 16 bits per channel.
  final bool sixteenBit;

  /// 8-bit output: quantize the float result with dither.
  final bool dither;
}

/// Exports a photo from its float source (camera RAW, 16-bit PNG, 10-bit
/// HEIC) so the file gets the highlight headroom and precision the editor
/// showed: a [Raster16] when [FloatExportRequest.sixteenBit], else a
/// [Raster8] (dithered when asked). Returns null when the photo has no
/// float source on this device: the export then takes the 8-bit path.
typedef FloatExportRenderer = Future<ExportRaster?> Function(
  FloatExportRequest request,
);

/// Renders watermark text [heightPx] tall (see `rasterizeWatermark`).
typedef WatermarkRasterizer = Future<WatermarkMask> Function(
  String text,
  double heightPx,
  int maxWidth,
);

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
  final lut = await CreativeLuts.forSettings(settings);
  return runInBackground(
    () => renderReference(src, settings, creativeLut: lut),
  );
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
    this.floatExport,
    this.watermarkRasterizer = rasterizeWatermark,
    DateTime Function()? clock,
    SourceRenderer? sourceRenderer,
  }) : _render = renderer ?? cpuFullResRender,
       _clock = clock ?? DateTime.now,
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

  /// Float export (null: every photo exports on the 8-bit path).
  final FloatExportRenderer? floatExport;

  /// Draws watermark text (null: watermarks are skipped).
  final WatermarkRasterizer? watermarkRasterizer;
  final DateTime Function() _clock;
  final SourceRenderer _renderSource;

  /// Renders, finishes (output sharpening, watermark) and encodes one
  /// photo. [seq] of [total] feed the `{seq}` naming token.
  Future<ExportedFile> exportOne(
    String assetId,
    ExportOptions options, {
    int seq = 1,
    int total = 1,
  }) async {
    final entry = await _catalog.get(assetId);
    if (entry == null) throw const CatalogException('Photo not found');
    final original = await _catalog.readPixelSource(assetId);
    final doc = await _catalog.loadEdit(assetId);
    final settings = doc.settings;
    final o = _withLongEdge(options, entry, settings);
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
    final floated = await floatExport?.call(
      FloatExportRequest(
        assetId: assetId,
        settings: settings,
        pixelSource: original,
        longEdge: o.longEdge,
        maskRasters: rasters,
        retouchMaps: faces.maps,
        faces: faces.faces,
        backdrop: swap,
        patches: patches,
        sixteenBit: o.format.sixteenBit,
        dither: !o.format.sixteenBit,
      ),
    );
    final ExportRaster raster;
    if (floated != null) {
      raster = floated;
    } else {
      raster = Raster8(
        await _render8(
          original,
          assetId,
          settings,
          o,
          heal: heal,
          rasters: rasters,
          faces: faces,
          swap: swap,
          swapped: swapped,
        ),
      );
    }
    await _finish(raster, o);
    final chunks = await encodeRaster(
      raster,
      format: o.format,
      quality: o.quality,
      // Sniffed, not entry.format: a RAW photo's pixel source is its JPEG
      // rendition, which carries the camera EXIF.
      sourceJpeg: sniffFormat(original) == PhotoFormat.jpeg ? original : null,
      keepMetadata: o.keepMetadata,
    );
    return ExportedFile.chunked(
      fileName: exportFileNameFor(
        o.naming,
        original: entry.fileName,
        format: o.format,
        date: entry.exif.capturedAt ?? _clock(),
        seq: seq,
        total: total,
        preset: o.presetName,
      ),
      chunks: chunks,
      width: raster.width,
      height: raster.height,
      note: faces.note,
      sixteenBitDetail: o.format.sixteenBit
          ? raster is Raster16 && raster.fromFloat
          : null,
    );
  }

  /// [o] with its size limit resolved to a long edge for this photo's
  /// output size (after crop).
  ExportOptions _withLongEdge(
    ExportOptions o,
    CatalogEntry entry,
    DevelopSettings settings,
  ) {
    if (o.size.isNone || entry.width < 1 || entry.height < 1) return o;
    final out = outputSizeFor(entry.width, entry.height, settings.geometry);
    final le = o.size.longEdgeFor(out.width, out.height);
    final capped = le == null
        ? o.longEdge
        : (o.longEdge == null ? le : math.min(le, o.longEdge!));
    return ExportOptions(
      format: o.format,
      quality: o.quality,
      longEdge: capped,
      sharpen: o.sharpen,
      watermark: o.watermark,
      naming: o.naming,
      presetName: o.presetName,
      keepMetadata: o.keepMetadata,
    );
  }

  /// Output sharpening, then the watermark, in place.
  Future<void> _finish(ExportRaster raster, ExportOptions o) async {
    final (List<int> data, int channels, int max) = switch (raster) {
      Raster8(:final pixels) => (pixels.data, 4, 255),
      Raster16(:final rgb) => (rgb, 3, 65535),
    };
    final w = raster.width, h = raster.height;
    await sharpenInPlaceAsync(data, w, h, channels, max, o.sharpen);
    final mark = o.watermark;
    final draw = watermarkRasterizer;
    if (mark == null || draw == null) return;
    final short = math.min(w, h);
    final mask = await draw(
      mark.text,
      math.max(6.0, mark.size * short),
      math.max(1, w - 2 * (short * 0.03).round()),
    );
    blendWatermark(
      data,
      w,
      h,
      channels,
      max,
      mask,
      mark.position,
      opacity: mark.opacity,
      margin: (short * 0.03).round(),
    );
  }

  Future<RgbaBuffer> _render8(
    Uint8List original,
    String assetId,
    DevelopSettings settings,
    ExportOptions o, {
    required bool heal,
    required Map<String, MaskRaster> rasters,
    required StoredRetouch faces,
    required BackdropInputs swap,
    required bool swapped,
  }) async {
    if (heal || rasters.isNotEmpty || faces.maps != null || swapped) {
      final source = await decodeHealedSource(
        original,
        assetId: assetId,
        ops: settings.heal,
        patches: patches,
        maxLongEdge: _renderSource.decodeLongEdge(o.longEdge),
      );
      return _renderSource.render(source, settings, (
        assetId: assetId,
        maskRasters: rasters,
        retouchMaps: faces.maps,
        faces: faces.faces,
        backdrop: swap,
      ), longEdge: o.longEdge);
    }
    return _render(original, settings, o.longEdge, assetId: assetId);
  }
}
