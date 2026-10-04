import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/ai/ai_panel.dart';
import 'package:lumen/features/ai/prompt_bar.dart';
import 'package:lumen/features/ai/styles_grid.dart';
import 'package:lumen/features/crop/crop_overlay.dart';
import 'package:lumen/features/crop/crop_panel.dart';
import 'package:lumen/features/develop/sections.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/photo_canvas.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/features/presets/presets_panel.dart';
import 'package:lumen/features/portrait/portrait_panel.dart';
import 'package:lumen/widgets/ai_glyph.dart';
import 'package:lumen/widgets/buttons.dart';

enum _Tab {
  ai,
  portrait,
  light,
  color,
  curve,
  grading,
  effects,
  detail,
  crop,
  presets,
}

/// Phone editor: canvas on top, slider sheet + tool tabs below (DESIGN.md §3.4).
class PhoneEditor extends ConsumerStatefulWidget {
  const PhoneEditor({
    super.key,
    required this.session,
    required this.onClose,
    required this.onStep,
  });

  final EditorSession session;
  final VoidCallback onClose;
  final ValueChanged<int> onStep;

  @override
  ConsumerState<PhoneEditor> createState() => _PhoneEditorState();
}

class _PhoneEditorState extends ConsumerState<PhoneEditor> {
  _Tab _tab = _Tab.ai;

  static const _tabs = {
    _Tab.ai: ('AI', LucideIcons.sparkles),
    _Tab.portrait: ('Portrait', LucideIcons.scanFace),
    _Tab.light: ('Light', LucideIcons.sun),
    _Tab.color: ('Color', LucideIcons.palette),
    _Tab.curve: ('Curve', LucideIcons.chartSpline),
    _Tab.grading: ('Grade', LucideIcons.circleDot),
    _Tab.effects: ('Effects', LucideIcons.sparkle),
    _Tab.detail: ('Detail', LucideIcons.scanSearch),
    _Tab.crop: ('Crop', LucideIcons.crop),
    _Tab.presets: ('Presets', LucideIcons.swatchBook),
  };

  void _select(_Tab tab) {
    final ctl = ref.read(editorProvider(widget.session.assetId).notifier);
    ctl.setCropMode(tab == _Tab.crop);
    ref
        .read(editorModuleProvider(widget.session.assetId).notifier)
        .select(
          tab == _Tab.portrait ? EditorModule.portrait : EditorModule.adjust,
        );
    setState(() => _tab = tab);
  }

  Widget _sheet() {
    final id = widget.session.assetId;
    final entry = widget.session.entry;
    final aspect = entry == null || entry.height == 0
        ? 1.5
        : entry.width / entry.height;
    return switch (_tab) {
      _Tab.ai => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AiPanel(session: widget.session, touch: true),
          const SizedBox(height: Sp.s4),
          StylesGrid(session: widget.session, horizontal: true),
          const SizedBox(height: Sp.s3),
          PromptBar(session: widget.session, width: double.infinity),
        ],
      ),
      _Tab.portrait => PortraitPanel(assetId: id, touch: true),
      _Tab.light => DevelopSections(
        assetId: id,
        touch: true,
        only: ParamGroup.light,
      ),
      _Tab.color => DevelopSections(
        assetId: id,
        touch: true,
        only: ParamGroup.color,
      ),
      _Tab.curve => DevelopSections(
        assetId: id,
        touch: true,
        only: ParamGroup.curve,
      ),
      _Tab.grading => DevelopSections(
        assetId: id,
        touch: true,
        only: ParamGroup.grading,
      ),
      _Tab.effects => DevelopSections(
        assetId: id,
        touch: true,
        only: ParamGroup.effects,
      ),
      _Tab.detail => DevelopSections(
        assetId: id,
        touch: true,
        only: ParamGroup.detail,
      ),
      _Tab.crop => CropPanel(assetId: id, imageAspect: aspect, touch: true),
      _Tab.presets => PresetsPanel(assetId: id),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final id = widget.session.assetId;
    final state = ref.watch(editorProvider(id)).value;
    final ctl = ref.read(editorProvider(id).notifier);
    final height = MediaQuery.sizeOf(context).height;
    final entry = widget.session.entry;
    final aspect = entry == null || entry.height == 0
        ? 1.5
        : entry.width / entry.height;
    ref.listen(editorProvider(id).select((s) => s.value?.cropMode ?? false), (
      _,
      crop,
    ) {
      if (crop && _tab != _Tab.crop) setState(() => _tab = _Tab.crop);
      if (!crop && _tab == _Tab.crop) setState(() => _tab = _Tab.light);
    });
    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                LumenIconButton(
                  icon: LucideIcons.x,
                  tooltip: 'Close',
                  size: 44,
                  iconSize: 22,
                  onPressed: widget.onClose,
                ),
                LumenIconButton(
                  icon: LucideIcons.undo2,
                  tooltip: 'Undo',
                  size: 44,
                  iconSize: 20,
                  onPressed: (state?.canUndo ?? false) ? ctl.undo : null,
                ),
                LumenIconButton(
                  icon: LucideIcons.redo2,
                  tooltip: 'Redo',
                  size: 44,
                  iconSize: 20,
                  onPressed: (state?.canRedo ?? false) ? ctl.redo : null,
                ),
                const Spacer(),
                LumenIconButton(
                  icon: LucideIcons.squareSplitHorizontal,
                  tooltip: 'Compare',
                  size: 44,
                  iconSize: 20,
                  selected: state?.compare == CompareMode.split,
                  onPressed: () => ctl.setCompare(
                    state?.compare == CompareMode.split
                        ? CompareMode.off
                        : CompareMode.split,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await ctl.flush();
                    if (context.mounted) {
                      await showExportDialog(context, ref, [id]);
                    }
                  },
                  child: Text(
                    'Export',
                    style: LumenType.button(touch: true)
                        .copyWith(color: t.accent),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v.abs() > 600 && !(state?.cropMode ?? false)) {
                        widget.onStep(v < 0 ? 1 : -1);
                      }
                    },
                    child: PhotoCanvas(
                      after: widget.session.renderer.output,
                      before: widget.session.renderer.before,
                      compare: state?.compare ?? CompareMode.off,
                      showingBefore: state?.showingBefore ?? false,
                      onHoldBefore: ctl.setShowingBefore,
                      padding: Sp.s2,
                      overlay: (state?.cropMode ?? false)
                          ? CropOverlay(assetId: id, imageAspect: aspect)
                          : null,
                    ),
                  ),
                ),
                if (state?.aiBusy ?? false)
                  Positioned(
                    left: Sp.s3,
                    top: Sp.s2,
                    child: StatusPill(
                      label: state?.aiStatus ?? 'Developing…',
                      leading: const AiGlyph(size: 14),
                      elevated: true,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            constraints: BoxConstraints(
              maxHeight: (height * 0.42).clamp(248.0, 420.0),
            ),
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Rad.sheet),
              ),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(Sp.s4, Sp.s3, Sp.s4, Sp.s4),
              children: [_sheet()],
            ),
          ),
          Container(
            height: Layout.phoneTabs,
            decoration: BoxDecoration(
              color: t.surface1,
              border: Border(top: BorderSide(color: t.line)),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in _tabs.entries)
                  Semantics(
                    button: true,
                    selected: e.key == _tab,
                    label: e.value.$1,
                    child: GestureDetector(
                      onTap: () => _select(e.key),
                      child: Container(
                        width: 64,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: e.key == _tab
                                  ? t.accent
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            e.key == _Tab.ai
                                ? const AiGlyph(size: 22)
                                : Icon(
                                    e.value.$2,
                                    size: 22,
                                    color: e.key == _tab
                                        ? t.accent
                                        : t.textSecondary,
                                  ),
                            const SizedBox(height: 4),
                            Text(
                              e.value.$1,
                              style: LumenType.caption().copyWith(
                                color: e.key == _tab
                                    ? t.textPrimary
                                    : t.textSecondary,
                              ),
                            ),
                          ],
                        ),
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
