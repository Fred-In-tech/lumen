import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_mode.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/widgets/ai_glyph.dart';

/// Switches the editor of photo [assetId] to [mode]. Going back to Auto puts
/// the canvas tools away (crop, masks, portrait and remove are Manual tools).
void setEditorMode(WidgetRef ref, String assetId, EditorMode mode) {
  if (mode == EditorMode.auto) {
    ref.read(editorProvider(assetId).notifier).setCropMode(false);
    ref.read(presetsOpenProvider(assetId).notifier).set(false);
    ref
        .read(editorModuleProvider(assetId).notifier)
        .select(EditorModule.adjust);
  }
  ref.read(editorModeProvider.notifier).select(mode);
}

/// Moves to Manual whenever something only Manual shows becomes active: a
/// module shortcut (M, Q) or crop (R).
/// Call from a widget's `build`.
void followManualTools(WidgetRef ref, String assetId) {
  void manual() =>
      ref.read(editorModeProvider.notifier).select(EditorMode.manual);
  ref
    ..listen(editorModuleProvider(assetId), (_, m) {
      if (m != EditorModule.adjust) manual();
    })
    ..listen(
      editorProvider(assetId).select((s) => s.value?.cropMode ?? false),
      (_, crop) {
        if (crop) manual();
      },
    );
}

/// The Auto | Manual pill.
class ModeSwitch extends ConsumerWidget {
  const ModeSwitch({super.key, required this.assetId, this.touch = false});

  final String assetId;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final mode = ref.watch(editorModeProvider);
    Widget segment(EditorMode m) {
      final selected = m == mode;
      final fg = selected ? t.textPrimary : t.textSecondary;
      return Semantics(
        button: true,
        selected: selected,
        label: '${m.label} mode',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => setEditorMode(ref, assetId, m),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: Motion.fast,
              height: touch ? 36 : 32,
              padding: EdgeInsets.symmetric(horizontal: touch ? Sp.s5 : Sp.s4),
              decoration: BoxDecoration(
                color: selected ? t.raised : Colors.transparent,
                borderRadius: BorderRadius.circular(Rad.pill),
                boxShadow: selected && t.isLight ? Elevation.e1 : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  m == EditorMode.auto
                      ? AiGlyph(size: 14, neutral: !selected)
                      : Icon(
                          LucideIcons.slidersHorizontal,
                          size: 14,
                          color: selected ? t.accent : fg,
                        ),
                  const SizedBox(width: Sp.s1_5),
                  Text(
                    m.label,
                    style: LumenType.button(touch: touch).copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(Rad.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [segment(EditorMode.auto), segment(EditorMode.manual)],
      ),
    );
  }
}
