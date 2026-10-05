/// Evaluation metrics of the retouch engine (research 09 §5.2), written
/// against the synthetic generator's own geometry so the engine's masks
/// cannot grade themselves.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'metrics.dart';
import 'synthetic_landmarks.dart';
import 'synthetic_portrait.dart';

/// CIEDE2000 colour difference of two sRGB byte triples.
double deltaE00Bytes(List<int> p, int i, List<int> q, int j) => deltaE00(
  linearSrgbToLab(
    kSrgbByteToLinear[p[i]],
    kSrgbByteToLinear[p[i + 1]],
    kSrgbByteToLinear[p[i + 2]],
  ),
  linearSrgbToLab(
    kSrgbByteToLinear[q[j]],
    kSrgbByteToLinear[q[j + 1]],
    kSrgbByteToLinear[q[j + 2]],
  ),
);

/// CIEDE2000 (Sharma, Wu, Dalal 2005), kL = kC = kH = 1.
double deltaE00(Lab x, Lab y) {
  double rad(double d) => d * math.pi / 180;
  double hue(double b, double a) {
    if (a == 0 && b == 0) return 0;
    final h = math.atan2(b, a) * 180 / math.pi;
    return h < 0 ? h + 360 : h;
  }

  final c1 = math.sqrt(x.a * x.a + x.b * x.b);
  final c2 = math.sqrt(y.a * y.a + y.b * y.b);
  final cm = (c1 + c2) / 2;
  final g =
      0.5 *
      (1 - math.sqrt(math.pow(cm, 7) / (math.pow(cm, 7) + math.pow(25.0, 7))));
  final a1 = (1 + g) * x.a, a2 = (1 + g) * y.a;
  final cp1 = math.sqrt(a1 * a1 + x.b * x.b);
  final cp2 = math.sqrt(a2 * a2 + y.b * y.b);
  final h1 = hue(x.b, a1), h2 = hue(y.b, a2);
  final dl = y.l - x.l, dc = cp2 - cp1;
  var dh = 0.0;
  if (cp1 * cp2 != 0) {
    dh = h2 - h1;
    if (dh > 180) dh -= 360;
    if (dh < -180) dh += 360;
  }
  final dH = 2 * math.sqrt(cp1 * cp2) * math.sin(rad(dh / 2));
  final lm = (x.l + y.l) / 2, cpm = (cp1 + cp2) / 2;
  var hm = h1 + h2;
  if (cp1 * cp2 != 0) {
    hm = (h1 - h2).abs() <= 180
        ? (h1 + h2) / 2
        : (h1 + h2 < 360 ? (h1 + h2 + 360) / 2 : (h1 + h2 - 360) / 2);
  }
  final t =
      1 -
      0.17 * math.cos(rad(hm - 30)) +
      0.24 * math.cos(rad(2 * hm)) +
      0.32 * math.cos(rad(3 * hm + 6)) -
      0.20 * math.cos(rad(4 * hm - 63));
  final dTheta = 30 * math.exp(-math.pow((hm - 275) / 25, 2));
  final rc =
      2 * math.sqrt(math.pow(cpm, 7) / (math.pow(cpm, 7) + math.pow(25.0, 7)));
  final sl =
      1 + 0.015 * math.pow(lm - 50, 2) / math.sqrt(20 + math.pow(lm - 50, 2));
  final sc = 1 + 0.045 * cpm, sh = 1 + 0.015 * cpm * t;
  final rt = -math.sin(rad(2 * dTheta)) * rc;
  return math.sqrt(
    math.pow(dl / sl, 2) +
        math.pow(dc / sc, 2) +
        math.pow(dH / sh, 2) +
        rt * (dc / sc) * (dH / sh),
  );
}

/// Ground-truth zones of a synthetic face, per pixel.
class SynthZones {
  SynthZones(this.face, this.w, this.h)
    : skin = Uint8List(w * h),
      hairRing = Uint8List(w * h),
      skinRing = Uint8List(w * h),
      deepSkin = Uint8List(w * h),
      protected = Uint8List(w * h) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = face.toLocal(x + 0.5, y + 0.5);
        final i = y * w + x;
        final ry = p.y < kOvalCy ? 1.65 : kOvalRyBottom;
        final r = math.sqrt(
          math.pow(p.x / kOvalRx, 2) + math.pow((p.y - kOvalCy) / ry, 2),
        );
        final head =
            math.pow(p.x / 1.4, 2) + math.pow((p.y - 0.2) / 1.85, 2) <= 1;
        final feature =
            (p.y > -0.55 &&
                p.y < 0.30 &&
                p.x.abs() > 0.12 &&
                p.x.abs() < 0.95) ||
            (p.y > 0.88 && p.y < 1.38 && p.x.abs() < 0.6) ||
            (p.y > 0.6 && p.y < 0.86 && p.x.abs() < 0.3);
        if (r < 0.86 && !feature) skin[i] = 1;
        if (r < 0.6 && !feature) deepSkin[i] = 1;
        if (r > 0.88 && r < 0.97 && p.y < 0.3) skinRing[i] = 1;
        if (r > 1.03 && r < 1.12 && head && p.y < 0.8) hairRing[i] = 1;
        final eye = p.y.abs() < 0.07 && (p.x.abs() - 0.5).abs() < 0.2;
        final brow =
            p.y > -0.42 && p.y < -0.28 && (p.x.abs() - 0.5).abs() < 0.2;
        final lips = p.y > 1.02 && p.y < 1.24 && p.x.abs() < 0.3;
        if (eye || brow || lips || hairRing[i] == 1) protected[i] = 1;
      }
    }
  }

  final SynthFace face;
  final int w;
  final int h;

  /// Skin away from every feature and from the face edge.
  final Uint8List skin;

  /// Hair just outside the hairline; skin just inside it; skin far inside.
  final Uint8List hairRing;
  final Uint8List skinRing;
  final Uint8List deepSkin;

  /// Eyes, brows, lips and the hair ring.
  final Uint8List protected;
}

/// RMS of `l − blur(l, sigma)` over [mask] (the band finer than sigma).
double bandRms(Float64List l, int w, int h, double sigma, Uint8List mask) {
  final b = blur(l, w, h, sigma);
  return math.sqrt(
    meanWhere(
      w * h,
      (i) => mask[i] == 1,
      (i) => math.pow(l[i] - b[i], 2).toDouble(),
    ),
  );
}

/// RMS of the band between two blurs over [mask].
double midRms(
  Float64List l,
  int w,
  int h,
  double fine,
  double coarse,
  Uint8List mask,
) {
  final a = blur(l, w, h, fine), b = blur(l, w, h, coarse);
  return math.sqrt(
    meanWhere(
      w * h,
      (i) => mask[i] == 1,
      (i) => math.pow(a[i] - b[i], 2).toDouble(),
    ),
  );
}

/// Mean and P95 CIEDE2000 between [a] and [b] over [mask], and the ΔE00
/// between their mean colours there.
({double mean, double p95, double ofMean}) colourShift(
  RgbaBuffer a,
  RgbaBuffer b,
  Uint8List mask,
) {
  final all = <double>[];
  final sa = [0.0, 0.0, 0.0], sb = [0.0, 0.0, 0.0];
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] == 0) continue;
    final o = i * 4;
    all.add(deltaE00Bytes(a.data, o, b.data, o));
    for (var c = 0; c < 3; c++) {
      sa[c] += kSrgbByteToLinear[a.data[o + c]];
      sb[c] += kSrgbByteToLinear[b.data[o + c]];
    }
  }
  all.sort();
  final n = all.length;
  return (
    mean: all.reduce((x, y) => x + y) / n,
    p95: all[((n - 1) * 0.95).round()],
    ofMean: deltaE00(
      linearSrgbToLab(sa[0] / n, sa[1] / n, sa[2] / n),
      linearSrgbToLab(sb[0] / n, sb[1] / n, sb[2] / n),
    ),
  );
}

/// OkLab hue angle (degrees) of the mean (a, b) over [mask].
double meanHue(
  ({Float64List l, Float64List a, Float64List b}) lab,
  bool Function(int i) mask,
) {
  final n = lab.l.length;
  return math.atan2(
        meanWhere(n, mask, (i) => lab.b[i]),
        meanWhere(n, mask, (i) => lab.a[i]),
      ) *
      180 /
      math.pi;
}
