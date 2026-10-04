import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

double _sum(List<double> p) => p.fold(0.0, (s, v) => s + v);

void main() {
  const rect = MapRect(0, 0, 64, 48);

  group('rasterizePolygon', () {
    test('a pixel-aligned square covers exactly its pixels', () {
      final p = rasterizePolygon(const [
        (x: 10.0, y: 8.0),
        (x: 30.0, y: 8.0),
        (x: 30.0, y: 20.0),
        (x: 10.0, y: 20.0),
      ], rect);
      expect(_sum(p), closeTo(20 * 12, 1e-9));
      expect(p[rect.index(10, 8)], 1);
      expect(p[rect.index(29, 19)], 1);
      expect(p[rect.index(9, 8)], 0);
      expect(p[rect.index(30, 19)], 0);
    });

    test('anti-aliased area of a triangle is within 0.5 %', () {
      final p = rasterizePolygon(const [
        (x: 3.3, y: 2.7),
        (x: 57.1, y: 9.4),
        (x: 21.8, y: 44.9),
      ], rect);
      const area =
          0.5 * ((57.1 - 3.3) * (44.9 - 2.7) - (21.8 - 3.3) * (9.4 - 2.7));
      expect(_sum(p), closeTo(area.abs(), area.abs() * 0.005));
      expect(p.any((v) => v > 0 && v < 1), isTrue, reason: 'soft edges');
    });

    test('is deterministic and independent of the vertex start', () {
      const tri = [(x: 5.5, y: 5.2), (x: 40.25, y: 12.0), (x: 18.0, y: 41.75)];
      final a = rasterizePolygon(tri, rect);
      final b = rasterizePolygon(tri, rect);
      final c = rasterizePolygon([tri[1], tri[2], tri[0]], rect);
      expect(b, a);
      expect(c, a);
    });

    test('clips to an offset sub-rect', () {
      const sub = MapRect(20, 10, 8, 6);
      final p = rasterizePolygon(const [
        (x: 0.0, y: 0.0),
        (x: 64.0, y: 0.0),
        (x: 64.0, y: 48.0),
        (x: 0.0, y: 48.0),
      ], sub);
      expect(p, everyElement(1.0));
    });

    test('degenerate input gives an empty plane', () {
      expect(
        rasterizePolygon(const [(x: 1.0, y: 1.0), (x: 9.0, y: 9.0)], rect),
        everyElement(0.0),
      );
    });
  });

  group('discs, ellipses and polylines', () {
    test('disc area ≈ πr²', () {
      final p = rasterizeDisc(32, 24, 10, rect);
      expect(_sum(p), closeTo(math.pi * 100, math.pi * 100 * 0.01));
      expect(p[rect.index(32, 24)], 1);
    });

    test('rotated ellipse area ≈ π·a·b', () {
      final p = rasterizeEllipse(32, 24, 14, 6, 0.6, rect);
      expect(_sum(p), closeTo(math.pi * 84, math.pi * 84 * 0.02));
    });

    test('polyline distance is exact at pixel centres and capped', () {
      final d = polylineDistance(
        const [(x: 10.0, y: 20.5), (x: 50.0, y: 20.5)],
        rect,
        8,
      );
      expect(d[rect.index(30, 20)], closeTo(0, 1e-9));
      expect(d[rect.index(30, 24)], closeTo(4, 1e-9));
      expect(d[rect.index(5, 20)], closeTo(4.5, 1e-9));
      expect(d[rect.index(30, 45)], 8);
    });
  });
}
