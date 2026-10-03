import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

(double, double) _map(
  Geometry g,
  double u,
  double v, {
  int w = 400,
  int h = 200,
}) {
  final size = outputSizeFor(w, h, g);
  final f = DevelopUniforms.pack(
    DevelopSettings.defaults.copyWith(geometry: g),
    DevelopContext(
      outWidth: size.width,
      outHeight: size.height,
      sourceWidth: w,
      sourceHeight: h,
      auxWidth: 1,
      auxHeight: 1,
    ),
  );
  return sourceUvFor(u, v, f);
}

void main() {
  group('outputSizeFor', () {
    test('identity keeps the source size', () {
      expect(outputSizeFor(400, 200, Geometry.none), (width: 400, height: 200));
    });

    test('odd quarter turns swap axes', () {
      final g = Geometry.none.copyWith(rotate90: 1);
      expect(outputSizeFor(400, 200, g), (width: 200, height: 400));
    });

    test('crop scales the oriented size', () {
      final g = Geometry.none.copyWith(
        crop: const CropRect(0.25, 0, 0.75, 0.5),
      );
      expect(outputSizeFor(400, 200, g), (width: 200, height: 100));
    });

    test('never returns an empty image', () {
      final g = Geometry.none.copyWith(
        crop: const CropRect(0, 0, 0.0001, 0.0001),
      );
      final s = outputSizeFor(10, 10, g);
      expect(s.width, greaterThanOrEqualTo(1));
      expect(s.height, greaterThanOrEqualTo(1));
    });
  });

  group('sourceUvFor', () {
    void expectUv((double, double) got, (double, double) want) {
      expect(got.$1, closeTo(want.$1, 1e-6));
      expect(got.$2, closeTo(want.$2, 1e-6));
    }

    test('identity maps uv to itself', () {
      expectUv(_map(Geometry.none, 0.2, 0.7), (0.2, 0.7));
    });

    test(
      'rotate90 = 1 (clockwise): output top-left shows source bottom-left',
      () {
        expectUv(_map(Geometry.none.copyWith(rotate90: 1), 0, 0), (0, 1));
        expectUv(_map(Geometry.none.copyWith(rotate90: 1), 1, 0), (0, 0));
      },
    );

    test('rotate90 = 2 and 3', () {
      expectUv(_map(Geometry.none.copyWith(rotate90: 2), 0, 0), (1, 1));
      expectUv(_map(Geometry.none.copyWith(rotate90: 3), 0, 0), (1, 0));
    });

    test('flips mirror the axes', () {
      expectUv(_map(Geometry.none.copyWith(flipH: true), 0.1, 0.2), (0.9, 0.2));
      expectUv(_map(Geometry.none.copyWith(flipV: true), 0.1, 0.2), (0.1, 0.8));
    });

    test('crop selects a sub-rectangle', () {
      final g = Geometry.none.copyWith(crop: const CropRect(0.5, 0.5, 1, 1));
      expectUv(_map(g, 0, 0), (0.5, 0.5));
      expectUv(_map(g, 1, 1), (1, 1));
    });

    test('straighten rotates around the center in pixel space', () {
      final g = Geometry.none.copyWith(angle: 90 / 2);
      expectUv(_map(g, 0.5, 0.5), (0.5, 0.5));
      // A point right of center maps above/below center, aspect-corrected.
      final (u, v) = _map(
        Geometry.none.copyWith(angle: 45),
        0.75,
        0.5,
        w: 200,
        h: 200,
      );
      expect(u, lessThan(0.75));
      expect(v, isNot(closeTo(0.5, 1e-3)));
    });
  });
}
