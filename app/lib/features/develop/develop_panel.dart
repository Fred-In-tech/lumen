import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/crop/crop_panel.dart';
import 'package:lumen/features/develop/histogram_view.dart';
import 'package:lumen/features/develop/sections.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_mode.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/module_overlay.dart';
import 'package:lumen/features/masks/masks_panel.dart';
import 'package:lumen/features/presets/presets_panel.dart';
import 'package:lumen/features/remove/remove_panel.dart';
import 'package:lumen/features/portrait/portrait_panel.dart';
import 'package:lumen/features/search/control_search_dialog.dart';
import 'package:lumen/features/sync/settings_clipboard.dart';
import 'package:lumen/widgets/buttons.dart';
import 'package:lumen/widgets/toast.dart';

/// Right-hand Manual panel (desktop/tablet): histogram, tool tabs, the
/// selected tool's controls, footer.
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
    final tool = ref.watch(manualToolProvider(id));
    final exif = _exifLine(session.entry?.exif);
    final entry = session.entry;
    final imageAspect = entry == null || entry.height == 0
        ? 1.5
        : entry.width / entry.height;
    return SizedBox(
      width: width,
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
                const SizedBox(height: Sp.s1),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exif.isEmpty ? 'No camera data' : exif,
                        overflow: TextOverflow.ellipsis,
                        style: LumenType.monoStyle().copyWith(
                          color: t.textTertiary,
                        ),
                      ),
                    ),
                    LumenIconButton(
                      icon: LucideIcons.search,
                      tooltip: 'Search controls  /',
                      onPressed: () =>
                          showControlSearch(context, ref, id, session: session),
                    ),
                  ],
                ),
                const SizedBox(height: Sp.s2),
                ModuleTabs(assetId: id),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...switch (tool) {
                  ManualTool.adjust => [DevelopSections(assetId: id)],
                  ManualTool.portrait => [PortraitPanel(assetId: id)],
                  ManualTool.masks => [
                    MasksPanel(assetId: id, sourceSize: sourceSizeOf(session)),
                  ],
                  ManualTool.remove => [RemovePanel(assetId: id)],
                  ManualTool.crop => [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Sp.s4,
                        Sp.s2,
                        Sp.s4,
                        0,
                      ),
                      child: CropPanel(assetId: id, imageAspect: imageAspect),
                    ),
                  ],
                  ManualTool.presets => [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Sp.s4,
                        Sp.s2,
                        Sp.s4,
                        0,
                      ),
                      child: PresetsPanel(assetId: id),
                    ),
                  ],
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

/// The tool shown in the Manual panel: an editing module, Crop, or Presets.
enum ManualTool {
  adjust('Adjust', LucideIcons.slidersHorizontal),
  portrait('Portrait', LucideIcons.scanFace),
  masks('Masks', LucideIcons.squareDashed),
  remove('Remove', LucideIcons.eraser),
  crop('Crop', LucideIcons.crop),
  presets('Presets', LucideIcons.swatchBook);

  const ManualTool(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The active Manual tool of one photo, derived from crop mode, the Presets
/// flag and the editing module (so shortcuts that change those move the tab).
final manualToolProvider = Provider.family<ManualTool, String>((ref, assetId) {
  final crop = ref.watch(
    editorProvider(assetId).select((s) => s.value?.cropMode ?? false),
  );
  if (crop) return ManualTool.crop;
  if (ref.watch(presetsOpenProvider(assetId))) return ManualTool.presets;
  return switch (ref.watch(editorModuleProvider(assetId))) {
    EditorModule.adjust => ManualTool.adjust,
    EditorModule.portrait => ManualTool.portrait,
    EditorModule.masks => ManualTool.masks,
    EditorModule.remove => ManualTool.remove,
  };
});

/// Shows [tool] for photo [assetId].
void selectManualTool(WidgetRef ref, String assetId, ManualTool tool) {
  ref
      .read(editorProvider(assetId).notifier)
      .setCropMode(tool == ManualTool.crop);
  ref
      .read(presetsOpenProvider(assetId).notifier)
      .set(tool == ManualTool.presets);
  ref.read(editorModuleProvider(assetId).notifier).select(switch (tool) {
    ManualTool.portrait => EditorModule.portrait,
    ManualTool.masks => EditorModule.masks,
    ManualTool.remove => EditorModule.remove,
    _ => EditorModule.adjust,
  });
}

/// Tool switcher at the top of the Manual panel (Adjust · Portrait · Masks ·
/// Remove · Crop · Presets): equal-width tabs, icon over label. Each tab
/// keeps its tool name as its semantics label and tooltip.
class ModuleTabs extends ConsumerWidget {
  const ModuleTabs({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final tool = ref.watch(manualToolProvider(assetId));
    return Container(
      height: 50,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(Rad.md),
      ),
      child: Row(
        children: [
          for (final m in ManualTool.values)
            Expanded(
              child: _ToolTab(
                tool: m,
                selected: m == tool,
                onTap: () => selectManualTool(ref, assetId, m),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolTab extends StatelessWidget {
  const _ToolTab({
    required this.tool,
    required this.selected,
    required this.onTap,
  });

  final ManualTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.textPrimary : t.textSecondary;
    final body = AnimatedContainer(
      duration: Motion.fast,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? t.raised : Colors.transparent,
        borderRadius: BorderRadius.circular(Rad.md - 3),
        boxShadow: selected && t.isLight ? Elevation.e1 : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(tool.icon, size: 16, color: selected ? t.accent : color),
          const SizedBox(height: 3),
          Text(
            tool.label,
            overflow: TextOverflow.clip,
            softWrap: false,
            maxLines: 1,
            style: LumenType.caption().copyWith(
              fontSize: 10,
              letterSpacing: 0,
              color: color,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: tool.label,
      excludeSemantics: true,
      child: Tooltip(
        message: tool.label,
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(cursor: SystemMouseCursors.click, child: body),
        ),
      ),
    );
  }
}
