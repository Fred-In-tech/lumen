/// Resolves persisted [SpotAnchor]s against freshly detected candidates.
library;

import 'dart:math' as math;

import 'blemish_types.dart';
import 'face_frame.dart';

/// Candidate-id overrides for face [f] after matching the anchors of [o]
/// to [spots], plus manual spots for remove anchors that matched nothing.
({BlemishOverrides overrides, List<BlemishCandidate> manual})
resolveSpotAnchors(
  FaceFrame f,
  List<BlemishCandidate> spots,
  BlemishOverrides o, {
  required int gridW,
  required int gridH,
}) {
  if (o.keepAt.isEmpty && o.removeAt.isEmpty) {
    return (overrides: o, manual: const []);
  }
  final keep = {...o.keep}, remove = {...o.remove};
  final manual = <BlemishCandidate>[];
  final b = f.bounds;
  bool onFace(SpotAnchor a) {
    final x = a.u * gridW, y = a.v * gridH;
    return x >= b.x0 && x < b.x1 && y >= b.y0 && y < b.y1;
  }

  BlemishCandidate? match(SpotAnchor a) {
    BlemishCandidate? best;
    var bestD = double.infinity;
    for (final c in spots) {
      final dx = (c.u - a.u) * gridW, dy = (c.v - a.v) * gridH;
      final d = math.sqrt(dx * dx + dy * dy);
      final tol =
          (kAnchorMatchIod + 0.5 * math.max(a.radiusIod, c.radiusIod)) * f.iod;
      if (d <= tol && d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  for (final a in o.keepAt) {
    if (!onFace(a)) continue;
    final c = match(a);
    if (c != null) keep.add(c.id);
  }
  for (final a in o.removeAt) {
    if (!onFace(a)) continue;
    final c = match(a);
    if (c != null) {
      remove.add(c.id);
      keep.remove(c.id);
      continue;
    }
    final m = BlemishCandidate(
      id:
          'manual:${f.faceId}:${a.u.toStringAsFixed(5)}x'
          '${a.v.toStringAsFixed(5)}',
      faceId: f.faceId,
      slot: f.slot,
      u: a.u,
      v: a.v,
      radiusIod: a.radiusIod,
      kind: BlemishKind.acne,
      score: 0,
      depthL: 0,
      deltaA: 0,
      deltaB: 0,
    );
    manual.add(m);
    remove.add(m.id);
  }
  return (
    overrides: BlemishOverrides(keep: keep, remove: remove),
    manual: manual,
  );
}
