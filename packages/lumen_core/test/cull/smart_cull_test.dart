import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'cull_fixtures.dart';

final _t0 = DateTime.utc(2026, 10, 3, 14);
DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

void main() {
  group('assessCull', () {
    test(
      'a sharp, open-eyed, well exposed photo scores high with no reasons',
      () {
        final a = assessCull(signals(sharp: 0.5, ear: 0.3));
        expect(a.reasons, isEmpty);
        expect(a.score, closeTo(1, 1e-9));
        expect(a.suggestsReject, isFalse);
      },
    );

    test('closed eyes reject; half open only warns; big groups are exempt', () {
      expect(assessCull(signals(ear: 0.08)).reasons, {CullReason.eyesClosed});
      final half = assessCull(signals(ear: 0.18));
      expect(half.reasons, {CullReason.eyesHalfOpen});
      expect(half.suggestsReject, isFalse);
      final group = assessCull(signals(ear: 0.08, faces: 7));
      expect(group.reasons, {CullReason.eyesHalfOpen});
      expect(group.suggestsReject, isFalse);
    });

    test('blur: absolute floor and relative to the cluster best', () {
      expect(assessCull(signals(sharp: 0.002)).reasons, {
        CullReason.blurryFace,
      });
      expect(assessCull(signals(sharp: 0.002, faces: 0)).reasons, {
        CullReason.blurry,
      });
      final relative = assessCull(
        signals(sharp: 0.1),
        clusterBestSharpness: 0.5,
      );
      expect(relative.reasons, {CullReason.blurryFace});
      expect(
        assessCull(signals(sharp: 0.3), clusterBestSharpness: 0.5).reasons,
        isEmpty,
      );
    });

    test('clipping reasons', () {
      expect(assessCull(signals(hiClip: 0.2, loClip: 0.3)).reasons, {
        CullReason.highlightsClipped,
        CullReason.shadowsCrushed,
      });
    });
  });

  group('smartCull', () {
    test('a burst becomes one cluster: best picked, rest alternates', () {
      final result = smartCull([
        CullItem(
          'a',
          signals(sharp: 0.2, hash: '00000000000000ff', at: _at(0)),
        ),
        CullItem(
          'b',
          signals(sharp: 0.5, hash: '00000000000000fe', at: _at(1)),
        ),
        CullItem(
          'c',
          signals(sharp: 0.3, hash: '00000000000000fc', at: _at(2)),
        ),
      ]);
      expect(result.clusters, hasLength(1));
      final cluster = result.clusters.single;
      expect(cluster.assetIds, ['a', 'b', 'c']);
      expect(cluster.bestId, 'b');
      final s = result.suggestions;
      expect(s['b']!.decision, CullDecision.pick);
      expect(s['a']!.decision, CullDecision.alternate);
      expect(s['a']!.reasons, contains(CullReason.notBestInCluster));
      expect(s['c']!.clusterSize, 3);
      expect(s['c']!.clusterId, cluster.id);
    });

    test('rejects are never the pick, even when sharpest', () {
      final s = smartCull([
        CullItem('closed', signals(sharp: 0.9, ear: 0.05, at: _at(0))),
        CullItem('open', signals(sharp: 0.5, ear: 0.3, at: _at(2))),
      ]).suggestions;
      expect(s['closed']!.decision, CullDecision.reject);
      expect(s['closed']!.reasons, contains(CullReason.eyesClosed));
      expect(s['open']!.decision, CullDecision.pick);
    });

    test('time window and hash distance split clusters', () {
      final result = smartCull([
        // Similar (8 bits) but a minute apart: two clusters.
        CullItem('a', signals(hash: '0000000000000000', at: _at(0))),
        CullItem('b', signals(hash: '00000000000000ff', at: _at(60))),
        // Near-duplicate of b (1 bit) much later: joins b.
        CullItem('c', signals(hash: '00000000000000fe', at: _at(600))),
        // Different scene within the window: new cluster.
        CullItem('d', signals(hash: 'ffffffffffff0000', at: _at(601))),
      ]);
      expect(
        [for (final c in result.clusters) c.assetIds],
        [
          ['a'],
          ['b', 'c'],
          ['d'],
        ],
      );
    });

    test('capture order is used when every photo has a time', () {
      final result = smartCull([
        CullItem('late', signals(hash: 'ffffffffffffffff', at: _at(100))),
        CullItem('early', signals(hash: '0000000000000000', at: _at(0))),
        CullItem('early2', signals(hash: '0000000000000001', at: _at(3))),
      ]);
      expect(result.clusters.first.assetIds, ['early', 'early2']);
    });

    test('singletons: picked only when good enough', () {
      final s = smartCull([
        CullItem(
          'good',
          signals(sharp: 0.5, ear: 0.3, hash: '0000000000000000'),
        ),
        CullItem(
          'meh',
          signals(sharp: 0.004, ear: 0.18, hash: 'ffffffffffffffff'),
        ),
      ]).suggestions;
      expect(s['good']!.decision, CullDecision.pick);
      expect(s['meh']!.decision, CullDecision.none);
      expect(s['meh']!.clusterId, isNull);
    });

    test('suggestions round-trip through JSON; decisions map to flags', () {
      final s = CullSuggestion(
        assetId: 'a',
        decision: CullDecision.reject,
        score: 0.25,
        reasons: {CullReason.blurryFace},
        clusterId: 'c:a',
        clusterSize: 2,
      );
      final back = CullSuggestion.fromJson(s.toJson());
      expect(back.decision, CullDecision.reject);
      expect(back.reasons, {CullReason.blurryFace});
      expect(back.clusterId, 'c:a');
      expect(back.inCluster, isTrue);
      expect(CullDecision.pick.flag, PhotoFlag.pick);
      expect(CullDecision.reject.flag, PhotoFlag.reject);
      expect(CullDecision.alternate.flag, isNull);
    });
  });
}
