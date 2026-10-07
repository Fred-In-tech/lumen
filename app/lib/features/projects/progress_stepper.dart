import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';

/// The five shoot steps as connected nodes: ticked when done, a partial
/// arc while under way, a dashed ring when there is nothing to do.
/// [detailed] adds each step's count line (project page header).
class ProgressStepper extends StatelessWidget {
  const ProgressStepper({
    super.key,
    required this.progress,
    this.detailed = false,
  });

  final ProjectProgress progress;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final steps = progress.steps;
    final node = detailed ? 22.0 : 16.0;
    final current = progress.next.step;
    // The line is lit as far as the steps are done without a gap.
    var reached = 0;
    while (reached < steps.length && steps[reached].isComplete) {
      reached++;
    }
    return Semantics(
      label:
          'Progress: ${progress.completedSteps} of ${steps.length} steps done. '
          '${steps.map((s) => '${s.step.label} ${_spoken(s.state)}').join(', ')}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: _StepColumn(
                step: steps[i],
                node: node,
                detailed: detailed,
                isCurrent: steps[i].step == current,
                lineBefore: i == 0 ? null : (i <= reached ? t.accent : t.line),
                lineAfter: i == steps.length - 1
                    ? null
                    : (i < reached ? t.accent : t.line),
              ),
            ),
        ],
      ),
    );
  }

  static String _spoken(StepStatus s) => switch (s) {
    StepStatus.done => 'done',
    StepStatus.partial => 'in progress',
    StepStatus.notStarted => 'not started',
    StepStatus.optional => 'nothing to do',
  };
}

class _StepColumn extends StatelessWidget {
  const _StepColumn({
    required this.step,
    required this.node,
    required this.detailed,
    required this.isCurrent,
    required this.lineBefore,
    required this.lineAfter,
  });

  final StepProgress step;
  final double node;
  final bool detailed;
  final bool isCurrent;
  final Color? lineBefore;
  final Color? lineAfter;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget line(Color? c) =>
        Expanded(child: Container(height: 1.5, color: c ?? Colors.transparent));
    final labelColor = step.isComplete
        ? t.textPrimary
        : isCurrent
        ? t.accent
        : t.textTertiary;
    return Column(
      children: [
        Row(
          children: [
            line(lineBefore),
            const SizedBox(width: 3),
            _Node(step: step, size: node),
            const SizedBox(width: 3),
            line(lineAfter),
          ],
        ),
        SizedBox(height: detailed ? Sp.s2 : Sp.s1),
        Text(
          step.step.label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: (detailed ? LumenType.label() : LumenType.micro()).copyWith(
            color: labelColor,
            letterSpacing: detailed ? null : 0.2,
          ),
        ),
        if (detailed) ...[
          const SizedBox(height: Sp.s0_5),
          Text(
            step.summary,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: LumenType.caption().copyWith(color: t.textTertiary),
          ),
        ],
      ],
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.step, required this.size});

  final StepProgress step;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (step.state == StepStatus.done) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
        child: Icon(
          LucideIcons.check,
          size: size * 0.62,
          color: t.textOnAccent,
        ),
      );
    }
    final fraction = step.total == 0 ? 0.0 : step.done / step.total;
    return CustomPaint(
      size: Size.square(size),
      painter: _RingPainter(
        track: t.lineStrong,
        fill: t.accent,
        fraction: step.state == StepStatus.partial ? fraction : 0,
        dashed: step.state == StepStatus.optional,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.track,
    required this.fill,
    required this.fraction,
    required this.dashed,
  });

  final Color track;
  final Color fill;
  final double fraction;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 1;
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = track;
    final rect = Rect.fromCircle(center: c, radius: r);
    if (dashed) {
      const dashes = 8;
      const sweep = math.pi * 2 / dashes;
      for (var i = 0; i < dashes; i++) {
        canvas.drawArc(rect, i * sweep, sweep * 0.55, false, stroke);
      }
      return;
    }
    canvas.drawCircle(c, r, stroke);
    if (fraction <= 0) return;
    canvas
      ..drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction.clamp(0.08, 1.0),
        false,
        stroke
          ..color = fill
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(c, r * 0.32, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.dashed != dashed ||
      old.track != track ||
      old.fill != fill;
}
