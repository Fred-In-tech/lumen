import 'dart:typed_data';

/// An 8-bit sRGB-encoded RGBA image held in memory (row-major, 4 bytes/pixel).
class RgbaBuffer {
  RgbaBuffer(this.width, this.height, [Uint8List? data])
    : data = data ?? Uint8List(width * height * 4) {
    if (this.data.length != width * height * 4) {
      throw ArgumentError(
        'data length ${this.data.length} != ${width * height * 4}',
      );
    }
  }

  /// Creates a buffer filled with one color.
  factory RgbaBuffer.filled(
    int width,
    int height,
    int r,
    int g,
    int b, [
    int a = 255,
  ]) {
    final buf = RgbaBuffer(width, height);
    for (var i = 0; i < buf.data.length; i += 4) {
      buf.data[i] = r;
      buf.data[i + 1] = g;
      buf.data[i + 2] = b;
      buf.data[i + 3] = a;
    }
    return buf;
  }

  final int width;
  final int height;
  final Uint8List data;

  int get pixelCount => width * height;

  int offset(int x, int y) => (y * width + x) * 4;

  int r(int x, int y) => data[offset(x, y)];
  int g(int x, int y) => data[offset(x, y) + 1];
  int b(int x, int y) => data[offset(x, y) + 2];

  void setPixel(int x, int y, int r, int g, int b, [int a = 255]) {
    final o = offset(x, y);
    data[o] = r;
    data[o + 1] = g;
    data[o + 2] = b;
    data[o + 3] = a;
  }

  RgbaBuffer copy() => RgbaBuffer(width, height, Uint8List.fromList(data));
}
