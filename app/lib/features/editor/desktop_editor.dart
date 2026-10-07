import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/auto_panel.dart';
import 'package:lumen/features/ai/prompt_bar.dart';
import 'package:lumen/features/crop/crop_overlay.dart';
import 'package:lumen/features/develop/develop_panel.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_mode.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/filmstrip.dart';
import 'package:lumen/features/editor/mode_switch.dart';
import 'package:lumen/features/editor/module_overlay.dart';
import 'package:lumen/features/editor/photo_canvas.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/features/info/photo_info_dialog.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';

/// Desktop/tablet-landscape editor shell: a soft grey workspace with the
/// photo in the middle, the Auto | Manual switch on top and one floating
/// panel on the right (DESIGN.md §3.3).
class DesktopEditor extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final id = session.assetId;
    final state = ref.watch(editorProvider(id)).value;
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width >= Layout.wideBreakpoint
        ? Layout.developPanelWide
        : Layout.developPanel;
    final cropMode = state?.cropMode ?? false;
    final module = ref.watch(editorModuleProvider(id));
    final mode = ref.watch(editorModeProvider);
    final auto = mode == EditorMode.auto;
    followManualTools(ref, id);
    final entry = session.entry;
    final imageAspect = entry == null || entry.height == 0
        ? 1.5
        : entry.width / entry.height;

    final canvas = Stack(
      children: [
        Positioned.fill(
          child: PhotoCanvas(
            after: session.renderer.output,
            before: session.renderer.before,
            compare: state?.compare ?? CompareMode.off,
            showingBefore: state?.showingBefore ?? false,
            onHoldBefore: (v) =>
                ref.read(editorProvider(id).notifier).setShowingBefore(v),
            padding: Sp.s6,
            overlay: cropMode
                ? CropOverlay(assetId: id, imageAspect: imageAspect)
                : ModuleOverlay.forModule(module, session: session),
          ),
        ),
        if (state?.aiBusy ?? false)
          Positioned(
            left: Sp.s4,
            top: Sp.s2,
            child: StatusPill(
              label: state?.aiStatus ?? 'Developing…',
              leading: const AiGlyph(size: 14),
              elevated: true,
            ),
          ),
        // The prompt is an AI tool: it belongs to Auto.
        if (auto && !cropMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: Sp.s4,
            child: Center(child: PromptBar(session: session, width: 520)),
          ),
      ],
    );

    final panel = Container(
      margin: const EdgeInsets.only(right: Sp.s3, bottom: Sp.s3),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(Rad.xl),
        border: Border.all(color: t.line),
        boxShadow: Elevation.e1,
      ),
      child: auto
          ? AutoPanel(
              session: session,
              width: panelWidth,
              onManual: () => setEditorMode(ref, id, EditorMode.manual),
              onFineTuneFaces: () =>
                  selectManualTool(ref, id, ManualTool.portrait),
            )
          : DevelopPanel(session: session, width: panelWidth),
    );

    return Column(
      children: [
        _TopBar(session: session, assetIds: assetIds, onClose: onClose),
        Expanded(
          child: Row(
            children: [
              Expanded(child: canvas),
              panel,
            ],
          ),
        ),
        Filmstrip(assetIds: assetIds, current: id, onOpen: onOpen),
      ],
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
      child: Row(
        children: [
          // Equal flexible sides keep the mode switch in the centre.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: LumenButton(
                    label: ref.watch(
                      editorBackLabelProvider(assetIds.join('\n')),
                    ),
                    icon: const Icon(LucideIcons.chevronLeft),
                    kind: ButtonKind.ghost,
                    tooltip: 'Back  G',
                    onPressed: onClose,
                  ),
                ),
                const SizedBox(width: Sp.s2),
                Flexible(
                  child: Text(
                    session.entry?.fileName ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: LumenType.bodyStrong().copyWith(
                      color: t.textPrimary,
                    ),
                  ),
                ),
                if (assetIds.length > 1) ...[
                  const SizedBox(width: Sp.s1_5),
                  Text(
                    '· $pos of ${assetIds.length}',
                    style: LumenType.caption().copyWith(color: t.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          ModeSwitch(assetId: id),
          Expanded(
            child: FittedBox(
              // Narrow windows: shrink the actions rather than overflow.
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  const SizedBox(width: Sp.s1),
                  _CompareButton(assetId: id),
                  const SizedBox(width: Sp.s1),
                  _HistoryButton(assetId: id),
                  const SizedBox(width: Sp.s1),
                  LumenIconButton(
                    icon: LucideIcons.info,
                    tooltip: 'Photo info  I',
                    onPressed: session.entry == null
                        ? null
                        : () => showPhotoInfo(context, session.entry!),
                  ),
                  const SizedBox(width: Sp.s3),
                  LumenButton(
                    label: 'Export',
                    icon: const Icon(LucideIcons.download, size: 14),
                    kind: ButtonKind.primary,
                    onPressed: () async {
                      await ctl.flush();
                      if (context.mounted) {
                        await showExportDialog(context, ref, [id]);
                      }
                    },
                  ),
                ],
              ),
            ),
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
