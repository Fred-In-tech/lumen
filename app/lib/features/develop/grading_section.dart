import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/develop/param_slider.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/widgets/segmented.dart';

/// Color-grading wheels: 3-way view or a single zone (DESIGN.md §4.7).
class GradingSection extends ConsumerStatefulWidget {
  const GradingSection({super.key, required this.assetId, this.touch = false});

  final String assetId;
  final bool touch;

  @override
  ConsumerState<GradingSection> createState() => _GradingSectionState();
}

class _GradingSectionState extends ConsumerState<GradingSection> {
  GradeZone? _zone; // null = 3-way

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final zones = _zone == null
        ? const [GradeZone.shadows, GradeZone.midtones, GradeZone.highlights]
        : [_zone!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Segmented<GradeZone?>(
            value: _zone,
            options: const {
              null: '3-way',
              GradeZone.shadows: 'Shad',
              GradeZone.midtones: 'Mid',
              GradeZone.highlights: 'High',
              GradeZone.global: 'Global',
            },
            onChanged: (z) => setState(() => _zone = z),
          ),
        ),
        const SizedBox(height: Sp.s3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final z in zones)
              Column(
                children: [
                  ColorWheel(
                    assetId: widget.assetId,
                    zone: z,
                    size: _zone == null ? 84 : 180,
                  ),
                  const SizedBox(height: Sp.s1),
                  Text(
                    z.name[0].toUpperCase() + z.name.substring(1),
                    style: LumenType.caption().copyWith(color: t.textSecondary),
                  ),
                ],
              ),
          ],
        ),
        for (final z in zones)
          ParamSlider(
            assetId: widget.assetId,
            param: P.grade(z, 'lum'),
            touch: widget.touch,
          ),
        ParamSlider(
          assetId: widget.assetId,
          param: P.gradeBlending,
          touch: widget.touch,
        ),
        ParamSlider(
          assetId: widget.assetId,
          param: P.gradeBalance,
          touch: widget.touch,
        ),
      ],
    );
  }
}

/// Hue/saturation wheel for one grading zone.
class ColorWheel extends ConsumerWidget {
  const ColorWheel({
    super.key,
    required this.assetId,
    required this.zone,
    this.size = 84,
  });

  final String assetId;
  final GradeZone zone;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hueId = P.grade(zone, 'hue'), satId = P.grade(zone, 'sat');
    final s = ref.watch(
      editorProvider(assetId).select((v) => v.value?.settings),
    );
    final hue = s?.value(hueId) ?? 0, sat = s?.value(satId) ?? 0;
    final ctl = ref.read(editorProvider(assetId).notifier);
    void set(Offset local, {bool preview = true}) {
      final c = Offset(size / 2, size / 2);
      final d = local - c;
      final r = (d.distance / (size / 2)).clamp(0.0, 1.0);
      var h = math.atan2(-d.dy, d.dx) * 180 / math.pi;
      if (h < 0) h += 360;
      final cur = ref.read(editorProvider(assetId)).value?.settings;
      if (cur == null) return;
      ctl.preview(
        cur.withValues({
          hueId: h.roundToDouble() % 360,
          satId: (r * 100).roundToDouble(),
        }),
      );
    }

    return Semantics(
      label:
          '${zone.name} color wheel, hue ${hue.round()}, saturation ${sat.round()}',
      child: GestureDetector(
        onPanStart: (d) {
          ctl.beginGesture('${zone.name} grade');
          set(d.localPosition);
        },
        onPanUpdate: (d) => set(d.localPosition),
        onPanEnd: (_) => ctl.commitGesture(label: 'Color grade ${zone.name}'),
        onDoubleTap: () {
          final cur = ref.read(editorProvider(assetId)).value?.settings;
          if (cur != null) {
            ctl.commit(
              cur.withValues({hueId: 0, satId: 0}),
              label: 'Reset ${zone.name} grade',
            );
          }
        },
        child: CustomPaint(
          size: Size.square(size),
          painter: _WheelPainter(
            hue: hue,
            sat: sat,
            rim: context.tokens.lineStrong,
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.hue, required this.sat, required this.rim});
  final double hue;
  final double sat;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final colors = [
      for (var i = 0; i <= 12; i++)
        HSVColor.fromAHSV(1, (360 - i * 30) % 360, 0.7, 0.85).toColor(),
    ];
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = SweepGradient(colors: colors).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF808080), Color(0x00808080)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke,
    );
    final a = hue * math.pi / 180;
    final puck = c + Offset(math.cos(a), -math.sin(a)) * (sat / 100 * r);
    canvas.drawLine(
      c,
      puck,
      Paint()
        ..color = const Color(0x80FFFFFF)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(puck, 6, Paint()..color = Colors.white);
    canvas.drawCircle(
      puck,
      6,
      Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter o) => o.hue != hue || o.sat != sat;
}
