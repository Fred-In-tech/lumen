import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/auto_edit_service.dart';
import 'package:lumen/ai/ondevice/analysis_pixels.dart';
import 'package:lumen/ai/ondevice/face_analysis_service.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/platform/background.dart';

final _log = Logger('AutoRetouch');

/// Shown when faces could not be analyzed (web, missing models): the photo
/// keeps its colour edit and no retouch is guessed.
const kFacesNotRetouchedNote =
    'Faces were not retouched: face analysis is unavailable here.';

/// Shown when Auto Retouch is pressed on a photo without faces.
const kNoFacesToRetouch =
    'No faces found in this photo, so there is nothing to retouch.';

/// What pressing Auto Retouch did, said in a toast so the button never
/// looks dead: [before] → [after] with [kept] hand-set values (lock keys)
/// left alone, for [faces] measured faces (null: static recipe).
String autoRetouchMessage({
  required PortraitSettings before,
  required PortraitSettings after,
  required Set<String> kept,
  int? faces,
}) {
  final hand = kept.length == 1
      ? 'the value you set by hand'
      : 'the ${kept.length} values you set by hand';
  if (after == before) {
    return kept.isEmpty
        ? 'Auto Retouch is already applied: nothing to change.'
        : 'Auto Retouch changed nothing: it kept $hand. '
              'Reset a slider to hand it back.';
  }
  final who = switch (faces) {
    null => '',
    1 => ' to 1 face',
    _ => ' to $faces faces',
  };
  final quiet = !after.hasFaceEdits
      ? ' These faces need no retouch.'
      : (kept.isEmpty ? '' : ' Kept $hand.');
  return 'Auto Retouch applied$who.$quiet';
}

/// Measured needs of a photo, or why there are none ([note]).
/// [needs] is [RetouchNeeds.none] when the photo has no retouchable faces.
typedef RetouchMeasure = ({RetouchNeeds? needs, String? note});

/// Need-scaled Auto Retouch for photos that may never have been opened.
abstract interface class AutoRetouchPlanner {
  /// Measures every face's needs. Never throws.
  Future<RetouchMeasure> measure(String assetId, DevelopSettings settings);

  /// The need-scaled portrait for [doc] (hand-set values locked from its
  /// history). Null portrait when the photo has no faces or analysis failed.
  Future<RetouchPlan> plan(String assetId, EditDocument doc);
}

/// Face analysis from the local cache (else run and cached), retouch maps
/// from the (healed) analysis decode, needs measured in one background
/// isolate.
class StoredAutoRetouchPlanner implements AutoRetouchPlanner {
  StoredAutoRetouchPlanner({
    required this.catalog,
    required this.faceService,
    this.patches,
  });

  final CatalogRepository catalog;
  final Future<FaceAnalysisService> Function() faceService;
  final PatchStoreGetter? patches;

  @override
  Future<RetouchMeasure> measure(
    String assetId,
    DevelopSettings settings,
  ) async {
    try {
      final service = await faceService();
      var entry = await service.cached(assetId);
      AnalysisPixels? decoded;
      if (entry == null) {
        final d = decoded = await loadAnalysisPixels(catalog, assetId);
        entry = await service.analyze(
          assetId,
          pixels: () async => d.pixels,
          sourceWidth: d.sourceWidth,
          sourceHeight: d.sourceHeight,
        );
      }
      final faces = entry.analysis;
      if (faces.faces.isEmpty) return (needs: RetouchNeeds.none, note: null);
      decoded ??= await loadAnalysisPixels(catalog, assetId);
      final pixels = await healedAnalysisPixels(
        decoded.pixels,
        assetId: assetId,
        ops: settings.heal,
        faces: faces,
        patches: patches,
      );
      final needs = await _measureInBackground(
        pixels,
        faces,
        settings.portrait.spots,
      );
      return (needs: needs, note: null);
    } on Exception catch (e) {
      _log.warning('retouch needs of $assetId unavailable: $e');
      return (needs: null, note: kFacesNotRetouchedNote);
    }
  }

  @override
  Future<RetouchPlan> plan(String assetId, EditDocument doc) async {
    final m = await measure(assetId, doc.settings);
    final needs = m.needs;
    if (needs == null || needs.isEmpty) return (portrait: null, note: m.note);
    return (
      portrait: PortraitPresets.autoRetouchFor(
        doc.settings.portrait,
        needs,
        locked: manualPortraitLocks(doc.history),
      ),
      note: null,
    );
  }
}

/// Maps + measurement in one isolate (the maps never cross back).
/// Top-level so the closure captures only its arguments.
Future<RetouchNeeds> _measureInBackground(
  RgbaBuffer pixels,
  FaceAnalysis faces,
  PortraitSpots spots,
) => runInBackground(() {
  final maps = computeRetouchMaps(
    pixels,
    faces,
    overrides: BlemishOverrides(keepAt: spots.keep, removeAt: spots.remove),
  );
  return measureRetouchNeeds(maps, pixels, faces);
});

final autoRetouchPlannerProvider = Provider<AutoRetouchPlanner>(
  (ref) => StoredAutoRetouchPlanner(
    catalog: ref.watch(catalogRepositoryProvider),
    faceService: () => ref.read(faceAnalysisServiceProvider.future),
    patches: () => ref.read(patchStoreProvider.future),
  ),
);
