import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('quantize', () {
    test('float tile to 16-bit RGB keeps 65536 levels and clamps', () {
      // A 4x2 tile with a 1-pixel apron on the left: copy columns 1..3.
      final tile = Float32List(4 * 2 * 4);
      for (var i = 0; i < 8; i++) {
        tile[i * 4] = i / 7;
        tile[i * 4 + 1] = -0.5;
        tile[i * 4 + 2] = 2.0;
        tile[i * 4 + 3] = 1;
      }
      final frame = Uint16List(5 * 3 * 3);
      blitFloatTile16(tile, 4, 1, 0, (x: 2, y: 1, w: 3, h: 2), frame, 5);
      // Row 1, x = 2 gets tile (1, 0).
      final o = (1 * 5 + 2) * 3;
      expect(frame[o], (65535 * 1 / 7).round());
      expect(frame[o + 1], 0);
      expect(frame[o + 2], 65535);
      expect(frame[0], 0, reason: 'outside the tile is untouched');
      expect(floatTo16(0.5), 32768);
    });

    test('dithered 8-bit stays within one level and averages to the value', () {
      const w = 64, h = 64;
      final tile = Float32List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        tile[i * 4] = 100.3 / 255;
        tile[i * 4 + 1] = 0;
        tile[i * 4 + 2] = 1.5;
        tile[i * 4 + 3] = 1;
      }
      final frame = Uint8List(w * h * 4);
      blitFloatTile8Dithered(tile, w, 0, 0, (x: 0, y: 0, w: w, h: h), frame, w);
      var sum = 0;
      for (var i = 0; i < w * h; i++) {
        final r = frame[i * 4];
        expect(r == 100 || r == 101, isTrue);
        expect(frame[i * 4 + 1], 0);
        expect(frame[i * 4 + 2], 255);
        expect(frame[i * 4 + 3], 255);
        sum += r;
      }
      expect(sum / (w * h), closeTo(100.3, 0.08));
      // Seamless: the pattern depends on absolute coordinates only.
      final again = Uint8List(w * h * 4);
      blitFloatTile8Dithered(tile, w, 0, 0, (x: 0, y: 0, w: w, h: h), again, w);
      expect(again, frame);
    });

    test('8-bit RGBA widened to 16-bit RGB', () {
      final rgba = Uint8List.fromList([0, 128, 255, 255, 1, 2, 3, 255]);
      expect(widenRgba8To16(rgba, 2, 1), [0, 32896, 65535, 257, 514, 771]);
    });
  });

  group('sharpen', () {
    for (final ch in [3, 4]) {
      test('flat areas stay flat, edges gain contrast ($ch channels)', () {
        const w = 16, h = 8;
        final data = Uint16List(w * h * ch);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final v = x < w ~/ 2 ? 20000 : 40000;
            for (var c = 0; c < 3; c++) {
              data[(y * w + x) * ch + c] = v;
            }
            if (ch == 4) data[(y * w + x) * ch + 3] = 65535;
          }
        }
        final before = Uint16List.fromList(data);
        sharpenInPlace(data, w, h, ch, 65535, OutputSharpen.printStandard);
        int at(int x) => data[(3 * w + x) * ch];
        expect(at(1), 20000);
        expect(at(w - 2), 40000);
        expect(at(w ~/ 2 - 1), lessThan(20000));
        expect(at(w ~/ 2), greaterThan(40000));
        if (ch == 4) expect(data[3], 65535);
        final none = Uint16List.fromList(before);
        sharpenInPlace(none, w, h, ch, 65535, OutputSharpen.none);
        expect(none, before);
      });
    }

    test('8-bit clamps, and the async version matches', () async {
      const w = 9, h = 9;
      final a = Uint8List(w * h * 3);
      for (var i = 0; i < a.length; i++) {
        a[i] = (i ~/ 3) % 2 == 0 ? 0 : 255;
      }
      final b = Uint8List.fromList(a);
      sharpenInPlace(a, w, h, 3, 255, OutputSharpen.screen);
      await sharpenInPlaceAsync(
        b,
        w,
        h,
        3,
        255,
        OutputSharpen.screen,
        rowsPerSlice: 2,
      );
      expect(b, a);
      expect(a.every((v) => v == 0 || v == 255), isTrue);
    });
  });

  group('watermark blend', () {
    test('coverage blends white at the opacity, nothing outside', () {
      const w = 10, h = 6;
      final data = Uint16List(w * h * 3);
      final mask = WatermarkMask(2, 2, Uint8List.fromList([255, 0, 128, 255]));
      blendWatermark(
        data,
        w,
        h,
        3,
        65535,
        mask,
        WatermarkPosition.bottomRight,
        opacity: 0.5,
        margin: 1,
      );
      int at(int x, int y) => data[(y * w + x) * 3];
      // bottom-right with margin 1: mask at x 7..8, y 3..4
      expect(at(7, 3), (65535 * 0.5).round());
      expect(at(8, 3), 0);
      expect(at(7, 4), closeTo(65535 * 0.5 * 128 / 255, 1));
      expect(at(0, 0), 0);
    });

    test('positions', () {
      final m = WatermarkMask(2, 1, Uint8List.fromList([255, 255]));
      ({int x, int y}) o(WatermarkPosition p) =>
          watermarkOrigin(p, 10, 5, m, margin: 1);
      expect(o(WatermarkPosition.topLeft), (x: 1, y: 1));
      expect(o(WatermarkPosition.topRight), (x: 7, y: 1));
      expect(o(WatermarkPosition.bottomLeft), (x: 1, y: 3));
      expect(o(WatermarkPosition.center), (x: 4, y: 2));
      final big = WatermarkMask(20, 1, Uint8List(20));
      final data = Uint8List(10 * 5 * 4);
      blendWatermark(
        data,
        10,
        5,
        4,
        255,
        big,
        WatermarkPosition.center,
        opacity: 1,
        margin: 0,
      );
      expect(data.every((v) => v == 0), isTrue);
      for (final p in WatermarkPosition.values) {
        expect(p.label, isNotEmpty);
      }
    });
  });
}
