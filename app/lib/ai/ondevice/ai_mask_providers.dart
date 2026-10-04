import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/ai_raster_store.dart';
import 'package:lumen/ai/ondevice/analysis_pixels.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/mask_segmenter.dart';
import 'package:lumen/ai/ondevice/ondevice_ai_mask_source.dart';
import 'package:lumen/ai/ondevice/ondevice_platform.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';

final _log = Logger('AiMaskProviders');

/// Model behind AI masks (downloaded on first use, 16.4 MB).
const kMaskSegmenterSpec = ModelManifest.selfieMulticlass;

/// The loaded segmenter. Fails with a `ModelStoreError` (offline, no disk
/// space, hash mismatch) or an `InferenceException`.
final maskSegmenterProvider = FutureProvider<MaskSegmenter>((ref) async {
  final store = await ref.watch(modelStoreProvider.future);
  final backend = ref.watch(inferenceBackendProvider);
  final session = await openVerifiedSession(store, backend, kMaskSegmenterSpec);
  final MaskSegmenter segmenter;
  try {
    segmenter = MaskSegmenter(session: session, spec: kMaskSegmenterSpec);
  } on ModelContractMismatch {
    await session.dispose();
    rethrow;
  }
  ref.onDispose(() => unawaited(segmenter.dispose()));
  return segmenter;
});

final aiRasterStoreProvider = FutureProvider<AiRasterStore>(
  (ref) => openAiRasterStore(),
);

/// Face boxes for per-face crops: accepted faces plus faces rejected only
/// for size or yaw (still faces). Empty when face analysis cannot run.
Future<List<FaceBox>> maskFaceBoxes(Ref ref, String assetId) async {
  try {
    final e = await ref.read(faceAnalysisProvider(assetId).future);
    return [
      for (final f in e.analysis.faces) f.box,
      for (final r in e.rejected)
        if (r.reason != FaceRejectReason.lowPresence) r.box,
    ];
  } on Exception catch (err) {
    _log.info('no face crops for $assetId: $err');
    return const [];
  }
}

/// The on-device [OnDeviceAiMaskSource]; null on web. `main.dart` feeds it
/// to `aiMaskSourceProvider` and `aiMaskRasterLoaderProvider`.
final onDeviceAiMaskSourceProvider = Provider<OnDeviceAiMaskSource?>((ref) {
  if (ref.watch(platformInfoProvider).isWeb) return null;
  final source = OnDeviceAiMaskSource(
    spec: kMaskSegmenterSpec,
    segmenter: () async {
      try {
        return await ref.read(maskSegmenterProvider.future);
      } on Exception {
        // Let the next attempt retry (e.g. after going back online).
        ref.invalidate(maskSegmenterProvider);
        rethrow;
      }
    },
    store: () => ref.read(aiRasterStoreProvider.future),
    pixels: (id) async => (await loadAnalysisPixels(
      ref.read(catalogRepositoryProvider),
      id,
    )).pixels,
    faces: (id) => maskFaceBoxes(ref, id),
  );
  ref.onDispose(() => unawaited(source.dispose()));
  return source;
});

/// Pipeline phases for a progress chip; download bytes for the model come
/// from `modelProgressProvider` (model id `selfie_multiclass_256`).
final aiMaskStatusProvider = StreamProvider<AiMaskStatus>(
  (ref) =>
      ref.watch(onDeviceAiMaskSourceProvider)?.status ?? const Stream.empty(),
);
