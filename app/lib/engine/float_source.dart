/// The high-bit-depth source of one photo (docs/HIGH_BIT_DEPTH.md).
///
/// A float source is decoded on demand, never stored: the preview asks for
/// the whole photo at preview size, the export for one window per output
/// tile. Pixels are float32 RGBA, **sRGB-encoded with extended range**
/// (above 1.0 = brighter than display white), alpha 1, upright, rows top
/// to bottom: the layout of `FloatBuffer` and of `uploadFloat`.
///
/// Public API:
/// * `FloatPixels(width, height, rgba)`; `buffer` views it as a
///   `FloatBuffer`.
/// * `abstract interface class FloatSource`: `width`, `height` (full
///   upright size), `profile`, `render(fullWidth:, fullHeight:, x, y,
///   width, height)`, `release()`.
/// * `typedef FloatSourceLoader = Future<FloatSource?> Function(assetId)`:
///   null when the photo has no float source on this device (8-bit photo,
///   platform without a decoder, file missing).
/// * `MemoryFloatSource(FloatBuffer)`: a source over pixels in memory (CPU
///   reference, tests); scaled renders are area averages.
library;

import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

class FloatPixels {
  FloatPixels(this.width, this.height, this.rgba, {this.decodeMs}) {
    if (rgba.length != width * height * 4) {
      throw ArgumentError(
        'float pixels ${rgba.length} != ${width * height * 4}',
      );
    }
  }

  final int width;
  final int height;

  /// Float32 RGBA, row-major.
  final Float32List rgba;

  /// Time the decoder itself took, when it reports it (diagnostics: the
  /// rest of a slow render is the hand-over).
  final int? decodeMs;

  FloatBuffer get buffer => FloatBuffer(width, height, rgba);
}

abstract interface class FloatSource {
  /// Full upright size of the photo.
  int get width;
  int get height;

  /// How develop renders this source (highlight shoulder, extra Highlights
  /// range); [HbdProfile.none] for sources without headroom.
  HbdProfile get profile;

  /// The window ([x], [y], [width], [height]; default: everything) of the
  /// photo scaled to [fullWidth]×[fullHeight].
  Future<FloatPixels> render({
    required int fullWidth,
    required int fullHeight,
    int x = 0,
    int y = 0,
    int? width,
    int? height,
  });

  /// Drops decoder caches held for this photo. The source stays usable
  /// (the next render decodes again).
  Future<void> release();
}

typedef FloatSourceLoader = Future<FloatSource?> Function(String assetId);

/// Thrown when a float source cannot be decoded; callers fall back to the
/// 8-bit path.
class FloatSourceException implements Exception {
  const FloatSourceException(this.message);
  final String message;

  @override
  String toString() => 'FloatSourceException: $message';
}

class MemoryFloatSource implements FloatSource {
  MemoryFloatSource(this.pixels, {this.profile = HbdProfile.none});

  final FloatBuffer pixels;

  @override
  final HbdProfile profile;

  /// Number of [render] calls and the largest window served (tests).
  int renders = 0;
  int largestWindow = 0;

  @override
  int get width => pixels.width;

  @override
  int get height => pixels.height;

  @override
  Future<FloatPixels> render({
    required int fullWidth,
    required int fullHeight,
    int x = 0,
    int y = 0,
    int? width,
    int? height,
  }) async {
    final w = width ?? fullWidth - x, h = height ?? fullHeight - y;
    if (x < 0 || y < 0 || w <= 0 || h <= 0) {
      throw const FloatSourceException('window outside the image');
    }
    if (x + w > fullWidth || y + h > fullHeight) {
      throw const FloatSourceException('window outside the image');
    }
    renders++;
    if (w * h > largestWindow) largestWindow = w * h;
    final scaled = _scaled(fullWidth, fullHeight);
    final out = scaled.width == w && scaled.height == h
        ? scaled
        : scaled.crop(x, y, w, h);
    return FloatPixels(w, h, out.data);
  }

  FloatBuffer _scaled(int w, int h) {
    final src = pixels;
    if (w == src.width && h == src.height) return src;
    final out = FloatBuffer(w, h);
    for (var y = 0; y < h; y++) {
      final y0 = y * src.height ~/ h;
      final y1 = y0 + 1 > (y + 1) * src.height ~/ h
          ? y0 + 1
          : (y + 1) * src.height ~/ h;
      for (var x = 0; x < w; x++) {
        final x0 = x * src.width ~/ w;
        final x1 = x0 + 1 > (x + 1) * src.width ~/ w
            ? x0 + 1
            : (x + 1) * src.width ~/ w;
        var r = 0.0, g = 0.0, b = 0.0;
        for (var sy = y0; sy < y1; sy++) {
          var o = src.offset(x0, sy);
          for (var sx = x0; sx < x1; sx++, o += 4) {
            r += src.data[o];
            g += src.data[o + 1];
            b += src.data[o + 2];
          }
        }
        final c = (x1 - x0) * (y1 - y0);
        out.setPixel(x, y, r / c, g / c, b / c);
      }
    }
    return out;
  }

  @override
  Future<void> release() async {}
}
