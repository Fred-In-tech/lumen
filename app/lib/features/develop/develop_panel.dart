import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/ai_panel.dart';
import 'package:lumen/features/develop/histogram_view.dart';
import 'package:lumen/features/develop/sections.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/module_overlay.dart';
import 'package:lumen/features/masks/masks_panel.dart';
import 'package:lumen/features/remove/remove_panel.dart';
import 'package:lumen/features/portrait/portrait_panel.dart';
import 'package:lumen/features/search/control_search_dialog.dart';
import 'package:lumen/features/sync/settings_clipboard.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Right-hand develop panel (desktop/tablet): histogram, AI, groups, footer.
class DevelopPanel extends ConsumerWidget {
  const DevelopPanel({super.key, required this.session, required this.width});

  final EditorSession session;
  final double width;

  String _exifLine(ExifSummary? e) {
    if (e == null || e.isEmpty) return '';
    return [
      if (e.aperture != null)
        'f/${e.aperture!.toStringAsFixed(e.aperture! < 10 ? 1 : 0)}',
      if (e.shutter != null) '${e.shutter} s',
      if (e.iso != null) 'ISO ${e.iso}',
      if (e.focalMm != null) '${e.focalMm!.round()} mm',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final id = session.assetId;
    final module = ref.watch(editorModuleProvider(id));
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border(left: BorderSide(color: t.line)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.s4, Sp.s3, Sp.s4, Sp.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<Histogram?>(
                  valueListenable: session.histogram,
                  builder: (_, h, _) => HistogramView(histogram: h),
                ),
                const SizedBox(height: Sp.s1_5),
                Text(
                  _exifLine(session.entry?.exif),
                  style: LumenType.monoStyle().copyWith(color: t.textTertiary),
                ),
                const SizedBox(height: Sp.s3),
                Row(
                  children: [
                    Expanded(child: ModuleTabs(assetId: id)),
                    const SizedBox(width: Sp.s1),
                    LumenIconButton(
                      icon: LucideIcons.search,
                      tooltip: 'Search controls  /',
                      onPressed: () =>
                          showControlSearch(context, ref, id, session: session),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...switch (module) {
                  EditorModule.adjust => [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Sp.s4,
                        Sp.s1,
                        Sp.s4,
                        Sp.s4,
                      ),
                      child: AiPanel(session: session),
                    ),
                    DevelopSections(assetId: id),
                  ],
                  EditorModule.portrait => [PortraitPanel(assetId: id)],
                  EditorModule.masks => [
                    MasksPanel(assetId: id, sourceSize: sourceSizeOf(session)),
                  ],
                  EditorModule.remove => [RemovePanel(assetId: id)],
                },
                const SizedBox(height: Sp.s6),
              ],
            ),
          ),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: Sp.s3),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.line)),
            ),
            child: Row(
              children: [
                LumenButton(
                  label: 'Copy',
                  kind: ButtonKind.ghost,
                  onPressed: () => copySettings(context, ref, id),
                ),
                LumenButton(
                  label: 'Paste',
                  kind: ButtonKind.ghost,
                  onPressed: () => pasteSettingsInto(context, ref, id),
                ),
                // Takes the rest of the row; the label ellipsizes rather
                // than overflow when the panel is at its narrowest.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: LumenButton(
                      label: 'Reset all',
                      onPressed: () {
                        ref.read(editorProvider(id).notifier).resetAll();
                        showToast(
                          context,
                          'Reset all edits.',
                          actionLabel: 'Undo',
                          onAction: () =>
                              ref.read(editorProvider(id).notifier).undo(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Module switcher at the top of the right panel (Adjust · Portrait · …):
/// equal-width segments with icon and label, icon-only (with a tooltip)
/// when the panel is too narrow for the labels. Each segment keeps its
/// module name as its semantics label.
class ModuleTabs extends ConsumerWidget {
  const ModuleTabs({super.key, required this.assetId});

  final String assetId;

  /// Below this width per segment the labels are dropped.
  static const minLabelledSegment = 76.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final module = ref.watch(editorModuleProvider(assetId));
    final select = ref.read(editorModuleProvider(assetId).notifier).select;
    const modules = EditorModule.values;
    return LayoutBuilder(
      builder: (context, c) {
        final labelled =
            (c.maxWidth - 4) / modules.length >= minLabelledSegment;
        return Container(
          height: 30,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(Rad.sm),
          ),
          child: Row(
            children: [
              for (final m in modules)
                Expanded(
                  child: _ModuleSegment(
                    module: m,
                    selected: m == module,
                    labelled: labelled,
                    onTap: () => select(m),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ModuleSegment extends StatelessWidget {
  const _ModuleSegment({
    required this.module,
    required this.selected,
    required this.labelled,
    required this.onTap,
  });

  final EditorModule module;
  final bool selected;
  final bool labelled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.textPrimary : t.textSecondary;
    final body = AnimatedContainer(
      duration: Motion.fast,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? t.surface3 : Colors.transparent,
        borderRadius: BorderRadius.circular(Rad.sm - 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(module.icon, size: 14, color: selected ? t.accent : color),
          if (labelled) ...[
            const SizedBox(width: Sp.s1),
            Flexible(
              child: Text(
                module.label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: LumenType.label().copyWith(color: color),
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: module.label,
      excludeSemantics: true,
      child: Tooltip(
        message: labelled ? '' : module.label,
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(cursor: SystemMouseCursors.click, child: body),
        ),
      ),
    );
  }
}
