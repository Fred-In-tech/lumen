import 'develop_settings.dart';
import 'param_registry.dart';

/// Groups used by copy/paste, sync and "save preset from settings".
enum SettingsGroup {
  light,
  color,
  presence,
  hsl,
  bw,
  curve,
  grading,
  detail,
  effects,
  geometry,
  masks,
  portrait,
  heal,
  liquify;

  /// Default selection of the copy dialog: everything except geometry,
  /// masks, heal ops and liquify strokes (those are image-specific).
  static const Set<SettingsGroup> defaultCopy = {
    light, color, presence, hsl, bw, curve, grading, detail, effects, //
    portrait,
  };

  static SettingsGroup forParam(ParamId id) =>
      switch (ParamRegistry.byId(id).group) {
        ParamGroup.light => light,
        ParamGroup.color => color,
        ParamGroup.presence => presence,
        ParamGroup.hsl => hsl,
        ParamGroup.bw => bw,
        ParamGroup.curve => curve,
        ParamGroup.grading => grading,
        ParamGroup.detail => detail,
        ParamGroup.effects => effects,
      };

  bool contains(ParamId id) => forParam(id) == this;

  String get label => switch (this) {
    light => 'Light',
    color => 'Color',
    presence => 'Presence',
    hsl => 'HSL',
    bw => 'Black & white',
    curve => 'Tone curve',
    grading => 'Color grading',
    detail => 'Detail',
    effects => 'Effects',
    geometry => 'Crop & geometry',
    masks => 'Masks',
    portrait => 'Portrait retouch',
    heal => 'Heal & remove',
    liquify => 'Liquify',
  };
}

/// Copies the [groups] of [source] onto [target]; everything else is kept.
DevelopSettings pasteSettings({
  required DevelopSettings source,
  required DevelopSettings target,
  required Set<SettingsGroup> groups,
}) {
  final values = <ParamId, double>{
    for (final spec in ParamRegistry.all)
      if (groups.contains(SettingsGroup.forParam(spec.id)))
        spec.id: source.value(spec.id),
  };
  return target
      .withValues(values)
      .copyWith(
        curves: groups.contains(SettingsGroup.curve) ? source.curves : null,
        treatment: groups.contains(SettingsGroup.bw) ? source.treatment : null,
        geometry: groups.contains(SettingsGroup.geometry)
            ? source.geometry
            : null,
        masks: groups.contains(SettingsGroup.masks) ? source.masks : null,
        portrait: groups.contains(SettingsGroup.portrait)
            ? source.portrait.withSpots(target.portrait.spots)
            : null,
        heal: groups.contains(SettingsGroup.heal) ? source.heal : null,
        liquify: groups.contains(SettingsGroup.liquify) ? source.liquify : null,
      );
}
