/// Shine reduction by separating the specular layer (research 09 §4.8,
/// with the dichromatic reflection model instead of an L/chroma pull).
///
/// Skin under one light is `I = d·k + m·w`: diffuse skin colour `k`
/// scaled by shading `d`, plus `m` of the light's own colour `w` mirrored
/// off the oil film. `k` comes from the broad, highlight-free skin
/// around the pixel, `w` is fitted per face from its own highlights, and
/// `(d, m)` are solved per pixel. Removing part of `m·w` takes the hot
/// spot down toward the skin underneath: the colour that appears is this
/// person's own skin with its shading, on every skin tone, never grey.
///
/// Everything is computed on the σ1 low-pass, so the delta is smooth and
/// pore-level sparkle (texture) stays on top of it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'band_split.dart';
import 'filters.dart';
import 'lab_planes.dart';

/// Share of the specular layer removed at Shine 100 (some specular is
/// kept for dimension: a matte face reads flat).
const double kShineRemove = 0.75;

/// Skin coverage of the reference blur below which no highlight is
/// judged (ramp).
const double kShineCoverLo = 0.15;
const double kShineCoverHi = 0.35;
const double kShineCoverIod = 0.1;

/// The diffuse reference is the highlight-free skin within this blur
/// (IOD): wide, so the middle of a broad forehead highlight still has
/// plain skin to compare with.
const double kShineRefIod = 0.45;

/// A pixel whose light is this much specular (by colour) is left out of
/// the reference (ramp).
const double kShineShareLo = 0.04;
const double kShineShareHi = 0.15;

/// The fitted light may be warmer than white by at most this share of the
/// way to the skin colour (a white-balanced photo has near-white light).
const double kShineLightWarmMax = 0.4;

/// Highlight gate on L above the diffuse reference (OkLab).
const double kShineGateLo = 0.02;
const double kShineGateHi = 0.07;

/// Pixels this far above the reference fit the light colour.
const double kShineFitRel = 0.05;
const int kShineFitMinPixels = 40;
const int kShineFitRounds = 4;

/// A pixel counts as shiny (need metric) when Shine 100 would darken it
/// by more than this (OkLab L).
const double kShinyDeltaL = 0.02;

class ShineResult {
  const ShineResult({
    required this.delta,
    required this.weight,
    required this.area,
    required this.p95,
  });

  /// OkLab change at Shine 100 (before the skin weight).
  final LabPlanes delta;

  /// 0..1 highlight weight (keeps colour evening off the highlights).
  final Float32List weight;

  /// Share of the skin core that is shiny, and the P95 L excess there.
  final double area;
  final double p95;
}

/// Shine layer of the face whose σ1 low-pass is `bands.l1`; [norm] and
/// [stats] are the skin masks.
ShineResult computeShine(
  SkinBands bands,
  Float32List norm,
  Float32List stats,
  double iod,
) {
  final low = bands.l1, rect = low.rect;
  final w = rect.w, h = rect.h, n = rect.area;
  final lin = [Float32List(n), Float32List(n), Float32List(n)];
  final t = Float64List(3);
  for (var i = 0; i < n; i++) {
    oklabToLinear(low.l[i], low.a[i], low.b[i], t, 0);
    for (var c = 0; c < 3; c++) {
      lin[c][i] = math.max(t[c], 0.0);
    }
  }
  // Diffuse reference: the masked mean of the skin around that is not
  // lit up. "Lit up" is first judged by colour alone (how much white
  // light the pixel holds, against this face's most saturated skin), so
  // a highlight wider than the blur is still left out of its own
  // reference.
  final sigma = math.max(3.0, kShineRefIod * iod);
  final skinDir = _saturatedSkin(lin, low, stats);
  final s3 = 1 / math.sqrt(3);
  final white = [s3, s3, s3];
  final wt = Float32List(n);
  for (var i = 0; i < n; i++) {
    if (norm[i] <= 0) continue;
    final share = _share(lin, skinDir, white, i);
    wt[i] = norm[i] * (1 - smoothstep(kShineShareLo, kShineShareHi, share));
  }
  final ref = maskedGaussians(lin, wt, w, h, sigma);
  // Where little skin is near (the very edge of the face), nothing is
  // judged: the reference there is partly hair or background.
  final cover = maskedCoverage(norm, w, h, kShineCoverIod * iod);
  final refL = Float32List(n), refA = Float32List(n), refB = Float32List(n);
  for (var i = 0; i < n; i++) {
    linearToOklab(ref[0][i], ref[1][i], ref[2][i], t, 0);
    refL[i] = t[0];
    refA[i] = t[1];
    refB[i] = t[2];
  }
  final light = _fitLight(lin, ref, low.l, refL, stats);
  final toneL = _medianL(low.l, stats);
  final dl = Float32List(n), da = Float32List(n), db = Float32List(n);
  final weight = Float32List(n);
  final excess = <double>[];
  var shiny = 0, core = 0;
  for (var i = 0; i < n; i++) {
    if (stats[i] > 0.5) core++;
    if (norm[i] <= 0) continue;
    // "The skin around": the local reference, but never brighter than
    // this face's typical skin. The forehead, nose and cheekbones are
    // lit and made up brighter as a whole; the excess a retoucher takes
    // down is measured against the face, not against the zone itself.
    final base = math.min(refL[i], toneL);
    final gate =
        smoothstep(kShineGateLo, kShineGateHi, low.l[i] - base) *
        smoothstep(kShineCoverLo, kShineCoverHi, cover[i]);
    if (gate <= 0) continue;
    // Specular amount against the skin around and against this face's
    // most saturated skin (a made-up, paler zone is still judged as
    // skin with light on it); the floor below bounds what is removed.
    final m = math.max(
      _specular(lin, ref, light, i),
      _specularFor(lin, skinDir, light, i),
    );
    if (m <= 0) continue;
    var k = kShineRemove * gate * m;
    _minus(lin, light, i, k, t);
    // Never below the surrounding skin: a highlight is compressed toward
    // it by at most [kShineRemove] of its excess, so no setting can turn
    // a hot spot into a dark or grey patch.
    final floor =
        low.l[i] - kShineRemove * gate * math.max(0.0, low.l[i] - base);
    if (t[0] < floor) {
      k *= (low.l[i] - floor) / math.max(low.l[i] - t[0], 1e-6);
      _minus(lin, light, i, k, t);
    }
    dl[i] = t[0] - low.l[i];
    weight[i] = smoothstep(0.0, 2 * kShinyDeltaL, -dl[i]);
    // What shows under the removed light moves to the surrounding skin
    // colour by the share of the highlight that went, so a dimmed
    // highlight is never a paler or greyer patch than the skin around.
    final over = low.l[i] - base;
    final q = over > 1e-4 ? clamp01(-dl[i] / over) : 0.0;
    da[i] = t[1] + q * (refA[i] - t[1]) - low.a[i];
    db[i] = t[2] + q * (refB[i] - t[2]) - low.b[i];
    if (stats[i] > 0.5 && -dl[i] > kShinyDeltaL) {
      shiny++;
      excess.add(low.l[i] - base);
    }
  }
  excess.sort();
  return ShineResult(
    delta: LabPlanes(rect, dl, da, db),
    weight: weight,
    area: core == 0 ? 0 : shiny / core,
    p95: excess.isEmpty ? 0 : excess[((excess.length - 1) * 0.95).round()],
  );
}

/// Median L of the skin core (this face's typical skin lightness).
double _medianL(Float32List l, Float32List stats) {
  final v = <double>[];
  final step = math.max(1, l.length ~/ 20000);
  for (var i = 0; i < l.length; i += step) {
    if (stats[i] > 0.5) v.add(l[i]);
  }
  if (v.isEmpty) return 1;
  v.sort();
  return v[v.length ~/ 2];
}

/// OkLab of pixel [i] with `k` of the [light] removed, into [out].
void _minus(
  List<Float32List> lin,
  List<double> light,
  int i,
  double k,
  Float64List out,
) => linearToOklab(
  math.max(lin[0][i] - k * light[0], 1e-5),
  math.max(lin[1][i] - k * light[1], 1e-5),
  math.max(lin[2][i] - k * light[2], 1e-5),
  out,
  0,
);

/// Unit linear-RGB direction of this face's most saturated skin (its
/// diffuse colour, least diluted by highlights): the mean of the more
/// chromatic half of the core.
List<double> _saturatedSkin(
  List<Float32List> lin,
  LabPlanes low,
  Float32List stats,
) {
  final sat = <double>[];
  final idx = <int>[];
  final step = math.max(1, stats.length ~/ 20000);
  for (var i = 0; i < stats.length; i += step) {
    if (stats[i] <= 0.5) continue;
    idx.add(i);
    sat.add(
      math.sqrt(low.a[i] * low.a[i] + low.b[i] * low.b[i]) /
          math.max(low.l[i], 0.05),
    );
  }
  final s3 = 1 / math.sqrt(3);
  if (idx.length < 16) return [s3, s3, s3];
  final sorted = [...sat]..sort();
  final median = sorted[sorted.length ~/ 2];
  var r = 0.0, g = 0.0, b = 0.0;
  for (var k = 0; k < idx.length; k++) {
    if (sat[k] < median) continue;
    r += lin[0][idx[k]];
    g += lin[1][idx[k]];
    b += lin[2][idx[k]];
  }
  final len = math.sqrt(r * r + g * g + b * b);
  return len < 1e-9 ? [s3, s3, s3] : [r / len, g / len, b / len];
}

/// Specular amount `m ≥ 0` of pixel [i] for a fixed unit skin direction.
double _specularFor(
  List<Float32List> lin,
  List<double> dir,
  List<double> light,
  int i,
) {
  final rho = dir[0] * light[0] + dir[1] * light[1] + dir[2] * light[2];
  final det = 1 - rho * rho;
  if (det < 1e-4) return 0;
  final ic = lin[0][i] * dir[0] + lin[1][i] * dir[1] + lin[2][i] * dir[2];
  final iw = lin[0][i] * light[0] + lin[1][i] * light[1] + lin[2][i] * light[2];
  final m = (iw - rho * ic) / det;
  return m > 0 ? m : 0;
}

/// Share of pixel [i]'s light that is specular, for the fixed skin
/// direction [dir] and [light] (both unit).
double _share(
  List<Float32List> lin,
  List<double> dir,
  List<double> light,
  int i,
) {
  final rho = dir[0] * light[0] + dir[1] * light[1] + dir[2] * light[2];
  final det = 1 - rho * rho;
  if (det < 1e-4) return 0;
  final ic = lin[0][i] * dir[0] + lin[1][i] * dir[1] + lin[2][i] * dir[2];
  final iw = lin[0][i] * light[0] + lin[1][i] * light[1] + lin[2][i] * light[2];
  final m = (iw - rho * ic) / det;
  if (m <= 0) return 0;
  final sum = lin[0][i] + lin[1][i] + lin[2][i];
  return sum < 1e-6 ? 0 : m * (light[0] + light[1] + light[2]) / sum;
}

/// Specular amount `m ≥ 0` of pixel [i]: least squares of
/// `I = d·k̂ + m·ŵ` with unit `k̂` (reference direction) and `ŵ`.
double _specular(
  List<Float32List> lin,
  List<Float32List> ref,
  List<double> light,
  int i,
) {
  final kr = ref[0][i], kg = ref[1][i], kb = ref[2][i];
  final kn = math.sqrt(kr * kr + kg * kg + kb * kb);
  if (kn < 1e-5) return 0;
  final cr = kr / kn, cg = kg / kn, cb = kb / kn;
  final rho = cr * light[0] + cg * light[1] + cb * light[2];
  final det = 1 - rho * rho;
  if (det < 1e-4) return 0;
  final ic = lin[0][i] * cr + lin[1][i] * cg + lin[2][i] * cb;
  final iw = lin[0][i] * light[0] + lin[1][i] * light[1] + lin[2][i] * light[2];
  final m = (iw - rho * ic) / det;
  return m > 0 ? m : 0;
}

/// Unit light colour fitted to the face's highlights by alternating least
/// squares (white when there are too few highlight pixels or the fit is
/// degenerate).
List<double> _fitLight(
  List<Float32List> lin,
  List<Float32List> ref,
  Float32List l,
  Float32List refL,
  Float32List stats,
) {
  final s = 1 / math.sqrt(3);
  final white = [s, s, s];
  final idx = <int>[];
  final step = math.max(1, l.length ~/ 40000);
  for (var i = 0; i < l.length; i += step) {
    if (stats[i] > 0.5 && l[i] - refL[i] > kShineFitRel) idx.add(i);
  }
  if (idx.length < kShineFitMinPixels) return white;
  var light = white;
  for (var round = 0; round < kShineFitRounds; round++) {
    var sr = 0.0, sg = 0.0, sb = 0.0;
    for (final i in idx) {
      final kr = ref[0][i], kg = ref[1][i], kb = ref[2][i];
      final kn = math.sqrt(kr * kr + kg * kg + kb * kb);
      if (kn < 1e-5) continue;
      final cr = kr / kn, cg = kg / kn, cb = kb / kn;
      final rho = cr * light[0] + cg * light[1] + cb * light[2];
      final det = 1 - rho * rho;
      if (det < 1e-4) continue;
      final ic = lin[0][i] * cr + lin[1][i] * cg + lin[2][i] * cb;
      final iw =
          lin[0][i] * light[0] + lin[1][i] * light[1] + lin[2][i] * light[2];
      final m = (iw - rho * ic) / det;
      if (m <= 0) continue;
      final d = (ic - rho * iw) / det;
      sr += m * (lin[0][i] - d * cr);
      sg += m * (lin[1][i] - d * cg);
      sb += m * (lin[2][i] - d * cb);
    }
    final norm = math.sqrt(sr * sr + sg * sg + sb * sb);
    if (norm < 1e-9 || sr <= 0 || sg <= 0 || sb <= 0) return white;
    light = [sr / norm, sg / norm, sb / norm];
  }
  // Keep the light between white and a little toward the mean skin
  // colour: the fit is noisy on few pixels, and a wrong light tints
  // what is left of the highlight.
  var kr = 0.0, kg = 0.0, kb = 0.0;
  for (final i in idx) {
    kr += ref[0][i];
    kg += ref[1][i];
    kb += ref[2][i];
  }
  final kn = math.sqrt(kr * kr + kg * kg + kb * kb);
  if (kn < 1e-9) return white;
  final dir = [kr / kn - s, kg / kn - s, kb / kn - s];
  final len2 = dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2];
  if (len2 < 1e-9) return white;
  final t =
      (((light[0] - s) * dir[0] +
                  (light[1] - s) * dir[1] +
                  (light[2] - s) * dir[2]) /
              len2)
          .clamp(0.0, kShineLightWarmMax);
  final out = [s + t * dir[0], s + t * dir[1], s + t * dir[2]];
  final on = math.sqrt(out[0] * out[0] + out[1] * out[1] + out[2] * out[2]);
  return [out[0] / on, out[1] / on, out[2] / on];
}
