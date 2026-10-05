/// What each skin slider changes at 100, per pixel (research 09 §4.3,
/// §4.4, §4.6, §4.7), computed once per photo with the maps.
///
/// The retouch pass is then a sum: `out = src + Σ slider · mask · Δ`.
/// Every Δ is built from the bands above the pore band, so no slider
/// value can attenuate pores, and every Δ is proportional to what it
/// corrects (blotch amplitude, colour excursion, specular amount,
/// under-eye darkness), so clean skin changes by almost nothing whatever
/// the slider says.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'band_split.dart';
import 'face_frame.dart';
import 'face_mesh.dart';
import 'filters.dart';
import 'lab_planes.dart';
import 'shine_model.dart';
import 'skin_mask.dart';

/// Band reductions at Smooth 100 (§4.3): the hard limits.
const double kSmoothB1 = 0.30;
const double kSmoothB2 = 0.75;
const double kSmoothB3 = 0.40;

/// Regional multipliers on Smooth (§4.3): pores are expected on the nose,
/// thin skin shows over-smoothing first.
const double kSmoothNose = 0.6;
const double kSmoothUpperLip = 0.5;
const double kSmoothChin = 0.8;
const double kSmoothUnderEye = 0.7;

/// Colour evenness (§4.6).
const double kEvenRed = 0.75;
const double kEvenOther = 0.50;
const double kEvenSlow = 0.25;
const double kEvenNoiseLo = 0.006;
const double kEvenNoiseHi = 0.020;
const double kEvenBlushGuard = 0.5;
const double kEvenChromaRef = 0.06;

/// Under-eye (§4.7): share of the L gap to the cheek that is lifted and
/// of the chroma gap that is closed, on light skin and on dark skin
/// (lifting dark skin without its colour reads ashy).
const double kUnderEyeLiftLight = 0.70;
const double kUnderEyeLiftDark = 0.55;
const double kUnderEyeChromaLight = 0.60;
const double kUnderEyeChromaDark = 0.70;
const double kUnderEyeRefIod = 0.22;
const double kCreaseTau = 0.03;
const double kBagFlatten = 0.45;

/// Skin lightness (median OkLab L of the core) where the dark-skin
/// factors fade into the light-skin ones.
const double kToneDarkL = 0.45;
const double kToneLightL = 0.65;

/// Resolution gates (§4.2), on the IOD in map pixels: pores and fine
/// structure do not exist below a certain sampling, so small faces get
/// reduced or no work.
double smoothSizeGate(double iodPx) => _ramp3(iodPx, 32, 48, 128, 0.6);
double colourSizeGate(double iodPx) => _ramp3(iodPx, 20, 40, 64, 0.5);

/// 0 below [a], [mid] at [b], 1 from [c] on (piecewise linear).
double _ramp3(double x, double a, double b, double c, double mid) {
  if (x <= a) return 0;
  if (x < b) return mid * (x - a) / (b - a);
  if (x < c) return mid + (1 - mid) * (x - b) / (c - b);
  return 1;
}

/// Measured state of one face's skin (inputs of Auto Retouch, §4.4–4.8).
class SkinMeasure {
  const SkinMeasure({
    this.toneL = 0.7,
    this.chroma = 0.06,
    this.n2 = 0,
    this.n3 = 0,
    this.colourP90 = 0,
    this.underEyeGap = 0,
    this.shineArea = 0,
    this.shineP95 = 0,
    this.hairShare = 0,
    this.corePixels = 0,
  });

  /// Median L and mean chroma of the skin core.
  final double toneL;
  final double chroma;

  /// Robust RMS (1.4826·MAD) of B2.L and B3.L on the core.
  final double n2;
  final double n3;

  /// P90 of the chroma excursion from the local skin colour.
  final double colourP90;

  /// Mean L gap between the under-eye zone and the cheek below it.
  final double underEyeGap;
  final double shineArea;
  final double shineP95;

  /// Mean hair-texture weight on the lower face (stubble / beard).
  final double hairShare;
  final int corePixels;
}

class SkinDeltas {
  const SkinDeltas({
    required this.smooth,
    required this.evenA,
    required this.evenB,
    required this.shine,
    required this.darkCircle,
    required this.bag,
    required this.measure,
  });

  final LabPlanes smooth;
  final Float32List evenA;
  final Float32List evenB;
  final LabPlanes shine;
  final LabPlanes darkCircle;
  final Float32List bag;
  final SkinMeasure measure;
}

/// Builds every skin delta of face [f]. [bands] are the bands of the
/// healed, wrinkle-filled image; [underEye] and [blush] its zone planes.
SkinDeltas computeSkinDeltas(
  FaceFrame f,
  SkinBands bands,
  SkinMasks masks, {
  required Float32List underEye,
  required Float32List blush,
}) {
  final rect = f.rect, n = rect.area, iod = f.iod;
  final l0 = bands.l0, l1 = bands.l1, l2 = bands.l2, l3 = bands.l3;
  final stats = masks.stats;
  final tone = _tone(l1, stats);
  final toneT = smoothstep(kToneDarkL, kToneLightL, tone.l);
  final shine = computeShine(bands, masks.norm, stats, iod);
  final gain = _regionGain(f, underEye);
  final gs = smoothSizeGate(iod), gc = colourSizeGate(iod);

  // Smooth: amplitude-selective band reduction, L of B1..B3, chroma of B1.
  final sl = Float32List(n), sa = Float32List(n), sb = Float32List(n);
  for (var i = 0; i < n; i++) {
    final k = gs * gain[i] * (1 - kHairSmoothKeep * masks.hair[i]);
    if (k <= 0) continue;
    final k1 = kSmoothB1 * bands.a1[i];
    // Highlights belong to Shine: the broad bands leave them alone, so
    // the two sliders never add up to a dip below the skin around.
    final lit = 1 - shine.weight[i];
    sl[i] =
        -k *
        (k1 * (l0.l[i] - l1.l[i]) +
            lit * kSmoothB2 * bands.a2[i] * (l1.l[i] - l2.l[i]) +
            lit * kSmoothB3 * bands.a3[i] * (l2.l[i] - l3.l[i]));
    sa[i] = -k * k1 * (l0.a[i] - l1.a[i]);
    sb[i] = -k * k1 * (l0.b[i] - l1.b[i]);
  }

  // Colour evenness: chroma excursions from the local skin colour.
  final cs = (tone.c / kEvenChromaRef).clamp(0.7, 1.4);
  final ea = Float32List(n), eb = Float32List(n);
  final excursion = <double>[];
  var ma = 0.0, mb = 0.0, mw = 0.0;
  for (var i = 0; i < n; i++) {
    final da = l1.a[i] - l3.a[i], db = l1.b[i] - l3.b[i];
    final mag = math.sqrt(da * da + db * db);
    if (stats[i] > 0.5 && shine.weight[i] < 0.2) excursion.add(mag);
    final wgt =
        gc *
        smoothstep(kEvenNoiseLo * cs, kEvenNoiseHi * cs, mag) *
        (1 - shine.weight[i]) *
        (1 - masks.hair[i]);
    final red = kEvenRed * (1 - kEvenBlushGuard * blush[i]);
    final slow = kEvenSlow * gc * (1 - shine.weight[i]);
    ea[i] =
        -wgt * (da > 0 ? red * da : kEvenOther * da) +
        slow * (tone.a - l3.a[i]);
    eb[i] = -wgt * kEvenOther * db + slow * (tone.b - l3.b[i]);
    final e = masks.effect[i];
    ma += e * ea[i];
    mb += e * eb[i];
    mw += e;
  }
  if (mw > 0) {
    // The mean face colour must not move.
    ma /= mw;
    mb /= mw;
    for (var i = 0; i < n; i++) {
      ea[i] -= ma;
      eb[i] -= mb;
    }
  }
  excursion.sort();

  // Under-eye: toward the cheek below the zone, lightness and colour.
  final outside = Float32List(n);
  for (var i = 0; i < n; i++) {
    outside[i] = masks.norm[i] * (1 - smoothstep(0.02, 0.2, underEye[i]));
  }
  final sigmaRef = math.max(2.0, kUnderEyeRefIod * iod);
  final ref = maskedLab(l2, outside, sigmaRef);
  final lift = _mix(kUnderEyeLiftDark, kUnderEyeLiftLight, toneT);
  final chroma = _mix(kUnderEyeChromaDark, kUnderEyeChromaLight, toneT);
  final dl = Float32List(n), da = Float32List(n), db = Float32List(n);
  final bag = Float32List(n);
  var gapSum = 0.0, gapN = 0;
  for (var i = 0; i < n; i++) {
    if (underEye[i] <= 0) continue;
    final gap = math.max(0.0, ref.l[i] - l1.l[i]);
    if (underEye[i] > 0.5 && masks.norm[i] > 0.5) {
      gapSum += gap;
      gapN++;
    }
    final b1 = l0.l[i] - l1.l[i], b2 = l1.l[i] - l2.l[i];
    final crease = smoothstep(
      kCreaseTau,
      kAmpRamp * kCreaseTau,
      b1.abs() + b2.abs(),
    );
    dl[i] = gs * lift * gap * (1 - crease);
    da[i] = gs * chroma * (ref.a[i] - l1.a[i]);
    db[i] = gs * chroma * (ref.b[i] - l1.b[i]);
    bag[i] = -gs * kBagFlatten * bands.a3[i] * (b2 + l2.l[i] - l3.l[i]);
  }

  return SkinDeltas(
    smooth: LabPlanes(rect, sl, sa, sb),
    evenA: ea,
    evenB: eb,
    shine: gc == 1
        ? shine.delta
        : shine.delta.mapChannels((c) => _scaled(c, gc)),
    darkCircle: LabPlanes(rect, dl, da, db),
    bag: bag,
    measure: SkinMeasure(
      toneL: tone.l,
      chroma: tone.c,
      n2: _robustRms(l1.l, l2.l, stats),
      n3: _robustRms(l2.l, l3.l, stats),
      colourP90: excursion.isEmpty
          ? 0
          : excursion[((excursion.length - 1) * 0.9).round()],
      underEyeGap: gapN < 8 ? 0 : gapSum / gapN,
      shineArea: shine.area,
      shineP95: shine.p95,
      hairShare: _lowerFaceHair(f, masks),
      corePixels: masks.statsCount,
    ),
  );
}

double _mix(double a, double b, double t) => a + (b - a) * t;

Float32List _scaled(Float32List p, double k) {
  final out = Float32List(p.length);
  for (var i = 0; i < p.length; i++) {
    out[i] = p[i] * k;
  }
  return out;
}

/// Median L and mean (a, b), chroma of the skin core.
({double l, double a, double b, double c}) _tone(
  LabPlanes lab,
  Float32List stats,
) {
  final ls = <double>[];
  var sa = 0.0, sb = 0.0;
  final step = math.max(1, stats.length ~/ 20000);
  for (var i = 0; i < stats.length; i += step) {
    if (stats[i] <= 0.5) continue;
    ls.add(lab.l[i]);
    sa += lab.a[i];
    sb += lab.b[i];
  }
  if (ls.length < 8) return (l: 0.7, a: 0.03, b: 0.04, c: 0.05);
  ls.sort();
  final a = sa / ls.length, b = sb / ls.length;
  return (l: ls[ls.length ~/ 2], a: a, b: b, c: math.sqrt(a * a + b * b));
}

/// 1.4826·MAD of `hi − lo` over the core.
double _robustRms(Float32List hi, Float32List lo, Float32List stats) {
  final v = <double>[];
  final step = math.max(1, stats.length ~/ 20000);
  for (var i = 0; i < stats.length; i += step) {
    if (stats[i] > 0.5) v.add(hi[i] - lo[i]);
  }
  if (v.length < 16) return 0;
  v.sort();
  final med = v[v.length ~/ 2];
  final dev = [for (final x in v) (x - med).abs()]..sort();
  return 1.4826 * dev[dev.length ~/ 2];
}

/// Smooth multiplier per pixel: soft blobs on the nose, upper lip and
/// chin, and the under-eye zone.
Float32List _regionGain(FaceFrame f, Float32List underEye) {
  final rect = f.rect, iod = f.iod;
  final out = Float32List(rect.area)..fillRange(0, rect.area, 1);
  void blob(({double x, double y}) c, double sigmaIod, double gain) {
    final s = sigmaIod * iod, reach = (3 * s).ceil();
    final x0 = math.max(rect.x0, c.x.floor() - reach);
    final x1 = math.min(rect.x1, c.x.ceil() + reach);
    final y0 = math.max(rect.y0, c.y.floor() - reach);
    final y1 = math.min(rect.y1, c.y.ceil() + reach);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final dx = x + 0.5 - c.x, dy = y + 0.5 - c.y;
        final g = math.exp(-(dx * dx + dy * dy) / (2 * s * s));
        out[rect.index(x, y)] *= 1 - (1 - gain) * g;
      }
    }
  }

  blob(f.p(FaceMesh.noseTip[1]), 0.14, kSmoothNose);
  blob(
    f.mid(FaceMesh.noseBase[2], FaceMesh.lipsOuter[5]),
    0.10,
    kSmoothUpperLip,
  );
  blob(f.p(FaceMesh.chinCenterLine[1]), 0.18, kSmoothChin);
  for (var i = 0; i < out.length; i++) {
    out[i] *= 1 - (1 - kSmoothUnderEye) * underEye[i];
  }
  return out;
}

/// Mean hair weight on the skin below the nose base (beard, stubble).
double _lowerFaceHair(FaceFrame f, SkinMasks m) {
  final rect = f.rect;
  final limit = f.alongAxis(f.p(FaceMesh.noseBase[2]));
  var sum = 0.0, count = 0;
  for (var y = rect.y0; y < rect.y1; y += 2) {
    for (var x = rect.x0; x < rect.x1; x += 2) {
      final i = rect.index(x, y);
      if (m.norm[i] <= 0.5) continue;
      if (f.alongAxis((x: x + 0.5, y: y + 0.5)) < limit) continue;
      sum += m.hair[i];
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}
