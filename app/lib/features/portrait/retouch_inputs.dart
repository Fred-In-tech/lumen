import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/analysis_pixels.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/remove_providers.dart';

/// What the renderer needs to retouch faces: the per-photo maps and the face
/// analysis they were built from.
typedef RetouchInputs = ({RetouchMaps maps, FaceAnalysis faces});

/// Pen-free retouch maps for one photo, built once per face analysis
/// (slider drags never rebuild them; they only change shader uniforms) and
/// rebuilt when the user keeps or removes a spot, a heal on a face changes,
/// or backdrop / clothing edits are switched on or off (the person / hair
/// and clothes rasters are loaded only then, each only for its own
/// edits). Null when the photo has no usable faces and no image-scope
/// edits; with them the maps carry `backdrop.state` / `clothesState` (and
/// their reasons) even when nothing can be cleaned.
final retouchBaseMapsProvider = FutureProvider.family<RetouchInputs?, String>((
  ref,
  assetId,
) async {
  final faces = (await ref.watch(faceAnalysisProvider(assetId).future))
      .analysis;
  final want = ref.watch(
    editorProvider(assetId).select(
      (s) => imageRasterRequest(
        s.value?.settings.portrait ?? PortraitSettings.empty,
      ),
    ),
  );
  if (faces.faces.isEmpty && want == null) return null;
  final spots = ref.watch(
    editorProvider(assetId)
        .select((s) => s.value?.settings.portrait.spots ?? PortraitSpots.none),
  );
  // Rebuilt when the heals that touch a face change (never for others):
  // blemish and skin analysis must see the healed face.
  ref.watch(
    editorProvider(assetId)
        .select((s) => faceHealKey(s.value?.settings.heal, faces)),
  );
  final heal =
      ref.read(editorProvider(assetId)).value?.settings.heal ?? const [];
  final decoded = await loadAnalysisPixels(
    ref.watch(catalogRepositoryProvider),
    assetId,
  );
  final pixels = await healedAnalysisPixels(
    decoded.pixels,
    assetId: assetId,
    ops: heal,
    faces: faces,
    patches: () => ref.read(patchStoreProvider.future),
  );
  final backdrop = want == null
      ? null
      : await loadBackdropRasters(
          ref.read(aiMaskSourceProvider),
          ref.read(aiMaskRasterLoaderProvider),
          assetId,
          want: want,
        );
  final maps = await computeRetouchMapsInBackground(
    pixels,
    faces,
    spots,
    backdrop: backdrop,
  );
  return maps.isUsable || want != null ? (maps: maps, faces: faces) : null;
});

/// The Manual Tuning Pen strokes of a photo, compared by content (so other
/// edits never re-apply the pen).
class _Pen {
  const _Pen(this.strokes);
  final List<BrushStroke> strokes;

  @override
  bool operator ==(Object other) =>
      other is _Pen && listEquals(other.strokes, strokes);

  @override
  int get hashCode => Object.hashAll(strokes);
}

/// Retouch maps the renderer uses: [retouchBaseMapsProvider] with the
/// Manual Tuning Pen applied (`applySkinPen`, milliseconds: a pen stroke
/// rewrites only the skin and face-id channels, and the GPU cache then
/// re-uploads only the two region atlases).
final retouchMapsBuildProvider = FutureProvider.family<RetouchInputs?, String>((
  ref,
  assetId,
) async {
  final base = await ref.watch(retouchBaseMapsProvider(assetId).future);
  final pen = ref.watch(
    editorProvider(assetId)
        .select((s) => _Pen(s.value?.settings.portrait.skinPen ?? const [])),
  );
  if (base == null || pen.strokes.isEmpty) return base;
  return (maps: applySkinPen(base.maps, pen.strokes), faces: base.faces);
});

/// Retouch inputs the open editor should use: built when the photo has face
/// retouch or backdrop edits or the Portrait module is open (so the first
/// slider drag is instant), otherwise null and nothing runs.
final retouchInputsProvider =
    Provider.family<AsyncValue<RetouchInputs?>, String>((ref, assetId) {
      final hasEdits = ref.watch(
        editorProvider(assetId).select(
          (s) => portraitNeedsRetouch(
            s.value?.settings.portrait ?? PortraitSettings.empty,
          ),
        ),
      );
      final portraitOpen =
          ref.watch(editorModuleProvider(assetId)) == EditorModule.portrait;
      if (!hasEdits && !portraitOpen) return const AsyncData(null);
      return ref.watch(retouchMapsBuildProvider(assetId));
    });

/// Why the backdrop sliders of photo [assetId] do nothing (or null when
/// they work or were never used): `BackdropState.reason` of its maps.
final backdropStatusProvider = Provider.family<BackdropState?, String>(
  (ref, assetId) =>
      ref.watch(retouchInputsProvider(assetId)).value?.maps.backdrop.state,
);

/// Why the clothing sliders of photo [assetId] do nothing (or null when
/// they work or were never used): `ClothesState.reason` of its maps.
final clothesStatusProvider = Provider.family<ClothesState?, String>(
  (ref, assetId) => ref
      .watch(retouchInputsProvider(assetId))
      .value
      ?.maps
      .backdrop
      .clothesState,
);

/// Faces the face-shape warp needs, as soon as they are known: when the photo
/// has face edits or Portrait is open (null otherwise, nothing runs).
final warpFacesProvider = Provider.family<FaceAnalysis?, String>((
  ref,
  assetId,
) {
  final hasEdits = ref.watch(
    editorProvider(assetId)
        .select((s) => s.value?.settings.portrait.hasFaceEdits ?? false),
  );
  final portraitOpen =
      ref.watch(editorModuleProvider(assetId)) == EditorModule.portrait;
  if (!hasEdits && !portraitOpen) return null;
  return ref.watch(faceAnalysisProvider(assetId)).value?.analysis;
});
