import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import 'enhance_exposure.dart';
import 'enhance_scene.dart';
import 'enhance_wb.dart';
import 'skin_bands.dart';

/// Things Auto Enhance decided to leave alone, told to the user.
enum EnhanceNote {
  nothingToDo('Already looks good: no changes needed'),
  skinInBand('Faces are already well exposed'),
  whiteBalanceKept('Skin tones look right, so the light was kept as shot'),
  lowKeyKept('Kept the dark, low-key mood'),
  highKeyKept('Kept the bright, airy look'),
  softLightKept('Contrast was left as shot'),
  skinColourKept('Skin is already rich, so colour was not pushed');

  const EnhanceNote(this.text);

  final String text;
}

/// What [EnhanceSolver.solve] produced.
class EnhanceOutcome {
  const EnhanceOutcome({
    required this.settings,
    required this.confidence,
    required this.renders,
    required this.reasons,
    required this.notes,
    required this.scene,
    required this.faces,
    required this.wb,
    required this.exposure,
  });

  final DevelopSettings settings;

  /// 0..1; every delta except white balance was scaled by it.
  final double confidence;

  /// Proxy renders the solver needed.
  final int renders;

  /// Why a param was changed, where the solver has a specific reason
  /// (a "to …" phrase that completes "Raised exposure +0.40 EV").
  final Map<ParamId, String> reasons;
  final List<EnhanceNote> notes;
  final EnhanceScene scene;

  /// Faces as last measured (largest first).
  final List<FaceRead> faces;
  final WbSolution wb;
  final ExposurePlan exposure;
}
