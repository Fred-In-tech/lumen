import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

/// On-device segmentation for AI masks (Subject, Person, Background, Face
/// skin, Sky). Implemented by the on-device inference module (PHASE2 W4);
/// the Masks panel only consumes this seam.
abstract interface class AiMaskSource {
  /// True when [kind] can be computed right now (its model is installed).
  bool supports(MaskKind kind);

  /// Segments photo [assetId] for [kind], stores the 8-bit raster under the
  /// asset folder and returns the shape that references it (`maskRef`,
  /// model, version). Throws when segmentation fails; never returns a guess.
  Future<AiShape> segment(String assetId, MaskKind kind);
}

/// Null until the on-device model ships: the AI entries then stay disabled
/// with an honest hint instead of a fake result. The app overrides it with
/// the on-device implementation (`main.dart`).
final aiMaskSourceProvider = Provider<AiMaskSource?>((ref) => null);

/// Loads the decoded raster an [AiShape.maskRef] points to, for rendering.
/// Implementations regenerate it when the local cache was cleared; null
/// means it cannot be produced (the mask then covers nothing).
abstract interface class AiMaskRasterLoader {
  Future<MaskRaster?> load(String assetId, String maskRef);
}

/// Null when no on-device masks exist (web, tests); overridden in `main.dart`.
final aiMaskRasterLoaderProvider = Provider<AiMaskRasterLoader?>((ref) => null);

/// Hint shown on disabled AI mask entries.
const String kAiMaskUnavailableHint = 'Needs the on-device model';

/// Sky has no on-device model; it will come from the cloud.
const String kSkyMaskHint = 'Sky needs the cloud model, coming later';

/// The hint for a disabled AI entry: specific for sky when a source exists.
String aiMaskUnavailableHint(AiMaskSource? source, MaskKind kind) =>
    source != null && kind == MaskKind.sky
    ? kSkyMaskHint
    : kAiMaskUnavailableHint;
