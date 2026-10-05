import 'dart:math' as math;
import 'dart:typed_data';

import '../model/develop_settings.dart';
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

/// Output-normalized uv → source uv for [s] on a [srcWidth]×[srcHeight]
/// source (crop, straighten, rotation, flips; no warp). Liquify strokes are
/// stored in this space: map pointer positions through it.
(double, double) sourceUvOf(
  DevelopSettings s,
  int srcWidth,
  int srcHeight,
  double u,
  double v,
) {
  final size = outputSizeFor(srcWidth, srcHeight, s.geometry);
  final f = DevelopUniforms.pack(
    s,
    DevelopContext(
      outWidth: size.width,
      outHeight: size.height,
      sourceWidth: srcWidth,
      sourceHeight: srcHeight,
      auxWidth: 1,
      auxHeight: 1,
    ),
  );
  return sourceUvFor(u, v, f);
}

/// The source pixels an output rectangle needs: the bounding box, in pixels
/// of the `uSrc`-sized source of the packed develop uniforms [f], of the
/// output rectangle [x0]..[x1] × [y0]..[y1] (pixels of the full output,
/// `uTile.zw`), grown by [margin] pixels (filter taps) and by the warp
/// range when a warp is on, clipped to the source.
///
/// The float export decodes one such window per output tile instead of
/// the whole photo. The geometry mapping is affine, so the four corners
/// bound it. A rectangle that maps entirely outside the source gives the
/// nearest edge pixels (the tile renders transparent anyway).
({int x, int y, int width, int height}) sourceWindowFor(
  Float32List f, {
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  int margin = 0,
}) {
  const t = DevelopIndex.tile, s = DevelopIndex.src, wi = DevelopIndex.warpInfo;
  final fw = f[t + 2], fh = f[t + 3];
  final sw = f[s].round(), sh = f[s + 1].round();
  var uMin = double.infinity, uMax = double.negativeInfinity;
  var vMin = double.infinity, vMax = double.negativeInfinity;
  for (final (px, py) in [(x0, y0), (x1, y0), (x0, y1), (x1, y1)]) {
    final (u, v) = sourceUvFor(px / fw, py / fh, f);
    uMin = math.min(uMin, u);
    uMax = math.max(uMax, u);
    vMin = math.min(vMin, v);
    vMax = math.max(vMax, v);
  }
  final range = f[wi + 3] > 0.5 ? f[wi + 2] : 0.0;
  var l = ((uMin - range) * sw).floor() - margin;
  var r = ((uMax + range) * sw).ceil() + margin;
  var top = ((vMin - range) * sh).floor() - margin;
  var bottom = ((vMax + range) * sh).ceil() + margin;
  l = l.clamp(0, sw - 1);
  top = top.clamp(0, sh - 1);
  r = r.clamp(l + 1, sw);
  bottom = bottom.clamp(top + 1, sh);
  return (x: l, y: top, width: r - l, height: bottom - top);
}
