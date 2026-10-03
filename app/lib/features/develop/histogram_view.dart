import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';

/// RGB + luminance histogram with clipping triangles (DESIGN.md §4.3).
class HistogramView extends StatelessWidget {
  const HistogramView({super.key, required this.histogram, this.height = 96});

  final Histogram? histogram;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final h = histogram;
    final lowClip =
        h != null &&
        h.luma.isNotEmpty &&
        h.luma.first / math.max(1, h.luma.fold<int>(0, (a, b) => a + b)) >
            0.001;
    final highClip =
        h != null &&
        h.luma.isNotEmpty &&
        h.luma.last / math.max(1, h.luma.fold<int>(0, (a, b) => a + b)) > 0.001;
    return Semantics(
      label:
          'Histogram${lowClip ? ', shadows clipped' : ''}${highClip ? ', highlights clipped' : ''}',
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _HistPainter(h, grid: t.line, bg: t.surface0),
          child: Stack(
            children: [
              Positioned(left: 4, top: 4, child: _Tri(on: lowClip, left: true)),
              Positioned(
                right: 4,
                top: 4,
                child: _Tri(on: highClip, left: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tri extends StatelessWidget {
  const _Tri({required this.on, required this.left});
  final bool on;
  final bool left;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(10, 8),
    painter: _TriPainter(on ? Colors.white : context.tokens.textDisabled, left),
  );
}

class _TriPainter extends CustomPainter {
  _TriPainter(this.color, this.left);
  final Color color;
  final bool left;

  @override
  void paint(Canvas canvas, Size s) {
    final p = left
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(s.width, 0)
            ..lineTo(0, s.height))
        : (Path()
            ..moveTo(0, 0)
            ..lineTo(s.width, 0)
            ..lineTo(s.width, s.height));
    canvas.drawPath(p..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TriPainter o) => o.color != color;
}

class _HistPainter extends CustomPainter {
  _HistPainter(this.h, {required this.grid, required this.bg});
  final Histogram? h;
  final Color grid;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final g = Paint()..color = grid;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(size.width * i / 4, 0),
        Offset(size.width * i / 4, size.height),
        g,
      );
    }
    final hist = h;
    if (hist == null) return;
    var peak = 1;
    for (final ch in [hist.red, hist.green, hist.blue]) {
      for (var i = 1; i < ch.length - 1; i++) {
        if (ch[i] > peak) peak = ch[i];
      }
    }
    void draw(List<int> bins, Color c, {BlendMode mode = BlendMode.plus}) {
      if (bins.isEmpty) return;
      final path = Path()..moveTo(0, size.height);
      for (var i = 0; i < bins.length; i++) {
        final x = i / (bins.length - 1) * size.width;
        final v = math.sqrt(bins[i] / peak).clamp(0.0, 1.0);
        path.lineTo(x, size.height - v * size.height);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..blendMode = mode,
      );
    }

    draw(hist.luma, const Color(0x598A8A8A), mode: BlendMode.srcOver);
    draw(hist.red, const Color(0x8CFF5A5A));
    draw(hist.green, const Color(0x8C5AD17A));
    draw(hist.blue, const Color(0x8C5A8CFF));
  }

  @override
  bool shouldRepaint(_HistPainter o) => !identical(o.h, h);
}
