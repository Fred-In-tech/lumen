import 'portrait.dart';

/// Built-in portrait retouch recipes (Evoto-style one-click retouch).
abstract final class PortraitPresets {
  /// Natural studio retouch for every face. Values sit in the range retouchers
  /// recommend for headshots (eyes 30–50 %, smoothing below the "plastic"
  /// zone), with gentler skin work on children and seniors.
  static const Map<String, double> natural = {
    PortraitIds.skinSoftening: 40,
    PortraitIds.skinEven: 30,
    PortraitIds.skinShine: 30,
    PortraitIds.acne: 80,
    PortraitIds.wrinkleForehead: 30,
    PortraitIds.wrinkleFrown: 30,
    PortraitIds.wrinkleCrowsFeet: 25,
    PortraitIds.wrinkleSmile: 20,
    PortraitIds.wrinkleMarionette: 20,
    PortraitIds.darkCircles: 40,
    PortraitIds.eyeBags: 35,
    PortraitIds.eyeWhites: 35,
    PortraitIds.iris: 30,
    PortraitIds.redVein: 50,
    PortraitIds.teethBrightness: 25,
    PortraitIds.teethDesaturate: 30,
  };

  /// Child skin keeps its texture; seniors keep character lines.
  static const Map<FaceGroup, Map<String, double>> groupOverrides = {
    FaceGroup.child: {
      PortraitIds.skinSoftening: 15,
      PortraitIds.acne: 40,
      PortraitIds.eyeBags: 0,
    },
    FaceGroup.senior: {
      PortraitIds.skinSoftening: 30,
      PortraitIds.eyeBags: 25,
      PortraitIds.wrinkleForehead: 15,
      PortraitIds.wrinkleCrowsFeet: 10,
      PortraitIds.wrinkleSmile: 10,
    },
  };

  /// Applies [natural] to the All group (plus group overrides), keeping any
  /// per-person values and image-scope settings from [current].
  static PortraitSettings autoRetouch(PortraitSettings current) {
    var next = PortraitSettings(
      individuals: current.individuals,
      image: current.image,
    );
    for (final e in natural.entries) {
      next = next.withGroupValue(FaceGroup.all, e.key, e.value);
    }
    for (final g in groupOverrides.entries) {
      for (final e in g.value.entries) {
        next = next.withGroupValue(g.key, e.key, e.value);
      }
    }
    return next;
  }
}
