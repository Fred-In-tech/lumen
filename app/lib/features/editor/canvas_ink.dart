import 'dart:math' as math;
import 'dart:ui';

import 'package:lumen_core/lumen_core.dart';

/// On-canvas ink (DESIGN.md §3.6: white guides with a black @ 40% outline,
/// readable on any photo) and the mask overlay tint (§2.3: #FF2E63 @ 45%).
/// Shared by every canvas tool (masks, portrait face boxes, remove).
abstract final class CanvasInk {
  static const line = Color(0xE6FFFFFF);
  static const lineSoft = Color(0x8CFFFFFF);
  static const halo = Color(0x66000000);
  static const pinFill = Color(0x8C000000);
  static const eraseStroke = Color(0x4DFFFFFF);
  static const maskOverlay = Color(0xFFFF2E63);
  static const maskOverlayAlpha = 0.45;

  /// [maskOverlay] as an engine overlay tint.
  static const MaskTint maskTint = (
    r: 1,
    g: 0x2E / 255,
    b: 0x63 / 255,
    a: maskOverlayAlpha,
  );
}

/// Ring radius for a brush of [radius] (fraction of the long edge).
double brushRingRadius(double radius, double longEdgeInView) =>
    math.max(2, radius * longEdgeInView);

/// Minimum pointer travel between recorded stroke points: a point every
/// ~15 % of the brush radius keeps strokes small.
double brushPointStep(double ringRadius) =>
    (ringRadius * 0.15).clamp(1.5, 12.0);

Paint _outline(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..isAntiAlias = true;

/// A live brush stroke through [points] (view px) with [radius], in [color].
void paintBrushStroke(
  Canvas canvas,
  List<Offset> points,
  double radius,
  Color color,
) {
  if (points.isEmpty || radius <= 0) return;
  final p = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = radius * 2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  if (points.length == 1) {
    canvas.drawCircle(points.first, radius, p..style = PaintingStyle.fill);
    return;
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final q in points.skip(1)) {
    path.lineTo(q.dx, q.dy);
  }
  canvas.drawPath(path, p);
}

/// The brush cursor: an outlined ring of [radius] at [at], plus a soft
/// inner ring at [hardness] × radius when it is large enough to read.
void paintBrushCursor(
  Canvas canvas,
  Offset at,
  double radius, {
  double hardness = 0,
}) {
  if (radius <= 0) return;
  canvas
    ..drawCircle(at, radius, _outline(CanvasInk.halo, 3))
    ..drawCircle(at, radius, _outline(CanvasInk.line, 1.25));
  final inner = radius * hardness;
  if (inner > 2) canvas.drawCircle(at, inner, _outline(CanvasInk.lineSoft, 1));
}

/// A source crosshair (clone / heal source) of half-size [size] at [at].
void paintCrosshair(Canvas canvas, Offset at, {double size = 9}) {
  for (final (w, c) in [(3.0, CanvasInk.halo), (1.25, CanvasInk.line)]) {
    final p = _outline(c, w);
    canvas
      ..drawLine(at - Offset(size, 0), at + Offset(size, 0), p)
      ..drawLine(at - Offset(0, size), at + Offset(0, size), p)
      ..drawCircle(at, size * 0.55, p);
  }
}
