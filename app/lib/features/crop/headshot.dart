import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart'
    show refreshThumbnail;
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/remove_providers.dart';

final _log = Logger('HeadshotCrop');

/// Faces a headshot frames: accepted faces (with landmarks) plus faces
/// rejected only for size or yaw (box only). Low-presence detections are
/// not faces.
List<DetectedFace> headshotFaces(FaceCacheEntry entry) => [
  ...entry.analysis.faces,
  for (final r in entry.rejected)
    if (r.reason != FaceRejectReason.lowPresence)
      DetectedFace(id: r.id, box: r.box, confidence: r.confidence),
];

/// The headshot geometry for one photo's [faces], or null without faces.
HeadshotCrop? headshotFor(
  FaceCacheEntry faces,
  Geometry current,
  HeadshotRatio ratio,
) => headshotCrop(
  faces: headshotFaces(faces),
  sourceWidth: faces.analysis.imageWidth,
  sourceHeight: faces.analysis.imageHeight,
  ratio: ratio,
  current: current,
);

/// History label for a headshot crop.
String headshotLabel(HeadshotRatio ratio) => 'Headshot crop ${ratio.id}';

/// Batch result of [headshotCropAssets].
typedef HeadshotBatchResult = ({int cropped, int noFace, int failed});

/// Applies a headshot crop to each stored photo in [assetIds] as one
/// geometry history entry (undoable in the editor) and refreshes its
/// thumbnail. Photos without a face are left alone. For the batch bar.
Future<HeadshotBatchResult> headshotCropAssets(
  WidgetRef ref,
  List<String> assetIds,
  HeadshotRatio ratio, {
  void Function(int done, int total)? onProgress,
}) async {
  final repo = ref.read(catalogRepositoryProvider);
  var cropped = 0, noFace = 0, failed = 0;
  for (var i = 0; i < assetIds.length; i++) {
    final id = assetIds[i];
    try {
      final faces = await ref.read(faceAnalysisProvider(id).future);
      final doc = await repo.loadEdit(id);
      final crop = headshotFor(faces, doc.settings.geometry, ratio);
      if (crop == null) {
        noFace++;
      } else {
        final next = doc.settings.copyWith(geometry: crop.geometry);
        final h = HistoryEntry.tryDiff(
          label: headshotLabel(ratio),
          kind: HistoryKind.geometry,
          before: doc.settings,
          after: next,
        );
        if (h != null) {
          await repo.saveEdit(
            doc.copyWith(
              settings: next,
              history: doc.history.push(h),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
          await refreshThumbnail(
            repo,
            id,
            next,
            patches: () => ref.read(patchStoreProvider.future),
            maskLoader: ref.read(aiMaskRasterLoaderProvider),
            retouch: ref.read(storedRetouchLoaderProvider).load,
          );
        }
        cropped++;
      }
    } on Exception catch (e) {
      _log.warning('headshot crop of $id failed: $e');
      failed++;
    }
    onProgress?.call(i + 1, assetIds.length);
  }
  return (cropped: cropped, noFace: noFace, failed: failed);
}
