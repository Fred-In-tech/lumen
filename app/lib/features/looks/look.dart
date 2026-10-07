import 'package:lumen_core/lumen_core.dart';

/// What a look card says it is (the badge).
enum LookKind {
  /// An AI style: a model edits each photo for its light.
  look('Look'),

  /// A preset: the same sliders on every photo.
  preset('Preset'),

  /// A creative LUT on its own.
  lut('LUT');

  const LookKind(this.label);
  final String label;
}

/// Something that gives a whole shoot one look: an AI style (a model
/// edits each photo for its own light), a preset (the same sliders on
/// every photo) or a LUT.
sealed class Look {
  const Look();
  String get name;
  String get id;
  LookKind get kind;

  /// Where it came from: "Built-in", "Imported from Lightroom", …
  String get sourceLabel;
}

final class StyleLook extends Look {
  const StyleLook(this.style);
  final AiStyle style;
  @override
  String get name => style.label;
  @override
  String get id => 'style:${style.id}';
  @override
  LookKind get kind => LookKind.look;
  @override
  String get sourceLabel => 'Built-in';
}

final class PresetLook extends Look {
  const PresetLook(this.preset);
  final Preset preset;
  @override
  String get name => preset.name;
  @override
  String get id => 'preset:${preset.id}';
  @override
  LookKind get kind => preset.isLutOnly ? LookKind.lut : LookKind.preset;
  @override
  String get sourceLabel => switch (preset.source) {
    PresetSource.builtIn => 'Built-in',
    PresetSource.user => 'Saved in the editor',
    PresetSource.lightroom => 'Imported from Lightroom',
    PresetSource.lut => 'Imported LUT',
  };

  /// User and imported presets can be renamed and deleted.
  bool get editable => !preset.builtIn;
}
