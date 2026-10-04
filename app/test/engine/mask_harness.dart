import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// Seeded random masks and AI rasters for the mask engine tests.

double _u(math.Random r, double lo, double hi) =>
    lo + (hi - lo) * r.nextDouble();

/// A smooth synthetic AI raster (blob) keyed by [ref].
MaskRaster syntheticRaster(int seed, {int w = 96, int h = 64}) {
  final r = math.Random(seed);
  final cx = _u(r, 0.3, 0.7) * w, cy = _u(r, 0.3, 0.7) * h;
  final rad = _u(r, 0.2, 0.4) * math.max(w, h);
  final data = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final d = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2)) / rad;
      data[y * w + x] = ((1 - d).clamp(0.0, 1.0) * 255).round();
    }
  }
  return MaskRaster(w, h, data);
}

/// Random sparse local adjustments (1–4 params).
Map<ParamId, double> randomLocalAdjustments(math.Random r) {
  final n = 1 + r.nextInt(4);
  final ids = [...kLocalParams]..shuffle(r);
  return {
    for (final id in ids.take(n))
      id: id == P.exposure ? _u(r, -2, 2) : _u(r, -100, 100),
  };
}

List<BrushStroke> randomStrokes(math.Random r, {int count = 2}) => [
  for (var i = 0; i < count; i++)
    BrushStroke(
      points: [for (var k = 0; k < 3; k++) (_u(r, 0.1, 0.9), _u(r, 0.1, 0.9))],
      radius: _u(r, 0.03, 0.12),
      hardness: _u(r, 0, 1),
      flow: _u(r, 0.4, 1),
      erase: i > 0 && r.nextBool(),
    ),
];

/// A random mask of [kind]; AI kinds reference `masks/<id>.png`.
LocalMask randomMask(math.Random r, MaskKind kind, String id) {
  final shape = switch (kind) {
    MaskKind.linear => LinearShape(
      x0: _u(r, 0, 1),
      y0: _u(r, 0, 1),
      x1: _u(r, 0, 1),
      y1: _u(r, 0, 1),
    ).toJson(),
    MaskKind.radial => RadialShape(
      cx: _u(r, 0.2, 0.8),
      cy: _u(r, 0.2, 0.8),
      rx: _u(r, 0.1, 0.4),
      ry: _u(r, 0.1, 0.4),
      angle: _u(r, -90, 90),
      feather: _u(r, 0, 1),
      inverted: r.nextBool(),
    ).toJson(),
    MaskKind.brush => const <String, Object?>{},
    _ => AiShape(maskRef: 'masks/$id.png', model: 'synthetic').toJson(),
  };
  return LocalMask(
    id: id,
    name: id,
    kind: kind,
    invert: r.nextInt(4) == 0,
    opacity: _u(r, 0.5, 1),
    shape: shape,
    strokes: kind == MaskKind.brush || r.nextInt(3) == 0
        ? randomStrokes(r)
        : const [],
    adjustments: randomLocalAdjustments(r),
  );
}

/// AI rasters for every AI mask in [masks].
Map<String, MaskRaster> rastersFor(List<LocalMask> masks) => {
  for (final (i, m) in masks.indexed)
    if (m.kind.isAi) m.ai.maskRef: syntheticRaster(i + 1),
};
