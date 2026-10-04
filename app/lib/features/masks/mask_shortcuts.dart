import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/masks/mask_commands.dart';
import 'package:lumen/features/masks/mask_ui_state.dart';
import 'package:lumen/widgets/toast.dart';

/// Single-key Masks shortcuts (DESIGN.md §6.3): `M` opens the Masks module,
/// `O` toggles the selected mask's overlay and `Delete`/`Backspace` removes
/// the selected mask. The caller filters out key-ups, modifier chords and
/// keys typed into text fields.
KeyEventResult handleMaskShortcut(
  ProviderReader read,
  String assetId,
  LogicalKeyboardKey key, {
  BuildContext? context,
}) {
  if (key == LogicalKeyboardKey.keyM) {
    read(editorProvider(assetId).notifier).setCropMode(false);
    read(editorModuleProvider(assetId).notifier).select(EditorModule.masks);
    return KeyEventResult.handled;
  }
  if (read(editorModuleProvider(assetId)) != EditorModule.masks) {
    return KeyEventResult.ignored;
  }
  if (key == LogicalKeyboardKey.keyO) {
    read(maskUiProvider(assetId).notifier).toggleOverlay();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
    final cmds = MaskCommands(read, assetId);
    final selected = read(maskUiProvider(assetId)).selectedIn(cmds.masks);
    if (selected == null) return KeyEventResult.ignored;
    cmds.delete(selected.id);
    if (context != null && context.mounted) {
      showToast(
        context,
        'Deleted ${selected.name}.',
        actionLabel: 'Undo',
        onAction: read(editorProvider(assetId).notifier).undo,
      );
    }
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
