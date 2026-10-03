import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/widgets/lumen_slider.dart';

/// Colored track gradients (DESIGN.md §2.3).
abstract final class TrackGradients {
  static const temp = LinearGradient(colors: [Color(0xFF3D7BD9), Color(0xFFE8E8E8), Color(0xFFE8C547)]);
  static const tint = LinearGradient(colors: [Color(0xFF3FAE5A), Color(0xFFE8E8E8), Color(0xFFC24FC0)]);
  static const lum = LinearGradient(colors: [Color(0xFF000000), Color(0xFFFFFFFF)]);

  static Gradient? forParam(ParamId id) {
    if (id == P.temp) return temp;
    if (id == P.tint) return tint;
    if (id.endsWith('.lum') && id.startsWith('grade.')) return lum;
    if (id.startsWith('hsl.')) {
      final parts = id.split('.');
      final band = HslBand.values.byName(parts[1]);
      final c = kHslBandColors[band.index];
      final hsl = HSLColor.fromColor(c);
      return switch (parts[2]) {
        'hue' => LinearGradient(colors: [
            hsl.withHue((hsl.hue - 30) % 360).toColor(),
            c,
            hsl.withHue((hsl.hue + 30) % 360).toColor(),
          ]),
        'sat' => LinearGradient(colors: [const Color(0xFF808080), c]),
        _ => LinearGradient(colors: [hsl.withLightness(0.25).toColor(), hsl.withLightness(0.85).toColor()]),
      };
    }
    return null;
  }
}

/// A [LumenSlider] bound to one [ParamId] of the open photo.
class ParamSlider extends ConsumerWidget {
  const ParamSlider({super.key, required this.assetId, required this.param, this.label, this.touch = false});

  final String assetId;
  final ParamId param;
  final String? label;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ParamRegistry.byId(param);
    final value = ref.watch(editorProvider(assetId).select((s) => s.value?.settings.value(param) ?? spec.defaultValue));
    final aiReason = ref.watch(editorProvider(assetId).select((s) {
      final st = s.value;
      final ai = st?.doc.ai;
      if (st == null || ai == null || st.lockedByUser.contains(param)) return null;
      for (final c in ai.changes) {
        if (c.param == param && (c.to - (st.settings.value(param))).abs() < 1e-6) return c.reason;
      }
      return null;
    }));
    final ctl = ref.read(editorProvider(assetId).notifier);
    final isExposure = spec.unit == 'EV';
    return LumenSlider(
      label: label ?? spec.label,
      value: value,
      min: spec.min,
      max: spec.max,
      defaultValue: spec.defaultValue,
      bipolar: spec.bipolar,
      step: isExposure ? 0.01 : spec.step,
      decimals: isExposure ? 2 : (spec.step < 1 ? 1 : 0),
      trackGradient: TrackGradients.forParam(param),
      aiReason: aiReason,
      touch: touch,
      onChangeStart: () => ctl.beginGesture(spec.label),
      onChanged: (v) {
        final s = ref.read(editorProvider(assetId)).value;
        if (s != null) ctl.preview(s.settings.withValue(param, v));
      },
      onChangeEnd: () {
        final s = ref.read(editorProvider(assetId)).value;
        final v = s?.settings.value(param) ?? 0;
        ctl.commitGesture(label: '${spec.label} ${_fmt(spec, v)}');
      },
      onCommit: (v) => ctl.setParam(param, v),
    );
  }

  static String _fmt(ParamSpec spec, double v) => spec.unit == 'EV'
      ? '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}'
      : '${v >= 0 && spec.bipolar ? '+' : ''}${v.round()}';
}
