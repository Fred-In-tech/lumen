/// Full-resolution, tiled export render.
///
/// Public API (consumed by the export service):
/// * `ExportRenderer(ShaderLibrary shaders)`
/// * `static Future<ui.Image> decodeOriginal(bytes, {maxLongEdge})`: decodes
///   the original at full resolution, downscaled to [kMaxExportEdge] (or the
///   given cap) if larger. The caller owns the image.
/// * `static exportSize(srcW, srcH, geometry, {longEdge})`: output size after crop/rotation and an optional
///   long-edge resize (never upscales).
/// * `render({source, aux, settings, assetId, longEdge, tileSize = 2048,
///   onProgress, cancel})` → `ExportPixels`: renders 2048² tiles (+ apron
///   when the finish pass runs) through denoise → develop → finish, reads
///   them back and assembles a full-frame RGBA8888 buffer. Progress is
///   reported per tile (0..1); a cancelled [CancelToken] stops between
///   tiles with [ExportCancelled]. Aux textures are the preview's (they are
///   resolution independent), so tiles have no seams.
/// * Masks: pass the preview's `MaskAtlasTextures` as `masks` (resolution
///   independent, source-uv space) or let them be rasterized from
///   `settings.masks` (with `maskRasters` for AI masks).
/// * Portrait retouch: pass `faceAnalysis` plus `retouchMaps` (or the
///   preview's uploaded `retouchTextures`; maps are source-uv, so the same
///   maps serve any resolution). Pass R runs over the full-res source in
///   `tileSize` tiles before develop; identity settings skip it.
/// * Warp: pass the editor's `warp` field, or let it be built from
///   `settings` (liquify + face-shape sliders, which need `faceAnalysis`)
///   off the UI isolate. It is sampled in source uv, so tiles are seamless.
/// * Backdrop: pass the editor's `backdropAssets` (exact for
///   `settings.backdrop`, e.g. `BackdropService.assetsFor`). Pass B runs
///   over the full-res source in tiles after R; develop then uses the
///   composite's aux maps when it needs spatial maps.
/// * Encode the result with `encodeImage(EncodeRequest(...))`.
/// * Float sources (docs/HIGH_BIT_DEPTH.md): `renderFloat({source, aux,
///   settings, ...})` exports a `FloatSource` without ever holding the
///   whole photo in float on the GPU. For each output tile it asks the
///   source for the window that tile samples (`sourceWindowFor`: crop,
///   rotation, warp range, filter halos), uploads it as float32, runs heal
///   overlay → denoise → retouch → backdrop on the window and develops the
///   tile from it (`uSrcWin`). `floatSourceSize` is the size the source is
///   rendered at (its "virtual" full size); `FloatExportStats` reports the
///   windows and the estimated peak GPU memory. `output:` reads the final
///   pass back as 8-bit (default), as float quantized with dither to 8 bits
///   (`dithered8`) or kept at 16 bits (`rgb16`, `ExportPixels.rgb16`).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:lumen_core/lumen_core.dart';

import 'aux_cache.dart';
import 'backdrop_stage.dart';
import 'backdrop_textures.dart';
import 'creative_lut_cache.dart';
import 'float_source.dart';
import 'gpu_pass.dart';
import 'lut_texture.dart';
import 'mask_atlas_cache.dart';
import 'retouch_textures.dart';
import 'shader_library.dart';
import 'warp_textures.dart';

/// Default cap for the export long edge (Android/Windows/web); Apple
/// platforms may pass 16384.
const int kMaxExportEdge = 8192;

class ExportCancelled implements Exception {
  const ExportCancelled();

  @override
  String toString() => 'ExportCancelled';
}

class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class ExportPixels {
  const ExportPixels(this.width, this.height, this.rgba, {this.rgb16});

  final int width;
  final int height;

  /// Opaque RGBA8888, row-major (empty when [rgb16] holds the frame).
  final Uint8List rgba;

  /// 16-bit RGB, row-major, for [FloatTileOutput.rgb16] exports.
  final Uint16List? rgb16;
}

/// What a float export reads back from the final pass of each tile.
enum FloatTileOutput {
  /// The 8-bit tile target (rounded on the GPU).
  bytes,

  /// A float32 tile, quantized to 8 bits with dither on the CPU (no
  /// banding in smooth float gradients).
  dithered8,

  /// A float32 tile, kept at 16 bits per channel (16-bit TIFF / PNG).
  rgb16,
}

/// What a windowed float export used (reported once, at the end).
class FloatExportStats {
  const FloatExportStats({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.tileSize,
    required this.tiles,
    required this.largestWindow,
    required this.peakGpuBytes,
    required this.decodeMs,
    required this.renderMs,
  });

  /// Size the float source was rendered at (see
  /// [ExportRenderer.floatSourceSize]).
  final int sourceWidth;
  final int sourceHeight;
  final int tileSize;
  final int tiles;

  /// Pixels of the largest source window.
  final int largestWindow;

  /// Estimated peak GPU memory of one tile: live float32 images (16 B/px
  /// plus the mip chain the engine always allocates) and the 8-bit tile
  /// targets. Computed, not read from the GPU.
  final int peakGpuBytes;

  /// Time spent in the source decoder and in upload + passes + readback.
  final int decodeMs;
  final int renderMs;

  @override
  String toString() =>
      'FloatExportStats(source ${sourceWidth}x$sourceHeight, $tiles tiles of '
      '$tileSize, largest window ${(largestWindow / 1e6).toStringAsFixed(1)} '
      'MP, peak GPU ~${(peakGpuBytes / (1 << 20)).round()} MB, decode '
      '$decodeMs ms, render $renderMs ms)';
}

/// Bytes of a float32 image on the GPU: 16 B/px plus the full mip chain
/// every `toImageSync` float target gets (research 08 §3).
int floatImageBytes(int pixels) => pixels * 16 * 4 ~/ 3;

class ExportRenderer {
  const ExportRenderer(this.shaders);

  final ShaderLibrary shaders;

  /// Pixels around a source window that the passes may read beyond what
  /// the tile maps to: bilinear (1) + texture 3×3 (1) + denoise 5×5 (2),
  /// with slack.
  static const int kWindowMargin = 6;

  /// Largest source window (pixels) of a float export; tiles shrink until
  /// their windows fit (a float32 window of this size is 256 MB plus mips).
  static const int kMaxWindowPixels = 16 * 1024 * 1024;

  /// The size a float source is rendered at for an export of [fullWidth]×
  /// [fullHeight] with [geometry]: the full size, capped at [maxLongEdge],
  /// scaled down so the output long edge is [longEdge] (never up). The
  /// source and the output then have the same pixel density, so a tile's
  /// window is about as large as the tile.
  static ({int width, int height}) floatSourceSize(
    int fullWidth,
    int fullHeight,
    Geometry geometry, {
    int? longEdge,
    int maxLongEdge = kMaxExportEdge,
  }) {
    final le = math.max(fullWidth, fullHeight);
    final cap = le > maxLongEdge ? maxLongEdge / le : 1.0;
    final cw = math.max(1, (fullWidth * cap).round());
    final ch = math.max(1, (fullHeight * cap).round());
    final out = outputSizeFor(cw, ch, geometry);
    final ole = math.max(out.width, out.height);
    if (longEdge == null || longEdge >= ole) return (width: cw, height: ch);
    final s = longEdge / ole;
    return (
      width: math.max(1, (cw * s).round()),
      height: math.max(1, (ch * s).round()),
    );
  }

  static Future<ui.Image> decodeOriginal(
    Uint8List bytes, {
    int maxLongEdge = kMaxExportEdge,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    try {
      final le = math.max(desc.width, desc.height);
      final s = le > maxLongEdge ? maxLongEdge / le : 1.0;
      final codec = await desc.instantiateCodec(
        targetWidth: s < 1 ? math.max(1, (desc.width * s).round()) : null,
        targetHeight: s < 1 ? math.max(1, (desc.height * s).round()) : null,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return EngineImages.track(frame.image);
    } finally {
      desc.dispose();
      buffer.dispose();
    }
  }

  static ({int width, int height}) exportSize(
    int srcWidth,
    int srcHeight,
    Geometry geometry, {
    int? longEdge,
  }) {
    final full = outputSizeFor(srcWidth, srcHeight, geometry);
    final le = math.max(full.width, full.height);
    if (longEdge == null || longEdge >= le) return full;
    final s = longEdge / le;
    return (
      width: math.max(1, (full.width * s).round()),
      height: math.max(1, (full.height * s).round()),
    );
  }

  Future<ExportPixels> render({
    required ui.Image source,
    required AuxTextures aux,
    required DevelopSettings settings,
    String assetId = '',
    int? longEdge,
    int tileSize = 2048,
    void Function(double progress)? onProgress,
    CancelToken? cancel,
    MaskAtlasTextures? masks,
    Map<String, MaskRaster> maskRasters = const {},
    FaceAnalysis? faceAnalysis,
    RetouchMaps? retouchMaps,
    RetouchTextures? retouchTextures,
    WarpField? warp,
    BackdropAssets? backdropAssets,
  }) async {
    final full = outputSizeFor(source.width, source.height, settings.geometry);
    final size = exportSize(
      source.width,
      source.height,
      settings.geometry,
      longEdge: longEdge,
    );
    final finish = !FinishUniforms.isIdentity(settings);
    final apron = finish ? 4 : 0;
    final ownMasks = masks == null;
    final atlases =
        masks ??
        await MaskAtlasTextures.upload(
          MaskRasterizer.build(
            settings.masks,
            source.width,
            source.height,
            rasters: maskRasters,
          ),
        );
    final field =
        warp ??
        (hasWarpEdits(settings, faceAnalysis)
            ? await compute(
                buildWarpField,
                WarpRequest.fromSettings(
                  settings,
                  faceAnalysis,
                  sourceWidth: source.width,
                  sourceHeight: source.height,
                ),
              )
            : null);
    final warpTex = field == null || field.isIdentity
        ? null
        : await WarpTexture.upload(field);
    final lut = await LutTexture.upload(ToneLut.bake(settings));
    final creative = CreativeLutCache();
    final creativeTex = await creative.obtain(settings.lut);
    final ui.Image src;
    final AuxTextures ax;
    try {
      final prepared = await _withBackdrop(
        source,
        await _preparedSource(
          source,
          settings,
          tileSize,
          faceAnalysis,
          retouchTextures?.maps ?? retouchMaps,
          retouchTextures,
        ),
        settings,
        backdropAssets,
        tileSize,
      );
      src = prepared.image;
      ax = prepared.aux ?? aux;
    } on Object {
      lut.dispose();
      creative.dispose();
      warpTex?.dispose();
      if (ownMasks) atlases.dispose();
      rethrow;
    }
    final frame = Uint8List(size.width * size.height * 4);
    final tilesX = (size.width / tileSize).ceil();
    final tilesY = (size.height / tileSize).ceil();
    try {
      for (var ty = 0; ty < tilesY; ty++) {
        for (var tx = 0; tx < tilesX; tx++) {
          if (cancel?.isCancelled ?? false) throw const ExportCancelled();
          final x0 = tx * tileSize, y0 = ty * tileSize;
          final tile = (
            x: x0,
            y: y0,
            w: math.min(tileSize, size.width - x0),
            h: math.min(tileSize, size.height - y0),
          );
          final r = (
            x: math.max(0, x0 - apron),
            y: math.max(0, y0 - apron),
            x1: math.min(size.width, x0 + tile.w + apron),
            y1: math.min(size.height, y0 + tile.h + apron),
          );
          final rw = r.x1 - r.x, rh = r.y1 - r.y;
          final ctx = DevelopContext(
            outWidth: rw,
            outHeight: rh,
            tileX: r.x.toDouble(),
            tileY: r.y.toDouble(),
            fullWidth: size.width.toDouble(),
            fullHeight: size.height.toDouble(),
            sourceWidth: source.width,
            sourceHeight: source.height,
            auxWidth: ax.width,
            auxHeight: ax.height,
            airlight: ax.maps.airlight,
            maskWidth: atlases.width,
            maskHeight: atlases.height,
            warpWidth: warpTex?.field.width ?? 1,
            warpHeight: warpTex?.field.height ?? 1,
            warpRange: warpTex?.field.range ?? 0,
            lutSize: creativeTex?.size ?? 0,
          );
          var image = runDevelop(
            shaders,
            floats: DevelopUniforms.pack(settings, ctx),
            source: src,
            auxA: ax.auxA,
            auxB: ax.auxB,
            lut: lut.image,
            width: rw,
            height: rh,
            masks0: atlases.atlas0,
            masks1: atlases.atlas1,
            warp: warpTex?.image,
            creativeLut: creativeTex?.image,
          );
          if (finish) {
            final developed = image;
            image = runFinish(
              shaders,
              floats: FinishUniforms.pack(
                settings,
                FinishContext(
                  width: rw,
                  height: rh,
                  tileX: r.x.toDouble(),
                  tileY: r.y.toDouble(),
                  fullWidth: size.width.toDouble(),
                  fullHeight: size.height.toDouble(),
                  seed: FinishUniforms.seedFor(assetId),
                  previewScale: math.max(1.0, full.width / size.width),
                ),
              ),
              image: developed,
            );
            EngineImages.dispose(developed);
          }
          final bytes = await readRgba(image);
          EngineImages.dispose(image);
          _blit(bytes, rw, tile.x - r.x, tile.y - r.y, tile, frame, size.width);
          onProgress?.call((ty * tilesX + tx + 1) / (tilesX * tilesY));
        }
      }
    } finally {
      lut.dispose();
      creative.dispose();
      warpTex?.dispose();
      if (ownMasks) atlases.dispose();
      if (!identical(src, source)) EngineImages.dispose(src);
      if (!identical(ax, aux)) ax.dispose();
    }
    return ExportPixels(size.width, size.height, frame);
  }

  /// Windowed export of a float [source]; see the library doc. [aux] are
  /// the photo's float aux maps (resolution independent). [healOverlay] is
  /// the premultiplied heal overlay at exactly [floatSourceSize] (from
  /// `composeHealOverlay`), null without heals. Everything else as in
  /// [render]. Throws [FloatSourceException] when the source cannot be
  /// decoded.
  Future<ExportPixels> renderFloat({
    required FloatSource source,
    required AuxTextures aux,
    required DevelopSettings settings,
    String assetId = '',
    int? longEdge,
    int tileSize = 2048,
    int maxLongEdge = kMaxExportEdge,
    void Function(double progress)? onProgress,
    CancelToken? cancel,
    MaskAtlasTextures? masks,
    Map<String, MaskRaster> maskRasters = const {},
    FaceAnalysis? faceAnalysis,
    RetouchMaps? retouchMaps,
    RetouchTextures? retouchTextures,
    WarpField? warp,
    BackdropAssets? backdropAssets,
    RgbaBuffer? healOverlay,
    void Function(FloatExportStats stats)? onStats,
    FloatTileOutput output = FloatTileOutput.bytes,
  }) async {
    final virt = floatSourceSize(
      source.width,
      source.height,
      settings.geometry,
      longEdge: longEdge,
      maxLongEdge: maxLongEdge,
    );
    if (healOverlay != null &&
        (healOverlay.width != virt.width ||
            healOverlay.height != virt.height)) {
      throw ArgumentError('heal overlay must be ${virt.width}x${virt.height}');
    }
    final size = outputSizeFor(virt.width, virt.height, settings.geometry);
    final le = math.max(source.width, source.height);
    final capped = le > maxLongEdge ? maxLongEdge / le : 1.0;
    final full = outputSizeFor(
      math.max(1, (source.width * capped).round()),
      math.max(1, (source.height * capped).round()),
      settings.geometry,
    );
    final finish = !FinishUniforms.isIdentity(settings);
    final apron = finish ? 4 : 0;
    final ownMasks = masks == null;
    final atlases =
        masks ??
        await MaskAtlasTextures.upload(
          MaskRasterizer.build(
            settings.masks,
            virt.width,
            virt.height,
            rasters: maskRasters,
          ),
        );
    final field =
        warp ??
        (hasWarpEdits(settings, faceAnalysis)
            ? await compute(
                buildWarpField,
                WarpRequest.fromSettings(
                  settings,
                  faceAnalysis,
                  sourceWidth: virt.width,
                  sourceHeight: virt.height,
                ),
              )
            : null);
    final warpTex = field == null || field.isIdentity
        ? null
        : await WarpTexture.upload(field);
    final lut = await LutTexture.upload(ToneLut.bake(settings));
    final creative = CreativeLutCache();
    final creativeTex = await creative.obtain(settings.lut);
    final maps = retouchTextures?.maps ?? retouchMaps;
    final ru = faceAnalysis == null
        ? null
        : RetouchUniforms.fromSettings(settings.portrait, faceAnalysis);
    RetouchTextures? retouch;
    BackdropTextures? swap;
    AuxTextures? swapAux;
    final b = settings.backdrop;
    try {
      if (ru != null &&
          maps != null &&
          RetouchPassUniforms.isActive(maps, ru)) {
        retouch = retouchTextures ?? await RetouchTextures.upload(maps);
      }
      if (backdropAssets != null && backdropAssets.canRender(b)) {
        swap = await BackdropTextures.upload(backdropAssets);
        if (needsAuxMaps(settings)) {
          swapAux = await backdropAuxTextures(backdropAssets, b);
        }
      }
    } on Object {
      lut.dispose();
      creative.dispose();
      warpTex?.dispose();
      if (ownMasks) atlases.dispose();
      if (!identical(retouch, retouchTextures)) retouch?.dispose();
      swap?.dispose();
      rethrow;
    }
    final ax = swapAux ?? aux;
    final denoise = !DenoiseUniforms.isIdentity(settings);

    DevelopContext context(
      ({int x, int y, int x1, int y1}) r, [
      ({int x, int y, int width, int height})? window,
    ]) => DevelopContext(
      outWidth: r.x1 - r.x,
      outHeight: r.y1 - r.y,
      tileX: r.x.toDouble(),
      tileY: r.y.toDouble(),
      fullWidth: size.width.toDouble(),
      fullHeight: size.height.toDouble(),
      sourceWidth: virt.width,
      sourceHeight: virt.height,
      auxWidth: ax.width,
      auxHeight: ax.height,
      airlight: ax.maps.airlight,
      maskWidth: atlases.width,
      maskHeight: atlases.height,
      warpWidth: warpTex?.field.width ?? 1,
      warpHeight: warpTex?.field.height ?? 1,
      warpRange: warpTex?.field.range ?? 0,
      profile: source.profile,
      windowX: window?.x ?? 0,
      windowY: window?.y ?? 0,
      windowWidth: window?.width,
      windowHeight: window?.height,
      lutSize: creativeTex?.size ?? 0,
    );

    // A tile's render rectangle: the tile plus the finish apron, clipped.
    ({int x, int y, int x1, int y1}) rectOf(int x0, int y0, int ts) => (
      x: math.max(0, x0 - apron),
      y: math.max(0, y0 - apron),
      x1: math.min(size.width, x0 + ts + apron),
      y1: math.min(size.height, y0 + ts + apron),
    );

    ({int x, int y, int width, int height}) windowOf(
      ({int x, int y, int x1, int y1}) r,
    ) => sourceWindowFor(
      DevelopUniforms.pack(settings, context(r)),
      x0: r.x.toDouble(),
      y0: r.y.toDouble(),
      x1: r.x1.toDouble(),
      y1: r.y1.toDouble(),
      margin: kWindowMargin,
    );

    // Shrink the tiles until every source window fits the budget (strong
    // rotations and large warp ranges widen the windows).
    var ts = tileSize;
    int largest(int t) {
      var worst = 0;
      for (var y0 = 0; y0 < size.height; y0 += t) {
        for (var x0 = 0; x0 < size.width; x0 += t) {
          final w = windowOf(rectOf(x0, y0, t));
          worst = math.max(worst, w.width * w.height);
        }
      }
      return worst;
    }

    var largestWindow = largest(ts);
    while (largestWindow > kMaxWindowPixels && ts > 256) {
      ts ~/= 2;
      largestWindow = largest(ts);
    }

    final floatOut = output != FloatTileOutput.bytes;
    // The one full-size buffer of the export: tiles stream into it.
    final frame = output == FloatTileOutput.rgb16
        ? Uint8List(0)
        : Uint8List(size.width * size.height * 4);
    final frame16 = output == FloatTileOutput.rgb16
        ? Uint16List(size.width * size.height * 3)
        : null;
    final tilesX = (size.width / ts).ceil();
    final tilesY = (size.height / ts).ceil();
    final decode = Stopwatch(), work = Stopwatch();
    try {
      for (var ty = 0; ty < tilesY; ty++) {
        for (var tx = 0; tx < tilesX; tx++) {
          if (cancel?.isCancelled ?? false) throw const ExportCancelled();
          final x0 = tx * ts, y0 = ty * ts;
          final tile = (
            x: x0,
            y: y0,
            w: math.min(ts, size.width - x0),
            h: math.min(ts, size.height - y0),
          );
          final r = rectOf(x0, y0, ts);
          final rw = r.x1 - r.x, rh = r.y1 - r.y;
          final win = windowOf(r);
          decode.start();
          final px = await source.render(
            fullWidth: virt.width,
            fullHeight: virt.height,
            x: win.x,
            y: win.y,
            width: win.width,
            height: win.height,
          );
          decode.stop();
          work.start();
          final src = await _preparedWindow(
            await uploadFloat(px.rgba, win.width, win.height),
            SourceWindow(
              x: win.x,
              y: win.y,
              fullWidth: virt.width,
              fullHeight: virt.height,
            ),
            settings,
            healOverlay: healOverlay,
            denoise: denoise,
            retouch: retouch,
            retouchUniforms: ru,
            backdrop: swap,
          );
          ui.Image image;
          try {
            image = runDevelop(
              shaders,
              floats: DevelopUniforms.pack(settings, context(r, win)),
              source: src,
              auxA: ax.auxA,
              auxB: ax.auxB,
              lut: lut.image,
              width: rw,
              height: rh,
              masks0: atlases.atlas0,
              masks1: atlases.atlas1,
              warp: warpTex?.image,
              creativeLut: creativeTex?.image,
              float: floatOut,
            );
          } finally {
            // The recorded pass keeps the texture alive until it is drawn.
            EngineImages.dispose(src);
          }
          if (finish) {
            final developed = image;
            image = runFinish(
              shaders,
              floats: FinishUniforms.pack(
                settings,
                FinishContext(
                  width: rw,
                  height: rh,
                  tileX: r.x.toDouble(),
                  tileY: r.y.toDouble(),
                  fullWidth: size.width.toDouble(),
                  fullHeight: size.height.toDouble(),
                  seed: FinishUniforms.seedFor(assetId),
                  previewScale: math.max(1.0, full.width / size.width),
                ),
              ),
              image: developed,
              float: floatOut,
            );
            EngineImages.dispose(developed);
          }
          final offX = tile.x - r.x, offY = tile.y - r.y;
          if (floatOut) {
            final floats = await readFloat(image);
            EngineImages.dispose(image);
            work.stop();
            if (frame16 != null) {
              blitFloatTile16(
                floats,
                rw,
                offX,
                offY,
                tile,
                frame16,
                size.width,
              );
            } else {
              blitFloatTile8Dithered(
                floats,
                rw,
                offX,
                offY,
                tile,
                frame,
                size.width,
              );
            }
          } else {
            final bytes = await readRgba(image);
            EngineImages.dispose(image);
            work.stop();
            _blit(bytes, rw, offX, offY, tile, frame, size.width);
          }
          onProgress?.call((ty * tilesX + tx + 1) / (tilesX * tilesY));
        }
      }
    } finally {
      lut.dispose();
      creative.dispose();
      warpTex?.dispose();
      if (ownMasks) atlases.dispose();
      if (!identical(retouch, retouchTextures)) retouch?.dispose();
      swap?.dispose();
      swapAux?.dispose();
    }
    // Live at once: the uploaded window plus one pass output (each pass
    // releases its input), then the 8-bit develop and finish tiles.
    final tilePixels = (ts + 2 * apron) * (ts + 2 * apron);
    onStats?.call(
      FloatExportStats(
        sourceWidth: virt.width,
        sourceHeight: virt.height,
        tileSize: ts,
        tiles: tilesX * tilesY,
        largestWindow: largestWindow,
        peakGpuBytes:
            2 * floatImageBytes(largestWindow) +
            (finish ? 2 : 1) * tilePixels * (floatOut ? 16 : 4) * 4 ~/ 3,
        decodeMs: decode.elapsedMilliseconds,
        renderMs: work.elapsedMilliseconds,
      ),
    );
    return ExportPixels(size.width, size.height, frame, rgb16: frame16);
  }

  /// Heal overlay → denoise → retouch → backdrop over one float source
  /// window; takes ownership of [window] and returns the image develop
  /// samples (the caller disposes it).
  Future<ui.Image> _preparedWindow(
    ui.Image window,
    SourceWindow at,
    DevelopSettings settings, {
    required RgbaBuffer? healOverlay,
    required bool denoise,
    required RetouchTextures? retouch,
    required RetouchUniforms? retouchUniforms,
    required BackdropTextures? backdrop,
  }) async {
    var src = window;
    void replace(ui.Image? next) {
      if (next == null) return;
      EngineImages.dispose(src);
      src = next;
    }

    try {
      if (healOverlay != null) {
        final crop = _cropRgba(healOverlay, at.x, at.y, src.width, src.height);
        if (crop != null) {
          final overlay = await uploadRgba(crop, src.width, src.height);
          try {
            replace(compositeOverlay(src, overlay));
          } finally {
            EngineImages.dispose(overlay);
          }
        }
      }
      if (denoise) {
        replace(
          runDenoise(
            shaders,
            floats: DenoiseUniforms.pack(settings, src.width, src.height),
            image: src,
            float: true,
          ),
        );
      }
      if (retouch != null && retouchUniforms != null) {
        replace(
          runRetouchPass(
            shaders,
            source: src,
            textures: retouch,
            uniforms: retouchUniforms,
            float: true,
            window: at,
          ),
        );
      }
      if (backdrop != null) {
        replace(
          runBackdropPass(
            shaders,
            source: src,
            textures: backdrop,
            change: settings.backdrop,
            float: true,
            window: at,
          ),
        );
      }
      return src;
    } on Object {
      EngineImages.dispose(src);
      rethrow;
    }
  }

  /// The [w]×[h] rectangle at ([x], [y]) of [b], or null when it is fully
  /// transparent (nothing to draw).
  static Uint8List? _cropRgba(RgbaBuffer b, int x, int y, int w, int h) {
    final out = Uint8List(w * h * 4);
    var any = false;
    for (var row = 0; row < h; row++) {
      final from = b.offset(x, y + row);
      out.setRange(row * w * 4, (row + 1) * w * 4, b.data, from);
    }
    for (var i = 3; i < out.length; i += 4) {
      if (out[i] != 0) {
        any = true;
        break;
      }
    }
    return any ? out : null;
  }

  /// Denoise (N) then retouch (R) over the full source; returns [source]
  /// itself when neither is active.
  Future<ui.Image> _preparedSource(
    ui.Image source,
    DevelopSettings settings,
    int tileSize,
    FaceAnalysis? analysis,
    RetouchMaps? maps,
    RetouchTextures? given,
  ) async {
    final u = analysis == null
        ? null
        : RetouchUniforms.fromSettings(settings.portrait, analysis);
    final textures =
        u == null || maps == null || !RetouchPassUniforms.isActive(maps, u)
        ? null
        : (given ?? await RetouchTextures.upload(maps));
    var src = DenoiseUniforms.isIdentity(settings)
        ? source
        : runDenoise(
            shaders,
            floats: DenoiseUniforms.pack(settings, source.width, source.height),
            image: source,
          );
    if (textures == null || u == null) return src;
    try {
      final retouched = runRetouchPass(
        shaders,
        source: src,
        textures: textures,
        uniforms: u,
        tileSize: tileSize,
      );
      if (retouched != null) {
        if (!identical(src, source)) EngineImages.dispose(src);
        src = retouched;
      }
    } finally {
      if (!identical(textures, given)) textures.dispose();
    }
    return src;
  }

  /// Pass B over [prepared] (replacing it) with the composite's aux, or
  /// [prepared] as is when the backdrop is off.
  Future<({ui.Image image, AuxTextures? aux})> _withBackdrop(
    ui.Image source,
    ui.Image prepared,
    DevelopSettings settings,
    BackdropAssets? assets,
    int tileSize,
  ) async {
    try {
      final swapped = await exportBackdrop(
        shaders,
        source: prepared,
        settings: settings,
        assets: assets,
        tileSize: tileSize,
      );
      if (swapped == null) return (image: prepared, aux: null);
      if (!identical(prepared, source)) EngineImages.dispose(prepared);
      return swapped;
    } on Object {
      if (!identical(prepared, source)) EngineImages.dispose(prepared);
      rethrow;
    }
  }

  /// Copies the apron-free [tile] region of a tile image into [frame].
  static void _blit(
    Uint8List bytes,
    int srcStride,
    int offX,
    int offY,
    ({int x, int y, int w, int h}) tile,
    Uint8List frame,
    int frameWidth,
  ) {
    for (var row = 0; row < tile.h; row++) {
      final from = ((offY + row) * srcStride + offX) * 4;
      final to = ((tile.y + row) * frameWidth + tile.x) * 4;
      frame.setRange(to, to + tile.w * 4, bytes, from);
    }
  }
}
