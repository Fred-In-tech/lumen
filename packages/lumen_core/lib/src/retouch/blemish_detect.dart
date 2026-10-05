/// Multi-scale blemish detection (research 07 §3.3, steps 1–6).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'blemish_measure.dart';
import 'blemish_types.dart';
import 'face_frame.dart';
import 'face_regions.dart';
import 'filters.dart';
import 'lab_planes.dart';
import 'map_rect.dart';

/// Detection runs on the face crop resampled to this IOD (pixels), so the
/// thresholds are scale-free.
const double kBlemishNormIod = 160;

/// Blob scales (pixels at [kBlemishNormIod]); the DoG of scale `i` is
/// `G(σ[i+1]) − G(σ[i])`, the last entry is only the outer Gaussian.
const List<double> kBlobSigmas = [1.5, 2.5, 4.0, 6.4];

/// Robust-σ window radius: 0.15 IOD wide.
const int kNoiseWindow = 12;

/// Minimum absolute contrast (a z-score alone fires on make-up texture,
/// pores and lashes): darker by this L, or redder by this a*.
const double kMinSpotDepthL = 0.02;
const double kMinSpotRedness = 0.012;

/// Dark marks without redness need more evidence than red ones: baby
/// hairs, lash tips and make-up texture are dark too.
const double kDarkSpotMinZ = 4.0;
const double kDarkSpotMinDepthL = 0.03;

/// Highlights (no spots there): L above the masked skin mean at
/// [kHighlightBaseIod] by more than [kHighlightRel].
const double kHighlightBaseIod = 0.2;
const double kHighlightRel = 0.045;

/// Smallest spot (IOD); below it a peak is a pore or a lash tip. Spots
/// up to [kMaxSpotRadiusIod] are listed (those above `kBlemishRMax` only
/// heal at 100 or when the user asks).
const double kMinSpotRadiusIod = 0.006;
const double kMaxSpotRadiusIod = 0.065;

/// Classification (research 09 §4.5).
/// * Mole: much darker than its ring, not red, not tiny: kept.
/// * Pimple (acne): red, whatever its darkness: healed.
/// * Freckle: brown (b* up more than a*): kept. A face with
///   [kFreckleFaceCount] or more of them is freckled, and its remaining
///   small dark marks count as freckles too.
/// * Dark mark (acne kind, `dark`): the rest; healed from
///   `kDarkSpotMinSlider` on.
const double kMoleDepthL = 0.07;
const double kMoleMinRadiusIod = 0.012;
const double kAcneMinRedness = 0.012;
const double kAcneRednessRatio = 0.8;

/// A pimple's redness is not small next to its darkness (a mole or a
/// scab can carry a little red and still be mostly dark).
const double kAcneRedPerDepth = 0.2;
const double kFreckleMinBrown = 0.010;
const double kFreckleMaxRadiusIod = 0.016;
const int kFreckleFaceCount = 12;

/// Resolution gate (§4.2): no spots below [kBlemishMinIodPx] map px of
/// IOD; below [kBlemishFullIodPx] only spots of at least
/// [kBlemishSmallFaceRadiusIod].
const double kBlemishMinIodPx = 40;
const double kBlemishFullIodPx = 80;
const double kBlemishSmallFaceRadiusIod = 0.02;

/// Hessian eigenvalue ratio limit (rejects wrinkles and pore lines).
const double kMaxBlobElongation = 3;

const int kMaxBlemishesPerFace = 120;

/// Peaks examined (strongest first) before giving up on weaker ones.
const int kMaxExaminedPeaks = 600;

class _Crop {
  _Crop(this.bounds, this.s, this.w, this.h);
  final MapRect bounds;
  final double s;
  final int w;
  final int h;

  /// Continuous map coordinates of crop pixel centre `(i, j)`.
  MapPoint toMap(double i, double j) =>
      (x: bounds.x0 + (i + 0.5) / s, y: bounds.y0 + (j + 0.5) / s);
}

/// Detects acne, freckle and mole candidates on the skin of face [f].
List<BlemishCandidate> detectBlemishes(
  FaceFrame f,
  LabPlanes lab,
  FaceRegionPlanes regions, {
  required int gridW,
  required int gridH,
}) {
  if (f.iod < kBlemishMinIodPx) return const [];
  final minRadius = f.iod < kBlemishFullIodPx
      ? kBlemishSmallFaceRadiusIod
      : kMinSpotRadiusIod;
  final s = kBlemishNormIod / f.iod;
  final crop = _Crop(
    f.bounds,
    s,
    math.max(8, (f.bounds.w * s).round()),
    math.max(8, (f.bounds.h * s).round()),
  );
  final pre = s < 0.75 ? 0.5 / s : 0.0;
  Float32List sample(Float32List p, {bool blur = false}) => _resample(
    blur && pre > 0 ? gaussianBlur(p, lab.rect.w, lab.rect.h, pre) : p,
    lab.rect,
    crop,
  );
  final l = sample(lab.l, blur: true), a = sample(lab.a, blur: true);
  final b = sample(lab.b, blur: true);
  // Candidates live on the confident skin core only (not the hairline,
  // not hair texture) and not inside a highlight, where the dark gaps
  // between sparkling pores would pass for spots.
  final core = sample(_coreOrForced(regions));
  final excl = sample(regions.blemishExclusion);
  final lit = sample(_highlight(f, lab, regions.masks.norm));
  final w = crop.w, h = crop.h, n = w * h;
  final valid = Float32List(n);
  for (var i = 0; i < n; i++) {
    valid[i] = core[i] >= 0.5 && excl[i] < 0.5 && lit[i] < 0.5 ? 1 : 0;
  }
  final gl = [for (final sg in kBlobSigmas) gaussianBlur(l, w, h, sg)];
  final ga = [for (final sg in kBlobSigmas) gaussianBlur(a, w, h, sg)];
  final scales = kBlobSigmas.length - 1;
  final zBest = Float32List(n), sBest = Int8List(n), redBest = Int8List(n);
  for (var k = 0; k < scales; k++) {
    final dl = Float32List(n), da = Float32List(n);
    for (var i = 0; i < n; i++) {
      dl[i] = gl[k + 1][i] - gl[k][i];
      da[i] = ga[k][i] - ga[k + 1][i];
    }
    final sl = _robustSigma(dl, valid, w, h, 0.0015);
    final sa = _robustSigma(da, valid, w, h, 0.0008);
    for (var i = 0; i < n; i++) {
      if (valid[i] == 0) continue;
      final zl = dl[i] / sl[i], za = da[i] / sa[i];
      final z = math.max(zl, za);
      if (z > zBest[i]) {
        zBest[i] = z;
        sBest[i] = k;
        redBest[i] = za > zl ? 1 : 0;
      }
    }
  }
  final peaks = _localMaxima(zBest, w, h)
    ..sort((p, q) => zBest[q].compareTo(zBest[p]));
  // Only the strongest peaks matter; the rest are pore noise.
  if (peaks.length > kMaxExaminedPeaks) peaks.length = kMaxExaminedPeaks;
  final out = <BlemishCandidate>[];
  final kept = <({double x, double y, double r})>[];
  for (final i in peaks) {
    if (out.length >= kMaxBlemishesPerFace) break;
    final cx = i % w, cy = i ~/ w, k = sBest[i];
    final rN = _blobRadius(k);
    if (kept.any((q) => _dist(q.x, q.y, cx, cy) < 0.8 * (q.r + rN))) continue;
    final blurred = redBest[i] == 1 ? ga[k + 1] : gl[k + 1];
    if (!_isRound(blurred, w, h, cx, cy, redBest[i] == 1 ? -1 : 1)) continue;
    final m = measureSpot(
      l,
      a,
      b,
      valid,
      w,
      h,
      cx,
      cy,
      rN,
      red: redBest[i] == 1,
    );
    if (m == null || !m.isolated) continue;
    if (m.depthL < kMinSpotDepthL && m.deltaA < kMinSpotRedness) continue;
    final red =
        m.deltaA >= kAcneMinRedness &&
        m.deltaA >= kAcneRednessRatio * m.deltaB &&
        m.deltaA >= kAcneRedPerDepth * m.depthL;
    final brown = m.deltaB >= kFreckleMinBrown && m.deltaB > m.deltaA;
    if (!red &&
        !brown &&
        (zBest[i] < kDarkSpotMinZ || m.depthL < kDarkSpotMinDepthL)) {
      continue;
    }
    final rIod = m.radius / kBlemishNormIod;
    if (rIod > kMaxSpotRadiusIod || rIod < minRadius) continue;
    kept.add((x: cx.toDouble(), y: cy.toDouble(), r: m.radius));
    final c = crop.toMap(cx.toDouble(), cy.toDouble());
    final u = c.x / gridW, v = c.y / gridH;
    final kind = _classify(m.depthL, m.deltaA, m.deltaB, rIod);
    out.add(
      BlemishCandidate(
        id: '${f.faceId}:${(u * 4096).round()}x${(v * 4096).round()}',
        faceId: f.faceId,
        slot: f.slot,
        u: u,
        v: v,
        radiusIod: rIod,
        kind: kind.kind,
        score: zBest[i].toDouble(),
        depthL: m.depthL,
        deltaA: m.deltaA,
        deltaB: m.deltaB,
        dark: kind.dark,
      ),
    );
  }
  return _policy(out);
}

/// The skin core, or the effect mask where the core is empty (tiny or
/// heavily occluded faces still get their strongest spots).
Float32List _coreOrForced(FaceRegionPlanes r) =>
    r.masks.statsCount >= 64 ? r.masks.spots : r.skin;

/// 1 where the skin is lit well above the skin around it (a highlight).
Float32List _highlight(FaceFrame f, LabPlanes lab, Float32List norm) {
  final w = lab.rect.w, h = lab.rect.h;
  final sigma = math.max(3.0, kHighlightBaseIod * f.iod);
  final den = gaussianBlur(norm, w, h, sigma);
  final num = gaussianBlur(productOf([norm, lab.l]), w, h, sigma);
  final local = gaussianBlur(lab.l, w, h, math.max(1.0, 0.02 * f.iod));
  final out = Float32List(lab.l.length);
  for (var i = 0; i < out.length; i++) {
    if (den[i] < 0.05) continue;
    if (local[i] - num[i] / den[i] > kHighlightRel) out[i] = 1;
  }
  return out;
}

/// Freckled faces keep their small dark marks; at most
/// [kMaxHealsPerFace] healable spots (the strongest) remain.
List<BlemishCandidate> _policy(List<BlemishCandidate> found) {
  final freckled =
      found.where((c) => c.kind == BlemishKind.freckle).length >=
      kFreckleFaceCount;
  var heals = 0;
  final out = <BlemishCandidate>[];
  for (final c in found) {
    if (c.kind != BlemishKind.acne) {
      out.add(c);
      continue;
    }
    if (freckled && c.dark && c.radiusIod <= kFreckleMaxRadiusIod) {
      out.add(
        BlemishCandidate(
          id: c.id,
          faceId: c.faceId,
          slot: c.slot,
          u: c.u,
          v: c.v,
          radiusIod: c.radiusIod,
          kind: BlemishKind.freckle,
          score: c.score,
          depthL: c.depthL,
          deltaA: c.deltaA,
          deltaB: c.deltaB,
        ),
      );
      continue;
    }
    // [found] is strongest first.
    if (heals++ < kMaxHealsPerFace) out.add(c);
  }
  return out;
}

/// Spot radius at DoG scale [k]: 1.4·σ·√2 (§3.3 step 4) with σ the
/// geometric mean of the DoG pair (the scale it actually peaks at).
double _blobRadius(int k) =>
    1.4 * math.sqrt(kBlobSigmas[k] * kBlobSigmas[k + 1]) * math.sqrt2;

({BlemishKind kind, bool dark}) _classify(
  double depthL,
  double da,
  double db,
  double rIod,
) {
  final red =
      da >= kAcneMinRedness &&
      da >= kAcneRednessRatio * db &&
      da >= kAcneRedPerDepth * depthL;
  if (red) return (kind: BlemishKind.acne, dark: false);
  if (depthL >= kMoleDepthL && rIod >= kMoleMinRadiusIod) {
    return (kind: BlemishKind.mole, dark: false);
  }
  if (db >= kFreckleMinBrown && db > da) {
    return (kind: BlemishKind.freckle, dark: false);
  }
  return (kind: BlemishKind.acne, dark: true);
}

double _dist(double ax, double ay, int bx, int by) =>
    math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));

/// Bilinear resample of a rect plane onto the normalized crop grid.
Float32List _resample(Float32List p, MapRect rect, _Crop c) {
  final xa = Int32List(c.w), xb = Int32List(c.w), fx = Float64List(c.w);
  for (var i = 0; i < c.w; i++) {
    final px = c.bounds.x0 + (i + 0.5) / c.s - 0.5 - rect.x0;
    final x0 = px.floor();
    fx[i] = px - x0;
    xa[i] = x0.clamp(0, rect.w - 1);
    xb[i] = (x0 + 1).clamp(0, rect.w - 1);
  }
  final out = Float32List(c.w * c.h);
  for (var j = 0; j < c.h; j++) {
    final py = c.bounds.y0 + (j + 0.5) / c.s - 0.5 - rect.y0;
    final y0 = py.floor(), fy = py - y0;
    final ra = y0.clamp(0, rect.h - 1) * rect.w;
    final rb = (y0 + 1).clamp(0, rect.h - 1) * rect.w;
    for (var i = 0; i < c.w; i++) {
      final f = fx[i];
      final top = p[ra + xa[i]] * (1 - f) + p[ra + xb[i]] * f;
      final bot = p[rb + xa[i]] * (1 - f) + p[rb + xb[i]] * f;
      out[j * c.w + i] = top * (1 - fy) + bot * fy;
    }
  }
  return out;
}

/// Local robust σ of [d] over valid pixels: a global MAD estimate, then a
/// windowed RMS with outliers clipped at 3σ (§3.3 step 2).
Float32List _robustSigma(
  Float32List d,
  Float32List valid,
  int w,
  int h,
  double floor,
) {
  // A strided subsample keeps the two sorts cheap on large crops.
  final step = math.max(1, d.length ~/ 8000);
  final vals = <double>[
    for (var i = 0; i < d.length; i += step)
      if (valid[i] > 0) d[i],
  ];
  var global = floor;
  if (vals.length > 16) {
    vals.sort();
    final med = vals[vals.length ~/ 2];
    final dev = [for (final v in vals) (v - med).abs()]..sort();
    global = math.max(floor, dev[dev.length ~/ 2] * 1.4826);
  }
  final clip = 9 * global * global;
  final sq = Float32List(d.length);
  for (var i = 0; i < d.length; i++) {
    sq[i] = valid[i] * math.min(d[i] * d[i], clip);
  }
  final num = boxBlur(sq, w, h, kNoiseWindow);
  final den = boxBlur(valid, w, h, kNoiseWindow);
  final out = Float32List(d.length);
  for (var i = 0; i < d.length; i++) {
    final local = den[i] > 1e-3 ? math.sqrt(num[i] / den[i]) : global;
    out[i] = math.max(math.max(local, 0.6 * global), floor);
  }
  return out;
}

/// Pixels with z ≥ the lowest slider threshold that are 3×3 maxima.
List<int> _localMaxima(Float32List z, int w, int h) {
  final out = <int>[];
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x, v = z[i];
      if (v < kBlemishKMin) continue;
      var isMax = true;
      for (var dy = -1; dy <= 1 && isMax; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final q = z[i + dy * w + dx];
          final before = dy < 0 || (dy == 0 && dx < 0);
          if (before ? q > v : q >= v) {
            isMax = false;
            break;
          }
        }
      }
      if (isMax) out.add(i);
    }
  }
  return out;
}

/// Roundness: both Hessian eigenvalues of [sign]·[g] positive (a minimum
/// for dark spots, a maximum of a* for red ones) and their ratio < 3.
bool _isRound(Float32List g, int w, int h, int x, int y, int sign) {
  if (x < 1 || y < 1 || x >= w - 1 || y >= h - 1) return false;
  double at(int dx, int dy) => sign * g[(y + dy) * w + x + dx];
  final hxx = at(1, 0) + at(-1, 0) - 2 * at(0, 0);
  final hyy = at(0, 1) + at(0, -1) - 2 * at(0, 0);
  final hxy = (at(1, 1) - at(1, -1) - at(-1, 1) + at(-1, -1)) / 4;
  final tr = hxx + hyy, det = hxx * hyy - hxy * hxy;
  final disc = math.sqrt(math.max(0.0, tr * tr / 4 - det));
  final l1 = tr / 2 + disc, l2 = tr / 2 - disc;
  return l2 > 0 && l1 < kMaxBlobElongation * l2;
}

/// Centre-disc vs ring statistics around `(x, y)` with blob radius [r].
