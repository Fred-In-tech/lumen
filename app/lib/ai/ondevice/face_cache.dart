import 'package:collection/collection.dart';
import 'package:lumen_core/lumen_core.dart';

/// Per-asset folder for rebuildable, device-local data. Everything under
/// `assets/<id>/cache/` is excluded from export, sync and backup (face
/// geometry is biometric; research 07 §1.5).
const kAssetCacheDir = 'cache';

/// File name of the face cache inside [kAssetCacheDir].
const kFaceCacheFile = 'face.json';

final _assetId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Rejects ids that could escape the asset folder (`..`, separators).
String checkAssetId(String assetId) {
  if (!_assetId.hasMatch(assetId)) {
    throw ArgumentError.value(assetId, 'assetId', 'not a valid asset id');
  }
  return assetId;
}

/// What `face.json` holds: the analysis, the rejected faces, and the model
/// keys it was computed with (a mismatch means "re-run").
class FaceCacheEntry {
  FaceCacheEntry({
    required Map<String, String> models,
    required this.analysis,
    List<RejectedFace> rejected = const [],
  }) : models = Map.unmodifiable(models),
       rejected = List.unmodifiable(rejected);

  static const cacheVersion = 1;

  final Map<String, String> models;
  final FaceAnalysis analysis;
  final List<RejectedFace> rejected;

  bool matchesModels(Map<String, String> current) =>
      const MapEquality<String, String>().equals(models, current);

  /// A manual group/person tag on [faceId] (persisted by the caller).
  FaceCacheEntry withTag(String faceId, FaceGroup group, {String? personId}) =>
      FaceCacheEntry(
        models: models,
        analysis: analysis.withTag(faceId, group, personId: personId),
        rejected: rejected,
      );

  Map<String, Object?> toJson() => {
    'cacheVersion': cacheVersion,
    'models': models,
    'analysis': analysis.toJson(),
    'rejected': [for (final r in rejected) r.toJson()],
  };

  /// Null for other cache versions or a malformed document (the cache is
  /// rebuildable, so the caller re-analyzes).
  static FaceCacheEntry? tryFromJson(Object? json) {
    if (json is! Map || json['cacheVersion'] != cacheVersion) return null;
    final models = json['models'];
    final analysis = json['analysis'];
    final rejected = json['rejected'];
    if (models is! Map || analysis is! Map) return null;
    return FaceCacheEntry(
      models: {
        for (final e in models.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      },
      analysis: FaceAnalysis.fromJson(analysis.cast()),
      rejected: [
        if (rejected is List)
          for (final r in rejected.whereType<Map<Object?, Object?>>())
            RejectedFace.fromJson(r.cast()),
      ],
    );
  }
}

/// Local, non-synced store for face analyses.
abstract interface class FaceCache {
  Future<FaceCacheEntry?> read(String assetId);
  Future<void> write(String assetId, FaceCacheEntry entry);
  Future<void> delete(String assetId);
}

/// Web and tests.
class MemoryFaceCache implements FaceCache {
  final Map<String, Map<String, Object?>> _docs = {};

  @override
  Future<FaceCacheEntry?> read(String assetId) async =>
      FaceCacheEntry.tryFromJson(_docs[checkAssetId(assetId)]);

  @override
  Future<void> write(String assetId, FaceCacheEntry entry) async =>
      _docs[checkAssetId(assetId)] = entry.toJson();

  @override
  Future<void> delete(String assetId) async =>
      _docs.remove(checkAssetId(assetId));
}
