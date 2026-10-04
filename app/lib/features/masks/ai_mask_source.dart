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
/// with an honest hint instead of a fake result.
final aiMaskSourceProvider = Provider<AiMaskSource?>((ref) => null);

/// Hint shown on disabled AI mask entries.
const String kAiMaskUnavailableHint = 'Needs the on-device model';
