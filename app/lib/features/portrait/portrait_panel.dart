import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/develop/develop_group.dart';
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
    final faces = ref.watch(portraitFacesProvider(assetId));
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
                faces: faces,
                showFaces: ui.showFaces,
              ),
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
            child: Column(
              children: [
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
    required this.faces,
    required this.showFaces,
  });

  final String assetId;
  final FaceAnalysis? faces;
  final bool showFaces;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final count = faces?.faces.length;
    final text = switch (count) {
      null => 'Face detection runs when the photo opens.',
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
