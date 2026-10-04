import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

/// Display data for each [MaskKind]: menu label, short name and icon
/// (DESIGN.md §2.11: Brush / Linear / Radial = paintbrush /
/// rectangleHorizontal / circleDashed).
extension MaskKindDisplay on MaskKind {
  /// Menu and history label ("Add Linear gradient").
  String get menuLabel => switch (this) {
    MaskKind.linear => 'Linear gradient',
    MaskKind.radial => 'Radial gradient',
    MaskKind.brush => 'Brush',
    MaskKind.subject => 'Subject',
    MaskKind.person => 'Person',
    MaskKind.background => 'Background',
    MaskKind.faceSkin => 'Face skin',
    MaskKind.sky => 'Sky',
    MaskKind.unsupported => 'Newer mask',
  };

  /// Base of a new mask's name ("Linear 2").
  String get shortName => switch (this) {
    MaskKind.linear => 'Linear',
    MaskKind.radial => 'Radial',
    _ => menuLabel,
  };

  IconData get icon => switch (this) {
    MaskKind.linear => LucideIcons.rectangleHorizontal,
    MaskKind.radial => LucideIcons.circleDashed,
    MaskKind.brush => LucideIcons.paintbrush,
    MaskKind.subject => LucideIcons.userRound,
    MaskKind.person => LucideIcons.personStanding,
    MaskKind.background => LucideIcons.image,
    MaskKind.faceSkin => LucideIcons.scanFace,
    MaskKind.sky => LucideIcons.cloudSun,
    MaskKind.unsupported => LucideIcons.circleOff,
  };
}

/// Manual kinds, in "Add mask" menu order.
const List<MaskKind> kManualMaskKinds = [
  MaskKind.linear,
  MaskKind.radial,
  MaskKind.brush,
];

/// AI kinds, in "Add mask" menu order.
const List<MaskKind> kAiMaskKinds = [
  MaskKind.subject,
  MaskKind.person,
  MaskKind.background,
  MaskKind.faceSkin,
  MaskKind.sky,
];

/// The 12 local sliders grouped the Lightroom way. Covers [kLocalParams]
/// exactly (guarded by a test).
const List<({String title, List<ParamId> ids})> kLocalSliderGroups = [
  (
    title: 'Light',
    ids: [P.exposure, P.contrast, P.highlights, P.shadows, P.whites, P.blacks],
  ),
  (title: 'Color', ids: [P.temp, P.tint, P.saturation]),
  (title: 'Effects', ids: [P.texture, P.clarity, P.dehaze]),
];
