import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/develop/develop_group.dart';
import 'package:lumen/features/develop/grading_section.dart';
import 'package:lumen/features/develop/hsl_section.dart';
import 'package:lumen/features/develop/param_slider.dart';
import 'package:lumen/features/develop/tone_curve_editor.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/widgets/segmented.dart';

/// True when any param in [ids] differs from its default.
bool _anyModified(DevelopSettings? s, Iterable<ParamId> ids) =>
    s != null && ids.any((id) => !ParamRegistry.byId(id).isDefault(s.value(id)));

Iterable<ParamId> _ids(ParamGroup g) => ParamRegistry.inGroup(g).map((p) => p.id);

/// All develop groups in Lightroom order.
class DevelopSections extends ConsumerWidget {
  const DevelopSections({super.key, required this.assetId, this.touch = false, this.only});

  final String assetId;
  final bool touch;

  /// Restrict to one group (phone tool tabs).
  final ParamGroup? only;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(editorProvider(assetId).select((v) => v.value?.settings));
    final ctl = ref.read(editorProvider(assetId).notifier);
    Widget sliders(Iterable<ParamId> ids) => Column(children: [
          for (final id in ids) ParamSlider(assetId: assetId, param: id, touch: touch),
        ]);
    final light = DevelopGroup(
      title: 'Light',
      initiallyOpen: true,
      modified: _anyModified(s, _ids(ParamGroup.light)),
      onReset: () => ctl.resetGroup(ParamGroup.light, 'Light'),
      child: sliders(_ids(ParamGroup.light)),
    );
    final color = DevelopGroup(
      title: 'Color',
      initiallyOpen: true,
      modified: _anyModified(s, [..._ids(ParamGroup.color), ..._ids(ParamGroup.hsl), ..._ids(ParamGroup.bw)]) ||
          s?.treatment == Treatment.bw,
      onReset: () {
        ctl.resetGroup(ParamGroup.color, 'Color');
        ctl.resetGroup(ParamGroup.hsl, 'HSL');
        ctl.resetGroup(ParamGroup.bw, 'B&W');
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _TreatmentToggle(assetId: assetId),
        const SubGroupLabel('White balance'),
        sliders([P.temp, P.tint]),
        if (s?.treatment != Treatment.bw) ...[
          const SubGroupLabel('Presence'),
          sliders([P.vibrance, P.saturation]),
          const SubGroupLabel('Mix'),
          HslSection(assetId: assetId, touch: touch),
        ] else ...[
          const SubGroupLabel('Black & white mix'),
          sliders(_ids(ParamGroup.bw)),
        ],
      ]),
    );
    final curve = DevelopGroup(
      title: 'Curve',
      modified: _anyModified(s, _ids(ParamGroup.curve)) || !(s?.curves.isIdentity ?? true),
      onReset: () => ctl.resetGroup(ParamGroup.curve, 'Curve'),
      child: Column(children: [
        ToneCurveEditor(assetId: assetId),
        const SubGroupLabel('Parametric'),
        sliders([P.curveHighlights, P.curveLights, P.curveDarks, P.curveShadows]),
      ]),
    );
    final grading = DevelopGroup(
      title: 'Color grading',
      modified: _anyModified(s, _ids(ParamGroup.grading)),
      onReset: () => ctl.resetGroup(ParamGroup.grading, 'Color grading'),
      child: GradingSection(assetId: assetId, touch: touch),
    );
    final effects = DevelopGroup(
      title: 'Effects',
      modified: _anyModified(s, [..._ids(ParamGroup.presence), ..._ids(ParamGroup.effects)]),
      onReset: () {
        ctl.resetGroup(ParamGroup.presence, 'Presence');
        ctl.resetGroup(ParamGroup.effects, 'Effects');
      },
      child: Column(children: [
        sliders([P.texture, P.clarity, P.dehaze]),
        const SubGroupLabel('Vignette'),
        sliders([P.vignetteAmount, P.vignetteMidpoint, P.vignetteRoundness, P.vignetteFeather, P.vignetteHighlights]),
        const SubGroupLabel('Grain'),
        sliders([P.grainAmount, P.grainSize, P.grainRoughness]),
      ]),
    );
    final detail = DevelopGroup(
      title: 'Detail',
      modified: _anyModified(s, _ids(ParamGroup.detail)),
      onReset: () => ctl.resetGroup(ParamGroup.detail, 'Detail'),
      child: Column(children: [
        sliders([P.sharpenAmount, P.sharpenRadius, P.sharpenDetail, P.sharpenMasking]),
        const SubGroupLabel('Noise reduction'),
        sliders([P.noiseLuminance, P.noiseColor]),
      ]),
    );
    final all = <ParamGroup, Widget>{
      ParamGroup.light: light,
      ParamGroup.color: color,
      ParamGroup.curve: curve,
      ParamGroup.grading: grading,
      ParamGroup.effects: effects,
      ParamGroup.detail: detail,
    };
    if (only != null) return all[only] ?? const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: all.values.toList());
  }
}

class _TreatmentToggle extends ConsumerWidget {
  const _TreatmentToggle({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treatment = ref.watch(editorProvider(assetId).select((v) => v.value?.settings.treatment ?? Treatment.color));
    return Padding(
      padding: const EdgeInsets.only(top: Sp.s1),
      child: Row(children: [
        Text('Treatment', style: LumenType.label().copyWith(color: context.tokens.textSecondary)),
        const Spacer(),
        Segmented<Treatment>(
          value: treatment,
          options: const {Treatment.color: 'Color', Treatment.bw: 'B&W'},
          onChanged: (v) {
            final ctl = ref.read(editorProvider(assetId).notifier);
            final s = ref.read(editorProvider(assetId)).value;
            if (s != null) ctl.commit(s.settings.copyWith(treatment: v), label: v == Treatment.bw ? 'Black & white' : 'Color');
          },
        ),
      ]),
    );
  }
}
