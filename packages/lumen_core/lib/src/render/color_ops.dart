/// Color stages 9–13 of `develop.frag` (HSL mixer, vibrance/saturation,
/// color grading, B&W mix, vignette), written to port line-by-line to GLSL.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'engine_constants.dart';
import 'uniform_layout.dart';

double smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Raised-cosine weight of band [i] for OkLCh hue [h] (degrees). Each band
/// falls to zero at its neighbors' centers, so the 8 weights sum to 1.
double hslBandWeight(int i, double h) {
  const c = kHslBandCenters;
  final center = c[i];
  final left = (center - c[(i + 7) % 8] + 360) % 360;
  final right = (c[(i + 1) % 8] - center + 360) % 360;
  final d = ((h - center + 540) % 360) - 180;
  final width = d >= 0 ? right : left;
  final ad = d.abs();
  if (ad >= width) return 0;
  return 0.5 * (1 + math.cos(math.pi * ad / width));
}

/// Hue in degrees 0..360 of OkLab (a, b).
double okHue(double a, double b) {
  final h = math.atan2(b, a) * 180 / math.pi;
  return h < 0 ? h + 360 : h;
}

/// True when any of stages 9–12 is active (the CPU skips the OkLab
/// round-trip otherwise; the GPU always runs it, error < 1e-6).
bool colorOpsActive(Float32List f) {
  for (var i = DevelopIndex.hslHue; i < DevelopIndex.gradeParams; i++) {
    if (f[i] != 0) return true;
  }
  for (var i = DevelopIndex.bwMix; i < DevelopIndex.bwMix + 8; i++) {
    if (f[i] != 0) return true;
  }
  return f[DevelopIndex.color] != 0 ||
      f[DevelopIndex.color + 1] != 0 ||
      f[DevelopIndex.color + 2] > 0.5;
}

/// Applies HSL, vibrance/saturation, grading and B&W to OkLab [lab]
/// (in place: L, a, b). [saturation] overrides the global value (it carries
/// the per-pixel local mask sum).
void applyColorOps(Float64List lab, Float32List f, {double? saturation}) {
  var l = lab[0], a = lab[1], b = lab[2];
  var c = math.sqrt(a * a + b * b);
  var h = okHue(a, b);
  // 9. HSL mixer (the CPU skips it when every band is 0).
  if (_anyNonZero(f, DevelopIndex.hslHue, 24)) {
    var dh = 0.0, ds = 0.0, dl = 0.0;
    for (var i = 0; i < 8; i++) {
      final w = hslBandWeight(i, h);
      if (w == 0) continue;
      dh += w * f[DevelopIndex.hslHue + i];
      ds += w * f[DevelopIndex.hslSat + i];
      dl += w * f[DevelopIndex.hslLum + i];
    }
    final chromaW = smoothstep(0, kHslChromaKnee, c);
    h += dh * kHslHueDegrees * chromaW;
    c *= math.max(0.0, 1 + ds * chromaW);
    l *= 1 + kHslLumScale * dl * chromaW;
  }
  // 10. Vibrance then saturation.
  final vib = f[DevelopIndex.color];
  final sat = saturation ?? f[DevelopIndex.color + 1];
  var k = 1 + sat;
  if (vib > 0) {
    final lowSat = 1 - smoothstep(0, kVibranceChromaKnee, c);
    final skin =
        smoothstep(kSkinHueLo - kSkinHueRamp, kSkinHueLo, h) *
        (1 - smoothstep(kSkinHueHi, kSkinHueHi + kSkinHueRamp, h));
    k *= 1 + vib * lowSat * (1 - kSkinProtect * skin);
  } else {
    k *= 1 + vib;
  }
  c *= math.max(k, 0.0);
  final hr = h * math.pi / 180;
  a = c * math.cos(hr);
  b = c * math.sin(hr);
  // 11. Color grading (skipped by the CPU when all wheels are 0).
  if (_anyNonZero(f, DevelopIndex.gradeShadows, 16)) {
    final g = _grade(l, f);
    a += g.$1;
    b += g.$2;
    l *= g.$3;
  }
  // 12. B&W mix.
  if (f[DevelopIndex.color + 2] > 0.5) {
    final c2 = math.sqrt(a * a + b * b);
    final h2 = okHue(a, b);
    var mix = 0.0;
    for (var i = 0; i < 8; i++) {
      mix += hslBandWeight(i, h2) * f[DevelopIndex.bwMix + i];
    }
    l *= 1 + kBwMixScale * mix * smoothstep(0, kBwChromaKnee, c2);
    a = 0;
    b = 0;
  }
  lab[0] = l;
  lab[1] = a;
  lab[2] = b;
}

bool _anyNonZero(Float32List f, int from, int count) {
  for (var i = from; i < from + count; i++) {
    if (f[i] != 0) return true;
  }
  return false;
}

/// Grading offsets (Δa, Δb) and L factor for lightness [l].
(double, double, double) _grade(double l, Float32List f) {
  const gp = DevelopIndex.gradeParams;
  final lc = l.clamp(0.0, 1.0);
  final pivot = 0.5 - kGradeBalanceShift * f[gp + 1];
  final width = kGradeWidthMin + (kGradeWidthMax - kGradeWidthMin) * f[gp];
  var ws = 1 - smoothstep(pivot - width, pivot + 0.5 * width, lc);
  var wh = smoothstep(pivot - 0.5 * width, pivot + width, lc);
  var wm = math.exp(-(lc - pivot) * (lc - pivot) / (2 * width * width));
  final sum = math.max(ws + wm + wh, 1.0);
  ws /= sum;
  wm /= sum;
  wh /= sum;
  double zone(int o) =>
      ws * f[DevelopIndex.gradeShadows + o] +
      wm * f[DevelopIndex.gradeMidtones + o] +
      wh * f[DevelopIndex.gradeHighlights + o] +
      f[DevelopIndex.gradeGlobal + o];
  final fade = (4 * l).clamp(0.0, 1.0);
  return (zone(0) * fade, zone(1) * fade, 1 + kGradeLumScale * zone(2));
}

/// 13. Post-crop vignette (paint style, encoded domain), in place on [e].
void applyVignette(Float64List e, double u, double v, Float32List f) {
  const vg = DevelopIndex.vignette, v2 = DevelopIndex.vignette2;
  final amount = f[vg];
  if (amount == 0) return;
  var px = (u * 2 - 1).abs(), py = (v * 2 - 1).abs();
  final aspect = f[v2 + 1];
  final round = f[vg + 2];
  final ax = aspect / math.max(aspect, 1), ay = 1 / math.max(aspect, 1);
  final rp = math.max(round, 0.0);
  px *= 1 + (ax - 1) * rp;
  py *= 1 + (ay - 1) * rp;
  final n = 2 + 6 * math.max(-round, 0.0);
  final d = math.pow(math.pow(px, n) + math.pow(py, n), 1 / n).toDouble();
  final mid = kVignetteMidMin + (kVignetteMidMax - kVignetteMidMin) * f[vg + 1];
  final fe = math.max(f[vg + 3], 0.02) * kVignetteFeatherScale;
  final m = smoothstep(mid - fe, mid + fe, d);
  if (amount < 0) {
    final luma = 0.2126 * e[0] + 0.7152 * e[1] + 0.0722 * e[2];
    final protect = f[v2] * smoothstep(0.5, 1, luma);
    final k = 1 + amount * m * (1 - protect);
    for (var i = 0; i < 3; i++) {
      e[i] *= k;
    }
  } else {
    for (var i = 0; i < 3; i++) {
      e[i] += (1 - e[i]) * amount * m;
    }
  }
}
