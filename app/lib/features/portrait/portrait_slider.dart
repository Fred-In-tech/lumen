import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/widgets/lumen_slider.dart';

/// A [LumenSlider] bound to one portrait retouch parameter at the active
/// target (face group or individual person).
class PortraitSlider extends ConsumerWidget {
  const PortraitSlider({
    super.key,
    required this.assetId,
    required this.param,
    required this.target,
    this.touch = false,
  });

  final String assetId;
  final String param;
  final PortraitTarget target;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = PortraitRegistry.byId(param);
    final value = ref.watch(
      editorProvider(assetId).select(
        (s) => s.value == null
            ? spec.defaultValue
            : portraitValue(s.value!.settings.portrait, param, target),
      ),
    );
    final ctl = ref.read(editorProvider(assetId).notifier);

    DevelopSettings? apply(double v) {
      final s = ref.read(editorProvider(assetId)).value?.settings;
      return s?.copyWith(
        portrait: withPortraitValue(s.portrait, param, target, v),
      );
    }

    String label(double v) {
      final scope = spec.scope == PortraitScope.face
          ? ' · ${target.label}'
          : '';
      final sign = spec.bipolar && v > 0 ? '+' : '';
      return '${spec.label} $sign${v.round()}$scope';
    }

    return LumenSlider(
      label: spec.label,
      value: value,
      min: spec.min,
      max: spec.max,
      defaultValue: spec.defaultValue,
      bipolar: spec.bipolar,
      touch: touch,
      onChangeStart: () => ctl.beginGesture(spec.label),
      onChanged: (v) {
        final next = apply(v);
        if (next != null) ctl.preview(next);
      },
      onChangeEnd: () {
        final s = ref.read(editorProvider(assetId)).value?.settings;
        final v = s == null
            ? spec.defaultValue
            : portraitValue(s.portrait, param, target);
        ctl.commitGesture(label: label(v));
      },
      onCommit: (v) {
        final next = apply(v);
        if (next != null) ctl.commit(next, label: label(spec.clamp(v)));
      },
    );
  }
}
