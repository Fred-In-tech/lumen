import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lumen/design/tokens.dart';
import 'package:lumen/features/editor/editor_mode.dart';
import 'package:lumen/features/editor/editor_screen.dart';

/// Opens the editor on [assetId]. The filmstrip and arrow keys walk
/// [assetIds] only (the grid the photo was opened from). With [mode] the
/// editor starts in that mode (e.g. Manual to save a preset).
Future<void> openEditor(
  BuildContext context,
  List<String> assetIds,
  String assetId, {
  WidgetRef? ref,
  EditorMode? mode,
}) {
  if (mode != null) ref?.read(editorModeProvider.notifier).select(mode);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: Motion.of(context, Motion.panel),
      pageBuilder: (_, _, _) =>
          EditorScreen(assetIds: assetIds, initialAssetId: assetId),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}
