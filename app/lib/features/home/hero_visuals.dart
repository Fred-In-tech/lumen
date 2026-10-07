import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Painted illustrations for the Home hero slides. They are drawings, not
/// product screenshots or measurements, so they never claim a number.

/// A warm sky gradient with a smooth tone curve and a histogram silhouette:
/// the RAW slide.
class RawVisualPainter extends CustomPainter {
  const RawVisualPainter({required this.ink, required this.accent});

  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas
      ..save()
      ..clipRRect(r)
      ..drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF233B6E), Color(0xFFB2607A), Color(0xFFF3B37A)],
            stops: [0, 0.55, 1],
          ).createShader(Offset.zero & size),
      );
    // Histogram silhouette along the bottom.
    final hist = Path()..moveTo(0, size.height);
    for (var i = 0; i <= 64; i++) {
      final x = size.width * i / 64;
      final v =
          0.18 +
          0.22 * math.exp(-math.pow((i - 20) / 9, 2)) +
          0.32 * math.exp(-math.pow((i - 44) / 7, 2));
      hist.lineTo(x, size.height * (1 - v));
    }
    hist
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(hist, Paint()..color = const Color(0x33FFFFFF));
    // Tone curve (a gentle S) on a faint grid.
    final grid = Paint()
      ..color = const Color(0x26FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4, y = size.height * i / 4;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), grid)
        ..drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final curve = Path()..moveTo(0, size.height);
    for (var i = 0; i <= 40; i++) {
      final t = i / 40;
      final s = t + 0.12 * math.sin(2 * math.pi * t);
      curve.lineTo(size.width * t, size.height * (1 - s));
    }
    canvas
      ..drawPath(
        curve,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = Colors.white,
      )
      ..drawCircle(
        Offset(
          size.width * 0.3,
          size.height * (1 - 0.3 - 0.12 * math.sin(2 * math.pi * 0.3)),
        ),
        5,
        Paint()..color = Colors.white,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(RawVisualPainter old) =>
      old.ink != ink || old.accent != accent;
}

/// A loupe over skin: the same fine texture on both halves, a few spots
/// only on the left. The retouch slide.
class SkinVisualPainter extends CustomPainter {
  const SkinVisualPainter({required this.line});

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas
      ..save()
      ..clipRRect(r)
      ..drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.4),
            radius: 1.2,
            colors: [Color(0xFFF2CDB4), Color(0xFFD9A487)],
          ).createShader(Offset.zero & size),
      );
    // Deterministic pore texture: identical on both halves.
    final rnd = math.Random(11);
    final pore = Paint()..color = const Color(0x22000000);
    final glint = Paint()..color = const Color(0x22FFFFFF);
    for (var i = 0; i < 900; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final s = 0.6 + rnd.nextDouble() * 1.1;
      canvas.drawCircle(Offset(x, y), s, i.isEven ? pore : glint);
    }
    // Blemishes on the "before" half only.
    final spots = Paint()..color = const Color(0x66B5463F);
    for (final (fx, fy, rr) in const [
      (0.18, 0.38, 7.0),
      (0.32, 0.62, 5.0),
      (0.12, 0.72, 4.0),
      (0.38, 0.3, 4.5),
    ]) {
      canvas.drawCircle(Offset(size.width * fx, size.height * fy), rr, spots);
    }
    // Split line and labels.
    final mid = size.width / 2;
    canvas
      ..drawLine(
        Offset(mid, 0),
        Offset(mid, size.height),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2,
      )
      ..drawCircle(
        Offset(mid, size.height / 2),
        12,
        Paint()..color = Colors.white,
      )
      ..restore();
    _label(canvas, 'Before', Offset(12, size.height - 26));
    _label(canvas, 'After', Offset(mid + 12, size.height - 26));
  }

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(at.dx - 6, at.dy - 3, tp.width + 12, tp.height + 6),
      const Radius.circular(99),
    );
    canvas.drawRRect(bg, Paint()..color = const Color(0x55000000));
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(SkinVisualPainter old) => old.line != line;
}

/// A contact sheet: six frames, picks ticked and rejects crossed. The
/// culling slide.
class CullVisualPainter extends CustomPainter {
  const CullVisualPainter({
    required this.pick,
    required this.reject,
    required this.paper,
  });

  final Color pick;
  final Color reject;
  final Color paper;

  static const _frames = [
    [Color(0xFF8FA3B8), Color(0xFFE2C9A6)],
    [Color(0xFF7D8F7A), Color(0xFFD8CBB0)],
    [Color(0xFF9C7F8E), Color(0xFFE9D3C4)],
    [Color(0xFF6E8199), Color(0xFFC9D4DE)],
    [Color(0xFFA48A6C), Color(0xFFEAD9BE)],
    [Color(0xFF7F7391), Color(0xFFD6CDE3)],
  ];

  // 1 pick, 2 reject, 0 none.
  static const _marks = [1, 0, 2, 1, 2, 1];

  @override
  void paint(Canvas canvas, Size size) {
    const cols = 3, rows = 2, gap = 8.0;
    final w = (size.width - gap * (cols - 1)) / cols;
    final h = (size.height - gap * (rows - 1)) / rows;
    for (var i = 0; i < 6; i++) {
      final x = (i % cols) * (w + gap), y = (i ~/ cols) * (h + gap);
      final rect = Rect.fromLTWH(x, y, w, h);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas
        ..save()
        ..clipRRect(rr)
        ..drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _frames[i],
            ).createShader(rect),
        );
      // A simple figure: head and shoulders.
      final c = Offset(rect.center.dx, rect.top + h * 0.45);
      final figure = Paint()..color = const Color(0x33000000);
      canvas
        ..drawCircle(c, h * 0.14, figure)
        ..drawOval(
          Rect.fromCenter(
            center: Offset(c.dx, rect.bottom),
            width: w * 0.55,
            height: h * 0.5,
          ),
          figure,
        );
      if (_marks[i] == 2) {
        canvas.drawRect(rect, Paint()..color = paper.withValues(alpha: 0.55));
      }
      canvas.restore();
      if (_marks[i] != 0) _badge(canvas, rect, _marks[i] == 1);
    }
  }

  void _badge(Canvas canvas, Rect rect, bool isPick) {
    final c = Offset(rect.right - 14, rect.top + 14);
    canvas.drawCircle(c, 9, Paint()..color = isPick ? pick : reject);
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (isPick) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - 4, c.dy)
          ..lineTo(c.dx - 1, c.dy + 3)
          ..lineTo(c.dx + 4, c.dy - 3),
        p,
      );
    } else {
      canvas
        ..drawLine(c + const Offset(-3, -3), c + const Offset(3, 3), p)
        ..drawLine(c + const Offset(3, -3), c + const Offset(-3, 3), p);
    }
  }

  @override
  bool shouldRepaint(CullVisualPainter old) =>
      old.pick != pick || old.reject != reject || old.paper != paper;
}
