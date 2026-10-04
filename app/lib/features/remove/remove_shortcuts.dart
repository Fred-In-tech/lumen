import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/masks/mask_commands.dart' show ProviderReader;
import 'package:lumen/features/remove/remove_ui_state.dart';

/// Single-key Remove shortcuts: `Q` opens the Remove module (Lightroom's
/// spot-removal key; `R` is Crop), and in the module `[` / `]` shrink and
/// grow the brush. The caller filters out key-ups, modifier chords and
/// keys typed into text fields.
KeyEventResult handleRemoveShortcut(
  ProviderReader read,
  String assetId,
  LogicalKeyboardKey key,
) {
  if (key == LogicalKeyboardKey.keyQ) {
    read(editorProvider(assetId).notifier).setCropMode(false);
    read(editorModuleProvider(assetId).notifier).select(EditorModule.remove);
    return KeyEventResult.handled;
  }
  if (read(editorModuleProvider(assetId)) != EditorModule.remove) {
    return KeyEventResult.ignored;
  }
  final ui = read(removeUiProvider(assetId).notifier);
  if (key == LogicalKeyboardKey.bracketLeft) {
    ui.nudgeSize(-1);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.bracketRight) {
    ui.nudgeSize(1);
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
