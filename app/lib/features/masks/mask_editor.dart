import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/develop/develop_group.dart';
import 'package:lumen/features/develop/param_slider.dart' show TrackGradients;
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/mask_commands.dart';
import 'package:lumen/features/masks/mask_kinds.dart';
import 'package:lumen/features/masks/mask_ui_state.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/lumen_slider.dart';
import 'package:lumen/widgets/segmented.dart';

/// The selected mask: "Editing" banner, opacity, brush tool (brush masks)
/// and the 12 local sliders with a per-mask reset.
class MaskEditor extends ConsumerWidget {
  const MaskEditor({
    super.key,
    required this.assetId,
    required this.mask,
    this.touch = false,
  });

  final String assetId;
  final LocalMask mask;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final cmds = MaskCommands.of(ref, assetId);
    final pad = touch ? 0.0 : Sp.s4;
    final opacity = (mask.opacity * 100).roundToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, Sp.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Banner(assetId: assetId, mask: mask, touch: touch),
              const SizedBox(height: Sp.s2),
              if (!mask.isSupported)
                Text(
                  'This mask was made in a newer version. It stays in the '
                  'photo but has no effect here.',
                  style: LumenType.body(touch: touch)
                      .copyWith(color: t.textSecondary),
                )
              else ...[
                LumenSlider(
                  label: 'Opacity',
                  value: opacity,
                  min: 0,
                  max: 100,
                  defaultValue: 100,
                  bipolar: false,
                  touch: touch,
                  onChangeStart: () => cmds.begin('Opacity'),
                  onChanged: (v) => cmds.preview(
                    mask.id,
                    (m) => m.copyWith(opacity: v / 100),
                  ),
                  onChangeEnd: () {
                    final m = cmds.byId(mask.id);
                    cmds.end(
                      m == null
                          ? 'Opacity'
                          : '${m.name} · Opacity ${(m.opacity * 100).round()}%',
                    );
                  },
                  onCommit: (v) => cmds.update(
                    mask.id,
                    (m) => m.copyWith(opacity: v / 100),
                    label: '${mask.name} · Opacity ${v.round()}%',
                  ),
                ),
                if (mask.kind == MaskKind.brush)
                  _BrushControls(assetId: assetId, mask: mask, touch: touch),
              ],
            ],
          ),
        ),
        if (mask.isSupported)
          DevelopGroup(
            key: ValueKey('mask-adjustments-${mask.id}'),
            title: 'Adjustments',
            initiallyOpen: true,
            modified: mask.hasAdjustments,
            onReset: () => cmds.resetAdjustments(mask.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in kLocalSliderGroups) ...[
                  SubGroupLabel(g.title),
                  for (final id in g.ids)
                    _LocalSlider(
                      assetId: assetId,
                      maskId: mask.id,
                      param: id,
                      touch: touch,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Banner extends ConsumerWidget {
  const _Banner({
    required this.assetId,
    required this.mask,
    this.touch = false,
  });

  final String assetId;
  final LocalMask mask;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Container(
      height: touch ? 44 : 32,
      padding: const EdgeInsets.only(left: Sp.s3),
      decoration: BoxDecoration(
        color: t.accentTint,
        borderRadius: BorderRadius.circular(Rad.sm),
      ),
      child: Row(
        children: [
          Icon(mask.kind.icon, size: 14, color: t.accent),
          const SizedBox(width: Sp.s2),
          Expanded(
            child: Text(
              'Editing: ${mask.name}',
              overflow: TextOverflow.ellipsis,
              style: LumenType.label(touch: touch)
                  .copyWith(color: t.textPrimary),
            ),
          ),
          LumenButton(
            label: 'Done',
            kind: ButtonKind.ghost,
            height: touch ? 44 : 28,
            tooltip: 'Stop editing this mask',
            onPressed: () =>
                ref.read(maskUiProvider(assetId).notifier).select(null),
          ),
        ],
      ),
    );
  }
}

class _BrushControls extends ConsumerWidget {
  const _BrushControls({
    required this.assetId,
    required this.mask,
    this.touch = false,
  });

  final String assetId;
  final LocalMask mask;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final brush = ref.watch(maskUiProvider(assetId).select((s) => s.brush));
    final ui = ref.read(maskUiProvider(assetId).notifier);
    Widget slider(
      String label,
      double value,
      double min,
      double def,
      BrushSettings Function(double v) apply,
    ) => LumenSlider(
      label: label,
      value: value,
      min: min,
      max: 100,
      defaultValue: def,
      bipolar: false,
      touch: touch,
      onChanged: (v) => ui.setBrush(apply(v)),
      onCommit: (v) => ui.setBrush(apply(v)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SubGroupLabel('Brush'),
        Align(
          alignment: Alignment.centerLeft,
          child: Segmented<bool>(
            value: brush.erase,
            height: touch ? 36 : 26,
            options: const {false: 'Paint', true: 'Erase'},
            onChanged: (erase) => ui.setBrush(brush.copyWith(erase: erase)),
          ),
        ),
        const SizedBox(height: Sp.s1),
        slider('Size', brush.size, 1, 20, (v) => brush.copyWith(size: v)),
        slider(
          'Hardness',
          brush.hardness,
          0,
          50,
          (v) => brush.copyWith(hardness: v),
        ),
        slider('Flow', brush.flow, 1, 100, (v) => brush.copyWith(flow: v)),
        if (mask.strokes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Sp.s1),
            child: Text(
              'Paint on the photo to add to this mask.',
              style: LumenType.body(touch: touch)
                  .copyWith(color: t.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// One local slider of mask [maskId]: a delta on top of the global value.
class _LocalSlider extends ConsumerWidget {
  const _LocalSlider({
    required this.assetId,
    required this.maskId,
    required this.param,
    this.touch = false,
  });

  final String assetId;
  final String maskId;
  final ParamId param;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ParamRegistry.byId(param);
    final value = ref.watch(
      editorProvider(assetId).select((s) {
        for (final m in s.value?.settings.masks ?? const <LocalMask>[]) {
          if (m.id == maskId) return m.adjustments[param] ?? 0.0;
        }
        return 0.0;
      }),
    );
    final cmds = MaskCommands.of(ref, assetId);
    final isExposure = spec.unit == 'EV';
    return LumenSlider(
      label: spec.label,
      value: value,
      min: spec.min,
      max: spec.max,
      step: isExposure ? 0.01 : spec.step,
      decimals: isExposure ? 2 : (spec.step < 1 ? 1 : 0),
      trackGradient: TrackGradients.forParam(param),
      touch: touch,
      onChangeStart: () {
        cmds.begin(spec.label);
        // Lightroom's auto-toggle: the tint hides while you adjust.
        ref.read(maskUiProvider(assetId).notifier).setShowOverlay(false);
      },
      onChanged: (v) => cmds.preview(maskId, (m) => m.withAdjustment(param, v)),
      onChangeEnd: () {
        final m = cmds.byId(maskId);
        cmds.end(
          m == null
              ? spec.label
              : adjustmentLabel(m, param, m.adjustments[param] ?? 0),
        );
      },
      onCommit: (v) => cmds.setAdjustment(maskId, param, v),
    );
  }
}
