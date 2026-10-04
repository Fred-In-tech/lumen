import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/prompt_bar.dart';
import 'package:lumen/features/ai/styles_grid.dart';
import 'package:lumen/features/crop/crop_overlay.dart';
import 'package:lumen/features/crop/crop_panel.dart';
import 'package:lumen/features/develop/develop_panel.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/filmstrip.dart';
import 'package:lumen/features/editor/module_overlay.dart';
import 'package:lumen/features/editor/photo_canvas.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/features/presets/presets_panel.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';

enum _Flyout { ai, presets }

/// Desktop/tablet-landscape editor shell (DESIGN.md §3.3).
class DesktopEditor extends ConsumerStatefulWidget {
  const DesktopEditor({
    super.key,
    required this.session,
    required this.assetIds,
    required this.onClose,
    required this.onOpen,
  });

  final EditorSession session;
  final List<String> assetIds;
  final VoidCallback onClose;
  final ValueChanged<String> onOpen;

  @override
  ConsumerState<DesktopEditor> createState() => _DesktopEditorState();
}

class _DesktopEditorState extends ConsumerState<DesktopEditor> {
  _Flyout? _flyout = _Flyout.ai;

  void _toggle(_Flyout f) => setState(() => _flyout = _flyout == f ? null : f);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final id = widget.session.assetId;
    final state = ref.watch(editorProvider(id)).value;
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width >= Layout.wideBreakpoint
        ? Layout.developPanelWide
        : Layout.developPanel;
    final cropMode = state?.cropMode ?? false;
    final module = ref.watch(editorModuleProvider(id));
    final entry = widget.session.entry;
    final imageAspect = entry == null || entry.height == 0
        ? 1.5
        : entry.width / entry.height;
    final flyoutDocked = width >= 1280;

    final flyout = _flyout == null || cropMode
        ? null
        : Container(
            width: Layout.flyout,
            decoration: BoxDecoration(
              color: t.surface1,
              border: Border(right: BorderSide(color: t.line)),
              boxShadow: flyoutDocked ? null : Elevation.e2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Sp.s4,
                    Sp.s3,
                    Sp.s2,
                    Sp.s2,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _flyout == _Flyout.ai ? 'AI Studio' : 'Presets',
                          style: LumenType.title().copyWith(
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      LumenIconButton(
                        icon: LucideIcons.x,
                        tooltip: 'Close',
                        onPressed: () => setState(() => _flyout = null),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Sp.s4, 0, Sp.s4, Sp.s4),
                    children: [
                      if (_flyout == _Flyout.ai) ...[
                        Text(
                          'Styles',
                          style: LumenType.caption().copyWith(
                            color: t.textTertiary,
                          ),
                        ),
                        const SizedBox(height: Sp.s2),
                        StylesGrid(session: widget.session),
                        const SizedBox(height: Sp.s4),
                        Text(
                          'Each style is the AI’s edit for this photo, set as sliders you can change.',
                          style: LumenType.body().copyWith(
                            color: t.textTertiary,
                          ),
                        ),
                      ] else
                        PresetsPanel(assetId: id),
                    ],
                  ),
                ),
              ],
            ),
          );

    final canvas = Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: t.surface0,
            child: PhotoCanvas(
              after: widget.session.renderer.output,
              before: widget.session.renderer.before,
              compare: state?.compare ?? CompareMode.off,
              showingBefore: state?.showingBefore ?? false,
              onHoldBefore: (v) =>
                  ref.read(editorProvider(id).notifier).setShowingBefore(v),
              padding: Sp.s6,
              overlay: cropMode
                  ? CropOverlay(assetId: id, imageAspect: imageAspect)
                  : ModuleOverlay.forModule(module, session: widget.session),
            ),
          ),
        ),
        if (state?.aiBusy ?? false)
          Positioned(
            left: Sp.s3,
            top: Sp.s3,
            child: StatusPill(
              label: state?.aiStatus ?? 'Developing…',
              leading: const AiGlyph(size: 14),
              elevated: true,
            ),
          ),
        if (!cropMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: Sp.s6,
            child: Center(
              child: PromptBar(session: widget.session, width: 520),
            ),
          ),
        if (!flyoutDocked && flyout != null)
          Positioned(left: 0, top: 0, bottom: 0, child: flyout),
      ],
    );

    return Column(
      children: [
        _TopBar(
          session: widget.session,
          assetIds: widget.assetIds,
          onClose: widget.onClose,
        ),
        Expanded(
          child: Row(
            children: [
              _Rail(
                active: cropMode ? null : _flyout,
                cropMode: cropMode,
                masksActive: !cropMode && module == EditorModule.masks,
                onAi: () => _toggle(_Flyout.ai),
                onPresets: () => _toggle(_Flyout.presets),
                onMasks: () {
                  ref.read(editorProvider(id).notifier).setCropMode(false);
                  ref
                      .read(editorModuleProvider(id).notifier)
                      .select(
                        module == EditorModule.masks && !cropMode
                            ? EditorModule.adjust
                            : EditorModule.masks,
                      );
                },
                onCrop: () => ref
                    .read(editorProvider(id).notifier)
                    .setCropMode(!cropMode),
                onLibrary: widget.onClose,
              ),
              if (flyoutDocked && flyout != null) flyout,
              Expanded(child: canvas),
              if (cropMode)
                Container(
                  width: panelWidth,
                  padding: const EdgeInsets.all(Sp.s4),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    border: Border(left: BorderSide(color: t.line)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Crop & geometry',
                          style: LumenType.title().copyWith(
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: Sp.s4),
                        CropPanel(assetId: id, imageAspect: imageAspect),
                      ],
                    ),
                  ),
                )
              else
                DevelopPanel(session: widget.session, width: panelWidth),
            ],
          ),
        ),
        Filmstrip(
          assetIds: widget.assetIds,
          current: id,
          onOpen: widget.onOpen,
        ),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.active,
    required this.cropMode,
    required this.masksActive,
    required this.onAi,
    required this.onPresets,
    required this.onMasks,
    required this.onCrop,
    required this.onLibrary,
  });

  final _Flyout? active;
  final bool cropMode;
  final bool masksActive;
  final VoidCallback onAi;
  final VoidCallback onPresets;
  final VoidCallback onMasks;
  final VoidCallback onCrop;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget item(Widget icon, String tip, bool selected, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.s1),
          child: Stack(
            children: [
              Pressable(
                onTap: onTap,
                tooltip: tip,
                semanticLabel: tip,
                builder: (context, states) => Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? t.accentTint
                        : (states.contains(WidgetState.hovered)
                              ? t.hoverOverlay
                              : Colors.transparent),
                    borderRadius: BorderRadius.circular(Rad.sm),
                  ),
                  child: Center(child: icon),
                ),
              ),
              if (selected)
                Positioned(
                  left: -8,
                  top: 12,
                  child: Container(width: 2, height: 16, color: t.accent),
                ),
            ],
          ),
        );
    Icon ic(IconData i, bool sel) =>
        Icon(i, size: 18, color: sel ? t.accent : t.textSecondary);
    return Container(
      width: Layout.rail,
      padding: const EdgeInsets.only(top: Sp.s2),
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border(right: BorderSide(color: t.line)),
      ),
      child: Column(
        children: [
          item(
            ic(LucideIcons.layoutGrid, false),
            'Library  G',
            false,
            onLibrary,
          ),
          item(
            const AiGlyph(size: 18),
            'AI Studio',
            active == _Flyout.ai,
            onAi,
          ),
          item(
            ic(LucideIcons.swatchBook, active == _Flyout.presets),
            'Presets',
            active == _Flyout.presets,
            onPresets,
          ),
          item(
            ic(EditorModule.masks.icon, masksActive),
            'Masks  M',
            masksActive,
            onMasks,
          ),
          item(
            ic(LucideIcons.crop, cropMode),
            'Crop & geometry  R',
            cropMode,
            onCrop,
          ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.session,
    required this.assetIds,
    required this.onClose,
  });

  final EditorSession session;
  final List<String> assetIds;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final id = session.assetId;
    final state = ref.watch(editorProvider(id)).value;
    final ctl = ref.read(editorProvider(id).notifier);
    final platform = ref.watch(platformInfoProvider);
    final pos = assetIds.indexOf(id) + 1;
    return Container(
      height: Layout.topBar,
      padding: EdgeInsets.only(
        left: platform.isMacOS ? 78 : Sp.s3,
        right: Sp.s3,
      ),
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          LumenButton(
            label: 'Library',
            icon: const Icon(LucideIcons.chevronLeft),
            kind: ButtonKind.ghost,
            onPressed: onClose,
          ),
          const SizedBox(width: Sp.s3),
          Flexible(
            child: Text(
              session.entry?.fileName ?? '',
              overflow: TextOverflow.ellipsis,
              style: LumenType.bodyStrong().copyWith(color: t.textPrimary),
            ),
          ),
          if (assetIds.length > 1) ...[
            const SizedBox(width: Sp.s1_5),
            Text(
              '· $pos of ${assetIds.length}',
              style: LumenType.caption().copyWith(color: t.textTertiary),
            ),
          ],
          const SizedBox(width: Sp.s4),
          LumenIconButton(
            icon: LucideIcons.undo2,
            tooltip: 'Undo',
            onPressed: (state?.canUndo ?? false) ? ctl.undo : null,
          ),
          LumenIconButton(
            icon: LucideIcons.redo2,
            tooltip: 'Redo',
            onPressed: (state?.canRedo ?? false) ? ctl.redo : null,
          ),
          const Spacer(),
          _CompareButton(assetId: id),
          const SizedBox(width: Sp.s1),
          _HistoryButton(assetId: id),
          const SizedBox(width: Sp.s3),
          LumenButton(
            label: 'Export',
            kind: ButtonKind.primary,
            onPressed: () async {
              await ctl.flush();
              if (context.mounted) await showExportDialog(context, ref, [id]);
            },
          ),
        ],
      ),
    );
  }
}

class _CompareButton extends ConsumerWidget {
  const _CompareButton({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      editorProvider(assetId)
          .select((s) => s.value?.compare ?? CompareMode.off),
    );
    final ctl = ref.read(editorProvider(assetId).notifier);
    return PopupMenuButton<CompareMode>(
      tooltip: 'Compare (hold \\ for before)',
      color: context.tokens.surface3,
      initialValue: mode,
      onSelected: ctl.setCompare,
      itemBuilder: (_) => [
        for (final (m, label) in [
          (CompareMode.off, 'Off'),
          (CompareMode.split, 'Split wipe  Y'),
          (CompareMode.sideBySide, 'Side by side'),
        ])
          PopupMenuItem(
            value: m,
            child: Text(
              label,
              style: LumenType.body().copyWith(
                color: context.tokens.textPrimary,
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(Sp.s1_5),
        child: Icon(
          LucideIcons.squareSplitHorizontal,
          size: 18,
          color: mode == CompareMode.off
              ? context.tokens.textSecondary
              : context.tokens.accent,
        ),
      ),
    );
  }
}

class _HistoryButton extends ConsumerWidget {
  const _HistoryButton({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final history = ref.watch(
      editorProvider(assetId)
          .select((s) => s.value?.history ?? HistoryStack.empty),
    );
    final ctl = ref.read(editorProvider(assetId).notifier);
    return PopupMenuButton<int>(
      tooltip: 'History',
      color: t.surface3,
      onSelected: (target) {
        final cursor =
            ref.read(editorProvider(assetId)).value?.history.cursor ?? 0;
        if (target < cursor) {
          for (var i = cursor; i > target; i--) {
            ctl.undo();
          }
        } else {
          for (var i = cursor; i < target; i++) {
            ctl.redo();
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 0,
          child: Text(
            'Original',
            style: LumenType.body().copyWith(color: t.textSecondary),
          ),
        ),
        for (var i = 0; i < history.entries.length; i++)
          PopupMenuItem(
            value: i + 1,
            child: Row(
              children: [
                if (history.entries[i].kind == HistoryKind.ai ||
                    history.entries[i].kind == HistoryKind.instruction) ...[
                  const AiGlyph(size: 12),
                  const SizedBox(width: Sp.s1_5),
                ],
                Expanded(
                  child: Text(
                    history.entries[i].label,
                    style: LumenType.body().copyWith(
                      color: i < history.cursor
                          ? t.textPrimary
                          : t.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ].reversed.toList(),
      child: Padding(
        padding: const EdgeInsets.all(Sp.s1_5),
        child: Icon(LucideIcons.history, size: 18, color: t.textSecondary),
      ),
    );
  }
}
