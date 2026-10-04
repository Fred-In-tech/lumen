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
import 'package:lumen/features/editor/compare_suppress.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/search/reveal.dart';
import 'package:lumen/features/search/reveal_target.dart';
import 'package:lumen/widgets/segmented.dart';

/// True when any param in [ids] differs from its default.
bool _anyModified(DevelopSettings? s, Iterable<ParamId> ids) =>
    s != null &&
    ids.any((id) => !ParamRegistry.byId(id).isDefault(s.value(id)));

Iterable<ParamId> _ids(ParamGroup g) =>
    ParamRegistry.inGroup(g).map((p) => p.id);

/// All develop groups in Lightroom order.
class DevelopSections extends ConsumerWidget {
  const DevelopSections({
    super.key,
    required this.assetId,
    this.touch = false,
    this.only,
  });

  final String assetId;
  final bool touch;

  /// Restrict to one group (phone tool tabs).
  final ParamGroup? only;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(
      editorProvider(assetId).select((v) => v.value?.settings),
    );
    final ctl = ref.read(editorProvider(assetId).notifier);
    final reveal = ref.watch(revealControlProvider(assetId));
    int? open(List<ParamGroup> groups) =>
        revealSignal(reveal, [for (final g in groups) ..._ids(g)]);
    ValueChanged<bool> compareAll(List<ParamGroup> groups) => (held) {
      final c = ref.read(compareSuppressProvider(assetId).notifier);
      held ? c.hold({for (final g in groups) ..._ids(g)}) : c.release();
    };
    ValueChanged<bool> compare(ParamGroup g) => compareAll([g]);
    Widget sliders(Iterable<ParamId> ids) => Column(
      children: [
        for (final id in ids)
          RevealTarget(
            assetId: assetId,
            id: id,
            child: ParamSlider(assetId: assetId, param: id, touch: touch),
          ),
      ],
    );
    final light = DevelopGroup(
      title: 'Light',
      openSignal: open([ParamGroup.light]),
      initiallyOpen: true,
      modified: _anyModified(s, _ids(ParamGroup.light)),
      onReset: () => ctl.resetGroup(ParamGroup.light, 'Light'),
      onHoldCompare: compare(ParamGroup.light),
      child: sliders(_ids(ParamGroup.light)),
    );
    final color = DevelopGroup(
      title: 'Color',
      openSignal: open([ParamGroup.color, ParamGroup.hsl, ParamGroup.bw]),
      initiallyOpen: true,
      modified:
          _anyModified(s, [
            ..._ids(ParamGroup.color),
            ..._ids(ParamGroup.hsl),
            ..._ids(ParamGroup.bw),
          ]) ||
          s?.treatment == Treatment.bw,
      onReset: () {
        ctl.resetGroup(ParamGroup.color, 'Color');
        ctl.resetGroup(ParamGroup.hsl, 'HSL');
        ctl.resetGroup(ParamGroup.bw, 'B&W');
      },
      onHoldCompare: compareAll([
        ParamGroup.color,
        ParamGroup.hsl,
        ParamGroup.bw,
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
        ],
      ),
    );
    final curve = DevelopGroup(
      title: 'Curve',
      openSignal: open([ParamGroup.curve]),
      modified:
          _anyModified(s, _ids(ParamGroup.curve)) ||
          !(s?.curves.isIdentity ?? true),
      onReset: () => ctl.resetGroup(ParamGroup.curve, 'Curve'),
      child: Column(
        children: [
          ToneCurveEditor(assetId: assetId),
          const SubGroupLabel('Parametric'),
          sliders([
            P.curveHighlights,
            P.curveLights,
            P.curveDarks,
            P.curveShadows,
          ]),
        ],
      ),
    );
    final grading = DevelopGroup(
      title: 'Color grading',
      openSignal: open([ParamGroup.grading]),
      modified: _anyModified(s, _ids(ParamGroup.grading)),
      onReset: () => ctl.resetGroup(ParamGroup.grading, 'Color grading'),
      onHoldCompare: compare(ParamGroup.grading),
      child: GradingSection(assetId: assetId, touch: touch),
    );
    final effects = DevelopGroup(
      title: 'Effects',
      openSignal: open([ParamGroup.presence, ParamGroup.effects]),
      modified: _anyModified(s, [
        ..._ids(ParamGroup.presence),
        ..._ids(ParamGroup.effects),
      ]),
      onReset: () {
        ctl.resetGroup(ParamGroup.presence, 'Presence');
        ctl.resetGroup(ParamGroup.effects, 'Effects');
      },
      onHoldCompare: compareAll([ParamGroup.presence, ParamGroup.effects]),
      child: Column(
        children: [
          sliders([P.texture, P.clarity, P.dehaze]),
          const SubGroupLabel('Vignette'),
          sliders([
            P.vignetteAmount,
            P.vignetteMidpoint,
            P.vignetteRoundness,
            P.vignetteFeather,
            P.vignetteHighlights,
          ]),
          const SubGroupLabel('Grain'),
          sliders([P.grainAmount, P.grainSize, P.grainRoughness]),
        ],
      ),
    );
    final detail = DevelopGroup(
      title: 'Detail',
      openSignal: open([ParamGroup.detail]),
      modified: _anyModified(s, _ids(ParamGroup.detail)),
      onReset: () => ctl.resetGroup(ParamGroup.detail, 'Detail'),
      onHoldCompare: compare(ParamGroup.detail),
      child: Column(
        children: [
          sliders([
            P.sharpenAmount,
            P.sharpenRadius,
            P.sharpenDetail,
            P.sharpenMasking,
          ]),
          const SubGroupLabel('Noise reduction'),
          sliders([P.noiseLuminance, P.noiseColor]),
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: all.values.toList(),
    );
  }
}

class _TreatmentToggle extends ConsumerWidget {
  const _TreatmentToggle({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treatment = ref.watch(
      editorProvider(assetId)
          .select((v) => v.value?.settings.treatment ?? Treatment.color),
    );
    return Padding(
      padding: const EdgeInsets.only(top: Sp.s1),
      child: Row(
        children: [
          Text(
            'Treatment',
            style: LumenType.label().copyWith(
              color: context.tokens.textSecondary,
            ),
          ),
          const Spacer(),
          Segmented<Treatment>(
            value: treatment,
            options: const {Treatment.color: 'Color', Treatment.bw: 'B&W'},
            onChanged: (v) {
              final ctl = ref.read(editorProvider(assetId).notifier);
              final s = ref.read(editorProvider(assetId)).value;
              if (s != null) {
                ctl.commit(
                  s.settings.copyWith(treatment: v),
                  label: v == Treatment.bw ? 'Black & white' : 'Color',
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
