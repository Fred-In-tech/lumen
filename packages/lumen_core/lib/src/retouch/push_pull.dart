import 'dart:math' as math;
import 'dart:typed_data';

/// Push-pull scattered-data fill (Gortler et al. 1996), research 07 §3.3.
///
/// [weights] (0..1) say how much each pixel of [values] is trusted (0 = a
/// hole). Pull: 2×2 weight-averaged reduction down to one pixel, with the
/// weight clamped to 1. Push: each level becomes `w·v + (1 − w)·up`, where
/// `up` is the bilinear upsample of the coarser filled level. Returns a new
/// plane; pixels with weight 1 keep their value exactly.
Float32List pushPull(Float32List values, Float32List weights, int w, int h) {
  final vs = <Float32List>[];
  final ws = <Float32List>[];
  final sizes = <(int, int)>[];
  var v = Float32List.fromList(values);
  var wt = Float32List(weights.length);
  for (var i = 0; i < wt.length; i++) {
    final x = weights[i];
    wt[i] = x <= 0 ? 0 : (x >= 1 ? 1 : x);
  }
  var cw = w, ch = h;
  vs.add(v);
  ws.add(wt);
  sizes.add((cw, ch));
  while (cw > 1 || ch > 1) {
    final nw = math.max(1, (cw + 1) >> 1), nh = math.max(1, (ch + 1) >> 1);
    final nv = Float32List(nw * nh), nwt = Float32List(nw * nh);
    for (var y = 0; y < nh; y++) {
      for (var x = 0; x < nw; x++) {
        var sw = 0.0, sv = 0.0;
        for (var dy = 0; dy < 2; dy++) {
          final yy = 2 * y + dy;
          if (yy >= ch) continue;
          for (var dx = 0; dx < 2; dx++) {
            final xx = 2 * x + dx;
            if (xx >= cw) continue;
            final i = yy * cw + xx;
            sw += wt[i];
            sv += wt[i] * v[i];
          }
        }
        final o = y * nw + x;
        nv[o] = sw > 0 ? sv / sw : 0;
        nwt[o] = math.min(1.0, sw);
      }
    }
    v = nv;
    wt = nwt;
    cw = nw;
    ch = nh;
    vs.add(v);
    ws.add(wt);
    sizes.add((cw, ch));
  }
  // Push, coarse to fine.
  var filled = vs.last;
  for (var k = vs.length - 2; k >= 0; k--) {
    final (lw, lh) = sizes[k];
    final (uw, uh) = sizes[k + 1];
    final lv = vs[k], lwt = ws[k];
    final out = Float32List(lw * lh);
    for (var y = 0; y < lh; y++) {
      final py = (y + 0.5) / 2 - 0.5;
      final y0 = py.floor(), fy = py - y0;
      final ya = y0.clamp(0, uh - 1), yb = (y0 + 1).clamp(0, uh - 1);
      for (var x = 0; x < lw; x++) {
        final i = y * lw + x;
        final wi = lwt[i];
        if (wi >= 1) {
          out[i] = lv[i];
          continue;
        }
        final px = (x + 0.5) / 2 - 0.5;
        final x0 = px.floor(), fx = px - x0;
        final xa = x0.clamp(0, uw - 1), xb = (x0 + 1).clamp(0, uw - 1);
        final top = filled[ya * uw + xa] * (1 - fx) + filled[ya * uw + xb] * fx;
        final bot = filled[yb * uw + xa] * (1 - fx) + filled[yb * uw + xb] * fx;
        final up = top * (1 - fy) + bot * fy;
        out[i] = wi * lv[i] + (1 - wi) * up;
      }
    }
    filled = out;
  }
  return filled;
}
