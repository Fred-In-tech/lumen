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
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:lumen_core/lumen_core.dart';

import 'aux_cache.dart';
import 'backdrop_stage.dart';
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
  const ExportPixels(this.width, this.height, this.rgba);

  final int width;
  final int height;

  /// Opaque RGBA8888, row-major.
  final Uint8List rgba;
}

class ExportRenderer {
  const ExportRenderer(this.shaders);

  final ShaderLibrary shaders;

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
      warpTex?.dispose();
      if (ownMasks) atlases.dispose();
      if (!identical(src, source)) EngineImages.dispose(src);
      if (!identical(ax, aux)) ax.dispose();
    }
    return ExportPixels(size.width, size.height, frame);
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
