import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/face_analyzer.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';

/// Supplies the pixels to analyze (decoded lazily, only on a cache miss).
typedef PixelLoader = Future<RgbaBuffer> Function();

/// Cache-first face analysis per photo, plus persisted group/person tags.
class FaceAnalysisService {
  FaceAnalysisService({
    required this.cache,
    required this.models,
    required Future<FaceAnalyzer> Function() analyzer,
  }) : _loadAnalyzer = analyzer;

  final FaceCache cache;

  /// Model keys of the current analyzer (cache version key).
  final Map<String, String> models;
  final Future<FaceAnalyzer> Function() _loadAnalyzer;
  final Map<String, Future<FaceCacheEntry>> _inFlight = {};

  /// The cached entry when it was computed with the current [models].
  Future<FaceCacheEntry?> cached(String assetId) async {
    final entry = await cache.read(assetId);
    return entry != null && entry.matchesModels(models) ? entry : null;
  }

  /// Returns the cached analysis or runs one and caches it. A re-run (new
  /// model version, or [force]) keeps the user's manual tags. Concurrent
  /// calls for one asset share the run. Throws `InferenceException` /
  /// `ModelStoreError` when the models cannot run.
  Future<FaceCacheEntry> analyze(
    String assetId, {
    required PixelLoader pixels,
    int? sourceWidth,
    int? sourceHeight,
    bool force = false,
  }) {
    final running = _inFlight[assetId];
    if (running != null) return running;
    final op = _analyze(assetId, pixels, sourceWidth, sourceHeight, force);
    _inFlight[assetId] = op;
    return op.whenComplete(() => _inFlight.remove(assetId));
  }

  Future<FaceCacheEntry> _analyze(
    String assetId,
    PixelLoader pixels,
    int? sourceWidth,
    int? sourceHeight,
    bool force,
  ) async {
    final previous = await cache.read(assetId);
    if (!force && previous != null && previous.matchesModels(models)) {
      return previous;
    }
    final analyzer = await _loadAnalyzer();
    final result = await analyzer.analyze(
      await pixels(),
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
    final entry = FaceCacheEntry(
      models: analyzer.models,
      analysis: previous == null
          ? result.analysis
          : carryOverManualTags(previous.analysis, result.analysis),
      rejected: result.rejected,
    );
    await cache.write(assetId, entry);
    return entry;
  }

  /// Tags [faceId] (manual) and persists it. Null when the photo has no
  /// cached analysis or no such face.
  Future<FaceCacheEntry?> tag(
    String assetId,
    String faceId,
    FaceGroup group, {
    String? personId,
  }) async {
    final entry = await cache.read(assetId);
    if (entry == null || entry.analysis.faceById(faceId) == null) return null;
    final next = entry.withTag(faceId, group, personId: personId);
    await cache.write(assetId, next);
    return next;
  }
}
