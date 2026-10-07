import 'dart:typed_data';

import 'export_preset.dart';

/// A tile of the output frame (no apron).
typedef TileRect = ({int x, int y, int w, int h});

/// A 0..1 sample as a 16-bit level (clamped, rounded).
int floatTo16(double v) =>
    v <= 0 ? 0 : (v >= 1 ? 65535 : (v * 65535 + 0.5).toInt());

/// Copies the [r] region of a float RGBA tile (rows of [tileStride]
/// pixels, [r] starting at ([offX], [offY]) in the tile) into a 16-bit
/// RGB [frame] of [frameWidth] pixels: full precision, no dither.
void blitFloatTile16(
  Float32List tile,
  int tileStride,
  int offX,
  int offY,
  TileRect r,
  Uint16List frame,
  int frameWidth,
) {
  for (var row = 0; row < r.h; row++) {
    var s = ((offY + row) * tileStride + offX) * 4;
    var d = ((r.y + row) * frameWidth + r.x) * 3;
    for (var x = 0; x < r.w; x++, s += 4, d += 3) {
      frame[d] = floatTo16(tile[s]);
      frame[d + 1] = floatTo16(tile[s + 1]);
      frame[d + 2] = floatTo16(tile[s + 2]);
    }
  }
}

/// Uniform noise in [0, 1) from absolute pixel coordinates and channel:
/// the same everywhere a pixel is rendered, so tiles have no seams.
double _noise(int x, int y, int c) {
  var h = (x * 0x27d4eb2d) ^ (y * 0x165667b1) ^ (c * 0x9e3779b9);
  h &= 0xFFFFFFFF;
  h ^= h >> 16;
  h = (h * 0x7feb352d) & 0xFFFFFFFF;
  h ^= h >> 15;
  h = (h * 0x846ca68b) & 0xFFFFFFFF;
  h ^= h >> 16;
  return (h & 0xFFFFFF) / 0x1000000;
}

/// As [blitFloatTile16] into an RGBA8888 [frame], quantized with
/// ±½-level random dither so smooth float gradients do not band in 8 bits
/// (every value stays within one level of the exact one).
void blitFloatTile8Dithered(
  Float32List tile,
  int tileStride,
  int offX,
  int offY,
  TileRect r,
  Uint8List frame,
  int frameWidth,
) {
  for (var row = 0; row < r.h; row++) {
    final y = r.y + row;
    var s = ((offY + row) * tileStride + offX) * 4;
    var d = (y * frameWidth + r.x) * 4;
    for (var i = 0; i < r.w; i++, s += 4, d += 4) {
      final x = r.x + i;
      for (var c = 0; c < 3; c++) {
        final v = (tile[s + c] * 255 + _noise(x, y, c)).floor();
        frame[d + c] = v < 0 ? 0 : (v > 255 ? 255 : v);
      }
      frame[d + 3] = 255;
    }
  }
}

/// RGBA8888 → 16-bit RGB (v × 257: 255 maps to 65535). Adds no detail.
Uint16List widenRgba8To16(Uint8List rgba, int width, int height) {
  final out = Uint16List(width * height * 3);
  for (var i = 0, o = 0; o < out.length; i += 4, o += 3) {
    out[o] = rgba[i] * 257;
    out[o + 1] = rgba[i + 1] * 257;
    out[o + 2] = rgba[i + 2] * 257;
  }
  return out;
}

({int radius, double amount})? _sharpenParams(OutputSharpen s) => switch (s) {
  OutputSharpen.none => null,
  OutputSharpen.screen => (radius: 1, amount: 0.5),
  OutputSharpen.printLow => (radius: 2, amount: 0.6),
  OutputSharpen.printStandard => (radius: 2, amount: 1.0),
};

/// Unsharp mask in place over interleaved pixels ([channels] 3 or 4, the
/// first three are RGB; a fourth is left alone), binomial blur of
/// [OutputSharpen]'s radius. Holds 2·radius + 1 original rows, never a
/// second copy of the image.
void sharpenInPlace(
  List<int> data,
  int width,
  int height,
  int channels,
  int maxValue,
  OutputSharpen level,
) {
  final s = _Sharpener.of(data, width, height, channels, maxValue, level);
  if (s == null) return;
  for (var y = 0; y < height; y++) {
    s.row(y);
  }
}

/// [sharpenInPlace], yielding to the event loop after [sliceMicros] of
/// work (checked every [rowsPerSlice] rows): a 45 MP frame takes seconds,
/// the UI keeps drawing meanwhile.
Future<void> sharpenInPlaceAsync(
  List<int> data,
  int width,
  int height,
  int channels,
  int maxValue,
  OutputSharpen level, {
  int rowsPerSlice = 16,
  int sliceMicros = 30000,
}) async {
  final s = _Sharpener.of(data, width, height, channels, maxValue, level);
  if (s == null) return;
  final slice = Stopwatch()..start();
  for (var y = 0; y < height; y++) {
    s.row(y);
    if ((y + 1) % rowsPerSlice == 0 &&
        slice.elapsedMicroseconds >= sliceMicros) {
      await Future<void>.delayed(Duration.zero);
      slice.reset();
    }
  }
}

class _Sharpener {
  _Sharpener(
    this.data,
    this.width,
    this.height,
    this.channels,
    this.maxValue,
    this.radius,
    this.amount,
  ) : kernel = radius == 1 ? const [1, 2, 1] : const [1, 4, 6, 4, 1],
      rows = List.generate(2 * radius + 1, (_) => Int32List(width * 3)),
      vert = Float64List(width * 3);

  static _Sharpener? of(
    List<int> data,
    int width,
    int height,
    int channels,
    int maxValue,
    OutputSharpen level,
  ) {
    final p = _sharpenParams(level);
    if (p == null || width < 1 || height < 1) return null;
    return _Sharpener(
      data,
      width,
      height,
      channels,
      maxValue,
      p.radius,
      p.amount,
    )..prime();
  }

  final List<int> data;
  final int width, height, channels, maxValue, radius;
  final double amount;
  final List<int> kernel;

  /// Original rows y - radius … y + radius, by (row mod length).
  final List<Int32List> rows;
  final Float64List vert;

  int get _norm => radius == 1 ? 4 : 16;

  void _load(int y) {
    final dst = rows[y % rows.length];
    final cy = y < 0 ? 0 : (y >= height ? height - 1 : y);
    var s = cy * width * channels;
    for (var x = 0, d = 0; x < width; x++, s += channels, d += 3) {
      dst[d] = data[s];
      dst[d + 1] = data[s + 1];
      dst[d + 2] = data[s + 2];
    }
  }

  Int32List _rowFor(int y) {
    final cy = y < 0 ? 0 : (y >= height ? height - 1 : y);
    return rows[cy % rows.length];
  }

  void prime() {
    for (var y = 0; y <= radius && y < height; y++) {
      _load(y);
    }
  }

  void row(int y) {
    if (y + radius < height && y + radius > radius) _load(y + radius);
    // Vertical blur of rows y-r … y+r.
    vert.fillRange(0, vert.length, 0);
    for (var k = -radius; k <= radius; k++) {
      final src = _rowFor(y + k);
      final w = kernel[k + radius];
      for (var i = 0; i < vert.length; i++) {
        vert[i] += src[i] * w;
      }
    }
    final orig = _rowFor(y);
    final n = _norm * _norm;
    var d = y * width * channels;
    for (var x = 0; x < width; x++, d += channels) {
      for (var c = 0; c < 3; c++) {
        var b = 0.0;
        for (var k = -radius; k <= radius; k++) {
          var xx = x + k;
          if (xx < 0) xx = 0;
          if (xx >= width) xx = width - 1;
          b += vert[xx * 3 + c] * kernel[k + radius];
        }
        final o = orig[x * 3 + c];
        final v = (o + amount * (o - b / n)).round();
        data[d + c] = v < 0 ? 0 : (v > maxValue ? maxValue : v);
      }
    }
  }
}

/// Coverage (0–255) of rendered watermark text, [width]×[height].
class WatermarkMask {
  WatermarkMask(this.width, this.height, this.coverage) {
    if (coverage.length != width * height) {
      throw ArgumentError('coverage ${coverage.length} != ${width}x$height');
    }
  }

  final int width;
  final int height;
  final Uint8List coverage;
}

/// Top-left corner of [mask] at [position] inside a [width]×[height]
/// image, [margin] pixels from the edges.
({int x, int y}) watermarkOrigin(
  WatermarkPosition position,
  int width,
  int height,
  WatermarkMask mask, {
  required int margin,
}) {
  final right = width - margin - mask.width;
  final bottom = height - margin - mask.height;
  return switch (position) {
    WatermarkPosition.topLeft => (x: margin, y: margin),
    WatermarkPosition.topRight => (x: right, y: margin),
    WatermarkPosition.bottomLeft => (x: margin, y: bottom),
    WatermarkPosition.bottomRight => (x: right, y: bottom),
    WatermarkPosition.center => (
      x: (width - mask.width) ~/ 2,
      y: (height - mask.height) ~/ 2,
    ),
  };
}

/// Blends white text ([mask]) at [opacity] into interleaved pixels
/// (clipped to the image).
void blendWatermark(
  List<int> data,
  int width,
  int height,
  int channels,
  int maxValue,
  WatermarkMask mask,
  WatermarkPosition position, {
  required double opacity,
  required int margin,
}) {
  final o = watermarkOrigin(position, width, height, mask, margin: margin);
  for (var my = 0; my < mask.height; my++) {
    final y = o.y + my;
    if (y < 0 || y >= height) continue;
    for (var mx = 0; mx < mask.width; mx++) {
      final x = o.x + mx;
      if (x < 0 || x >= width) continue;
      final cov = mask.coverage[my * mask.width + mx];
      if (cov == 0) continue;
      final a = opacity * cov / 255;
      final d = (y * width + x) * channels;
      for (var c = 0; c < 3; c++) {
        final v = data[d + c];
        data[d + c] = (v + (maxValue - v) * a).round();
      }
    }
  }
}
