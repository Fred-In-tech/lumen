/// PatchMatch engine (Barnes et al. 2009) on one pyramid level: a dense
/// nearest-neighbour field over square patches, refined by propagation and
/// random search, and an expectation-maximization vote (Wexler et al.
/// 2007) that re-synthesizes the hole.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Returns true when the caller wants the running fill to stop.
typedef CancelCheck = bool Function();

/// Thrown from a fill when its [CancelCheck] returned true.
class InpaintCancelled implements Exception {
  const InpaintCancelled();

  @override
  String toString() => 'InpaintCancelled';
}

/// Small deterministic PRNG (xorshift32 seeded through splitmix), identical
/// on every platform and isolate.
class SeededRng {
  SeededRng(int seed) : _s = _mix(seed);

  int _s;

  static int _mix(int seed) {
    var z = (seed * 0x9E3779B1 + 0x7F4A7C15) & 0xffffffff;
    z = ((z ^ (z >> 16)) * 0x85EBCA6B) & 0xffffffff;
    z = ((z ^ (z >> 13)) * 0xC2B2AE35) & 0xffffffff;
    z ^= z >> 16;
    return z == 0 ? 0x6D2B79F5 : z;
  }

  int _next() {
    var x = _s;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    _s = x;
    return x;
  }

  /// Uniform in `0..max-1` (max ≥ 1).
  int nextInt(int max) => _next() % max;
}

/// One PatchMatch level. [feat] holds [ch] channels per pixel; channels
/// `voteFrom..voteFrom+voteCount-1` are re-synthesized inside [hole].
class PmLevel {
  PmLevel({
    required this.w,
    required this.h,
    required this.ch,
    required this.feat,
    required this.hole,
    required this.voteFrom,
    required this.voteCount,
    required this.r,
  }) {
    final sat = _sat(hole, w, h);
    final dom = <int>[], src = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final inside = x >= r && y >= r && x < w - r && y < h - r;
        final holes = _boxSum(sat, w, h, x - r, y - r, x + r + 1, y + r + 1);
        if (holes > 0) dom.add(y * w + x);
        if (inside && holes == 0) {
          valid[y * w + x] = 1;
          src.add(y * w + x);
        }
      }
    }
    domain = Int32List.fromList(dom);
    sources = Int32List.fromList(src);
  }

  final int w;
  final int h;
  final int ch;
  final Float32List feat;
  final Uint8List hole;
  final int voteFrom;
  final int voteCount;

  /// Patch radius (patch side = 2r + 1).
  final int r;

  /// Target patch centres whose patch overlaps the hole.
  late final Int32List domain;

  /// Valid source centres (patch inside the image, no hole pixel).
  late final Int32List sources;
  late final Uint8List valid = Uint8List(w * h);
  late final Int32List nnf = Int32List(w * h);
  late final Float32List dist = Float32List(w * h);

  bool get canMatch => sources.isNotEmpty && domain.isNotEmpty;

  void randomInit(SeededRng rng) {
    for (final p in domain) {
      nnf[p] = sources[rng.nextInt(sources.length)];
    }
  }

  /// NNF from the next coarser level (offsets doubled, parity kept).
  void upsampleFrom(PmLevel coarse, SeededRng rng) {
    for (final p in domain) {
      final x = p % w, y = p ~/ w;
      final cx = math.min(x >> 1, coarse.w - 1);
      final cy = math.min(y >> 1, coarse.h - 1);
      final cs = coarse.nnf[cy * coarse.w + cx];
      final sx = (2 * (cs % coarse.w) + (x & 1)).clamp(r, w - r - 1);
      final sy = (2 * (cs ~/ coarse.w) + (y & 1)).clamp(r, h - r - 1);
      final s = sy * w + sx;
      nnf[p] = valid[s] != 0 ? s : sources[rng.nextInt(sources.length)];
    }
  }

  void computeDistances() {
    for (final p in domain) {
      dist[p] = patchDistance(p, nnf[p], double.infinity);
    }
  }

  /// SSD between the target patch at [p] and the source patch at [s]
  /// (target pixels outside the image are skipped); stops early once it
  /// reaches [bound].
  double patchDistance(int p, int s, double bound) {
    final px = p % w, py = p ~/ w;
    final full = px >= r && py >= r && px < w - r && py < h - r;
    var sum = 0.0;
    for (var dy = -r; dy <= r; dy++) {
      final ty = py + dy;
      if (!full && (ty < 0 || ty >= h)) continue;
      final rowOff = dy * w;
      for (var dx = -r; dx <= r; dx++) {
        if (!full) {
          final tx = px + dx;
          if (tx < 0 || tx >= w) continue;
        }
        final t = (p + rowOff + dx) * ch, q = (s + rowOff + dx) * ch;
        for (var c = 0; c < ch; c++) {
          final d = feat[t + c] - feat[q + c];
          sum += d * d;
        }
      }
      if (sum >= bound) return sum;
    }
    return sum;
  }

  /// One propagation + random-search sweep (alternating scan direction).
  void sweep(int iteration, SeededRng rng, void Function() tick) {
    final forward = iteration.isEven;
    final step = forward ? 1 : -1;
    final n = domain.length;
    final maxR = math.max(w, h);
    for (var k = 0; k < n; k++) {
      if ((k & 4095) == 0) tick();
      final p = domain[forward ? k : n - 1 - k];
      final py = p ~/ w;
      var best = nnf[p];
      var bestD = dist[p];
      // Propagation from the already-visited horizontal/vertical neighbour.
      for (final q in [p - step, p - step * w]) {
        if (q < 0 || q >= w * h) continue;
        if (q == p - step && (q ~/ w) != py) continue;
        if (!_inDomain(q)) continue;
        // Sources sit ≥ r px from every edge, so ±1 / ±w never wraps into
        // a valid source on another row.
        final cand = nnf[q] + (p - q);
        if (cand < 0 || cand >= w * h || valid[cand] == 0) continue;
        final d = patchDistance(p, cand, bestD);
        if (d < bestD) {
          bestD = d;
          best = cand;
        }
      }
      // Random search around the current best, halving the radius.
      var rad = maxR;
      while (rad >= 1) {
        final bx = best % w, by = best ~/ w;
        final sx = (bx + rng.nextInt(2 * rad + 1) - rad).clamp(r, w - r - 1);
        final sy = (by + rng.nextInt(2 * rad + 1) - rad).clamp(r, h - r - 1);
        final cand = sy * w + sx;
        if (valid[cand] != 0 && cand != best) {
          final d = patchDistance(p, cand, bestD);
          if (d < bestD) {
            bestD = d;
            best = cand;
          }
        }
        rad >>= 1;
      }
      nnf[p] = best;
      dist[p] = bestD;
    }
  }

  late final Uint8List _domainMask = () {
    final m = Uint8List(w * h);
    for (final p in domain) {
      m[p] = 1;
    }
    return m;
  }();

  bool _inDomain(int q) => _domainMask[q] != 0;

  /// Winner-take-all vote: every hole pixel takes the centre pixel of its
  /// own nearest patch. Keeps full texture amplitude (no averaging of
  /// incoherent matches); used for the very last pass.
  void voteCenters() {
    for (final t in domain) {
      if (hole[t] == 0) continue;
      final q = nnf[t] * ch + voteFrom;
      for (var c = 0; c < voteCount; c++) {
        feat[t * ch + voteFrom + c] = feat[q + c];
      }
    }
  }

  /// Re-synthesizes the vote channels of every hole pixel as the weighted
  /// mean of the source pixels that overlapping patches map onto it.
  /// [uniform] ignores patch distances (used right after upsampling).
  void vote({bool uniform = false}) {
    final vc = voteCount;
    final acc = Float64List(w * h * vc);
    final sumW = Float64List(w * h);
    final sigma2 = uniform ? 1.0 : _sigma2();
    for (final p in domain) {
      final s = nnf[p];
      final wt = uniform ? 1.0 : math.exp(-_meanDist(p) / (2 * sigma2));
      final px = p % w, py = p ~/ w;
      for (var dy = -r; dy <= r; dy++) {
        final ty = py + dy;
        if (ty < 0 || ty >= h) continue;
        for (var dx = -r; dx <= r; dx++) {
          final tx = px + dx;
          if (tx < 0 || tx >= w) continue;
          final t = ty * w + tx;
          if (hole[t] == 0) continue;
          final q = (s + dy * w + dx) * ch + voteFrom;
          for (var c = 0; c < vc; c++) {
            acc[t * vc + c] += wt * feat[q + c];
          }
          sumW[t] += wt;
        }
      }
    }
    for (var t = 0; t < w * h; t++) {
      if (hole[t] == 0 || sumW[t] <= 0) continue;
      for (var c = 0; c < vc; c++) {
        feat[t * ch + voteFrom + c] = acc[t * vc + c] / sumW[t];
      }
    }
  }

  double _meanDist(int p) => dist[p] / ((2 * r + 1) * (2 * r + 1) * ch);

  /// Wexler's bandwidth: the 75th percentile of the mean patch distances.
  double _sigma2() {
    final stride = math.max(1, domain.length ~/ 4096);
    final sample = [
      for (var k = 0; k < domain.length; k += stride) _meanDist(domain[k]),
    ]..sort();
    if (sample.isEmpty) return 1;
    return math.max(1.0, sample[(sample.length * 3) ~/ 4]);
  }
}

/// Summed-area table of non-zero mask pixels, (w+1)×(h+1).
Int32List _sat(Uint8List m, int w, int h) {
  final sat = Int32List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0;
    for (var x = 0; x < w; x++) {
      if (m[y * w + x] != 0) row++;
      sat[(y + 1) * (w + 1) + x + 1] = sat[y * (w + 1) + x + 1] + row;
    }
  }
  return sat;
}

/// Count over `[x0, x1) × [y0, y1)`, clipped to the grid.
int _boxSum(Int32List sat, int w, int h, int x0, int y0, int x1, int y1) {
  final a = x0.clamp(0, w), b = y0.clamp(0, h);
  final c = x1.clamp(0, w), d = y1.clamp(0, h);
  if (c <= a || d <= b) return 0;
  final s = w + 1;
  return sat[d * s + c] - sat[b * s + c] - sat[d * s + a] + sat[b * s + a];
}
