import '../model/exif_summary.dart';
import 'auto_edit_provider.dart';
import 'enhance_constants.dart';
import 'frame_measure.dart';
import 'skin_bands.dart';

typedef _C = EnhanceConstants;

/// Which per-scene limits apply (research 09 §2.11 table).
enum SceneKind { portrait, group, other }

/// Rule-based scene flags (research 09 §2.3), read from the unedited frame.
class EnhanceScene {
  const EnhanceScene({
    required this.kind,
    required this.faceArea,
    required this.smallFaces,
    required this.backlit,
    required this.highKey,
    required this.lowKey,
    required this.night,
    required this.warmIntent,
    required this.alreadyEdited,
  });

  factory EnhanceScene.classify({
    required FrameMeasure frame,
    required List<FaceRead> faces,
    ExifSummary? exif,
    SceneInfo? hints,
  }) {
    final area = faces.fold(0.0, (s, f) => s + f.region.areaFraction);
    final widest = faces.fold(
      0.0,
      (s, f) => f.region.widthFraction > s ? f.region.widthFraction : s,
    );
    final portrait =
        faces.isNotEmpty &&
        (area >= _C.portraitArea || widest >= _C.portraitFaceWidth);
    final many =
        faces.where((f) => f.region.weight > _C.groupFaceWeight).length >= 3;
    final skinY = faces.fold(0.0, (s, f) => s + f.region.weight * f.skin.litY);
    return EnhanceScene(
      kind: many
          ? SceneKind.group
          : portrait
          ? SceneKind.portrait
          : SceneKind.other,
      faceArea: area,
      smallFaces: faces.isNotEmpty && area < _C.smallFacesArea,
      backlit: faces.isNotEmpty && skinY < _C.backlitRatio * frame.medianY,
      highKey:
          hints?.keyIntent == 'high_key' ||
          (frame.p50 > _C.highKeyP50 &&
              frame.p5 > _C.highKeyP5 &&
              frame.p99_5 >= _C.highKeyWhite &&
              frame.clipFraction < _C.highKeyMaxClip),
      lowKey:
          hints?.keyIntent == 'low_key' ||
          (frame.p50 < _C.lowKeyP50 && frame.p95 > _C.lowKeyP95),
      night: (exif?.exposureSeconds ?? 0) >= 1 / 15 && (exif?.iso ?? 0) >= 1600,
      warmIntent: warmLightIntended(exif, hints),
      alreadyEdited: editedBefore(exif),
    );
  }

  final SceneKind kind;

  /// Summed face-box area as a fraction of the frame.
  final double faceArea;

  /// Faces are present but tiny: a guard, not the exposure anchor.
  final bool smallFaces;
  final bool backlit;
  final bool highKey;
  final bool lowKey;
  final bool night;

  /// Capture time or scene hints suggest deliberately warm light.
  final bool warmIntent;

  /// The file was written by an editor: it carries someone's look already.
  final bool alreadyEdited;

  bool get hasFaces => faceArea > 0;
  bool get isPeople => kind != SceneKind.other;

  /// True when the EXIF software tag names a photo editor (§2.3
  /// `alreadyEdited`), not camera firmware.
  static bool editedBefore(ExifSummary? exif) {
    final software = exif?.software?.toLowerCase();
    if (software == null) return false;
    const editors = [
      'lightroom',
      'photoshop',
      'camera raw',
      'capture one',
      'darktable',
      'rawtherapee',
      'luminar',
      'snapseed',
      'vsco',
      'affinity',
      'pixelmator',
      'gimp',
      'lumen',
    ];
    return editors.any(software.contains);
  }

  /// True when EXIF time or scene hints suggest a deliberate warm cast.
  static bool warmLightIntended(ExifSummary? exif, SceneInfo? hints) {
    const warmScenes = {
      'golden_hour',
      'blue_hour',
      'sunset',
      'sunrise',
      'night',
      'indoor_tungsten',
    };
    if (warmScenes.contains(hints?.timeOfDay)) return true;
    final t = exif?.capturedAt;
    if (t == null) return false;
    final h = t.hour + t.minute / 60;
    return (h >= 16.5 && h <= 21.5) || (h >= 5 && h <= 8.5);
  }
}
