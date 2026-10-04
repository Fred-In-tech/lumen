import 'dart:ui' show Size, VoidCallback;

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/masks/mask_commands.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/remove/remove_ui_state.dart';
import 'package:lumen/features/search/control_index.dart';
import 'package:lumen/features/search/reveal.dart';

/// Opens [e] in [assetId]'s editor: switches module, reveals the control and
/// performs one-step actions (add a manual mask at [sourceSize], pick a
/// Remove tool, start the spot editor, run Auto edit via [runAuto]).
void openControl(
  ProviderReader read,
  String assetId,
  ControlEntry e, {
  Size sourceSize = const Size(1, 1),
  VoidCallback? runAuto,
}) {
  read(editorProvider(assetId).notifier).setCropMode(false);
  read(editorModuleProvider(assetId).notifier).select(e.module);
  switch (e.kind) {
    case ControlKind.mask:
      final kind = MaskKind.parse(e.id);
      if (!kind.isAi) {
        MaskCommands(read, assetId).add(kind, sourceSize: sourceSize);
      }
    case ControlKind.removeTool:
      read(removeUiProvider(assetId).notifier)
          .setTool(RemoveTool.values.byName(e.id));
    case ControlKind.action when e.id == 'editSpots':
      read(portraitUiProvider(assetId).notifier).setSpotEdit(true);
    case ControlKind.action when e.id == 'auto':
      runAuto?.call();
    case ControlKind.action ||
        ControlKind.developParam ||
        ControlKind.portraitParam:
      break;
  }
  read(revealControlProvider(assetId).notifier).reveal(e);
}
