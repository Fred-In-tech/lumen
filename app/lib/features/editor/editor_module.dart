import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Top-level editing module shown in the right panel (Evoto-style module tabs).
/// The active module also decides which canvas overlay is live (face boxes for
/// Portrait, handles for Masks, a brush for Remove).
enum EditorModule {
  adjust('Adjust', LucideIcons.slidersHorizontal),
  portrait('Portrait', LucideIcons.scanFace),
  masks('Masks', LucideIcons.squareDashed),
  remove('Remove', LucideIcons.eraser);

  const EditorModule(this.label, this.icon);

  final String label;
  final IconData icon;
}

class EditorModuleNotifier extends Notifier<EditorModule> {
  EditorModuleNotifier(this.assetId);

  final String assetId;

  @override
  EditorModule build() => EditorModule.adjust;

  void select(EditorModule module) => state = module;
}

/// The active module for one open photo.
final editorModuleProvider =
    NotifierProvider.family<EditorModuleNotifier, EditorModule, String>(
      EditorModuleNotifier.new,
    );
