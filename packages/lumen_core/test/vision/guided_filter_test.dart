import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

const _w = 100, _h = 20;

/// Sharp vertical edge at x = [edge]: 0.2 left, 0.8 right.
Float32List stepGuide({int edge = 50}) => Float32List.fromList([
  for (var y = 0; y < _h; y++)
    for (var x = 0; x < _w; x++) x < edge ? 0.2 : 0.8,
]);

/// A coarse mask: linear ramp from 0 to 1 over x in [edge − half, edge + half).
Float32List ramp({int edge = 50, int half = 6}) => Float32List.fromList([
  for (var y = 0; y < _h; y++)
    for (var x = 0; x < _w; x++)
      ((x - (edge - half) + 0.5) / (2 * half)).clamp(0.0, 1.0),
]);

void main() {
  group('boxMean', () {
    test('constant stays constant, radius 0 copies', () {
      final c = Float32List(_w * _h)..fillRange(0, _w * _h, 0.37);
      expect(
        boxMean(c, _w, _h, 5).every((v) => (v - 0.37).abs() < 1e-6),
        isTrue,
      );
      final r = ramp();
      expect(boxMean(r, _w, _h, 0), r);
    });

    test('averages the clipped window (border divisor = pixels inside)', () {
      final p = Float32List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]);
      final m = boxMean(p, 3, 3, 1);
      expect(m[4], closeTo(5, 1e-6)); // full 3×3
      expect(m[0], closeTo((1 + 2 + 4 + 5) / 4, 1e-6)); // corner 2×2
      expect(m[1], closeTo((1 + 2 + 3 + 4 + 5 + 6) / 6, 1e-6)); // edge 3×2
    });

    test('rejects a plane of the wrong size', () {
      expect(() => boxMean(Float32List(3), 2, 2, 1), throwsArgumentError);
    });
  });

  group('guidedFilterPlanes', () {
    test('snaps a coarse mask edge to the guide edge', () {
      final coarse = ramp();
      final q = guidedFilterPlanes(
        stepGuide(),
        [coarse],
        _w,
        _h,
        radius: 8, // must span the ±6 px coarse transition
        eps: 1e-4,
      ).single;
      // The coarse ramp rises 1/12 per pixel; the filtered mask jumps at
      // the photo edge and crosses 50 % exactly there.
      final row = 10 * _w;
      expect(coarse[row + 50] - coarse[row + 49], closeTo(1 / 12, 1e-6));
      expect(q[row + 50] - q[row + 49], greaterThan(0.5));
      expect(q[row + 49], lessThan(0.5));
      expect(q[row + 50], greaterThan(0.5));
      // Far from the edge the mask is untouched.
      expect(q[10 * _w + 5], closeTo(0, 1e-3));
      expect(q[10 * _w + 95], closeTo(1, 1e-3));
    });

    test('is linear: filter(1 − p) = 1 − filter(p)', () {
      final p = ramp(half: 9);
      final inv = Float32List.fromList([for (final v in p) 1 - v]);
      final out = guidedFilterPlanes(
        stepGuide(edge: 40),
        [p, inv],
        _w,
        _h,
        radius: 3,
        eps: 1e-3,
      );
      for (var i = 0; i < p.length; i++) {
        expect(out[0][i] + out[1][i], closeTo(1, 1e-4));
      }
    });

    test('a flat guide smooths noise like a box filter', () {
      final rnd = math.Random(3);
      final noisy = Float32List.fromList([
        for (var i = 0; i < _w * _h; i++) 0.5 + (rnd.nextDouble() - 0.5) * 0.4,
      ]);
      final flat = Float32List(_w * _h)..fillRange(0, _w * _h, 0.5);
      final q = guidedFilterPlanes(
        flat,
        [noisy],
        _w,
        _h,
        radius: 3,
        eps: 1e-3,
      ).single;
      double spread(Float32List p) =>
          p.map((v) => (v - 0.5).abs()).reduce(math.max);
      expect(spread(q), lessThan(spread(noisy) * 0.5));
    });

    test('the guide must match the grid', () {
      expect(
        () => guidedFilterPlanes(
          Float32List(5),
          [Float32List(5)],
          2,
          2,
          radius: 1,
          eps: 1e-3,
        ),
        throwsArgumentError,
      );
    });
  });

  group('lumaPlane', () {
    test('Rec. 709 luma, area-averaged', () {
      final src = RgbaBuffer.filled(8, 4, 255, 0, 0);
      final l = lumaPlane(src, width: 4, height: 2);
      expect(l.every((v) => (v - 0.2126).abs() < 1e-5), isTrue);
      final board = RgbaBuffer(8, 8);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          final v = (x + y).isEven ? 255 : 0;
          board.setPixel(x, y, v, v, v);
        }
      }
      final half = lumaPlane(board, width: 4, height: 4);
      expect(half.every((v) => (v - 0.5).abs() < 1e-5), isTrue);
    });
  });
}
