import 'package:flutter/material.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/widgets/buttons.dart';

/// A dashed, empty "add something" card (New project, Create a preset):
/// the first card of a row, inviting the next thing to make.
class DashedCard extends StatelessWidget {
  const DashedCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback onTap;

  /// Accent edge (e.g. while files are dragged over it).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      radius: Rad.lg,
      builder: (context, states) {
        final hot = highlight || states.contains(WidgetState.hovered);
        return CustomPaint(
          foregroundPainter: _DashedRRect(
            color: hot ? t.accent : t.lineStrong,
            radius: Rad.lg,
          ),
          child: AnimatedContainer(
            duration: Motion.fast,
            decoration: BoxDecoration(
              color: hot ? t.accentTint : t.surface1.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(Rad.lg),
            ),
            padding: const EdgeInsets.all(Sp.s4),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: Motion.fast,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: hot ? t.accent : t.surface1,
                      shape: BoxShape.circle,
                      boxShadow: hot ? null : Elevation.e1,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: hot ? t.textOnAccent : t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Sp.s3),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: LumenType.bodyStrong().copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: Sp.s1),
                    Text(
                      caption!,
                      textAlign: TextAlign.center,
                      style: LumenType.caption().copyWith(
                        color: t.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashedRRect extends CustomPainter {
  const _DashedRRect({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) =>
      old.color != color || old.radius != radius;
}
