import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen_core/lumen_core.dart';

const _source = Size(3000, 2000);

/// Crop + straighten + every quarter turn + every flip combination.
List<Geometry> _geometries() => [
  for (final q in [0, 1, 2, 3])
    for (final (h, v) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ])
      Geometry(
        crop: const CropRect(0.12, 0.08, 0.83, 0.9),
        angle: q.isEven ? 7.5 : -12.25,
        rotate90: q,
        flipH: h,
        flipV: v,
      ),
];

CanvasMapping _map(Geometry g) {
  final size = outputSizeFor(_source.width.toInt(), _source.height.toInt(), g);
  // Displayed at an arbitrary zoom with the frame's aspect.
  return CanvasMapping(
    geometry: g,
    source: _source,
    view: Size(size.width * 0.37, size.height * 0.37),
  );
}

void main() {
  test('view → source → view round-trips within 1e-6', () {
    for (final g in _geometries()) {
      final map = _map(g);
      for (final (u, v) in [
        (0.0, 0.0),
        (0.25, 0.8),
        (0.5, 0.5),
        (0.93, 0.07),
        (1.0, 1.0),
      ]) {
        final p = Offset(u * map.view.width, v * map.view.height);
        final (su, sv) = map.toSource(p);
        final back = map.toView(su, sv);
        expect(back.dx / map.view.width, closeTo(u, 1e-6), reason: '$g');
        expect(back.dy / map.view.height, closeTo(v, 1e-6), reason: '$g');
      }
    }
  });

  test('source → view → source round-trips within 1e-6', () {
    for (final g in _geometries()) {
      final map = _map(g);
      for (final (su, sv) in [
        (0.31, 0.42),
        (0.5, 0.5),
        (0.6, 0.2),
        (0.4, 0.7),
      ]) {
        final p = map.toView(su, sv);
        final (u, v) = map.toSource(p);
        expect(u, closeTo(su, 1e-6), reason: '$g');
        expect(v, closeTo(sv, 1e-6), reason: '$g');
      }
    }
  });

  test('view → source matches the develop shader mapping exactly', () {
    for (final g in _geometries()) {
      final map = _map(g);
      final out = outputSizeFor(
        _source.width.toInt(),
        _source.height.toInt(),
        g,
      );
      final f = DevelopUniforms.pack(
        DevelopSettings.defaults.copyWith(geometry: g),
        DevelopContext(
          outWidth: out.width,
          outHeight: out.height,
          sourceWidth: _source.width.toInt(),
          sourceHeight: _source.height.toInt(),
          auxWidth: 1,
          auxHeight: 1,
        ),
      );
      for (final (u, v) in [(0.1, 0.9), (0.5, 0.5), (0.77, 0.33)]) {
        final mine = map.toSource(
          Offset(u * map.view.width, v * map.view.height),
        );
        final shader = sourceUvFor(u, v, f);
        expect(mine.$1, closeTo(shader.$1, 1e-12));
        expect(mine.$2, closeTo(shader.$2, 1e-12));
      }
    }
  });

  test('identity maps corners to corners', () {
    final map = CanvasMapping(
      geometry: Geometry.none,
      source: _source,
      view: const Size(300, 200),
    );
    expect(map.toView(0, 0), Offset.zero);
    expect(map.toView(1, 1), const Offset(300, 200));
    expect(map.scale, closeTo(0.1, 1e-12));
  });

  test(
    'a clockwise quarter turn puts the source bottom-left at the top-left',
    () {
      final map = CanvasMapping(
        geometry: const Geometry(rotate90: 1),
        source: _source,
        view: const Size(200, 300),
      );
      final (u, v) = map.toSource(Offset.zero);
      expect(u, closeTo(0, 1e-9));
      expect(v, closeTo(1, 1e-9));
    },
  );

  test('source pixels map to view pixels by a uniform scale', () {
    for (final g in _geometries()) {
      final map = _map(g);
      final c = map.toView(0.5, 0.5);
      final dx = map.toView(0.5 + 1 / _source.width, 0.5) - c;
      final dy = map.toView(0.5, 0.5 + 1 / _source.height) - c;
      expect(dx.distance, closeTo(map.scale, 1e-6));
      expect(dy.distance, closeTo(map.scale, 1e-6));
      // Perpendicular: angles survive.
      expect(dx.dx * dy.dx + dx.dy * dy.dy, closeTo(0, 1e-9));
    }
  });

  test('output mapping is in source pixels (scale 1)', () {
    final map = CanvasMapping.output(
      const Geometry(crop: CropRect(0, 0, 0.5, 0.5), rotate90: 1),
      _source,
    );
    expect(map.view, const Size(1000, 1500));
    expect(map.scale, closeTo(1, 1e-9));
  });
}
