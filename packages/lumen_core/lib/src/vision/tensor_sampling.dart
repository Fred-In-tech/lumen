import 'dart:math' as math;
import 'dart:typed_data';

import '../render/rgba_buffer.dart';
import 'affine.dart';
import 'face_detection.dart';

/// Value range a model expects for 8-bit input.
enum TensorRange {
  zeroToOne,
  minusOneToOne;

  /// Encodes an 8-bit value (may be fractional after filtering).
  double encode(num v) => this == zeroToOne ? v / 255.0 : v / 127.5 - 1.0;
}

/// A pixel rectangle inside an image.
typedef PixelRegion = ({int left, int top, int width, int height});

/// Padding a letterbox added, as fractions of the tensor size.
class Letterbox {
  const Letterbox({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Maps a detection normalized to the tensor back to the sampled region
  /// (MediaPipe `DetectionLetterboxRemovalCalculator`).
  FaceDetection remove(FaceDetection d) {
    final sx = 1 / (1 - left - right);
    final sy = 1 / (1 - top - bottom);
    return d.mapped(
      offsetX: -left * sx,
      offsetY: -top * sy,
      scaleX: sx,
      scaleY: sy,
    );
  }
}

/// An NHWC float tensor (`[1, height, width, 3]`) plus its letterbox.
class LetterboxedTensor {
  const LetterboxedTensor(this.data, this.width, this.height, this.letterbox);

  final Float32List data;
  final int width;
  final int height;
  final Letterbox letterbox;
}

/// Fits [region] of [src] (whole image by default) into a [width]×[height]
/// tensor keeping the aspect ratio, centred, padded with black. Downscaling
/// averages every source pixel whose centre falls in the tensor pixel's
/// footprint (box filter); upscaling takes the nearest pixel.
LetterboxedTensor letterboxToTensor(
  RgbaBuffer src, {
  required int width,
  required int height,
  PixelRegion? region,
  TensorRange range = TensorRange.minusOneToOne,
}) {
  final r = region ?? (left: 0, top: 0, width: src.width, height: src.height);
  if (r.width <= 0 || r.height <= 0) {
    throw ArgumentError('empty region $r');
  }
  final scale = math.min(width / r.width, height / r.height);
  final padX = (width - r.width * scale) / 2;
  final padY = (height - r.height * scale) / 2;
  final cols = _spans(width, padX, scale, r.left, r.width);
  final rows = _spans(height, padY, scale, r.top, r.height);
  final out = Float32List(width * height * 3);
  final pad = range.encode(0);
  final data = src.data;
  for (var j = 0; j < height; j++) {
    final (y0, y1) = rows[j];
    for (var i = 0; i < width; i++) {
      final o = (j * width + i) * 3;
      final (x0, x1) = cols[i];
      if (y0 < 0 || x0 < 0) {
        out[o] = out[o + 1] = out[o + 2] = pad;
        continue;
      }
      var sr = 0, sg = 0, sb = 0;
      for (var y = y0; y <= y1; y++) {
        var p = (y * src.width + x0) * 4;
        for (var x = x0; x <= x1; x++, p += 4) {
          sr += data[p];
          sg += data[p + 1];
          sb += data[p + 2];
        }
      }
      final count = (y1 - y0 + 1) * (x1 - x0 + 1);
      out[o] = range.encode(sr / count);
      out[o + 1] = range.encode(sg / count);
      out[o + 2] = range.encode(sb / count);
    }
  }
  return LetterboxedTensor(
    out,
    width,
    height,
    Letterbox(
      left: padX / width,
      right: padX / width,
      top: padY / height,
      bottom: padY / height,
    ),
  );
}

/// For each output index along one axis: the inclusive source pixel span it
/// averages, or (-1, -1) for padding.
List<(int, int)> _spans(int n, double pad, double scale, int start, int len) {
  return List.generate(n, (i) {
    final centre = i + 0.5;
    if (centre < pad || centre > pad + len * scale) return (-1, -1);
    final s0 = (i - pad) / scale;
    final s1 = (i + 1 - pad) / scale;
    var a = (s0 - 0.5).ceil();
    var b = (s1 - 0.5).ceil() - 1;
    if (b < a) a = b = ((s0 + s1) / 2).floor();
    a = a.clamp(0, len - 1);
    b = b.clamp(a, len - 1);
    return (start + a, start + b);
  }, growable: false);
}

/// Samples [src] through [cropToSource] (crop pixels → source pixels) into a
/// [size]×[size] NHWC tensor with bilinear filtering; outside the image the
/// edge pixels repeat.
Float32List warpToTensor(
  RgbaBuffer src,
  Affine2x3 cropToSource, {
  required int size,
  TensorRange range = TensorRange.zeroToOne,
}) {
  final out = Float32List(size * size * 3);
  final w = src.width;
  final h = src.height;
  final data = src.data;
  final m = cropToSource;
  for (var j = 0; j < size; j++) {
    for (var i = 0; i < size; i++) {
      final (sx, sy) = m.apply(i + 0.5, j + 0.5);
      final fx = (sx - 0.5).clamp(0.0, w - 1.0);
      final fy = (sy - 0.5).clamp(0.0, h - 1.0);
      final x0 = fx.floor();
      final y0 = fy.floor();
      final x1 = math.min(x0 + 1, w - 1);
      final y1 = math.min(y0 + 1, h - 1);
      final tx = fx - x0;
      final ty = fy - y0;
      final p00 = (y0 * w + x0) * 4;
      final p10 = (y0 * w + x1) * 4;
      final p01 = (y1 * w + x0) * 4;
      final p11 = (y1 * w + x1) * 4;
      final o = (j * size + i) * 3;
      for (var c = 0; c < 3; c++) {
        final top = data[p00 + c] + (data[p10 + c] - data[p00 + c]) * tx;
        final bot = data[p01 + c] + (data[p11 + c] - data[p01 + c]) * tx;
        final v = top + (bot - top) * ty;
        out[o + c] = range.encode(v);
      }
    }
  }
  return out;
}
