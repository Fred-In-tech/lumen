/// Multi-scale PatchMatch fill (Barnes et al. 2009; EM voting after Wexler
/// et al. 2007) and the detail-restoration mode of §5.2.4.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'float_image.dart';
import 'patch_match_core.dart';
import 'push_pull.dart';

/// Plain, sendable PatchMatch settings.
class PatchMatchParams {
  const PatchMatchParams({
    this.patchRadius = 3,
    this.iterationsPerLevel = 5,
    this.seed = 1,
    this.maxLevels = 12,
    this.highWeight = 0.5,
  });

  /// Patch side = 2·radius + 1 (7×7 by default).
  final int patchRadius;

  /// EM iterations per pyramid level (the coarsest level gets twice this).
  final int iterationsPerLevel;

  /// RNG seed: the same seed and input give identical output.
  final int seed;

  /// Upper bound on pyramid levels (the fill stops coarsening once the
  /// hole is ≤ 2 patches or the image would get too small).
  final int maxLevels;

  /// Detail mode: weight of the fine band in the patch distance.
  final double highWeight;

  /// Cheaper settings for detail restoration: the fine band is grain, so
  /// 5×5 patches and 3 iterations per level suffice.
  const PatchMatchParams.detail({int seed = 1})
    : this(patchRadius: 2, iterationsPerLevel: 3, seed: seed);

  PatchMatchParams copyWith({int? maxLevels}) => PatchMatchParams(
    patchRadius: patchRadius,
    iterationsPerLevel: iterationsPerLevel,
    seed: seed,
    maxLevels: maxLevels ?? this.maxLevels,
    highWeight: highWeight,
  );
}

/// Fills hole pixels (`hole[i] != 0`) with texture copied from the known
/// pixels, coarse to fine. Known pixels are returned unchanged. Throws
/// [InpaintCancelled] once [shouldCancel] returns true.
FloatImage patchMatchFill(
  FloatImage img,
  Uint8List hole, {
  PatchMatchParams params = const PatchMatchParams(),
  CancelCheck? shouldCancel,
}) {
  final feat = _synthesize(
    img.width,
    img.height,
    img.channels,
    Float32List.fromList(img.data),
    hole,
    0,
    img.channels,
    params,
    shouldCancel,
  );
  return FloatImage(img.width, img.height, channels: img.channels, data: feat);
}

/// Detail restoration (§5.2.4): inside the hole the low band comes from
/// [guide] (e.g. an upsampled model output, same size as [img]) and the
/// fine band (scale [sigma] px) is synthesized by PatchMatch from the known
/// pixels around it, so grain and noise match the surroundings.
FloatImage patchMatchDetail(
  FloatImage img,
  Uint8List hole,
  FloatImage guide, {
  double sigma = 2,
  PatchMatchParams params = const PatchMatchParams.detail(),
  CancelCheck? shouldCancel,
}) {
  final w = img.width, h = img.height, ch = img.channels, n = w * h;
  if (guide.width != w || guide.height != h || guide.channels != ch) {
    throw ArgumentError('guide must match the image size');
  }
  final known = Float32List(n);
  final composite = img.copy();
  for (var i = 0; i < n; i++) {
    if (hole[i] == 0) {
      known[i] = 1;
    } else {
      for (var c = 0; c < ch; c++) {
        composite.data[i * ch + c] = guide.data[i * ch + c];
      }
    }
  }
  final lowKnown = gaussianBlur(img, sigma, weights: known);
  final low = gaussianBlur(composite, sigma);
  final beta = params.highWeight;
  final fc = 2 * ch;
  final feat = Float32List(n * fc);
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < ch; c++) {
      feat[i * fc + c] = low.data[i * ch + c];
      if (hole[i] == 0) {
        feat[i * fc + ch + c] =
            beta * (img.data[i * ch + c] - lowKnown.data[i * ch + c]);
      }
    }
  }
  final res = _synthesize(
    w,
    h,
    fc,
    feat,
    hole,
    ch,
    ch,
    params.copyWith(maxLevels: math.min(params.maxLevels, 3)),
    shouldCancel,
  );
  final out = img.copy();
  for (var i = 0; i < n; i++) {
    if (hole[i] == 0) continue;
    for (var c = 0; c < ch; c++) {
      out.data[i * ch + c] = low.data[i * ch + c] + res[i * fc + ch + c] / beta;
    }
  }
  return out;
}

Float32List _synthesize(
  int w,
  int h,
  int ch,
  Float32List feat,
  Uint8List hole,
  int voteFrom,
  int voteCount,
  PatchMatchParams params,
  CancelCheck? shouldCancel,
) {
  final r = params.patchRadius;
  final side = 2 * r + 1;
  final levels = [
    PmLevel(
      w: w,
      h: h,
      ch: ch,
      feat: feat,
      hole: hole,
      voteFrom: voteFrom,
      voteCount: voteCount,
      r: r,
    ),
  ];
  while (levels.length < params.maxLevels) {
    final cur = levels.last;
    final holeSide = maskBounds(cur.hole, cur.w, cur.h)?.maxSide ?? 0;
    if (holeSide <= 2 * side || math.min(cur.w, cur.h) < 8 * side) break;
    levels.add(_down(cur));
  }
  void tick() {
    if (shouldCancel?.call() ?? false) throw const InpaintCancelled();
  }

  final rng = SeededRng(params.seed);
  _membraneInit(levels.last);
  PmLevel? prev;
  var prevMatched = false;
  for (var li = levels.length - 1; li >= 0; li--) {
    tick();
    final level = levels[li];
    if (prev != null) _upsampleValues(prev, level);
    if (!level.canMatch) {
      prev = level;
      prevMatched = false;
      continue;
    }
    if (prev != null && prevMatched) {
      level.upsampleFrom(prev, rng);
      level.vote(uniform: true);
    } else {
      level.randomInit(rng);
    }
    level.computeDistances();
    final iters = prev == null
        ? 2 * params.iterationsPerLevel
        : params.iterationsPerLevel;
    for (var it = 0; it < iters; it++) {
      tick();
      level.sweep(it, rng, tick);
      if (li == 0 && it == iters - 1) {
        level.voteCenters();
      } else {
        level.vote();
        level.computeDistances();
      }
    }
    prev = level;
    prevMatched = true;
  }
  return levels.first.feat;
}

/// Half-size level: 2×2 means; a coarse pixel is a hole if any child is.
PmLevel _down(PmLevel l) {
  final w2 = (l.w + 1) >> 1, h2 = (l.h + 1) >> 1, ch = l.ch;
  final feat = Float32List(w2 * h2 * ch);
  final hole = Uint8List(w2 * h2);
  for (var y = 0; y < h2; y++) {
    for (var x = 0; x < w2; x++) {
      final o = y * w2 + x;
      var n = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final fx = 2 * x + dx, fy = 2 * y + dy;
          if (fx >= l.w || fy >= l.h) continue;
          final i = fy * l.w + fx;
          if (l.hole[i] != 0) hole[o] = 255;
          for (var c = 0; c < ch; c++) {
            feat[o * ch + c] += l.feat[i * ch + c];
          }
          n++;
        }
      }
      for (var c = 0; c < ch; c++) {
        feat[o * ch + c] /= n;
      }
    }
  }
  return PmLevel(
    w: w2,
    h: h2,
    ch: ch,
    feat: feat,
    hole: hole,
    voteFrom: l.voteFrom,
    voteCount: l.voteCount,
    r: l.r,
  );
}

/// Membrane-fills the vote channels of the coarsest level's hole.
void _membraneInit(PmLevel l) {
  final img = FloatImage(l.w, l.h, channels: l.voteCount);
  for (var i = 0; i < l.w * l.h; i++) {
    for (var c = 0; c < l.voteCount; c++) {
      img.data[i * l.voteCount + c] = l.feat[i * l.ch + l.voteFrom + c];
    }
  }
  final filled = pushPullFill(img, l.hole);
  _writeHole(l, filled.data);
}

/// Bilinear upsample of [coarse]'s vote channels into [fine]'s hole.
void _upsampleValues(PmLevel coarse, PmLevel fine) {
  final vc = fine.voteCount;
  final src = FloatImage(coarse.w, coarse.h, channels: vc);
  for (var i = 0; i < coarse.w * coarse.h; i++) {
    for (var c = 0; c < vc; c++) {
      src.data[i * vc + c] = coarse.feat[i * coarse.ch + coarse.voteFrom + c];
    }
  }
  // A 2× grid maps exactly onto (w+1)>>1 only for even sizes; resampling
  // to 2·coarse and cropping keeps the pixel-centre alignment for odd ones.
  final up = resizeBilinear(src, coarse.w * 2, coarse.h * 2);
  final vals = Float32List(fine.w * fine.h * vc);
  for (var y = 0; y < fine.h; y++) {
    for (var x = 0; x < fine.w; x++) {
      for (var c = 0; c < vc; c++) {
        vals[(y * fine.w + x) * vc + c] = up.data[(y * up.width + x) * vc + c];
      }
    }
  }
  _writeHole(fine, vals);
}

void _writeHole(PmLevel l, Float32List vals) {
  final vc = l.voteCount;
  for (var i = 0; i < l.w * l.h; i++) {
    if (l.hole[i] == 0) continue;
    for (var c = 0; c < vc; c++) {
      l.feat[i * l.ch + l.voteFrom + c] = vals[i * vc + c];
    }
  }
}
