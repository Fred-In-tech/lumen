import 'dart:math' as math;
import 'dart:typed_data';

import '../model/geometry.dart';
import 'uniform_layout.dart';

/// Output pixel size of a [srcWidth]×[srcHeight] source under [g]:
/// oriented size (axes swapped for odd quarter turns) × crop size.
({int width, int height}) outputSizeFor(
  int srcWidth,
  int srcHeight,
  Geometry g,
) {
  final ow = g.swapsAxes ? srcHeight : srcWidth;
  final oh = g.swapsAxes ? srcWidth : srcHeight;
  return (
    width: math.max(1, (ow * g.crop.width).round()),
    height: math.max(1, (oh * g.crop.height).round()),
  );
}

/// Maps an output-normalized uv to a source uv using the packed develop
/// uniforms [f], exactly like `sourceUv()` in `develop.frag`:
/// uncrop → unstraighten (rotate about the center in pixel space) →
/// unflip → unrotate the quarter turns. The result may fall outside 0..1.
(double, double) sourceUvFor(double u, double v, Float32List f) {
  const c = DevelopIndex.crop, g = DevelopIndex.geom, s = DevelopIndex.src;
  var x = f[c] + (f[c + 2] - f[c]) * u;
  var y = f[c + 1] + (f[c + 3] - f[c + 1]) * v;
  final k = f[g + 1].round() % 4;
  final dw = k.isOdd ? f[s + 1] : f[s];
  final dh = k.isOdd ? f[s] : f[s + 1];
  final angle = f[g];
  if (angle != 0) {
    final px = (x - 0.5) * dw, py = (y - 0.5) * dh;
    final ca = math.cos(angle), sa = math.sin(angle);
    x = (px * ca + py * sa) / dw + 0.5;
    y = (-px * sa + py * ca) / dh + 0.5;
  }
  if (f[g + 2] > 0.5) x = 1 - x;
  if (f[g + 3] > 0.5) y = 1 - y;
  return switch (k) {
    1 => (y, 1 - x),
    2 => (1 - x, 1 - y),
    3 => (1 - y, x),
    _ => (x, y),
  };
}
