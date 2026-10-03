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
/// * Encode the result with `encodeImage(EncodeRequest(...))`.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

import 'aux_cache.dart';
import 'gpu_pass.dart';
import 'lut_texture.dart';
import 'shader_library.dart';

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
    final lut = await LutTexture.upload(ToneLut.bake(settings));
    final src = DenoiseUniforms.isIdentity(settings)
        ? source
        : runDenoise(
            shaders,
            floats: DenoiseUniforms.pack(settings, source.width, source.height),
            image: source,
          );
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
            auxWidth: aux.width,
            auxHeight: aux.height,
            airlight: aux.maps.airlight,
          );
          var image = runDevelop(
            shaders,
            floats: DevelopUniforms.pack(settings, ctx),
            source: src,
            auxA: aux.auxA,
            auxB: aux.auxB,
            lut: lut.image,
            width: rw,
            height: rh,
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
      if (!identical(src, source)) EngineImages.dispose(src);
    }
    return ExportPixels(size.width, size.height, frame);
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
