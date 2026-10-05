import 'dart:typed_data';

import '../color/srgb.dart';
import '../render/rgba_buffer.dart';

/// Linear-light RGB pixels the Auto Enhance measurements read.
///
/// Values are relative to display white (1.0) and are **not** assumed to be
/// clamped: a float RAW pipeline may hand over highlights above 1.0, an
/// 8-bit rendition is decoded with [LinearPixels.fromRgba].
class LinearPixels {
  LinearPixels(this.width, this.height, this.rgb) {
    if (rgb.length != width * height * 3) {
      throw ArgumentError('rgb length ${rgb.length} != ${width * height * 3}');
    }
  }

  /// Decodes 8-bit sRGB [image] (alpha is ignored).
  factory LinearPixels.fromRgba(RgbaBuffer image) {
    final d = image.data;
    final out = Float32List(image.pixelCount * 3);
    for (var i = 0, o = 0; i < d.length; i += 4, o += 3) {
      out[o] = kSrgbByteToLinear[d[i]];
      out[o + 1] = kSrgbByteToLinear[d[i + 1]];
      out[o + 2] = kSrgbByteToLinear[d[i + 2]];
    }
    return LinearPixels(image.width, image.height, out);
  }

  final int width;
  final int height;

  /// Row-major linear R, G, B (3 floats per pixel).
  final Float32List rgb;

  int get pixelCount => width * height;
}

/// Rec. 709 relative luminance of linear RGB.
double luminanceOf(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;

/// sRGB-encodes [linear] clamped to 0..1 (table-free; measurement only).
double encodeClamped(double linear) => linearToSrgb(linear);
