import 'package:flutter/widgets.dart';

import 'package:lumen/features/editor/canvas_ink.dart';
import 'package:lumen/features/masks/canvas/mask_handles.dart';

export 'package:lumen/features/editor/canvas_ink.dart'
    show CanvasInk, brushRingRadius;

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
      paintBrushStroke(
        canvas,
        stroke,
        strokeRadius,
        erase
            ? CanvasInk.eraseStroke
            : CanvasInk.maskOverlay.withValues(
                alpha: CanvasInk.maskOverlayAlpha,
              ),
      );
    }
    final c = cursor;
    if (c != null && strokeRadius > 0) {
      paintBrushCursor(canvas, c, strokeRadius, hardness: cursorHardness);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MaskToolPainter old) => true;
}
