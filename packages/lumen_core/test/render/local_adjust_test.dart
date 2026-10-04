import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

/// Mid-gray with a mild horizontal ramp and a little texture.
RgbaBuffer _scene(int w, int h) {
  final b = RgbaBuffer(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = 90 + (x * 60 ~/ w) + ((x + y).isEven ? 6 : 0);
      b.setPixel(x, y, v, (v * 0.95).round(), (v * 0.85).round());
    }
  }
  return b;
}

double _luma(RgbaBuffer b, int x, int y) =>
    0.2126 * b.r(x, y) + 0.7152 * b.g(x, y) + 0.0722 * b.b(x, y);

LocalMask _radial(Map<String, double> adj, {bool invert = false}) => LocalMask(
  id: 'r',
  name: 'Radial',
  kind: MaskKind.radial,
  invert: invert,
  shape: const RadialShape(rx: 0.2, ry: 0.2, feather: 0.2).toJson(),
  adjustments: adj,
);

DevelopSettings _with(List<LocalMask> masks, [DevelopSettings? base]) =>
    (base ?? DevelopSettings.defaults).copyWith(masks: masks);

void main() {
  final scene = _scene(80, 60);
  final plain = renderReference(scene, DevelopSettings.defaults);

  test('radial exposure +1 brightens inside, not outside', () {
    final out = renderReference(
      scene,
      _with([
        _radial({P.exposure: 1}),
      ]),
    );
    expect(_luma(out, 40, 30), greaterThan(_luma(plain, 40, 30) + 25));
    expect(_luma(out, 2, 2), _luma(plain, 2, 2));
  });

  test('invert flips the affected region', () {
    final out = renderReference(
      scene,
      _with([
        _radial({P.exposure: 1}, invert: true),
      ]),
    );
    expect(_luma(out, 40, 30), _luma(plain, 40, 30));
    expect(_luma(out, 2, 2), greaterThan(_luma(plain, 2, 2) + 25));
  });

  test('linear gradient exposure is monotone along the gradient', () {
    final flat = RgbaBuffer.filled(64, 64, 110, 110, 110);
    final out = renderReference(
      flat,
      _with([
        const LocalMask(
          id: 'l',
          name: 'Linear',
          kind: MaskKind.linear,
          shape: {'x0': 0.5, 'y0': 0.0, 'x1': 0.5, 'y1': 1.0},
          adjustments: {P.exposure: 1.5},
        ),
      ]),
    );
    for (var y = 1; y < 64; y++) {
      expect(out.r(32, y), lessThanOrEqualTo(out.r(32, y - 1)));
    }
    expect(out.r(32, 0), greaterThan(out.r(32, 63) + 40));
  });

  test('masks without adjustments leave the image byte-identical', () {
    final out = renderReference(scene, _with([_radial({})]));
    expect(out.data, plain.data);
  });

  test('every local param changes the inside and not the outside', () {
    // Highlights only act on bright pixels: use a brighter scene for it.
    final bright = RgbaBuffer.filled(80, 60, 215, 205, 190);
    for (final id in kLocalParams) {
      final src = id == P.highlights ? bright : scene;
      final ref = renderReference(src, DevelopSettings.defaults);
      final v = switch (id) {
        P.exposure => 1.0,
        P.highlights => -100.0,
        _ => 70.0,
      };
      final out = renderReference(
        src,
        _with([
          _radial({id: v}),
        ]),
      );
      final inside = <int>[], outside = <int>[];
      for (var c = 0; c < 3; c++) {
        final i = src.offset(40, 30) + c, o = src.offset(2, 2) + c;
        inside.add((out.data[i] - ref.data[i]).abs());
        outside.add((out.data[o] - ref.data[o]).abs());
      }
      expect(
        inside.reduce((a, b) => a > b ? a : b),
        greaterThan(0),
        reason: '$id inside',
      );
      expect(outside, [0, 0, 0], reason: '$id outside');
    }
  });

  test('local adjustments add to the global value', () {
    final globalOnly = renderReference(
      scene,
      DevelopSettings.defaults.withValue(P.exposure, 1),
    );
    final split = renderReference(
      scene,
      _with([
        _radial({P.exposure: 0.5}),
      ], DevelopSettings.defaults.withValue(P.exposure, 0.5)),
    );
    // Center of the radial mask has full coverage: 0.5 + 0.5 EV = 1 EV.
    expect(
      (split.r(40, 30) - globalOnly.r(40, 30)).abs(),
      lessThanOrEqualTo(1),
    );
  });

  test('local contrast steepens around mid-gray, whites/blacks stretch', () {
    final ramp = RgbaBuffer(256, 2);
    for (var x = 0; x < 256; x++) {
      ramp.setPixel(x, 0, x, x, x);
      ramp.setPixel(x, 1, x, x, x);
    }
    LocalMask full(Map<String, double> adj) => LocalMask(
      id: 'f',
      name: 'Full',
      kind: MaskKind.radial,
      shape: const RadialShape(rx: 10, ry: 10).toJson(),
      adjustments: adj,
    );
    final c = renderReference(
      ramp,
      _with([
        full({P.contrast: 80}),
      ]),
    );
    expect(c.r(50, 0), lessThan(50));
    expect(c.r(200, 0), greaterThan(200));
    final w = renderReference(
      ramp,
      _with([
        full({P.whites: 100}),
      ]),
    );
    expect(w.r(200, 0), greaterThan(225));
    final b = renderReference(
      ramp,
      _with([
        full({P.blacks: -100}),
      ]),
    );
    expect(b.r(40, 0), lessThan(5));
  });

  test('precomputed MaskAtlases give the same result; AI rasters are used', () {
    const subject = LocalMask(
      id: 's',
      name: 'Subject',
      kind: MaskKind.subject,
      shape: {'maskRef': 'masks/s.png'},
      adjustments: {P.exposure: 1},
    );
    final raster = MaskRaster(2, 1, Uint8List.fromList([0, 255]));
    final s = _with([subject]);
    final viaMap = renderReference(
      scene,
      s,
      maskRasters: {'masks/s.png': raster},
    );
    final atlases = MaskRasterizer.build(
      s.masks,
      scene.width,
      scene.height,
      rasters: {'masks/s.png': raster},
    );
    expect(renderReference(scene, s, masks: atlases).data, viaMap.data);
    expect(_luma(viaMap, 75, 30), greaterThan(_luma(plain, 75, 30) + 20));
    expect(_luma(viaMap, 3, 30), _luma(plain, 3, 30));
    // Without the raster the AI mask covers nothing.
    expect(renderReference(scene, s).data, plain.data);
  });

  test('mask overlay reference tints covered pixels in output space', () {
    final s = _with([
      _radial({P.exposure: 1}),
    ]);
    final atlases = MaskRasterizer.build(s.masks, 80, 60);
    final o = renderMaskOverlayReference(80, 60, s, atlases, 0);
    expect([o.r(40, 30), o.g(40, 30), o.b(40, 30)], [128, 0, 0]);
    expect(o.data[o.offset(40, 30) + 3], 128);
    expect(o.data.sublist(0, 4), [0, 0, 0, 0]);
    final rotated = renderMaskOverlayReference(
      80,
      60,
      s.copyWith(geometry: Geometry.none.copyWith(rotate90: 1)),
      atlases,
      0,
    );
    expect([rotated.width, rotated.height], [60, 80]);
    expect(rotated.data[rotated.offset(30, 40) + 3], 128);
  });
}
