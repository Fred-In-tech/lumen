/// Wrinkle detection and fill (research 07 §3.4).
///
/// 1. A Frangi-style valley map on OkLab L (Hessian at three IOD-relative
///    scales, largest eigenvalue > 0, anisotropy and edge suppression),
///    only inside the wrinkle zones and on skin.
/// 2. The valleys, dilated and feathered, are a soft hole filled by
///    push-pull from the surrounding skin on a pore-smoothed copy, so pores
///    continue through a softened line (like the blemish heal).
/// 3. The result is `ΔW = hole·(fill − smooth) ≥ 0` (L only: wrinkles are
///    shading). The retouch pass removes `wEff·ΔW`, where `wEff` comes from
///    the zone's slider; nothing else is slider dependent.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'face_frame.dart';
import 'filters.dart';
import 'map_rect.dart';
import 'push_pull.dart';
import 'region_parts.dart';
import 'wrinkle_zones.dart';

/// Hessian scales (IOD units; 1.5 / 2.5 / 4 px at IOD 160), floored at
/// [kRidgeMinSigmaPx].
const List<double> kRidgeScalesIod = [0.009, 0.016, 0.025];
const double kRidgeMinSigmaPx = 0.8;

/// Frangi anisotropy β (`exp(−Rb²/2β²)`).
const double kRidgeBeta = 0.5;

/// Edge suppression: the smoothed L at ±[kRidgeSideSigmas]·σ across the
/// valley must rise on *both* sides. `sym = (min − centre)/(max − centre)`
/// is ≈ 1 for a valley and ≈ 0 for the dark side of a step edge
/// (jawline, hairline); the strength is multiplied by it.
const double kRidgeSideSigmas = 2.0;

/// Valley strength σ²·λ₁ (OkLab L) ramp: 0 below [kRidgeLo], 1 above
/// [kRidgeHi] (a Gaussian valley of depth d gives ≈ 0.35·d at its scale).
const double kRidgeLo = 0.004;
const double kRidgeHi = 0.008;

/// Hole growth around the valley and its feather (IOD units).
const double kWrinkleDilateIod = 0.015;
const double kWrinkleFeatherIod = 0.006;

/// Holes above this weight are untrusted in the fill.
const double kWrinkleTrustCut = 0.02;

/// Pore-scale smoothing before the fill (as the blemish heal).
const double kWrinklePoreSigmaIod = 0.0035;
const double kWrinklePoreSigmaMinPx = 0.7;

/// Faces smaller than this (IOD, map px) get no wrinkle map.
const double kMinWrinkleIodPx = 60;

/// Unsigned encoding range of ΔW in `regionB` (L units per 255).
const double kWrinkleRangeL = 0.2;

/// Wrinkle fill and zone codes of one face over its work rect.
class WrinklePlanes {
  const WrinklePlanes({
    required this.rect,
    required this.delta,
    required this.zone,
  });

  factory WrinklePlanes.empty(MapRect rect) => WrinklePlanes(
    rect: rect,
    delta: Float32List(rect.area),
    zone: Uint8List(rect.area),
  );

  final MapRect rect;

  /// L lift (≥ 0) that removes every detected wrinkle, before sliders.
  final Float32List delta;

  /// Zone code per pixel, see `wrinkle_zones.dart`.
  final Uint8List zone;
}

/// Computes [WrinklePlanes] for face [f] from OkLab L [l] (spots already
/// healed) and the skin weight [skin], both covering `f.rect`. [exclude]
/// (optional, same rect) marks pixels that must not be filled.
WrinklePlanes computeWrinkles(
  FaceFrame f,
  Float32List l,
  Float32List skin, {
  Float32List? exclude,
}) {
  final rect = f.rect, iod = f.iod;
  if (iod < kMinWrinkleIodPx) return WrinklePlanes.empty(rect);
  final delta = Float32List(rect.area), zone = Uint8List(rect.area);
  final best = Float32List(rect.area);
  final dil = math.max(1, (kWrinkleDilateIod * iod).round());
  final feather = kWrinkleFeatherIod * iod;
  final sigmaMax = math.max(kRidgeMinSigmaPx, kRidgeScalesIod.last * iod);
  final margin = 3 * sigmaMax + dil + 3 * feather + 2;
  final poreSigma = math.max(
    kWrinklePoreSigmaMinPx,
    kWrinklePoreSigmaIod * iod,
  );
  for (final g in wrinkleZoneGroups(f, margin)) {
    final sub = g.sub, w = sub.w, h = sub.h;
    final lSub = cropPlane(l, rect, sub), sk = cropPlane(skin, rect, sub);
    final ex = exclude == null ? null : cropPlane(exclude, rect, sub);
    final ridge = ridgeStrength(lSub, w, h, iod, only: g.cover);
    final h0 = Float32List(sub.area);
    for (var i = 0; i < h0.length; i++) {
      final keep = ex == null ? 1.0 : 1 - ex[i];
      h0[i] =
          smoothstep(kRidgeLo, kRidgeHi, ridge[i]) * g.cover[i] * sk[i] * keep;
    }
    final hole = gaussianBlur(rankFilter(h0, w, h, dil, true), w, h, feather);
    final smooth = gaussianBlur(lSub, w, h, poreSigma);
    final trust = Float32List(sub.area);
    for (var i = 0; i < hole.length; i++) {
      final keep = ex == null ? 1.0 : 1 - ex[i];
      hole[i] = clamp01(hole[i]) * sk[i] * keep;
      trust[i] = hole[i] < kWrinkleTrustCut && sk[i] > 0.5 ? 1 : 0;
    }
    final filled = pushPull(smooth, trust, w, h);
    for (var y = sub.y0; y < sub.y1; y++) {
      var j = (y - sub.y0) * w;
      var i = rect.index(sub.x0, y);
      for (var x = 0; x < w; x++, i++, j++) {
        final d = hole[j] * (filled[j] - smooth[j]);
        if (d > delta[i]) delta[i] = d;
        if (g.cover[j] > best[i]) {
          best[i] = g.cover[j];
          zone[i] = g.code[j];
        }
      }
    }
  }
  return WrinklePlanes(rect: rect, delta: delta, zone: zone);
}

/// Multi-scale valley strength of [l] (`w × h`): the max over
/// [kRidgeScalesIod] of `σ²λ₁ · exp(−Rb²/2β²) · sym`, where `λ₁ > 0` is
/// the largest Hessian eigenvalue, `Rb = |λ₂|/λ₁` and `sym` is the
/// two-sided check of [kRidgeSideSigmas]. With [only], pixels where it is
/// 0 are skipped (left 0).
Float32List ridgeStrength(
  Float32List l,
  int w,
  int h,
  double iod, {
  Float32List? only,
}) => ridgeStrengthAt(l, w, h, [
  for (final s in kRidgeScalesIod) math.max(kRidgeMinSigmaPx, s * iod),
], only: only);

/// [ridgeStrength] at explicit pixel scales [sigmas].
Float32List ridgeStrengthAt(
  Float32List l,
  int w,
  int h,
  List<double> sigmas, {
  Float32List? only,
}) {
  final out = Float32List(w * h);
  if (w < 3 || h < 3) return out;
  const inv2b2 = 1 / (2 * kRidgeBeta * kRidgeBeta);
  for (final sigma in sigmas) {
    final g = gaussianBlur(l, w, h, sigma);
    final s2 = sigma * sigma, reach = kRidgeSideSigmas * sigma;
    double at(double x, double y) {
      final fx0 = x.floorToDouble(), fy0 = y.floorToDouble();
      final fx = x - fx0, fy = y - fy0;
      final xa = _ci(fx0.toInt(), w), xb = _ci(fx0.toInt() + 1, w);
      final ya = _ci(fy0.toInt(), h) * w, yb = _ci(fy0.toInt() + 1, h) * w;
      return (g[ya + xa] * (1 - fx) + g[ya + xb] * fx) * (1 - fy) +
          (g[yb + xa] * (1 - fx) + g[yb + xb] * fx) * fy;
    }

    for (var y = 1; y < h - 1; y++) {
      var i = y * w + 1;
      for (var x = 1; x < w - 1; x++, i++) {
        if (only != null && only[i] <= 0) continue;
        final c = g[i];
        final lxx = g[i + 1] - 2 * c + g[i - 1];
        final lyy = g[i + w] - 2 * c + g[i - w];
        final lxy =
            (g[i + w + 1] - g[i + w - 1] - g[i - w + 1] + g[i - w - 1]) * 0.25;
        final half = 0.5 * (lxx + lyy), hd = 0.5 * (lxx - lyy);
        final disc = math.sqrt(hd * hd + lxy * lxy);
        final l1 = half + disc;
        if (l1 <= 0) continue;
        final rb = (half - disc).abs() / l1;
        final v = s2 * l1 * math.exp(-rb * rb * inv2b2);
        if (v <= out[i]) continue;
        // Across-valley direction: the eigenvector of λ₁.
        var ex = lxy, ey = l1 - lxx;
        if (ex.abs() + ey.abs() < 1e-12) {
          ex = l1 - lyy;
          ey = lxy;
        }
        final n = math.sqrt(ex * ex + ey * ey);
        if (n < 1e-12) continue;
        ex *= reach / n;
        ey *= reach / n;
        final a = at(x + ex, y + ey) - c, b = at(x - ex, y - ey) - c;
        final lo = math.min(a, b), hi = math.max(a, b);
        if (lo <= 0 || hi <= 0) continue;
        final r = v * lo / hi;
        if (r > out[i]) out[i] = r;
      }
    }
  }
  return out;
}

int _ci(int i, int size) => i < 0 ? 0 : (i >= size ? size - 1 : i);

/// ΔW → unsigned byte (`regionB` left tile, B).
int encodeWrinkle(double dl) {
  final t = dl / kWrinkleRangeL;
  if (!(t > 0)) return 0;
  if (t >= 1) return 255;
  return (t * 255 + 0.5).toInt();
}

/// Inverse of [encodeWrinkle] for a (possibly interpolated) byte value.
double decodeWrinkle(double byteValue) => byteValue / 255 * kWrinkleRangeL;
