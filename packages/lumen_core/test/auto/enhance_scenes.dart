// Synthetic people scenes for the Auto Enhance tests: painted from skin
// reflectances (deep … light), a light level and an illuminant colour, so
// every scene has a known "right answer".
import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_core/src/testing/synthetic_scenes.dart';

export 'package:lumen_core/src/testing/synthetic_scenes.dart' show Lin;

/// Plausible linear skin reflectances, deep to light (Monk-scale-like).
abstract final class Skin {
  static const Lin deep = (0.13, 0.075, 0.05);
  static const Lin brown = (0.25, 0.14, 0.085);
  static const Lin tan = (0.42, 0.26, 0.17);
  static const Lin light = (0.58, 0.40, 0.30);

  static const all = {'deep': deep, 'brown': brown, 'tan': tan, 'light': light};
}

/// One painted face: where it is and what it is made of.
class PaintedFace {
  const PaintedFace(this.skin, {this.u = 0.5, this.v = 0.4, this.size = 1});

  final Lin skin;
  final double u;
  final double v;
  final double size;

  double get ru => 0.085 * size;
  double get rv => 0.14 * size;

  /// The detector-style box around the face oval.
  FaceBox get box => FaceBox(u - ru, v - rv, 2 * ru, 2 * rv);
}

class PeopleScene {
  const PeopleScene(this.image, this.faces, this.neutral, {this.exif});

  final RgbaBuffer image;
  final List<FaceBox> faces;

  /// A patch that is neutral grey in the un-cast scene.
  final PixelRect neutral;
  final ExifSummary? exif;
}

/// Paints people in a room. [stops] under/over-exposes the whole frame,
/// [light] is the illuminant colour, [wall] the background reflectance and
/// [shirt] the clothing reflectance (0.85 = a white shirt: a white reference).
PeopleScene paintPeople(
  List<PaintedFace> people, {
  double stops = 0,
  Lin light = (1, 1, 1),
  double wall = 0.35,
  double shirt = 0.85,
  double hair = 0.012,
  ExifSummary? exif,
  int seed = 7,
}) {
  final p = ScenePainter(512);
  final gain = math.pow(2, stops).toDouble();
  Lin shade(double u, double v) {
    for (final f in people) {
      if (inEllipse(u, v, f.u, f.v, f.ru, f.rv)) {
        // Lit from the left: the far cheek falls off, a soft form shadow.
        final side = ((u - f.u) / f.ru).clamp(-1.0, 1.0);
        final k = 1.0 - 0.22 * math.max(0.0, side) + 0.06 * math.min(0.0, side);
        return tinted(k, f.skin);
      }
    }
    for (final f in people) {
      if (inEllipse(u, v, f.u, f.v - 0.3 * f.rv, 1.35 * f.ru, 1.3 * f.rv)) {
        return gray(hair);
      }
      if (inEllipse(u, v, f.u, f.v + 2.6 * f.rv, 2.4 * f.ru, 1.6 * f.rv)) {
        return gray(shirt * (0.92 + 0.08 * math.sin(u * 60)));
      }
    }
    if (inRect(u, v, 0.03, 0.05, 0.13, 0.2)) return gray(0.18);
    if (inRect(u, v, 0.85, 0.7, 0.97, 0.95)) return gray(0.004);
    return gray(wall * (0.85 + 0.3 * v));
  }

  return PeopleScene(
    p.paint(
      shade,
      noise: 0.6,
      seed: seed,
      gains: (light.$1 * gain, light.$2 * gain, light.$3 * gain),
    ),
    [for (final f in people) f.box],
    p.rect(0.04, 0.06, 0.12, 0.19),
    exif: exif,
  );
}

/// What one face looks like in [image], located on [source].
List<SkinReading> skinOf(RgbaBuffer image, PeopleScene source) {
  final src = LinearPixels.fromRgba(source.image);
  final px = LinearPixels.fromRgba(image);
  return [
    for (final r in SkinRegions.locate(src, source.faces))
      SkinReading.of(px, r),
  ];
}

/// A run of the local engine on [scene] plus its CPU reference render.
class EnhanceRun {
  const EnhanceRun(this.scene, this.outcome, this.rendered);

  final PeopleScene scene;
  final AutoEditOutcome outcome;
  final RgbaBuffer rendered;

  double v(ParamId id) => outcome.settings.value(id);
  List<SkinReading> get before => skinOf(scene.image, scene);
  List<SkinReading> get after => skinOf(rendered, scene);
}

Future<EnhanceRun> enhance(
  PeopleScene scene, {
  AiStyle style = AiStyle.natural,
  bool withFaces = true,
}) async {
  final outcome = await const LocalAutoEditProvider().autoEdit(
    AutoEditInput(
      stats: ImageStats.compute(scene.image),
      exif: scene.exif,
      proxy: scene.image,
      style: style,
      faces: withFaces ? scene.faces : const [],
    ),
  );
  return EnhanceRun(
    scene,
    outcome,
    renderReference(scene.image, outcome.settings),
  );
}
