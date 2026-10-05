/// Glasses glare (research 07 §3.12): a lens reflection is an additive,
/// smooth, near-white veil. It is estimated and subtracted, never filled,
/// so the eye, lashes and brows under a semi-transparent glare survive.
///
/// 1. Lens zone: an ellipse around each iris centre (face axes), roughly
///    the lens outline from brow to cheek. Frame pixels (far darker than
///    the face around the lens) and catchlights are filled before the
///    low-pass and never corrected.
/// 2. On skin inside the zone (eyes and brows excluded), the low-passed L
///    is compared with a push-pull fill from the skin around the zone:
///    brighter by 0.03–0.08 L and less saturated means glare. An opening
///    drops anything smaller than a catchlight; the evidence then decides
///    where (a ramp to full coverage, grown so the band's soft tails go
///    too), the measured veil decides how much.
/// 3. The veil is measured in linear luminance (glare is added light):
///    `Y(low) − Y(ref)`, the reference being the same spot on the other
///    side of the face (mirrored across the face axis) when that is darker
///    than the surround by at most [kGlareMirrorSlack]. Eyes and brows take
///    the veil the other eye confirms (their excess over the mirrored eye),
///    at most a little above the strongest veil on the skin next to them,
///    so catchlights, eye whites and a normal eye are never treated as
///    glare.
/// 4. Correction: subtract that much grey light in linear RGB (×
///    [kGlareMax], never below 5 % of the darkest channel), so chroma comes
///    back on its own. The OkLab delta joins the heal deltas with spot code
///    [kGlareCode], selected by the Glasses glare slider. Tinted lenses and
///    very large glare are under-estimated (the references are untinted /
///    glare-free face), so they degrade to a partial reduction, never a
///    fill.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'blemish_heal.dart';
import 'blemish_types.dart';
import 'face_frame.dart';
import 'face_mesh.dart';
import 'filters.dart';
import 'lab_planes.dart';
import 'map_rect.dart';
import 'push_pull.dart';
import 'region_parts.dart';

/// Lens zone: half-width / half-height (IOD) around each iris centre,
/// dropped by [kLensDropIod] toward the chin.
const double kLensHalfWidthIod = 0.44;
const double kLensHalfHeightIod = 0.34;
const double kLensDropIod = 0.02;

/// Veil detection on the low-passed image (σ in IOD).
const double kGlareLowSigmaIod = 0.025;
const double kGlareLo = 0.03;
const double kGlareHi = 0.08;

/// Frame pixels: darker than the face around the lens by this (OkLab L).
const double kGlareFrameDepth = 0.25;

/// Glare is less saturated than the face around the lens: chroma ratio
/// ramp (1 below lo, 0 above hi).
const double kGlareDesatLo = 0.6;
const double kGlareDesatHi = 0.9;

/// Eyes and brows (grown by this, IOD) inherit the veil instead of
/// defining it.
const double kGlareInheritGrowIod = 0.015;

/// Opening radius: glare is bigger than a catchlight.
const double kGlareMinRadiusIod = 0.025;

/// Eyes and brows inherit the veil only where glare covers at least this
/// share of their surroundings (lo → hi ramp).
const double kGlareInheritLo = 0.02;
const double kGlareInheritHi = 0.1;

/// The mirrored skin may stand in for the lens surround down to this much
/// darker (linear luminance).
const double kGlareMirrorSlack = 0.04;

/// Eyes and brows take at most [kGlareNearGain] × the strongest skin veil
/// within [kGlareNearIod] (the low-pass flattens the skin peak a little).
const double kGlareNearIod = 0.15;
const double kGlareNearGain = 1.15;
const double kGlareNearSmoothIod = 0.04;

/// Catchlights: L above a σ (IOD) blur by lo → hi.
const double kSparkleSigmaIod = 0.02;
const double kSparkleLo = 0.08;
const double kSparkleHi = 0.15;

/// Opened evidence → coverage ramp.
const double kGlareEvidenceLo = 0.25;
const double kGlareEvidenceHi = 0.6;

/// The detection grows by this (IOD) to take the band's soft tails.
const double kGlareGrowIod = 0.04;

/// At Glasses glare 100 this share of the veil is removed; the veil never
/// exceeds [kGlareMaxY] (linear luminance).
const double kGlareMax = 0.95;
const double kGlareMaxY = 0.5;

/// The full OkLab correction of one face's glare over [sub] (zero where
/// there is none) and the region its spot code covers.
class GlarePlanes {
  const GlarePlanes(this.sub, this.dl, this.da, this.db, this.cover);
  final MapRect sub;
  final Float32List dl;
  final Float32List da;
  final Float32List db;

  /// 1 where the glare delta (or its σ1 spill) lands.
  final Uint8List cover;
}

/// Detects the glasses glare of face [f] on [lab] (covering `f.rect`), or
/// null when there is none.
GlarePlanes? detectGlare(FaceFrame f, LabPlanes lab) {
  final iod = f.iod, rect = f.rect;
  final ex = (x: f.axis.y, y: -f.axis.x);
  final centres = [
    for (final c in [FaceMesh.rightIrisCenter, FaceMesh.leftIrisCenter])
      (
        x: f.xs[c] + f.axis.x * kLensDropIod * iod,
        y: f.ys[c] + f.axis.y * kLensDropIod * iod,
      ),
  ];
  final hw = kLensHalfWidthIod * iod, hh = kLensHalfHeightIod * iod;
  final pad = 0.15 * iod;
  final sub = boxOf(
    [
      for (final c in centres) ...[
        (x: c.x - hw - pad, y: c.y - hw - pad),
        (x: c.x + hw + pad, y: c.y + hw + pad),
      ],
    ],
    0,
    rect,
  );
  if (sub.isEmpty || iod < 24) return null;
  final w = sub.w, h = sub.h, n = sub.area;
  // Lens zone (soft ellipses in face axes).
  final zone = Float32List(n);
  for (var y = sub.y0; y < sub.y1; y++) {
    for (var x = sub.x0; x < sub.x1; x++) {
      var z = 0.0;
      for (final c in centres) {
        final dx = x + 0.5 - c.x, dy = y + 0.5 - c.y;
        final u = (dx * ex.x + dy * ex.y) / hw;
        final v = (dx * f.axis.x + dy * f.axis.y) / hh;
        z = math.max(z, 1 - smoothstep(0.85, 1.0, math.sqrt(u * u + v * v)));
      }
      zone[sub.index(x, y)] = z;
    }
  }
  // Eyes and brows: they inherit the veil instead of defining it.
  final features = unionOfPolygons([
    f.pts(FaceMesh.rightEye),
    f.pts(FaceMesh.leftEye),
    f.pts([...FaceMesh.rightBrowLower, ...FaceMesh.rightBrowUpper.reversed]),
    f.pts([...FaceMesh.leftBrowLower, ...FaceMesh.leftBrowUpper.reversed]),
  ], sub);
  final inherit = gaussianBlur(
    dilate(features, w, h, math.max(1, (kGlareInheritGrowIod * iod).round())),
    w,
    h,
    0.01 * iod,
  );
  final l = cropPlane(lab.l, rect, sub);
  final a = cropPlane(lab.a, rect, sub), b = cropPlane(lab.b, rect, sub);
  final sigma = kGlareLowSigmaIod * iod;
  final outside = Float32List(n);
  for (var i = 0; i < n; i++) {
    // Skin around the lens: brows and eyes are no reference.
    outside[i] = zone[i] > 0 ? 0 : 1 - clamp01(inherit[i]);
  }
  // Frames: pixels far darker than the face around the lens are filled
  // before the low-pass, so a rim does not hide the glare next to it.
  final rough = pushPull(gaussianBlur(l, w, h, sigma), outside, w, h);
  final notFrame = Float32List(n);
  for (var i = 0; i < n; i++) {
    // Pupils, lashes and brows are dark too, but they are no frame.
    notFrame[i] = l[i] < rough[i] - kGlareFrameDepth && inherit[i] < 0.5
        ? 0
        : 1;
  }
  // Catchlights are filled too: they differ between the eyes, and the
  // eyes are compared with each other below.
  final sparkle = _sparkle(l, sub, f);
  final lowTrust = Float32List.fromList([
    for (var i = 0; i < n; i++) notFrame[i] * (1 - sparkle[i]),
  ]);
  Float32List low(Float32List c) =>
      gaussianBlur(pushPull(c, lowTrust, w, h), w, h, sigma);
  // Frames themselves are never corrected (soft edge of one pixel
  // outward).
  final frameKeep = gaussianBlur(notFrame, w, h, 0.7);
  for (var i = 0; i < n; i++) {
    frameKeep[i] *= notFrame[i];
  }
  final lowL = low(l), lowA = low(a), lowB = low(b);
  final chroma = Float32List(n);
  for (var i = 0; i < n; i++) {
    chroma[i] = math.sqrt(lowA[i] * lowA[i] + lowB[i] * lowB[i]);
  }
  final refL = pushPull(lowL, outside, w, h);
  final refC = pushPull(chroma, outside, w, h);
  final lowY = Float32List(n);
  for (var i = 0; i < n; i++) {
    lowY[i] = lowL[i] * lowL[i] * lowL[i];
  }
  final refY = pushPull(lowY, outside, w, h);
  // Glare evidence on the skin part of the zone.
  final g0 = Float32List(n);
  var any = false;
  for (var i = 0; i < n; i++) {
    final desat = chroma[i] / math.max(refC[i], 0.005);
    g0[i] =
        smoothstep(kGlareLo, kGlareHi, lowL[i] - refL[i]) *
        (1 - smoothstep(kGlareDesatLo, kGlareDesatHi, desat)) *
        zone[i] *
        (1 - clamp01(inherit[i]));
    if (g0[i] > 0.5) any = true;
  }
  if (!any) return null;
  final open = math.max(1, (kGlareMinRadiusIod * iod).round());
  final g1 = rankFilter(rankFilter(g0, w, h, open, false), w, h, open, true);
  // Evidence decides where; the measured veil decides how much.
  for (var i = 0; i < n; i++) {
    g1[i] = smoothstep(kGlareEvidenceLo, kGlareEvidenceHi, g1[i]);
  }
  final grow = math.max(1, (kGlareGrowIod * iod).round());
  final mask = gaussianBlur(rankFilter(g1, w, h, grow, true), w, h, 0.5 * grow);
  final mid = f.eyeMid;
  // Mirror of (x, y) across the face axis through the eye midpoint.
  int mirror(int x, int y) {
    final px = x + 0.5 - mid.x, py = y + 0.5 - mid.y;
    final u = px * ex.x + py * ex.y, t = px * f.axis.x + py * f.axis.y;
    final mx = (mid.x - u * ex.x + t * f.axis.x).floor();
    final my = (mid.y - u * ex.y + t * f.axis.y).floor();
    return sub.contains(mx, my) ? sub.index(mx, my) : -1;
  }

  final veil = Float32List(n), skinTrust = Float32List(n);
  any = false;
  for (var y = sub.y0; y < sub.y1; y++) {
    for (var x = sub.x0; x < sub.x1; x++) {
      final i = sub.index(x, y);
      final skin = 1 - clamp01(inherit[i]);
      final cover = clamp01(mask[i]) * zone[i];
      mask[i] = cover * skin;
      skinTrust[i] = skin;
      if (cover <= 0) continue;
      // The same spot of the other side is the closer reference (the face
      // around the lens is shaded differently from the eye socket); it is
      // trusted down to kGlareMirrorSlack below the surround, and up to
      // anything (a brighter mirror only means less correction).
      final m = mirror(x, y);
      final ref = m < 0
          ? refY[i]
          : math.max(lowY[m], refY[i] - kGlareMirrorSlack);
      veil[i] = cover * (lowY[i] - ref).clamp(0.0, kGlareMaxY);
      if (veil[i] > 1e-3) any = true;
    }
  }
  if (!any) return null;
  // Eyes and brows: at most the strongest veil on the skin next to them,
  // confirmed by the mirrored other eye; catchlights keep their sparkle.
  final skinVeil = Float32List.fromList([
    for (var i = 0; i < n; i++) veil[i] * skinTrust[i],
  ]);
  // Smooth, so an eye never gets a patchy correction.
  final vNear = gaussianBlur(
    pushPull(
      rankFilter(
        skinVeil,
        w,
        h,
        math.max(1, (kGlareNearIod * iod).round()),
        true,
      ),
      skinTrust,
      w,
      h,
    ),
    w,
    h,
    kGlareNearSmoothIod * iod,
  );
  final mFill = pushPull(mask, skinTrust, w, h);
  final dl = Float32List(n), da = Float32List(n), db = Float32List(n);
  final cover = Uint8List(n);
  final lin = Float64List(3), out = Float64List(3);
  for (var y = sub.y0; y < sub.y1; y++) {
    for (var x = sub.x0; x < sub.x1; x++) {
      final i = sub.index(x, y);
      final inh = clamp01(inherit[i]);
      var v = veil[i];
      if (inh > 0 && mFill[i] > 1e-3) {
        final m = mirror(x, y);
        final other = m < 0 ? lowY[i] : lowY[m];
        final eye =
            math.min(
              kGlareNearGain * vNear[i],
              math.max(0.0, lowY[i] - other),
            ) *
            smoothstep(kGlareInheritLo, kGlareInheritHi, mFill[i]) *
            (1 - sparkle[i]);
        v = v * (1 - inh) + eye * inh;
      }
      v *= zone[i] * frameKeep[i];
      if (v <= 1e-4) continue;
      // Subtract grey light in linear RGB.
      oklabToLinear(l[i], a[i], b[i], lin, 0);
      final darkest = math.min(lin[0], math.min(lin[1], lin[2]));
      final grey = math.min(kGlareMax * v, 0.95 * math.max(0.0, darkest));
      if (grey <= 0) continue;
      linearToOklab(lin[0] - grey, lin[1] - grey, lin[2] - grey, out, 0);
      dl[i] = out[0] - l[i];
      da[i] = out[1] - a[i];
      db[i] = out[2] - b[i];
      cover[i] = 1;
    }
  }
  // The code covers the delta plus a bilinear fringe.
  final spill = (kSpotCodeSpillSigmas * kHealSpillIod * iod).ceil();
  final grown = dilate(
    Float32List.fromList([for (final c in cover) c.toDouble()]),
    w,
    h,
    spill,
  );
  for (var i = 0; i < n; i++) {
    cover[i] = grown[i] > 0 ? 1 : 0;
  }
  return GlarePlanes(sub, dl, da, db, cover);
}

/// Catchlights (0..1): small near-white blobs well above their
/// surroundings on the irises (the cornea). Glare over them is left alone
/// (it is clipped light).
Float32List _sparkle(Float32List l, MapRect sub, FaceFrame f) {
  final w = sub.w, h = sub.h;
  final local = gaussianBlur(l, w, h, kSparkleSigmaIod * f.iod);
  final out = Float32List(l.length);
  final irises = [
    (FaceMesh.rightIrisCenter, f.irisRadiusRight),
    (FaceMesh.leftIrisCenter, f.irisRadiusLeft),
  ];
  for (var y = sub.y0; y < sub.y1; y++) {
    for (var x = sub.x0; x < sub.x1; x++) {
      final i = sub.index(x, y);
      var cornea = 0.0;
      for (final (c, r) in irises) {
        final d = math.sqrt(
          math.pow(x + 0.5 - f.xs[c], 2) + math.pow(y + 0.5 - f.ys[c], 2),
        );
        cornea = math.max(cornea, 1 - smoothstep(0.9 * r, 1.05 * r, d));
      }
      if (cornea <= 0) continue;
      out[i] =
          cornea *
          smoothstep(kSparkleLo, kSparkleHi, l[i] - local[i]) *
          smoothstep(0.8, 0.9, l[i]);
    }
  }
  return gaussianBlur(dilate(out, w, h, 1), w, h, 0.5);
}

/// [heal] with the glare correction merged in: code [kGlareCode] where
/// no spot code is set, and the corrected image as the input of the bands.
HealPlanes mergeGlare(HealPlanes heal, GlarePlanes g) {
  final rect = heal.rect, sub = g.sub;
  final full = [g.dl, g.da, g.db];
  final out = [
    for (final p in [heal.dl, heal.da, heal.db]) Float32List.fromList(p),
  ];
  final codes = Uint8List.fromList(heal.spotCode);
  final healed = [
    for (final c in heal.healed.channels) Float32List.fromList(c),
  ];
  for (var y = sub.y0; y < sub.y1; y++) {
    for (var x = sub.x0; x < sub.x1; x++) {
      final j = sub.index(x, y), i = rect.index(x, y);
      if (g.cover[j] == 0) continue;
      if (codes[i] != 0 && codes[i] != kGlareCode) continue;
      codes[i] = kGlareCode;
      for (var c = 0; c < 3; c++) {
        out[c][i] += full[c][j];
        healed[c][i] += full[c][j];
      }
    }
  }
  return HealPlanes(
    rect: rect,
    dl: out[0],
    da: out[1],
    db: out[2],
    spotCode: codes,
    healed: LabPlanes(rect, healed[0], healed[1], healed[2]),
  );
}
