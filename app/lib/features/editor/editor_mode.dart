import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two ways to edit a photo. Auto is the short AI path (enhance, retouch,
/// looks, a prompt); Manual holds every slider and tool.
enum EditorMode {
  auto('Auto'),
  manual('Manual');

  const EditorMode(this.label);

  final String label;
}

class EditorModeNotifier extends Notifier<EditorMode> {
  @override
  EditorMode build() => EditorMode.auto;

  void select(EditorMode mode) => state = mode;
}

/// The editor mode; kept while moving between photos.
final editorModeProvider = NotifierProvider<EditorModeNotifier, EditorMode>(
  EditorModeNotifier.new,
);

class PresetsOpenNotifier extends Notifier<bool> {
  PresetsOpenNotifier(this.assetId);

  final String assetId;

  @override
  bool build() => false;

  void set(bool open) => state = open;
}

/// Whether the Manual panel of one photo shows Presets (it is a tool tab,
/// not an editing module: no canvas overlay goes with it).
final presetsOpenProvider =
    NotifierProvider.family<PresetsOpenNotifier, bool, String>(
      PresetsOpenNotifier.new,
    );
