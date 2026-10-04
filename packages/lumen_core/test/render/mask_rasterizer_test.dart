import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

LocalMask _mask(
  MaskKind kind, {
  Map<String, Object?> shape = const {},
  List<BrushStroke> strokes = const [],
  bool invert = false,
  double opacity = 1,
}) => LocalMask(
  id: kind.name,
  name: kind.name,
  kind: kind,
  shape: shape,
  strokes: strokes,
  invert: invert,
  opacity: opacity,
  adjustments: const {P.exposure: 1},
);

int _at(Uint8List c, int w, int x, int y) => c[y * w + x];

void main() {
  group('gridSize', () {
    test('caps the long edge at 1024 and never upscales', () {
      expect(MaskRasterizer.gridSize(4000, 3000), (width: 1024, height: 768));
      expect(MaskRasterizer.gridSize(300, 200), (width: 300, height: 200));
    });
  });

  group('shapes', () {
    test('linear: full at p0, ~0.5 at the midpoint, none at p1, monotone', () {
      final m = _mask(
        MaskKind.linear,
        shape: const LinearShape(x0: 0.5, y0: 0, x1: 0.5, y1: 1).toJson(),
      );
      final c = MaskRasterizer.rasterize(m, 64, 101);
      expect(_at(c, 64, 10, 0), greaterThanOrEqualTo(252));
      expect(_at(c, 64, 10, 50), closeTo(128, 2));
      expect(_at(c, 64, 10, 100), lessThanOrEqualTo(3));
      for (var y = 1; y < 101; y++) {
        expect(_at(c, 64, 10, y), lessThanOrEqualTo(_at(c, 64, 10, y - 1)));
      }
    });

    test('radial: solid center, feathered rim, zero outside', () {
      final m = _mask(
        MaskKind.radial,
        shape: const RadialShape(rx: 0.25, ry: 0.25, feather: 0.5).toJson(),
      );
      final c = MaskRasterizer.rasterize(m, 100, 100);
      expect(_at(c, 100, 50, 50), 255);
      expect(_at(c, 100, 2, 2), 0);
      // e = 0.75 is the middle of the feather band [0.5, 1].
      expect(_at(c, 100, 50 + 18, 50), closeTo(128, 20));
      final hard = MaskRasterizer.rasterize(
        _mask(
          MaskKind.radial,
          shape: const RadialShape(rx: 0.25, ry: 0.25, feather: 0).toJson(),
        ),
        100,
        100,
      );
      expect(_at(hard, 100, 50 + 23, 50), 255);
      expect(_at(hard, 100, 50 + 27, 50), 0);
    });

    test('radial inverted flag and mask invert both flip coverage', () {
      const shape = RadialShape(rx: 0.2, ry: 0.2);
      final inv = MaskRasterizer.rasterize(
        _mask(
          MaskKind.radial,
          shape: const RadialShape(rx: 0.2, ry: 0.2, inverted: true).toJson(),
        ),
        50,
        50,
      );
      final masked = MaskRasterizer.rasterize(
        _mask(MaskKind.radial, shape: shape.toJson(), invert: true),
        50,
        50,
      );
      expect(_at(inv, 50, 25, 25), 0);
      expect(_at(inv, 50, 1, 1), 255);
      expect(masked, inv);
    });

    test('opacity scales coverage', () {
      final c = MaskRasterizer.rasterize(
        _mask(MaskKind.radial, opacity: 0.5),
        40,
        40,
      );
      expect(_at(c, 40, 20, 20), closeTo(128, 1));
    });
  });

  group('brush', () {
    test('hardness 1 gives a hard disc; hardness 0 a soft falloff', () {
      const stroke = BrushStroke(
        points: [(0.5, 0.5)],
        radius: 0.1,
        hardness: 1,
      );
      final hard = MaskRasterizer.rasterize(
        _mask(MaskKind.brush, strokes: const [stroke]),
        100,
        100,
      );
      expect(_at(hard, 100, 50, 50), 255);
      expect(_at(hard, 100, 58, 50), 255);
      expect(_at(hard, 100, 62, 50), 0);
      final soft = MaskRasterizer.rasterize(
        _mask(
          MaskKind.brush,
          strokes: const [
            BrushStroke(points: [(0.5, 0.5)], radius: 0.1, hardness: 0),
          ],
        ),
        100,
        100,
      );
      expect(_at(soft, 100, 55, 50), inExclusiveRange(10, 245));
    });

    test('a stroke covers the whole segment between its points', () {
      final c = MaskRasterizer.rasterize(
        _mask(
          MaskKind.brush,
          strokes: const [
            BrushStroke(
              points: [(0.1, 0.5), (0.9, 0.5)],
              radius: 0.05,
              hardness: 1,
            ),
          ],
        ),
        100,
        100,
      );
      for (var x = 12; x < 88; x += 7) {
        expect(_at(c, 100, x, 50), 255, reason: 'x $x');
      }
      expect(_at(c, 100, 50, 60), 0);
    });

    test('flow limits strength; erase removes coverage', () {
      final c = MaskRasterizer.rasterize(
        _mask(
          MaskKind.brush,
          strokes: const [
            BrushStroke(
              points: [(0.5, 0.5)],
              radius: 0.2,
              hardness: 1,
              flow: 0.5,
            ),
          ],
        ),
        50,
        50,
      );
      expect(_at(c, 50, 25, 25), closeTo(128, 1));
      final erased = MaskRasterizer.rasterize(
        _mask(
          MaskKind.radial,
          shape: const RadialShape(rx: 0.4, ry: 0.4, feather: 0).toJson(),
          strokes: const [
            BrushStroke(
              points: [(0.5, 0.5)],
              radius: 0.1,
              hardness: 1,
              erase: true,
            ),
          ],
        ),
        100,
        100,
      );
      expect(_at(erased, 100, 50, 50), 0);
      expect(_at(erased, 100, 70, 50), 255);
    });

    test('a brush mask without strokes covers nothing', () {
      final c = MaskRasterizer.rasterize(_mask(MaskKind.brush), 20, 20);
      expect(c.every((v) => v == 0), isTrue);
    });
  });

  group('AI rasters', () {
    test('are resampled to the grid; missing rasters cover nothing', () {
      final raster = MaskRaster(2, 1, Uint8List.fromList([0, 255]));
      final m = _mask(
        MaskKind.subject,
        shape: const AiShape(maskRef: 'masks/s.png').toJson(),
      );
      final c = MaskRasterizer.rasterize(m, 8, 4, raster: raster);
      expect(_at(c, 8, 0, 1), 0);
      expect(_at(c, 8, 7, 1), 255);
      expect(_at(c, 8, 3, 1), inExclusiveRange(0, 255));
      final none = MaskRasterizer.rasterize(m, 8, 4);
      expect(none.every((v) => v == 0), isTrue);
    });
  });

  group('MaskAtlases', () {
    final masks = [
      for (var i = 0; i < 9; i++)
        _mask(
          MaskKind.radial,
          shape: RadialShape(
            cx: 0.1 + i * 0.1,
            rx: 0.05,
            ry: 0.05,
            feather: 0,
          ).toJson(),
        ),
    ];

    test('packs 4 masks per atlas (RGB left tile, R right tile), max 8', () {
      final a = MaskRasterizer.build(masks, 200, 100);
      expect(a.count, 8);
      expect([a.width, a.height], [200, 100]);
      for (var k = 0; k < 2; k++) {
        final rgba = a.atlasRgba(k);
        expect(rgba.length, 2 * a.width * a.height * 4);
        for (var i = 3; i < rgba.length; i += 4) {
          expect(rgba[i], 255);
        }
      }
      for (var m = 0; m < 8; m++) {
        final rgba = a.atlasRgba(m ~/ 4);
        final slot = m % 4;
        final x = slot < 3 ? 50 : a.width + 50;
        final ch = slot < 3 ? slot : 0;
        expect(
          rgba[(50 * 2 * a.width + x) * 4 + ch],
          a.coverage[m][50 * a.width + 50],
        );
      }
    });

    test('bilinear sampling hits texel values at texel centers', () {
      final a = MaskRasterizer.build(masks.take(3).toList(), 200, 100);
      final want = a.coverage[1][40 * 200 + 20] / 255;
      expect(a.sample(1, 20.5 / 200, 40.5 / 100), closeTo(want, 1e-12));
      final all = Float64List(8);
      a.sampleAll(20.5 / 200, 40.5 / 100, all);
      expect(all[1], closeTo(want, 1e-12));
      expect(all[5], 0);
    });

    test('is deterministic', () {
      final s = [
        _mask(
          MaskKind.brush,
          strokes: const [
            BrushStroke(points: [(0.2, 0.3), (0.6, 0.7)], radius: 0.03),
          ],
        ),
      ];
      expect(
        MaskRasterizer.build(s, 300, 200).coverage.first,
        MaskRasterizer.build(s, 300, 200).coverage.first,
      );
    });

    test('empty atlases are 1x1 with no masks', () {
      final e = MaskAtlases.empty();
      expect(e.count, 0);
      expect(e.sample(0, 0.5, 0.5), 0);
    });
  });
}
