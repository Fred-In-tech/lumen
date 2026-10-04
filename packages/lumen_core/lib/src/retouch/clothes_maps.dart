/// Clothing de-wrinkle and lint (image scope; research 06 §1.5-style
/// cleanup on the vision pipeline's clothes raster).
///
/// * Wrinkles: the skin-smoothing idea on clothes. The mid band (σ1
///   low-pass minus an edge-aware base over the clothes, the rest of the
///   frame push-pull filled from them) holds the soft folds; strong
///   structure is kept by amplitude (`keep`, like §3.1) and by gradient
///   (seams, panel edges, buttons, plus the base radius around strong
///   edges). The base is re-estimated with the removable folds taken out
///   (a local mean otherwise follows part of each fold). The result is the
///   "removable fold" field D: the pass subtracts `wrinkles · D`, so slider
///   drags are uniform-only. Fabric texture lives in the fine band and is
///   never touched.
/// * Lint: small round high-contrast specks (DoG blobs, either polarity)
///   are push-pull filled from the fabric around them (feathered holes);
///   the pass adds `lint · Δ`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'filters.dart';
import 'lab_planes.dart';
import 'push_pull.dart';

/// Edge-aware base: guided filter radius (fraction of the long edge) and ε.
const double kClothesBaseFrac = 0.02;
const double kClothesBaseEps = 0.002;

/// Base estimates (the first from the image, the rest with the removable
/// folds taken out).
const int kClothesBaseIterations = 3;

/// Mid-band structure above this (OkLab L, ramp to 2.5×) is kept.
const double kClothesKeepL = 0.05;

/// Gradient (L per texel, 3×3 max) ramp that protects seams and edges
/// (and, feathered, the base radius around them).
const double kClothesEdgeLo = 0.01;
const double kClothesEdgeHi = 0.025;

/// Clothes needed (fraction of the frame) before anything is built.
const double kMinClothesFraction = 0.01;

/// Lint: DoG scale pairs (texels), z-score and absolute contrast.
const List<(double, double)> kLintScales = [(0.8, 1.6), (1.6, 3.2)];
const double kLintZ = 6;
const double kLintMinContrast = 0.04;

/// Lint hole radius = this × the blob radius, plus a feather.
const double kLintHoleScale = 1.5;

/// Signed encoding ranges (OkLab L, a, b) of the fold field and lint fill.
const List<double> kClothesFoldRange = [0.2, 0.08, 0.08];
const List<double> kLintRange = [0.6, 0.15, 0.15];

/// Decoded field magnitude below which a pixel is untouched (bilinear
/// rounding residue of neutral texels; the shader uses the same literal).
const double kClothesZero = 1e-6;

/// The two clothes fields over the whole grid (zero off the clothes).
class ClothesPlanes {
  const ClothesPlanes(this.fold, this.lint);

  /// Removable fold field D (OkLab L, a, b).
  final List<Float32List> fold;

  /// Lint fill delta Δ (OkLab L, a, b).
  final List<Float32List> lint;
}

/// Clothes fields for [lab] (`w × h`), its σ1 low-pass [g1] and the
/// clothes matte [cloth] (0..1), or null when there is too little cloth.
ClothesPlanes? computeClothes(
  LabPlanes lab,
  LabPlanes g1,
  Float32List cloth,
  int w,
  int h,
) {
  final n = w * h, long = math.max(w, h);
  var area = 0.0;
  for (var i = 0; i < n; i++) {
    area += cloth[i] >= 0.5 ? 1 : 0;
  }
  if (area < kMinClothesFraction * n) return null;
  // Edge-aware base over the clothes (the rest filled from the clothes).
  final trust = Float32List(n);
  for (var i = 0; i < n; i++) {
    trust[i] = smoothstep(0.5, 0.9, cloth[i]);
  }
  final holes = _lintHoles(lab, cloth, w, h);
  final filled = g1.mapChannels((c) => pushPull(c, trust, w, h));
  final rBase = math.max(1, (kClothesBaseFrac * long).round());
  final protect = _protect(filled.l, holes, w, h, rBase);
  // The base is a local mean, so it follows part of each fold: re-estimate
  // it from the image with the removable folds taken out.
  var guide = filled.channels;
  var base = guidedFilter(guide[0], guide, w, h, rBase, kClothesBaseEps);
  var k = _removable(guide[0], base[0], cloth, protect);
  for (var it = 1; it < kClothesBaseIterations; it++) {
    final b = base, kk = k;
    guide = [
      for (var c = 0; c < 3; c++)
        Float32List.fromList([
          for (var i = 0; i < n; i++)
            filled.channels[c][i] - kk[i] * (filled.channels[c][i] - b[c][i]),
        ]),
    ];
    base = guidedFilter(guide[0], guide, w, h, rBase, kClothesBaseEps);
    k = _removable(filled.l, base[0], cloth, protect);
  }
  final fold = [for (var c = 0; c < 3; c++) Float32List(n)];
  final g = g1.channels;
  for (var i = 0; i < n; i++) {
    if (k[i] <= 0) continue;
    for (var c = 0; c < 3; c++) {
      fold[c][i] = k[i] * (g[c][i] - base[c][i]);
    }
  }
  return ClothesPlanes(fold, _lintFill(lab, cloth, holes, w, h));
}

/// Seam and edge protection (0..1) on the clothes-filled σ1 image [l]
/// (so the clothes outline is no edge): the 3×3 max gradient ramp, plus
/// the band of radius [r] around strong edges where the base bends
/// (dilated, feathered). Lint specks (near [holes]) raise no band: they
/// are healed, and a band would leave fold stubs around them.
Float32List _protect(Float32List l, Float32List? holes, int w, int h, int r) {
  final n = w * h;
  final grad = Float32List(n), strong = Float32List(n);
  final lint = holes == null ? null : rankFilter(holes, w, h, 2, true);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final gx = 0.5 * (l[i + 1] - l[i - 1]);
      final gy = 0.5 * (l[i + w] - l[i - w]);
      final m = math.sqrt(gx * gx + gy * gy);
      strong[i] = m >= kClothesEdgeHi && (lint == null || lint[i] == 0) ? 1 : 0;
      grad[i] = smoothstep(kClothesEdgeLo, kClothesEdgeHi, m);
    }
  }
  final edge = rankFilter(grad, w, h, 1, true);
  final near = boxBlur(
    rankFilter(strong, w, h, r, true),
    w,
    h,
    math.max(1, r ~/ 2),
  );
  for (var i = 0; i < n; i++) {
    edge[i] = 1 - math.max(edge[i], near[i]);
  }
  return edge;
}

/// Removable fraction of the mid band (`l − base`): on the clothes, small
/// amplitudes only, away from seams and edges.
Float32List _removable(
  Float32List l,
  Float32List base,
  Float32List cloth,
  Float32List protect,
) {
  final k = Float32List(l.length);
  for (var i = 0; i < l.length; i++) {
    if (cloth[i] <= 0) continue;
    final mid = (l[i] - base[i]).abs();
    final keep = smoothstep(kClothesKeepL, 2.5 * kClothesKeepL, mid);
    k[i] = cloth[i] * (1 - keep) * protect[i];
  }
  return k;
}

/// Lint holes (0..1, feathered): DoG blobs on the clothes core, or null
/// when there are none.
Float32List? _lintHoles(LabPlanes lab, Float32List cloth, int w, int h) {
  final n = w * h;
  final hole = Float32List(n);
  final core = Float32List(n);
  for (var i = 0; i < n; i++) {
    core[i] = cloth[i] >= 0.9 ? 1 : 0;
  }
  final valid = erode(core, w, h, 3);
  var anyHole = false;
  for (final (sa, sb) in kLintScales) {
    final ga = gaussianBlur(lab.l, w, h, sa),
        gb = gaussianBlur(lab.l, w, h, sb);
    final d = Float32List(n);
    final samples = <double>[];
    for (var i = 0; i < n; i++) {
      d[i] = ga[i] - gb[i];
      if (valid[i] > 0 && i % 3 == 0) samples.add(d[i].abs());
    }
    if (samples.length < 32) continue;
    samples.sort();
    final sigma = math.max(1e-4, 1.4826 * samples[samples.length ~/ 2]);
    final radius = 1.4 * math.sqrt(sa * sb) * math.sqrt2;
    final rh = kLintHoleScale * radius + 1;
    for (var y = 2; y < h - 2; y++) {
      for (var x = 2; x < w - 2; x++) {
        final i = y * w + x;
        final v = d[i].abs();
        if (valid[i] == 0 || v < kLintMinContrast || v < kLintZ * sigma) {
          continue;
        }
        if (!_isPeak(d, w, i, v) || !_isRound(ga, w, i)) continue;
        anyHole = true;
        final r = rh.ceil() + 1;
        for (var yy = math.max(0, y - r); yy <= math.min(h - 1, y + r); yy++) {
          for (
            var xx = math.max(0, x - r);
            xx <= math.min(w - 1, x + r);
            xx++
          ) {
            final dd = math.sqrt(
              ((xx - x) * (xx - x) + (yy - y) * (yy - y)).toDouble(),
            );
            final a = 1 - smoothstep(rh - 1, rh + 0.5, dd);
            final j = yy * w + xx;
            if (a > hole[j]) hole[j] = a;
          }
        }
      }
    }
  }
  return anyHole ? hole : null;
}

/// Lint fill delta: the [hole]s healed by push-pull from the fabric.
List<Float32List> _lintFill(
  LabPlanes lab,
  Float32List cloth,
  Float32List? hole,
  int w,
  int h,
) {
  final n = w * h;
  final out = [for (var c = 0; c < 3; c++) Float32List(n)];
  if (hole == null) return out;
  final trust = Float32List(n);
  for (var i = 0; i < n; i++) {
    trust[i] = 1 - hole[i];
  }
  for (var c = 0; c < 3; c++) {
    final src = lab.channels[c];
    final fill = pushPull(src, trust, w, h);
    for (var i = 0; i < n; i++) {
      if (hole[i] > 0) out[c][i] = cloth[i] * hole[i] * (fill[i] - src[i]);
    }
  }
  return out;
}

/// |d| at [i] is the max of its 3×3 neighbourhood (same sign).
bool _isPeak(Float32List d, int w, int i, double v) {
  final s = d[i].sign;
  for (final o in [-w - 1, -w, -w + 1, -1, 1, w - 1, w, w + 1]) {
    final u = d[i + o];
    if (u.sign == s && u.abs() > v) return false;
  }
  return true;
}

/// Hessian eigenvalues of [g] at [i] have the same sign and a ratio below
/// 3: a round blob, not a seam or a thread.
bool _isRound(Float32List g, int w, int i) {
  final c = g[i];
  final lxx = g[i + 1] - 2 * c + g[i - 1], lyy = g[i + w] - 2 * c + g[i - w];
  final lxy =
      0.25 * (g[i + w + 1] - g[i + w - 1] - g[i - w + 1] + g[i - w - 1]);
  final half = 0.5 * (lxx + lyy), hd = 0.5 * (lxx - lyy);
  final disc = math.sqrt(hd * hd + lxy * lxy);
  final l1 = half + disc, l2 = half - disc;
  if (l1 * l2 <= 0) return false;
  final a = math.max(l1.abs(), l2.abs()), b = math.min(l1.abs(), l2.abs());
  return a < 3 * b;
}
