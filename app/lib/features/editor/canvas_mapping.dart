import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:lumen_core/lumen_core.dart';

/// Maps between source uv (where masks, strokes and AI rasters live) and a
/// canvas overlay's view coordinates through the current geometry (crop,
/// straighten, quarter turns, flips).
///
/// View → source is `sourceUvFor` from `geometry_mapping.dart` on the same
/// packed (float32) uniforms the develop shader uses, so a point picked on
/// the canvas lands on exactly the source pixel the renderer shows there.
/// Source → view is its analytic inverse on the same values.
///
/// The view rectangle is the displayed frame (`Size(0..w, 0..h)` = output
/// uv `0..1`). Source pixels map to view pixels by a similarity (rotation,
/// optional reflection, uniform [scale]), so angles and circles in source
/// pixel space stay angles and circles on screen.
class CanvasMapping {
  CanvasMapping({
    required Geometry geometry,
    required Size source,
    required this.view,
  }) : source = _safe(source),
       _f = _pack(geometry, _safe(source));

  /// Maps onto the output frame in source-pixel units (scale 1).
  factory CanvasMapping.output(Geometry geometry, Size source) {
    final s = _safe(source);
    final ow = geometry.swapsAxes ? s.height : s.width;
    final oh = geometry.swapsAxes ? s.width : s.height;
    return CanvasMapping(
      geometry: geometry,
      source: s,
      view: Size(ow * geometry.crop.width, oh * geometry.crop.height),
    );
  }

  /// Source pixel size (only its aspect ratio matters for uv mapping).
  final Size source;

  /// Size of the overlay = displayed frame.
  final Size view;

  final Float32List _f;

  static const _c = DevelopIndex.crop;
  static const _g = DevelopIndex.geom;
  static const _s = DevelopIndex.src;

  static Size _safe(Size s) => Size(
    s.width > 0 && s.width.isFinite ? s.width : 1,
    s.height > 0 && s.height.isFinite ? s.height : 1,
  );

  static Float32List _pack(Geometry g, Size src) => Float32List(_s + 4)
    ..[_c] = g.crop.left
    ..[_c + 1] = g.crop.top
    ..[_c + 2] = g.crop.right
    ..[_c + 3] = g.crop.bottom
    ..[_g] = g.angle * math.pi / 180
    ..[_g + 1] = g.rotate90.toDouble()
    ..[_g + 2] = g.flipH ? 1 : 0
    ..[_g + 3] = g.flipV ? 1 : 0
    ..[_s] = src.width
    ..[_s + 1] = src.height;

  int get _quarter => _f[_g + 1].round() % 4;

  /// Oriented (pre-crop) size in source pixels.
  double get _orientedWidth => _quarter.isOdd ? _f[_s + 1] : _f[_s];
  double get _orientedHeight => _quarter.isOdd ? _f[_s] : _f[_s + 1];

  /// View pixels per source pixel.
  double get scale {
    final w = _orientedWidth * (_f[_c + 2] - _f[_c]);
    return w <= 0 ? 1 : view.width / w;
  }

  /// Length of the source long edge in view pixels (brush radii are
  /// fractions of it).
  double get longEdgeInView => math.max(source.width, source.height) * scale;

  /// View point → source uv (may fall outside 0..1 near the frame edges).
  (double, double) toSource(Offset p) =>
      sourceUvFor(p.dx / view.width, p.dy / view.height, _f);

  /// Source uv → view point.
  Offset toView(double su, double sv) {
    final (u, v) = outputUv(su, sv);
    return Offset(u * view.width, v * view.height);
  }

  /// Source uv → output uv: the inverse of `sourceUvFor`, step by step.
  (double, double) outputUv(double su, double sv) {
    // Undo the quarter turns.
    var (x, y) = switch (_quarter) {
      1 => (1 - sv, su),
      2 => (1 - su, 1 - sv),
      3 => (sv, 1 - su),
      _ => (su, sv),
    };
    // Undo the flips (involutions).
    if (_f[_g + 2] > 0.5) x = 1 - x;
    if (_f[_g + 3] > 0.5) y = 1 - y;
    // Undo the straighten rotation (in oriented pixel space).
    final angle = _f[_g];
    if (angle != 0) {
      final dw = _orientedWidth, dh = _orientedHeight;
      final qx = (x - 0.5) * dw, qy = (y - 0.5) * dh;
      final ca = math.cos(angle), sa = math.sin(angle);
      x = (qx * ca - qy * sa) / dw + 0.5;
      y = (qx * sa + qy * ca) / dh + 0.5;
    }
    // Undo the crop.
    return (
      (x - _f[_c]) / (_f[_c + 2] - _f[_c]),
      (y - _f[_c + 1]) / (_f[_c + 3] - _f[_c + 1]),
    );
  }

  /// Source uv → source pixels.
  Offset uvToPixels(double su, double sv) =>
      Offset(su * source.width, sv * source.height);

  /// Source pixels → source uv.
  (double, double) pixelsToUv(Offset px) =>
      (px.dx / source.width, px.dy / source.height);
}
