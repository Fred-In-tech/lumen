import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/analysis_pixels.dart';
import 'package:lumen/ai/ondevice/face_analysis_service.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/platform/background.dart';

final _log = Logger('RetouchBuild');

/// Builds the retouch maps off the UI isolate. Top-level so the isolate
/// closure only captures plain data.
Future<RetouchMaps> computeRetouchMapsInBackground(
  RgbaBuffer pixels,
  FaceAnalysis faces,
  PortraitSpots spots,
) => runInBackground(
  () => computeRetouchMaps(
    pixels,
    faces,
    overrides: BlemishOverrides(keepAt: spots.keep, removeAt: spots.remove),
  ),
);

/// How far around a detected face box a heal still counts as "on the face"
/// (the retouch maps reach the hairline and the jaw).
const kFaceHealMargin = 0.2;

/// The visible heal ops whose box overlaps a face box (grown by
/// [kFaceHealMargin] of its size): those change what the retouch analysis
/// should see.
List<HealOp> healOpsOnFaces(List<HealOp> ops, FaceAnalysis faces) {
  if (ops.isEmpty || faces.faces.isEmpty) return const [];
  return [
    for (final op in ops)
      if (!op.hidden && op.isRenderable && _onAFace(op, faces)) op,
  ];
}

bool _onAFace(HealOp op, FaceAnalysis faces) {
  final x0 = op.bbox.x / op.srcWidth, y0 = op.bbox.y / op.srcHeight;
  final x1 = op.bbox.right / op.srcWidth, y1 = op.bbox.bottom / op.srcHeight;
  for (final f in faces.faces) {
    final b = f.box;
    final mx = b.width * kFaceHealMargin, my = b.height * kFaceHealMargin;
    if (math.max(x0, b.x - mx) < math.min(x1, b.x + b.width + mx) &&
        math.max(y0, b.y - my) < math.min(y1, b.y + b.height + my)) {
      return true;
    }
  }
  return false;
}

/// A stable key of [healOpsOnFaces] (op ids): the retouch maps are rebuilt
/// only when it changes, never for heals away from the faces.
String faceHealKey(List<HealOp>? ops, FaceAnalysis? faces) => faces == null
    ? ''
    : healOpsOnFaces(ops ?? const [], faces).map((o) => o.id).join(',');

/// [pixels] (an analysis decode, any size) with the heal ops that touch a
/// face drawn in, so blemish and skin analysis sees the healed face.
Future<RgbaBuffer> healedAnalysisPixels(
  RgbaBuffer pixels, {
  required String assetId,
  required List<HealOp> ops,
  required FaceAnalysis faces,
  required PatchStoreGetter? patches,
}) async {
  final onFaces = healOpsOnFaces(ops, faces);
  if (patches == null || onFaces.isEmpty) return pixels;
  return composeHealedFullRes(await patches(), assetId, pixels, onFaces);
}

/// Portrait retouch inputs for a stored photo, or why there are none.
typedef StoredRetouch = ({
  RetouchMaps? maps,
  FaceAnalysis? faces,
  String? note,
});

const StoredRetouch kNoRetouch = (maps: null, faces: null, note: null);

final Future<StoredRetouch> kNoRetouchFuture = Future.value(kNoRetouch);

/// Loads a stored photo's retouch inputs ([StoredRetouchLoader.load]).
typedef RetouchLoader = Future<StoredRetouch> Function(
  String assetId,
  DevelopSettings settings,
);

/// Shown with an export or thumbnail that had to skip portrait retouch.
const kRetouchSkippedNote =
    'Portrait retouch was skipped: face analysis is unavailable here.';

/// Loads what export, batch and thumbnails need to apply portrait retouch
/// to a photo that may never have been opened: the face analysis (cached,
/// else run now and cached) and the retouch maps (built in the background,
/// from the healed analysis pixels when heals touch a face).
class StoredRetouchLoader {
  StoredRetouchLoader({
    required this.catalog,
    required this.faceService,
    this.patches,
  });

  final CatalogRepository catalog;
  final Future<FaceAnalysisService> Function() faceService;
  final PatchStoreGetter? patches;

  /// Never throws: when analysis cannot run (web, missing models) the
  /// result has no maps and a [kRetouchSkippedNote].
  Future<StoredRetouch> load(String assetId, DevelopSettings settings) async {
    if (!settings.portrait.hasFaceEdits) return kNoRetouch;
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
      if (faces.faces.isEmpty) return kNoRetouch;
      decoded ??= await loadAnalysisPixels(catalog, assetId);
      final pixels = await healedAnalysisPixels(
        decoded.pixels,
        assetId: assetId,
        ops: settings.heal,
        faces: faces,
        patches: patches,
      );
      final maps = await computeRetouchMapsInBackground(
        pixels,
        faces,
        settings.portrait.spots,
      );
      return maps.hasFaces
          ? (maps: maps, faces: faces, note: null)
          : kNoRetouch;
    } on Exception catch (e) {
      _log.warning('portrait retouch skipped for $assetId: $e');
      return (maps: null, faces: null, note: kRetouchSkippedNote);
    }
  }
}

final storedRetouchLoaderProvider = Provider<StoredRetouchLoader>(
  (ref) => StoredRetouchLoader(
    catalog: ref.watch(catalogRepositoryProvider),
    faceService: () => ref.read(faceAnalysisServiceProvider.future),
    patches: () => ref.read(patchStoreProvider.future),
  ),
);
