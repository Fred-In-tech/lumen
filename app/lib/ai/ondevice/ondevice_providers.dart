import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/analysis_pixels.dart';
import 'package:lumen/ai/ondevice/face_analysis_service.dart';
import 'package:lumen/ai/ondevice/face_analyzer.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/ai/ondevice/ondevice_platform.dart';
import 'package:lumen/app/providers.dart';

/// Detector for photos: full-range BlazeFace (groups, half-body, wide).
const kFaceDetectorSpec = ModelManifest.blazeFaceFullRange;
const kFaceMeshSpec = ModelManifest.faceLandmarksDetector;

/// Version key of cached face analyses (matches `FaceAnalyzer.models`).
final Map<String, String> kFaceModels = Map.unmodifiable({
  'detector': kFaceDetectorSpec.key,
  'mesh': kFaceMeshSpec.key,
});

/// Long edge face analysis decodes at; landmarks are normalized, and
/// reject lengths are rescaled to the original size.
const kFaceAnalysisLongEdge = kOnDeviceAnalysisLongEdge;

final inferenceBackendProvider = Provider<InferenceBackend>(
  (ref) => createInferenceBackend(ref.watch(platformInfoProvider)),
);

/// Bundled models come from `assets/models/` (checked against the asset
/// manifest so a missing file is a typed error, not a FlutterError).
Future<Uint8List?> loadBundledModel(String assetKey) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  if (!manifest.listAssets().contains(assetKey)) return null;
  final data = await rootBundle.load(assetKey);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

final modelStoreProvider = FutureProvider<ModelStore>((ref) async {
  final store = await openModelStore(
    ref.watch(platformInfoProvider),
    bundled: loadBundledModel,
  );
  ref.onDispose(() => unawaited(store.dispose()));
  return store;
});

/// Download/verify progress for every model (drive a progress chip).
final modelProgressProvider = StreamProvider<ModelProgress>((ref) async* {
  final store = await ref.watch(modelStoreProvider.future);
  yield* store.progress;
});

final faceCacheProvider = FutureProvider<FaceCache>((ref) => openFaceCache());

/// Resolves [spec] through the store and loads it with its contract checked.
Future<InferenceSession> openVerifiedSession(
  ModelStore store,
  InferenceBackend backend,
  ModelSpec spec, {
  CancelToken? cancel,
}) async {
  final result = await store.ensure(spec, cancel: cancel);
  return switch (result) {
    ModelReady(:final path) => loadVerifiedSession(
      backend,
      spec,
      ModelFileSource(path),
    ),
    ModelFailed(:final error) => throw error,
  };
}

/// The loaded detector + mesh. Fails with a `ModelStoreError` or an
/// `InferenceException` when the models cannot run here.
final faceAnalyzerProvider = FutureProvider<FaceAnalyzer>((ref) async {
  final store = await ref.watch(modelStoreProvider.future);
  final backend = ref.watch(inferenceBackendProvider);
  final detector = await openVerifiedSession(store, backend, kFaceDetectorSpec);
  final InferenceSession mesh;
  try {
    mesh = await openVerifiedSession(store, backend, kFaceMeshSpec);
  } on Exception {
    await detector.dispose();
    rethrow;
  }
  final FaceAnalyzer analyzer;
  try {
    analyzer = FaceAnalyzer(
      detector: detector,
      detectorSpec: kFaceDetectorSpec,
      mesh: mesh,
      meshSpec: kFaceMeshSpec,
    );
  } on ModelContractMismatch {
    await detector.dispose();
    await mesh.dispose();
    rethrow;
  }
  ref.onDispose(() => unawaited(analyzer.dispose()));
  return analyzer;
});

final faceAnalysisServiceProvider = FutureProvider<FaceAnalysisService>((
  ref,
) async {
  final cache = await ref.watch(faceCacheProvider.future);
  return FaceAnalysisService(
    cache: cache,
    models: kFaceModels,
    analyzer: () => ref.read(faceAnalyzerProvider.future),
  );
});

/// Faces of one photo: the cache when current, else a fresh analysis of the
/// original (decoded at [kFaceAnalysisLongEdge]). This is what
/// `portraitFacesProvider` should read (`.value?.analysis`). Errors mean
/// "no automatic face features"; masks and manual tools still work.
final faceAnalysisProvider = FutureProvider.family<FaceCacheEntry, String>((
  ref,
  assetId,
) async {
  final service = await ref.watch(faceAnalysisServiceProvider.future);
  final cached = await service.cached(assetId);
  if (cached != null) return cached;
  final decoded = await loadAnalysisPixels(
    ref.watch(catalogRepositoryProvider),
    assetId,
  );
  return service.analyze(
    assetId,
    pixels: () async => decoded.pixels,
    sourceWidth: decoded.sourceWidth,
    sourceHeight: decoded.sourceHeight,
  );
});
