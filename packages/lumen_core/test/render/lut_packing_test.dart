import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

void main() {
  group('16-bit packing', () {
    test('every 16-bit value round-trips through hi/lo bytes exactly', () {
      for (var q = 0; q <= 65535; q++) {
        final hi = packHi(q), lo = packLo(q);
        expect(hi, inInclusiveRange(0, 255));
        expect(lo, inInclusiveRange(0, 255));
        expect(unpackBytes16(hi, lo), q);
      }
    });

    test('quantize16 clamps and rounds', () {
      expect(quantize16(-1), 0);
      expect(quantize16(2), 65535);
      expect(quantize16(0.5), 32768);
      expect(dequantize16(65535), 1);
    });

    test('unpackNormalized mirrors the shader formula', () {
      // Shader: dot(rg, vec2(65280, 255)) / 65535 with rg = bytes / 255.
      for (final q in [0, 1, 255, 256, 12345, 65534, 65535]) {
        final r = packHi(q) / 255, g = packLo(q) / 255;
        final shader = (r * 65280 + g * 255) / 65535;
        expect(unpackNormalized(packHi(q), packLo(q)), closeTo(shader, 1e-12));
        expect(shader, closeTo(q / 65535, 1e-12));
      }
    });

    test('packPlane16 writes R=hi, G=lo, B=extra, A=255', () {
      final values = Float64List.fromList([0, 0.25, 1]);
      final extra = Uint8List.fromList([7, 8, 9]);
      final rgba = packPlane16(values, blue: extra);
      expect(rgba.length, 12);
      for (var i = 0; i < 3; i++) {
        final q = quantize16(values[i]);
        expect(rgba[i * 4], packHi(q));
        expect(rgba[i * 4 + 1], packLo(q));
        expect(rgba[i * 4 + 2], extra[i]);
        expect(rgba[i * 4 + 3], 255);
      }
    });
  });
}
