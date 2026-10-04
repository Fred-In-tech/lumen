import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  test('letterbox: 2:1 image pads top and bottom with black', () {
    final src = RgbaBuffer.filled(200, 100, 255, 0, 51);
    final t = letterboxToTensor(src, width: 128, height: 128);
    expect(t.data, hasLength(128 * 128 * 3));
    expect(t.letterbox.top, closeTo(0.25, 1e-12));
    expect(t.letterbox.bottom, closeTo(0.25, 1e-12));
    expect(t.letterbox.left, 0);
    // Row 0 is padding (black → −1), row 64 is content.
    expect(t.data.sublist(0, 3), [-1, -1, -1]);
    final mid = (64 * 128 + 64) * 3;
    expect(t.data[mid], closeTo(1, 1e-6));
    expect(t.data[mid + 1], closeTo(-1, 1e-6));
    expect(t.data[mid + 2], closeTo(51 / 127.5 - 1, 1e-6));
  });

  test('letterbox: box-filter average of a checkerboard is mid-grey', () {
    final src = RgbaBuffer(256, 256);
    for (var y = 0; y < 256; y++) {
      for (var x = 0; x < 256; x++) {
        final v = (x + y).isEven ? 255 : 0;
        src.setPixel(x, y, v, v, v);
      }
    }
    final t = letterboxToTensor(
      src,
      width: 128,
      height: 128,
      range: TensorRange.zeroToOne,
    );
    for (var i = 0; i < t.data.length; i++) {
      expect(t.data[i], closeTo(0.5, 1e-6));
    }
  });

  test('letterbox: a region samples only that sub-rectangle', () {
    final src = RgbaBuffer.filled(100, 100, 0, 0, 0);
    for (var y = 50; y < 100; y++) {
      for (var x = 50; x < 100; x++) {
        src.setPixel(x, y, 255, 255, 255);
      }
    }
    final t = letterboxToTensor(
      src,
      width: 10,
      height: 10,
      region: (left: 50, top: 50, width: 50, height: 50),
      range: TensorRange.zeroToOne,
    );
    expect(t.data.every((v) => (v - 1).abs() < 1e-6), isTrue);
  });

  test('warp: identity crop reproduces pixels; outside repeats edges', () {
    final src = RgbaBuffer(4, 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        src.setPixel(x, y, x * 60, y * 60, 0);
      }
    }
    final t = warpToTensor(src, Affine2x3.identity, size: 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        final o = (y * 4 + x) * 3;
        expect(t[o], closeTo(x * 60 / 255, 1e-6));
        expect(t[o + 1], closeTo(y * 60 / 255, 1e-6));
      }
    }
    final shifted = warpToTensor(
      src,
      const Affine2x3(1, 0, -10, 0, 1, -10),
      size: 2,
    );
    expect(shifted[0], 0); // clamped to pixel (0, 0)
  });

  test('warp: an aligned crop of a flat image is flat, in range', () {
    final src = RgbaBuffer.filled(300, 200, 255, 255, 255);
    const crop = AlignedCrop(
      centerX: 150,
      centerY: 100,
      side: 120,
      rotation: 0.7,
      outputSize: 32,
    );
    final t = warpToTensor(
      src,
      crop.cropToSource,
      size: 32,
      range: TensorRange.minusOneToOne,
    );
    expect(t.every((v) => (v - 1).abs() < 1e-6), isTrue);
  });
}
