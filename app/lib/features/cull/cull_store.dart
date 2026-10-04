import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/face_cache.dart';

/// File name of the cull cache inside `assets/<id>/cache/`.
const kCullCacheFile = 'cull.json';

/// Where a suggestion stands. Only accepted ones reach the catalog.
enum SuggestionStatus {
  pending,
  accepted,
  dismissed;

  static SuggestionStatus fromName(Object? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => pending);
}

/// One photo's cull cache: signals (keyed by what produced them) and the
/// latest Smart Cull suggestion.
class CullRecord {
  const CullRecord({
    required this.signalsKey,
    required this.signals,
    this.suggestion,
    this.status = SuggestionStatus.pending,
  });

  static const cacheVersion = 1;

  /// Null for other cache versions or malformed documents (recomputed).
  static CullRecord? tryFromJson(Object? json) {
    if (json is! Map || json['cacheVersion'] != cacheVersion) return null;
    final signals = CullSignals.tryFromJson(json['signals']);
    final key = json['signalsKey'];
    if (signals == null || key is! String) return null;
    final s = json['suggestion'];
    return CullRecord(
      signalsKey: key,
      signals: signals,
      suggestion: s is Map ? CullSuggestion.fromJson(s.cast()) : null,
      status: SuggestionStatus.fromName(json['status']),
    );
  }

  final String signalsKey;
  final CullSignals signals;
  final CullSuggestion? suggestion;
  final SuggestionStatus status;

  /// The suggestion while it still awaits the user.
  CullSuggestion? get pending =>
      status == SuggestionStatus.pending ? suggestion : null;

  CullRecord withSuggestion(CullSuggestion? s) =>
      CullRecord(signalsKey: signalsKey, signals: signals, suggestion: s);

  CullRecord withStatus(SuggestionStatus s) => CullRecord(
    signalsKey: signalsKey,
    signals: signals,
    suggestion: suggestion,
    status: s,
  );

  Map<String, Object?> toJson() => {
    'cacheVersion': cacheVersion,
    'signalsKey': signalsKey,
    'signals': signals.toJson(),
    'suggestion': suggestion?.toJson(),
    'status': status.name,
  };
}

/// Local, non-synced cull cache (beside the face cache).
abstract interface class CullStore {
  Future<CullRecord?> read(String assetId);
  Future<void> write(String assetId, CullRecord record);
}

/// Web and tests.
class MemoryCullStore implements CullStore {
  final Map<String, Map<String, Object?>> docs = {};

  @override
  Future<CullRecord?> read(String assetId) async =>
      CullRecord.tryFromJson(docs[checkAssetId(assetId)]);

  @override
  Future<void> write(String assetId, CullRecord record) async =>
      docs[checkAssetId(assetId)] = record.toJson();
}
