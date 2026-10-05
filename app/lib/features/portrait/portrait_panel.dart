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
import 'package:lumen/features/portrait/portrait_header.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/portrait/portrait_tools.dart';
import 'package:lumen/features/search/reveal.dart';
import 'package:lumen/features/search/reveal_target.dart';
import 'package:lumen/widgets/buttons.dart';

typedef PortraitSection = ({
  String title,
  PortraitCategory category,
  List<String> ids,
});

/// Retouch sections shown in the panel (features with a working engine).
const List<PortraitSection> kPortraitSections = [
  (
    title: 'Skin',
    category: PortraitCategory.skin,
    ids: [
      PortraitIds.skinSoftening,
      PortraitIds.skinEven,
      PortraitIds.skinTexture,
      PortraitIds.skinShine,
    ],
  ),
  (
    title: 'Blemishes',
    category: PortraitCategory.skin,
    ids: [PortraitIds.acne, PortraitIds.freckle, PortraitIds.mole],
  ),
  (
    title: 'Wrinkles',
    category: PortraitCategory.skin,
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
    category: PortraitCategory.face,
    ids: [
      PortraitIds.darkCircles,
      PortraitIds.eyeBags,
      PortraitIds.lidProtect,
      PortraitIds.eyeWhites,
      PortraitIds.iris,
      PortraitIds.redVein,
      PortraitIds.redEye,
      PortraitIds.glare,
    ],
  ),
  (
    title: 'Teeth',
    category: PortraitCategory.face,
    ids: [PortraitIds.teethBrightness, PortraitIds.teethDesaturate],
  ),
  (
    title: 'Makeup',
    category: PortraitCategory.face,
    ids: [PortraitIds.lips, PortraitIds.blush],
  ),
  (
    title: 'Face shape',
    category: PortraitCategory.shape,
    ids: [
      PortraitIds.faceWidth,
      PortraitIds.vShape,
      PortraitIds.chin,
      PortraitIds.eyeSize,
      PortraitIds.noseWidth,
      PortraitIds.mouthSize,
    ],
  ),
  (
    title: 'Background',
    category: PortraitCategory.scene,
    ids: [
      PortraitIds.bgClean,
      PortraitIds.bgUnify,
      PortraitIds.bgUnifyLuminance,
      PortraitIds.strayHairs,
    ],
  ),
  (
    title: 'Clothing',
    category: PortraitCategory.scene,
    ids: [PortraitIds.clothesWrinkles, PortraitIds.clothesLint],
  ),
];

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
    final reveal = ref.watch(revealControlProvider(assetId));
    final category = ui.category;
    final sections = [
      for (final s in kPortraitSections)
        if (s.category == category) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.s4, Sp.s2, Sp.s4, Sp.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RevealTarget(
                assetId: assetId,
                id: 'autoRetouch',
                child: AutoRetouchButton(
                  assetId: assetId,
                  height: touch ? 48 : 40,
                ),
              ),
              const SizedBox(height: Sp.s3),
              PortraitFaceStatus(
                assetId: assetId,
                status: status,
                showFaces: ui.showFaces,
              ),
              if (selected != null) ...[
                const SizedBox(height: Sp.s2),
                FaceTagRow(assetId: assetId, face: selected),
              ],
              const SizedBox(height: Sp.s2),
              Row(
                children: [
                  Text(
                    'Apply to',
                    style: LumenType.caption().copyWith(
                      color: context.tokens.textTertiary,
                    ),
                  ),
                  const SizedBox(width: Sp.s2),
                  Expanded(
                    child: PortraitTargetTabs(assetId: assetId, ui: ui),
                  ),
                ],
              ),
              const SizedBox(height: Sp.s4),
              PortraitCategoryTabs(assetId: assetId, category: category),
            ],
          ),
        ),
        if (category == PortraitCategory.scene)
          BackgroundSwapGroup(assetId: assetId),
        for (final section in sections) ...[
          DevelopGroup(
            key: ValueKey('portrait-${section.title}'),
            title: section.title,
            initiallyOpen: section == sections.first,
            openSignal: revealSignal(reveal, [
              ...section.ids,
              if (section.title == 'Blemishes') 'editSpots',
            ]),
            modified: _modified(portrait, section.ids, target),
            onReset: () => _resetSection(ref, section, target),
            onHoldCompare: (held) {
              final c = ref.read(compareSuppressProvider(assetId).notifier);
              held ? c.hold(section.ids.toSet()) : c.release();
            },
            child: Column(
              children: [
                if (section.title == 'Background')
                  BackdropNote(assetId: assetId),
                if (section.title == 'Clothing') ClothesNote(assetId: assetId),
                if (section.title == 'Skin')
                  SkinPenRow(assetId: assetId, ui: ui, portrait: portrait),
                if (section.title == 'Blemishes')
                  RevealTarget(
                    assetId: assetId,
                    id: 'editSpots',
                    child: _SpotEditRow(
                      assetId: assetId,
                      ui: ui,
                      portrait: portrait,
                    ),
                  ),
                for (final id in section.ids)
                  if (_visible(portrait, id, target))
                    RevealTarget(
                      assetId: assetId,
                      id: id,
                      child: PortraitSlider(
                        key: ValueKey('$id-${target.group}-${target.personId}'),
                        assetId: assetId,
                        param: id,
                        target: target,
                        touch: touch,
                      ),
                    ),
              ],
            ),
          ),
        ],
        if (category == PortraitCategory.shape)
          LiquifyGroup(assetId: assetId, ui: ui),
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
      final spec = PortraitRegistry.byId(id);
      if (spec.scope == PortraitScope.image) {
        p = p.withImageValue(id, spec.defaultValue);
        continue;
      }
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

/// The portrait part that holds control [id] (a slider, 'editSpots', or a
/// tool of the Shape / Scene groups); null for controls shown in every part.
PortraitCategory? categoryOfControl(String id) {
  if (id == 'editSpots') return PortraitCategory.skin;
  for (final s in kPortraitSections) {
    if (s.ids.contains(id)) return s.category;
  }
  return null;
}

/// Skin · Face · Shape · Scene: equal-width tabs across the panel.
class PortraitCategoryTabs extends ConsumerWidget {
  const PortraitCategoryTabs({
    super.key,
    required this.assetId,
    required this.category,
  });

  final String assetId;
  final PortraitCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Container(
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(Rad.md),
      ),
      child: Row(
        children: [
          for (final c in PortraitCategory.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: c == category,
                label: '${c.label} tools',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => ref
                      .read(portraitUiProvider(assetId).notifier)
                      .setCategory(c),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c == category ? t.raised : Colors.transparent,
                        borderRadius: BorderRadius.circular(Rad.md - 3),
                        boxShadow: c == category && t.isLight
                            ? Elevation.e1
                            : null,
                      ),
                      child: Text(
                        c.label,
                        style: LumenType.label().copyWith(
                          color: c == category
                              ? t.textPrimary
                              : t.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
