import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'cull_scoring.dart';
import 'cull_signals.dart';
import 'quality_measures.dart';

/// Catalog flag values (`CatalogEntry.flag`).
abstract final class PhotoFlag {
  static const none = 'none';
  static const pick = 'pick';
  static const reject = 'reject';
}

/// What Smart Cull suggests for one photo (the user accepts or dismisses).
enum CullDecision {
  pick,
  reject,

  /// In a cluster, acceptable, but not its best.
  alternate,

  /// No suggestion.
  none;

  static CullDecision fromName(Object? v) =>
      values.firstWhere((d) => d.name == v, orElse: () => none);

  /// The catalog flag accepting this decision writes (null = unchanged).
  String? get flag => switch (this) {
    pick => PhotoFlag.pick,
    reject => PhotoFlag.reject,
    alternate || none => null,
  };
}

class CullSuggestion {
  CullSuggestion({
    required this.assetId,
    required this.decision,
    required this.score,
    Set<CullReason> reasons = const {},
    this.clusterId,
    this.clusterSize = 1,
  }) : reasons = Set.unmodifiable(reasons);

  factory CullSuggestion.fromJson(Map<String, Object?> j) => CullSuggestion(
    assetId: j['assetId'] as String? ?? '',
    decision: CullDecision.fromName(j['decision']),
    score: (j['score'] as num?)?.toDouble() ?? 0,
    reasons: {
      for (final r in (j['reasons'] as List?) ?? const [])
        ?CullReason.fromName(r),
    },
    clusterId: j['cluster'] as String?,
    clusterSize: (j['clusterSize'] as num?)?.toInt() ?? 1,
  );

  final String assetId;
  final CullDecision decision;
  final double score;
  final Set<CullReason> reasons;
  final String? clusterId;
  final int clusterSize;

  bool get inCluster => clusterSize > 1;

  Map<String, Object?> toJson() => {
    'assetId': assetId,
    'decision': decision.name,
    'score': score,
    'reasons': [for (final r in reasons) r.name],
    'cluster': clusterId,
    'clusterSize': clusterSize,
  };
}

/// Similar shots, in capture order, with the best one.
class CullCluster {
  CullCluster(this.id, List<String> assetIds, this.bestId)
    : assetIds = List.unmodifiable(assetIds);

  final String id;
  final List<String> assetIds;
  final String? bestId;
}

class CullItem {
  const CullItem(this.assetId, this.signals);
  final String assetId;
  final CullSignals signals;
}

class SmartCullResult {
  SmartCullResult(
    Map<String, CullSuggestion> suggestions,
    List<CullCluster> clusters,
  ) : suggestions = Map.unmodifiable(suggestions),
      clusters = List.unmodifiable(clusters);

  final Map<String, CullSuggestion> suggestions;
  final List<CullCluster> clusters;
}

/// Groups [items] into similar-shot clusters, picks the best of each and
/// suggests rejects (research 06 §1.8). Items are taken in capture order
/// when every item has an EXIF time, else in the given (library) order.
SmartCullResult smartCull(
  List<CullItem> items, {
  CullConfig config = const CullConfig(),
}) {
  final clusters = clusterSimilar(items, config: config);
  final suggestions = <String, CullSuggestion>{};
  final out = <CullCluster>[];
  for (final members in clusters) {
    final id = 'c:${members.first.assetId}';
    final best = members
        .map((m) => primarySharpness(m.signals))
        .reduce(math.max);
    final scored = [
      for (final m in members)
        (
          item: m,
          a: assessCull(
            m.signals,
            config: config,
            clusterBestSharpness: members.length > 1 ? best : null,
          ),
        ),
    ];
    final keepers =
        [
          for (final s in scored)
            if (!s.a.suggestsReject) s,
        ]..sort((x, y) {
          final byScore = y.a.score.compareTo(x.a.score);
          if (byScore != 0) return byScore;
          // Both crisp (the score saturates): the sharper one wins.
          return primarySharpness(y.item.signals)
              .compareTo(primarySharpness(x.item.signals));
        });
    final bestId = keepers.isEmpty ? null : keepers.first.item.assetId;
    for (final s in scored) {
      final isBest = s.item.assetId == bestId;
      final decision = s.a.suggestsReject
          ? CullDecision.reject
          : isBest && (members.length > 1 || s.a.score >= config.minPickScore)
          ? CullDecision.pick
          : members.length > 1 && !isBest
          ? CullDecision.alternate
          : CullDecision.none;
      suggestions[s.item.assetId] = CullSuggestion(
        assetId: s.item.assetId,
        decision: decision,
        score: s.a.score,
        reasons: {
          ...s.a.reasons,
          if (decision == CullDecision.alternate) CullReason.notBestInCluster,
        },
        clusterId: members.length > 1 ? id : null,
        clusterSize: members.length,
      );
    }
    out.add(CullCluster(id, [for (final m in members) m.assetId], bestId));
  }
  return SmartCullResult(suggestions, out);
}

/// Sequential clustering: a shot joins the current cluster when its dHash
/// is within [CullConfig.similarHash] of a member and it was taken within
/// [CullConfig.burstWindow] of the previous shot (or a time is unknown),
/// or when it is a near-duplicate ([CullConfig.duplicateHash]) at any time.
List<List<CullItem>> clusterSimilar(
  List<CullItem> items, {
  CullConfig config = const CullConfig(),
}) {
  final ordered = [...items];
  if (ordered.every((i) => i.signals.capturedAt != null)) {
    mergeSort(
      ordered,
      compare: (a, b) => a.signals.capturedAt!.compareTo(b.signals.capturedAt!),
    );
  }
  final clusters = <List<CullItem>>[];
  for (final item in ordered) {
    final current = clusters.isEmpty ? null : clusters.last;
    if (current != null && _joins(current, item, config)) {
      current.add(item);
    } else {
      clusters.add([item]);
    }
  }
  return clusters;
}

bool _joins(List<CullItem> cluster, CullItem item, CullConfig c) {
  final recent = cluster.length > 8
      ? cluster.sublist(cluster.length - 8)
      : cluster;
  final d = recent
      .map((m) => hammingDistance(m.signals.dHash, item.signals.dHash))
      .reduce(math.min);
  if (d <= c.duplicateHash) return true;
  if (d > c.similarHash) return false;
  final a = cluster.last.signals.capturedAt, b = item.signals.capturedAt;
  return a == null || b == null || b.difference(a).abs() <= c.burstWindow;
}
