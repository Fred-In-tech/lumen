import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/analysis_pixels.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/remove_providers.dart';

/// What the renderer needs to retouch faces: the per-photo maps and the face
/// analysis they were built from.
typedef RetouchInputs = ({RetouchMaps maps, FaceAnalysis faces});

/// Retouch maps for one photo, built once per face analysis (slider drags
/// never rebuild them; they only change shader uniforms) and rebuilt when the
/// user keeps or removes a spot or a heal on a face changes. Null when the photo has no usable faces.
final retouchMapsBuildProvider = FutureProvider.family<RetouchInputs?, String>((
  ref,
  assetId,
) async {
  final faces = (await ref.watch(faceAnalysisProvider(assetId).future))
      .analysis;
  if (faces.faces.isEmpty) return null;
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
  final maps = await computeRetouchMapsInBackground(pixels, faces, spots);
  return maps.hasFaces ? (maps: maps, faces: faces) : null;
});

/// Retouch inputs the open editor should use: built when the photo has face
/// retouch edits or the Portrait module is open (so the first slider drag is
/// instant), otherwise null and nothing runs.
final retouchInputsProvider =
    Provider.family<AsyncValue<RetouchInputs?>, String>((ref, assetId) {
      final hasEdits = ref.watch(
        editorProvider(assetId)
            .select((s) => s.value?.settings.portrait.hasFaceEdits ?? false),
      );
      final portraitOpen =
          ref.watch(editorModuleProvider(assetId)) == EditorModule.portrait;
      if (!hasEdits && !portraitOpen) return const AsyncData(null);
      return ref.watch(retouchMapsBuildProvider(assetId));
    });
