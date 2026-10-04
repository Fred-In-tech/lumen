import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/develop/develop_group.dart';
import 'package:lumen/features/editor/compare_suppress.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_slider.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/segmented.dart';

typedef PortraitSection = ({String title, List<String> ids});

/// Retouch sections shown in the panel (features with a working engine).
const List<PortraitSection> kPortraitSections = [
  (
    title: 'Skin',
    ids: [
      PortraitIds.skinSoftening,
      PortraitIds.skinEven,
      PortraitIds.skinTexture,
      PortraitIds.skinShine,
    ],
  ),
  (
    title: 'Blemishes',
    ids: [PortraitIds.acne, PortraitIds.freckle, PortraitIds.mole],
  ),
  (
    title: 'Wrinkles',
    ids: [
      PortraitIds.wrinkleForehead,
      PortraitIds.wrinkleFrown,
      PortraitIds.wrinkleCrowsFeet,
      PortraitIds.wrinkleSmile,
      PortraitIds.wrinkleMarionette,
    ],
  ),
  (
    title: 'Eyes',
    ids: [
      PortraitIds.darkCircles,
      PortraitIds.eyeBags,
      PortraitIds.lidProtect,
      PortraitIds.eyeWhites,
      PortraitIds.iris,
      PortraitIds.redVein,
    ],
  ),
  (
    title: 'Teeth',
    ids: [PortraitIds.teethBrightness, PortraitIds.teethDesaturate],
  ),
  (title: 'Makeup', ids: [PortraitIds.lips, PortraitIds.blush]),
];

const _individualKey = 'individual';

/// Evoto-style Portrait module: face status, group tabs (All · Female · Male ·
/// Child · Senior · Individual), one-click Auto Retouch and retouch sections.
class PortraitPanel extends ConsumerWidget {
  const PortraitPanel({super.key, required this.assetId, this.touch = false});

  final String assetId;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(portraitUiProvider(assetId));
    final status = ref.watch(portraitFacesStatusProvider(assetId));
    final selected = status.value?.faceById(ui.selectedFaceId ?? '');
    final portrait = ref.watch(
      editorProvider(assetId)
          .select((s) => s.value?.settings.portrait ?? PortraitSettings.empty),
    );
    final target = ui.target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.s4, Sp.s2, Sp.s4, Sp.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FaceStatus(
                assetId: assetId,
                status: status,
                showFaces: ui.showFaces,
              ),
              if (selected != null) ...[
                const SizedBox(height: Sp.s3),
                _TagRow(assetId: assetId, face: selected),
              ],
              const SizedBox(height: Sp.s3),
              _TargetTabs(assetId: assetId, ui: ui),
              const SizedBox(height: Sp.s3),
              _AutoRetouchButton(assetId: assetId),
            ],
          ),
        ),
        for (final section in kPortraitSections)
          DevelopGroup(
            key: ValueKey('portrait-${section.title}'),
            title: section.title,
            initiallyOpen: section.title == 'Skin',
            modified: _modified(portrait, section.ids, target),
            onReset: () => _resetSection(ref, section, target),
            onHoldCompare: (held) {
              final c = ref.read(compareSuppressProvider(assetId).notifier);
              held ? c.hold(section.ids.toSet()) : c.release();
            },
            child: Column(
              children: [
                if (section.title == 'Blemishes')
                  _SpotEditRow(assetId: assetId, ui: ui, portrait: portrait),
                for (final id in section.ids)
                  if (_visible(portrait, id, target))
                    PortraitSlider(
                      key: ValueKey('$id-${target.group}-${target.personId}'),
                      assetId: assetId,
                      param: id,
                      target: target,
                      touch: touch,
                    ),
              ],
            ),
          ),
      ],
    );
  }

  /// Lower-lid protection only matters once under-eye work is on (Evoto).
  static bool _visible(PortraitSettings p, String id, PortraitTarget t) =>
      id != PortraitIds.lidProtect ||
      portraitValue(p, PortraitIds.eyeBags, t) > 0 ||
      portraitValue(p, PortraitIds.darkCircles, t) > 0;

  static bool _modified(
    PortraitSettings p,
    List<String> ids,
    PortraitTarget t,
  ) => ids.any((id) {
    if (t.isPerson) return p.individuals[t.personId]?.containsKey(id) ?? false;
    if (t.group != FaceGroup.all) return p.groupOverrides(t.group, id);
    return !PortraitRegistry.byId(id).isDefault(portraitValue(p, id, t));
  });

  void _resetSection(WidgetRef ref, PortraitSection section, PortraitTarget t) {
    final ctl = ref.read(editorProvider(assetId).notifier);
    final s = ref.read(editorProvider(assetId)).value?.settings;
    if (s == null) return;
    var p = s.portrait;
    for (final id in section.ids) {
      final person = t.personId;
      if (person != null) {
        p = p.clearIndividualValue(person, id);
      } else if (t.group != FaceGroup.all) {
        p = p.clearGroupOverride(t.group, id);
      } else {
        p = p.withGroupValue(
          FaceGroup.all,
          id,
          PortraitRegistry.byId(id).defaultValue,
        );
      }
    }
    ctl.commit(
      s.copyWith(portrait: p),
      label: 'Reset ${section.title} · ${t.label}',
      kind: HistoryKind.reset,
    );
  }
}

class _FaceStatus extends ConsumerWidget {
  const _FaceStatus({
    required this.assetId,
    required this.status,
    required this.showFaces,
  });

  final String assetId;
  final AsyncValue<FaceAnalysis?> status;
  final bool showFaces;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final count = status.value?.faces.length;
    final text = switch (count) {
      null when status.hasError => 'Face detection isn’t available here. Masks and manual tools still work.',
      null => 'Detecting faces…',
      0 => 'No faces found. Retouch applies when a face is visible.',
      1 => '1 face. Click it to edit this person only.',
      _ => '$count faces. Click a face to edit one person.',
    };
    return Row(
      children: [
        Icon(LucideIcons.scanFace, size: 16, color: t.textSecondary),
        const SizedBox(width: Sp.s2),
        Expanded(
          child: Text(
            text,
            style: LumenType.body().copyWith(color: t.textSecondary),
          ),
        ),
        if ((count ?? 0) > 0)
          LumenIconButton(
            icon: showFaces ? LucideIcons.eye : LucideIcons.eyeOff,
            tooltip: showFaces ? 'Hide face boxes' : 'Show face boxes',
            onPressed: () => ref
                .read(portraitUiProvider(assetId).notifier)
                .setShowFaces(!showFaces),
          ),
      ],
    );
  }
}

class _TargetTabs extends ConsumerWidget {
  const _TargetTabs({required this.assetId, required this.ui});

  final String assetId;
  final PortraitUiState ui;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(portraitUiProvider(assetId).notifier);
    final options = <String, String>{
      for (final g in FaceGroup.values) g.name: g.label,
      if (ui.selectedFaceId != null) _individualKey: 'Individual',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Segmented<String>(
        value: ui.target.isPerson ? _individualKey : ui.target.group.name,
        options: options,
        onChanged: (key) {
          if (key == _individualKey) return;
          notifier.selectGroup(FaceGroup.fromName(key));
        },
      ),
    );
  }
}

class _AutoRetouchButton extends ConsumerWidget {
  const _AutoRetouchButton({required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LumenButton(
    label: 'Auto Retouch',
    kind: ButtonKind.ai,
    expand: true,
    icon: const AiGlyph(size: 14, neutral: true),
    tooltip: 'Natural skin, eyes and teeth retouch for every face',
    onPressed: () {
      final s = ref.read(editorProvider(assetId)).value?.settings;
      if (s == null) return;
      ref
          .read(editorProvider(assetId).notifier)
          .commit(
            s.copyWith(portrait: PortraitPresets.autoRetouch(s.portrait)),
            label: 'Auto Retouch',
            kind: HistoryKind.preset,
          );
    },
  );
}

/// Lets the user correct the selected face's retouch group (Evoto's gender /
/// age chips). Stored in the local face cache only.
class _TagRow extends ConsumerWidget {
  const _TagRow({required this.assetId, required this.face});

  final String assetId;
  final DetectedFace face;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Row(
      children: [
        Text(
          'Tag as',
          style: LumenType.caption().copyWith(color: t.textTertiary),
        ),
        const SizedBox(width: Sp.s2),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Segmented<FaceGroup>(
              value: face.group,
              options: {
                for (final g in FaceGroup.values)
                  g: g == FaceGroup.all ? 'None' : g.label,
              },
              onChanged: (g) => tagFace(ref, assetId, face, g),
            ),
          ),
        ),
      ],
    );
  }
}

/// Blemishes: toggle the on-canvas spot editor, with the decision counts and
/// a reset (spots are per photo; they never sync or go into presets).
class _SpotEditRow extends ConsumerWidget {
  const _SpotEditRow({
    required this.assetId,
    required this.ui,
    required this.portrait,
  });

  final String assetId;
  final PortraitUiState ui;
  final PortraitSettings portrait;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final spots = portrait.spots;
    final counts = spots.isEmpty
        ? 'Click spots on the photo to keep or remove them.'
        : '${spots.remove.length} removed · ${spots.keep.length} kept by hand';
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              counts,
              style: LumenType.caption().copyWith(color: t.textTertiary),
            ),
          ),
          if (!spots.isEmpty)
            LumenIconButton(
              icon: LucideIcons.rotateCcw,
              tooltip: 'Reset spot choices',
              onPressed: () {
                final s = ref.read(editorProvider(assetId)).value?.settings;
                if (s == null) return;
                ref
                    .read(editorProvider(assetId).notifier)
                    .commit(
                      s.copyWith(
                        portrait: s.portrait.withSpots(PortraitSpots.none),
                      ),
                      label: 'Reset spot choices',
                      kind: HistoryKind.reset,
                    );
              },
            ),
          LumenButton(
            label: ui.spotEdit ? 'Done' : 'Edit spots',
            kind: ui.spotEdit ? ButtonKind.primary : ButtonKind.secondary,
            height: 28,
            onPressed: () => ref
                .read(portraitUiProvider(assetId).notifier)
                .setSpotEdit(!ui.spotEdit),
          ),
        ],
      ),
    );
  }
}
