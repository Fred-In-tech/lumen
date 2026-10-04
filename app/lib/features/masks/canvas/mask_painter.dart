import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/masks/canvas/mask_handles.dart';

/// On-canvas ink (DESIGN.md §3.6: white guides with a black @ 40% outline,
/// readable on any photo) and the mask overlay tint (§2.3: #FF2E63 @ 45%).
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

/// Paints the selected mask's guides and handles, other masks' pins, the
/// live brush stroke and the brush cursor ring.
class MaskToolPainter extends CustomPainter {
  MaskToolPainter({
    required this.scene,
    required this.accent,
    required this.touch,
    this.hot,
    this.stroke = const [],
    this.strokeRadius = 0,
    this.erase = false,
    this.cursor,
    this.cursorHardness = 0.5,
  });

  final MaskScene scene;
  final Color accent;
  final bool touch;

  /// The hovered or dragged handle (drawn larger).
  final HandleRole? hot;

  /// Live brush stroke (view points) and its radius in view pixels.
  final List<Offset> stroke;
  final double strokeRadius;
  final bool erase;

  /// Brush cursor centre (null hides the ring).
  final Offset? cursor;
  final double cursorHardness;

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..isAntiAlias = true;

  void _guide(Canvas canvas, Offset a, Offset b, {bool soft = false}) {
    canvas.drawLine(a, b, _stroke(CanvasInk.halo, 3));
    canvas.drawLine(
      a,
      b,
      _stroke(soft ? CanvasInk.lineSoft : CanvasInk.line, 1.25),
    );
  }

  void _oval(Canvas canvas, RadialGuide g, double k, {bool soft = false}) {
    canvas
      ..save()
      ..translate(g.center.dx, g.center.dy)
      ..rotate(g.rotation);
    final r = Rect.fromCenter(
      center: Offset.zero,
      width: 2 * g.rx * k,
      height: 2 * g.ry * k,
    );
    canvas
      ..drawOval(r, _stroke(CanvasInk.halo, 3))
      ..drawOval(r, _stroke(soft ? CanvasInk.lineSoft : CanvasInk.line, 1.25))
      ..restore();
  }

  void _dot(
    Canvas canvas,
    Offset at,
    double r,
    Color fill, {
    double ring = 1.5,
  }) {
    canvas
      ..drawCircle(at, r + ring + 1, Paint()..color = CanvasInk.halo)
      ..drawCircle(at, r + ring, Paint()..color = CanvasInk.line)
      ..drawCircle(at, r, Paint()..color = fill);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final half = size.longestSide * 2;
    final linear = scene.linear;
    if (linear != null) {
      final (a0, a1) = linear.lineAt(0, half);
      final (m0, m1) = linear.lineAt(0.5, half);
      final (b0, b1) = linear.lineAt(1, half);
      _guide(canvas, a0, a1);
      _guide(canvas, m0, m1, soft: true);
      _guide(canvas, b0, b1);
    }
    final radial = scene.radial;
    if (radial != null) {
      _oval(canvas, radial, 1);
      if (radial.feather > 0.001) {
        _oval(canvas, radial, 1 - radial.feather, soft: true);
      }
      final knob = scene.handles
          .where((h) => h.role == HandleRole.radialRotate)
          .firstOrNull;
      if (knob != null) {
        _guide(canvas, radial.center - radial.yAxis, knob.at, soft: true);
      }
    }
    final base = touch ? 6.0 : 4.5;
    for (final h in scene.pins) {
      _dot(canvas, h.at, base, CanvasInk.pinFill);
    }
    for (final h in scene.handles) {
      final grow = h.role == hot ? 1.5 : 0.0;
      final (r, fill) = switch (h.role) {
        HandleRole.linearMove || HandleRole.radialMove => (base + 1.5, accent),
        HandleRole.radialRotate => (base, CanvasInk.pinFill),
        HandleRole.radialFeather => (base - 1, CanvasInk.line),
        _ => (base, CanvasInk.line),
      };
      _dot(canvas, h.at, r + grow, fill);
    }
    if (stroke.isNotEmpty && strokeRadius > 0) {
      final p = Paint()
        ..color = erase
            ? CanvasInk.eraseStroke
            : CanvasInk.maskOverlay.withValues(
                alpha: CanvasInk.maskOverlayAlpha,
              )
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeRadius * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (stroke.length == 1) {
        canvas.drawCircle(
          stroke.first,
          strokeRadius,
          p..style = PaintingStyle.fill,
        );
      } else {
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (final q in stroke.skip(1)) {
          path.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(path, p);
      }
    }
    final c = cursor;
    if (c != null && strokeRadius > 0) {
      canvas
        ..drawCircle(c, strokeRadius, _stroke(CanvasInk.halo, 3))
        ..drawCircle(c, strokeRadius, _stroke(CanvasInk.line, 1.25));
      final inner = strokeRadius * cursorHardness;
      if (inner > 2) {
        canvas.drawCircle(c, inner, _stroke(CanvasInk.lineSoft, 1));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MaskToolPainter old) => true;
}

/// Ring radius for a brush of [radius] (fraction of the long edge).
double brushRingRadius(double radius, double longEdgeInView) =>
    math.max(2, radius * longEdgeInView);
