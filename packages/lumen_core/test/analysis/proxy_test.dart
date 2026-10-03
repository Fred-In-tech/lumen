import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('makeProxy', () {
    test('scales the long edge and keeps the aspect ratio', () {
      final p = makeProxy(RgbaBuffer.filled(1200, 800, 10, 20, 30));
      expect(p.width, 512);
      expect(p.height, 341);
      final portrait = makeProxy(
        RgbaBuffer.filled(300, 900, 1, 1, 1),
        longEdge: 256,
      );
      expect(portrait.height, 256);
      expect(portrait.width, 85);
    });

    test('a constant image stays constant', () {
      final p = makeProxy(RgbaBuffer.filled(1000, 700, 77, 140, 210));
      for (var i = 0; i < p.data.length; i += 4) {
        expect(p.data[i], 77);
        expect(p.data[i + 1], 140);
        expect(p.data[i + 2], 210);
        expect(p.data[i + 3], 255);
      }
    });

    test('averages in linear light', () {
      final src = RgbaBuffer(4, 2);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 4; x++) {
          final v = (x + y).isEven ? 255 : 0;
          src.setPixel(x, y, v, v, v);
        }
      }
      final p = makeProxy(src, longEdge: 2);
      expect(p.width, 2);
      expect(p.height, 1);
      final expected = (linearToSrgb(0.5) * 255).round();
      expect(p.r(0, 0), expected);
      expect(p.g(1, 0), expected);
    });

    test('non-integer ratios conserve mean linear light', () {
      final src = RgbaBuffer(7, 3);
      for (var x = 0; x < 7; x++) {
        for (var y = 0; y < 3; y++) {
          src.setPixel(x, y, x < 3 ? 255 : 0, 0, 0);
        }
      }
      final p = makeProxy(src, longEdge: 3);
      var sum = 0.0;
      for (var x = 0; x < p.width; x++) {
        sum += srgbToLinear(p.r(x, 0) / 255);
      }
      expect(sum / p.width, closeTo(3 / 7, 0.01));
    });

    test('never upscales: small inputs are copied', () {
      final src = SyntheticScenes.markerCorners(longEdge: 200).image;
      final p = makeProxy(src);
      expect(p.width, src.width);
      expect(p.data, src.data);
      expect(identical(p.data, src.data), isFalse);
    });
  });
}
