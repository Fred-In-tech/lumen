import 'dart:math' as math;
import 'dart:typed_data';

import '../render/rgba_buffer.dart';

/// A float working image (interleaved channels, sRGB-encoded 0..255 for
/// colour). Algorithms take one and return a new one; the buffer itself is
/// a plain mutable scratch surface like [RgbaBuffer].
class FloatImage {
  FloatImage(this.width, this.height, {this.channels = 3, Float32List? data})
    : data = data ?? Float32List(width * height * channels) {
    if (this.data.length != width * height * channels) {
      throw ArgumentError(
        'data ${this.data.length} != $width x $height x $channels',
      );
    }
  }

  /// RGB of [b] (alpha ignored: sources are opaque).
  factory FloatImage.fromRgba(RgbaBuffer b) {
    final out = FloatImage(b.width, b.height);
    final d = out.data, s = b.data;
    for (var i = 0, o = 0; i < s.length; i += 4, o += 3) {
      d[o] = s[i].toDouble();
      d[o + 1] = s[i + 1].toDouble();
      d[o + 2] = s[i + 2].toDouble();
    }
    return out;
  }

  final int width;
  final int height;
  final int channels;
  final Float32List data;

  int get pixelCount => width * height;

  double at(int x, int y, int c) => data[(y * width + x) * channels + c];

  void set(int x, int y, int c, double v) =>
      data[(y * width + x) * channels + c] = v;

  FloatImage copy() => FloatImage(
    width,
    height,
    channels: channels,
    data: Float32List.fromList(data),
  );

  /// The in-bounds window at ([x], [y]) of [w]×[h] (a new buffer).
  FloatImage window(int x, int y, int w, int h) {
    final out = FloatImage(w, h, channels: channels);
    for (var row = 0; row < h; row++) {
      final s = ((y + row) * width + x) * channels;
      out.data.setRange(row * w * channels, (row + 1) * w * channels, data, s);
    }
    return out;
  }

  /// Rounded, clamped RGB (first 3 channels) with alpha 255.
  RgbaBuffer toRgba() {
    final out = RgbaBuffer(width, height);
    final o = out.data;
    for (var i = 0, p = 0; p < o.length; i += channels, p += 4) {
      o[p] = data[i].round().clamp(0, 255);
      o[p + 1] = data[i + 1].round().clamp(0, 255);
      o[p + 2] = data[i + 2].round().clamp(0, 255);
      o[p + 3] = 255;
    }
    return out;
  }
}

typedef _Taps = List<List<(int, double)>>;

/// Area-average resize (exact box footprint); falls back to bilinear on an
/// axis that is enlarged.
FloatImage resizeArea(FloatImage src, int w, int h) => _resample(
  src,
  w,
  h,
  w <= src.width ? _areaTaps(src.width, w) : _bilinearTaps(src.width, w),
  h <= src.height ? _areaTaps(src.height, h) : _bilinearTaps(src.height, h),
);

/// Bilinear resize over pixel centres (edges clamp).
FloatImage resizeBilinear(FloatImage src, int w, int h) => _resample(
  src,
  w,
  h,
  _bilinearTaps(src.width, w),
  _bilinearTaps(src.height, h),
);

_Taps _areaTaps(int n, int m) {
  final s = n / m;
  return [
    for (var i = 0; i < m; i++)
      () {
        final a = i * s, b = (i + 1) * s;
        return [
          for (var j = a.floor(); j < math.min(n, b.ceil()); j++)
            (j, (math.min(b, j + 1.0) - math.max(a, j.toDouble())) / s),
        ];
      }(),
  ];
}

_Taps _bilinearTaps(int n, int m) {
  final s = n / m;
  return [
    for (var i = 0; i < m; i++)
      () {
        final c = (i + 0.5) * s - 0.5;
        final j0 = c.floor();
        final f = c - j0;
        return [(j0.clamp(0, n - 1), 1 - f), ((j0 + 1).clamp(0, n - 1), f)];
      }(),
  ];
}

FloatImage _resample(FloatImage src, int w, int h, _Taps tx, _Taps ty) {
  final ch = src.channels;
  final tmp = Float32List(w * src.height * ch);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * ch;
      for (final (j, wt) in tx[x]) {
        final s = (y * src.width + j) * ch;
        for (var c = 0; c < ch; c++) {
          tmp[o + c] += wt * src.data[s + c];
        }
      }
    }
  }
  final out = FloatImage(w, h, channels: ch);
  for (var y = 0; y < h; y++) {
    for (final (j, wt) in ty[y]) {
      final srow = j * w * ch, orow = y * w * ch;
      for (var i = 0; i < w * ch; i++) {
        out.data[orow + i] += wt * tmp[srow + i];
      }
    }
  }
  return out;
}

/// Gaussian blur (separable, radius 3σ, edges clamp). With [weights]
/// (one per pixel) it is a normalized convolution:
/// `blur(w·v) / blur(w)`, 0 where no weight is in reach.
FloatImage gaussianBlur(FloatImage src, double sigma, {Float32List? weights}) {
  final w = src.width, h = src.height, ch = src.channels;
  final r = math.max(1, (3 * sigma).ceil());
  final k = Float64List(2 * r + 1);
  for (var i = -r; i <= r; i++) {
    k[i + r] = math.exp(-(i * i) / (2 * sigma * sigma));
  }
  final wt = weights ?? (Float32List(w * h)..fillRange(0, w * h, 1));
  // Premultiply by weight; carry the weight as an extra channel.
  final c1 = ch + 1;
  final a = Float32List(w * h * c1);
  for (var i = 0; i < w * h; i++) {
    for (var c = 0; c < ch; c++) {
      a[i * c1 + c] = src.data[i * ch + c] * wt[i];
    }
    a[i * c1 + ch] = wt[i];
  }
  final b = Float32List(w * h * c1);
  _blurAxis(a, b, w, h, c1, k, r, horizontal: true);
  _blurAxis(b, a, w, h, c1, k, r, horizontal: false);
  final out = FloatImage(w, h, channels: ch);
  for (var i = 0; i < w * h; i++) {
    final s = a[i * c1 + ch];
    for (var c = 0; c < ch; c++) {
      out.data[i * ch + c] = s > 1e-12 ? a[i * c1 + c] / s : 0;
    }
  }
  return out;
}

void _blurAxis(
  Float32List src,
  Float32List dst,
  int w,
  int h,
  int ch,
  Float64List k,
  int r, {
  required bool horizontal,
}) {
  final n = horizontal ? w : h, lines = horizontal ? h : w;
  final acc = Float64List(ch);
  for (var l = 0; l < lines; l++) {
    for (var i = 0; i < n; i++) {
      acc.fillRange(0, ch, 0);
      for (var t = -r; t <= r; t++) {
        final j = (i + t).clamp(0, n - 1);
        final p = horizontal ? l * w + j : j * w + l;
        final kv = k[t + r];
        for (var c = 0; c < ch; c++) {
          acc[c] += kv * src[p * ch + c];
        }
      }
      final o = horizontal ? l * w + i : i * w + l;
      for (var c = 0; c < ch; c++) {
        dst[o * ch + c] = acc[c];
      }
    }
  }
}
