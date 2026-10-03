import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

/// 10x10 image: 40 black, 30 white, 20 pure red, 10 mid gray (128).
RgbaBuffer _fourColors() {
  final buf = RgbaBuffer(10, 10);
  for (var i = 0; i < 100; i++) {
    final x = i % 10, y = i ~/ 10;
    if (i < 40) {
      buf.setPixel(x, y, 0, 0, 0);
    } else if (i < 70) {
      buf.setPixel(x, y, 255, 255, 255);
    } else if (i < 90) {
      buf.setPixel(x, y, 255, 0, 0);
    } else {
      buf.setPixel(x, y, 128, 128, 128);
    }
  }
  return buf;
}

void main() {
  group('pixel helpers', () {
    test('displayLuma matches the exact sRGB encode of Rec.709 luminance', () {
      expect(displayLuma(0, 0, 0), 0);
      expect(displayLuma(255, 255, 255), closeTo(1, 1e-6));
      expect(displayLuma(128, 128, 128), closeTo(128 / 255, 1e-4));
      final y = relativeLuminance(1, 0, 0);
      expect(displayLuma(255, 0, 0), closeTo(linearToSrgb(y), 1e-4));
    });

    test('srgbEncodeFast is within 1e-4 of the exact encode', () {
      for (var i = 0; i <= 2000; i++) {
        final x = i / 2000;
        expect(srgbEncodeFast(x), closeTo(linearToSrgb(x), 1e-4));
      }
      expect(srgbEncodeFast(-1), 0);
      expect(srgbEncodeFast(2), 1);
    });
  });

  group('Histogram', () {
    test('AC-16: bin counts of a known 4-color image are exact', () {
      final h = Histogram.compute(_fourColors());
      expect(h.pixelCount, 100);
      expect(h.red[0], 40);
      expect(h.red[255], 50);
      expect(h.red[128], 10);
      expect(h.green[0], 60);
      expect(h.green[255], 30);
      expect(h.green[128], 10);
      expect(h.blue, h.green);
      final redLuma = (displayLuma(255, 0, 0) * 255).round();
      expect(h.luma[0], 40);
      expect(h.luma[255], 30);
      expect(h.luma[redLuma], 20);
      expect(h.luma[128], 10);
      expect(h.luma.reduce((a, b) => a + b), 100);
    });

    test('clip counts and warnings', () {
      final h = Histogram.compute(_fourColors());
      expect(h.highClipped, 50);
      expect(h.lowClipped, 40);
      expect(h.highClipFraction, 0.5);
      expect(h.lowClipFraction, 0.4);
      expect(h.showHighClipWarning, isTrue);
      final flat = Histogram.compute(RgbaBuffer.filled(10, 10, 100, 100, 100));
      expect(flat.showHighClipWarning, isFalse);
      expect(flat.showLowClipWarning, isFalse);
    });

    test('luma percentiles from the cumulative distribution', () {
      final h = Histogram.compute(_fourColors());
      expect(h.lumaPercentile(0), 0);
      expect(h.lumaPercentile(0.39), 0);
      expect(h.lumaPercentile(1), closeTo(1, 1e-9));
      final p50 = h.lumaPercentile(0.5);
      expect(p50 * 255, closeTo((displayLuma(255, 0, 0) * 255).round(), 1));
    });

    test('lists are unmodifiable', () {
      final h = Histogram.compute(_fourColors());
      expect(() => h.red[0] = 1, throwsUnsupportedError);
    });
  });
}
