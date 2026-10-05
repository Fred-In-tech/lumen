import 'dart:math' as math;
import 'dart:typed_data';

import '../color/cielab.dart';
import '../color/srgb.dart';
import 'enhance_constants.dart';
import 'enhance_pixels.dart';
import 'skin_bands.dart';

typedef _C = EnhanceConstants;

double _log2(double x) => math.log(x) / math.ln2;

/// An illuminant estimate as a cast relative to neutral, in stops:
/// [a] = log2(R/B) (> 0 warm) and [m] = log2(G/√RB) (> 0 green).
class Cast {
  const Cast(this.a, this.m);

  static const none = Cast(0, 0);

  factory Cast.ofRgb(double r, double g, double b) => Cast(
    _log2(math.max(r, 1e-9) / math.max(b, 1e-9)),
    _log2(math.max(g, 1e-9) / math.sqrt(math.max(r * b, 1e-18))),
  );

  final double a;
  final double m;

  /// Angle in degrees between this illuminant and [other] in RGB.
  double angleTo(Cast other) {
    final p = _rgb, q = other._rgb;
    var dot = 0.0, np = 0.0, nq = 0.0;
    for (var c = 0; c < 3; c++) {
      dot += p[c] * q[c];
      np += p[c] * p[c];
      nq += q[c] * q[c];
    }
    final cos = (dot / math.sqrt(np * nq)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  List<double> get _rgb => [
    math.pow(2, a / 2 - m).toDouble(),
    1,
    math.pow(2, -a / 2 - m).toDouble(),
  ];
}

/// The illuminant candidates of research 09 §2.5 (null: not available).
class WbCandidates {
  const WbCandidates({
    this.shadesOfGrey,
    this.greyEdge,
    this.whitePatch,
    this.neutral,
    this.neutralQ = 0,
    this.monochrome = false,
  });

  /// Measures [px], leaving out pixels flagged in [skin], pixels coloured
  /// like one of [skinTones] (necks, arms and hands would vote "warm
  /// light"), and very saturated or invalid ones.
  factory WbCandidates.of(
    LinearPixels px, {
    Uint8List? skin,
    List<Cast> skinTones = const [],
  }) {
    final n = px.pixelCount, d = px.rgb, w = px.width, h = px.height;
    final use = Uint8List(n);
    final sog = [0.0, 0.0, 0.0];
    final hist = [for (var c = 0; c < 3; c++) Int32List(1025)];
    final hueBins = Int32List(12);
    var used = 0, coloured = 0, clipped = 0;
    var nr = 0.0, ng = 0.0, nb = 0.0, neutralN = 0;
    for (var i = 0, o = 0; i < n; i++, o += 3) {
      final r = d[o], g = d[o + 1], b = d[o + 2];
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      if (linearToSrgb(mx) >= _C.clipEncoded) {
        clipped++;
        continue;
      }
      if (luminanceOf(r, g, b) < _C.darkY) continue;
      final emx = linearToSrgb(mx), emn = linearToSrgb(mn);
      final sat = emx <= 0 ? 0.0 : (emx - emn) / emx;
      if (sat > 0.45) {
        coloured++;
        hueBins[_hueBin(r, g, b, mx, mn)]++;
      }
      if (skin != null && skin[i] != 0) continue;
      if (sat > 0.6) continue;
      if (sat > 0.15 && skinTones.isNotEmpty) {
        final c = Cast.ofRgb(r, g, b);
        if (skinTones.any(
          (t) => (c.a - t.a).abs() < 0.5 && (c.m - t.m).abs() < 0.15,
        )) {
          continue;
        }
      }
      use[i] = 1;
      used++;
      sog[0] += math.pow(r, _C.minkowskiP);
      sog[1] += math.pow(g, _C.minkowskiP);
      sog[2] += math.pow(b, _C.minkowskiP);
      hist[0][(r.clamp(0.0, 1.0) * 1024).round()]++;
      hist[1][(g.clamp(0.0, 1.0) * 1024).round()]++;
      hist[2][(b.clamp(0.0, 1.0) * 1024).round()]++;
      final lab = linearSrgbToLab(r, g, b);
      if (lab.chroma < _C.neutralChroma &&
          lab.l > _C.neutralLMin &&
          lab.l < _C.neutralLMax) {
        nr += r;
        ng += g;
        nb += b;
        neutralN++;
      }
    }
    var pair = 0;
    for (var k = 0; k < 12; k++) {
      pair = math.max(pair, hueBins[k] + hueBins[(k + 1) % 12]);
    }
    final monochrome = coloured > 0.4 * n && pair > 0.65 * coloured;
    if (used < 16) return WbCandidates(monochrome: monochrome);
    double root(double v) => math.pow(v / used, 1 / _C.minkowskiP).toDouble();
    final neutralShare = neutralN / n;
    return WbCandidates(
      shadesOfGrey: Cast.ofRgb(root(sog[0]), root(sog[1]), root(sog[2])),
      greyEdge: _greyEdge(d, w, h, use),
      whitePatch: clipped / n < 0.01
          ? Cast.ofRgb(
              _top(hist[0], used),
              _top(hist[1], used),
              _top(hist[2], used),
            )
          : null,
      neutral: neutralN < 16 ? null : Cast.ofRgb(nr, ng, nb),
      neutralQ: 0.8 * (neutralShare / _C.neutralShareFull).clamp(0.0, 1.0),
      monochrome: monochrome,
    );
  }

  final Cast? shadesOfGrey;
  final Cast? greyEdge;
  final Cast? whitePatch;

  /// Mean of near-neutral objects and how far to trust it (0..0.8).
  final Cast? neutral;
  final double neutralQ;

  /// One hue dominates the frame: grey-world statistics are meaningless.
  final bool monochrome;

  List<Cast> get statistical => monochrome
      ? const []
      : [shadesOfGrey, greyEdge, whitePatch].nonNulls.toList();

  static int _hueBin(double r, double g, double b, double mx, double mn) {
    final c = mx - mn;
    if (c <= 0) return 0;
    final double h;
    if (mx == r) {
      h = ((g - b) / c) % 6;
    } else if (mx == g) {
      h = (b - r) / c + 2;
    } else {
      h = (r - g) / c + 4;
    }
    return (h * 2).floor().clamp(0, 11);
  }

  static double _top(Int32List h, int count) {
    final rank = ((count - 1) * 0.995).round();
    var cum = 0;
    for (var b = 0; b < h.length; b++) {
      cum += h[b];
      if (rank < cum) return math.max(b / 1024, 1e-4);
    }
    return 1;
  }

  /// First-order grey-edge with Minkowski norm p on a 3×3-smoothed image.
  static Cast? _greyEdge(Float32List d, int w, int h, Uint8List use) {
    if (w < 5 || h < 5) return null;
    final blur = Float32List(d.length);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final o = (y * w + x) * 3;
        for (var c = 0; c < 3; c++) {
          var s = 4.0 * d[o + c];
          s += 2 * (d[o + c - 3] + d[o + c + 3]);
          s += 2 * (d[o + c - w * 3] + d[o + c + w * 3]);
          s += d[o + c - w * 3 - 3] + d[o + c - w * 3 + 3];
          s += d[o + c + w * 3 - 3] + d[o + c + w * 3 + 3];
          blur[o + c] = s / 16;
        }
      }
    }
    final acc = [0.0, 0.0, 0.0];
    var count = 0;
    for (var y = 2; y < h - 2; y++) {
      for (var x = 2; x < w - 2; x++) {
        final i = y * w + x;
        if (use[i] == 0) continue;
        final o = i * 3;
        for (var c = 0; c < 3; c++) {
          final gx = (blur[o + c + 3] - blur[o + c - 3]) / 2;
          final gy = (blur[o + c + w * 3] - blur[o + c - w * 3]) / 2;
          acc[c] += math.pow(math.sqrt(gx * gx + gy * gy), _C.minkowskiP);
        }
        count++;
      }
    }
    if (count == 0) return null;
    final e = [
      for (final v in acc) math.pow(v / count, 1 / _C.minkowskiP).toDouble(),
    ];
    final top = e.reduce(math.max);
    if (top < 1e-6 || e.any((v) => v < top * 1e-3)) return null;
    return Cast.ofRgb(e[0], e[1], e[2]);
  }
}

/// Why white balance ended where it did.
enum WbVerdict {
  /// Nothing to correct, or the evidence was too weak to act on.
  leftAlone,

  /// Skin already sits in its window: the light is kept as shot.
  skinLooksRight,

  /// A warm cast was corrected only in part, to keep the ambience.
  keptWarmth,

  /// A cast was corrected.
  corrected,
}

/// Result of the white-balance stage.
class WbSolution {
  const WbSolution({
    required this.temp,
    required this.tint,
    required this.confidence,
    required this.verdict,
    required this.estimate,
  });

  final double temp;
  final double tint;

  /// 0..1 (research `wbConfidence`).
  final double confidence;
  final WbVerdict verdict;

  /// The combined cast estimate before strength and gates.
  final Cast estimate;
}

/// Stage C: a gated, confidence-weighted vote with a skin-locus check.
abstract final class EnhanceWb {
  static WbSolution solve({
    required WbCandidates candidates,
    required List<FaceRead> faces,
    bool warmIntent = false,
    bool alreadyEdited = false,
    double? styleStrength,
  }) {
    final stat = candidates.statistical;
    final skin = _skinCast(faces);
    final skinOk = skin != null && skin.outside.a == 0 && skin.outside.m == 0;
    var agree = 0.0;
    var sumA = 0.0, sumM = 0.0, sumW = _C.wbWeightAsShot * _C.wbAsShotQ;
    if (stat.isNotEmpty) {
      var worst = 0.0;
      for (var i = 0; i < stat.length; i++) {
        for (var j = i + 1; j < stat.length; j++) {
          worst = math.max(worst, stat[i].angleTo(stat[j]));
        }
      }
      agree = stat.length < 2
          ? 0.5
          : 1 - (worst / _C.wbAgreeAngle).clamp(0.0, 1.0);
      final w = _C.wbWeightStat * agree;
      sumA += w * stat.fold(0.0, (s, c) => s + c.a) / stat.length;
      sumM += w * stat.fold(0.0, (s, c) => s + c.m) / stat.length;
      sumW += w;
    }
    final neutral = candidates.neutral;
    if (neutral != null && candidates.neutralQ > 0) {
      final w = _C.wbWeightNeutral * candidates.neutralQ;
      sumA += w * neutral.a;
      sumM += w * neutral.m;
      sumW += w;
    }
    // Skin outside its window is evidence of a cast; skin inside it is
    // not evidence of neutral light (the window is wide), so it only gates.
    if (skin != null && !skinOk) {
      const w = _C.wbWeightSkin * _C.wbSkinQ;
      sumA += w * skin.outside.a;
      sumM += w * skin.outside.m;
      sumW += w;
    }
    final estimate = Cast(sumA / sumW, sumM / sumW);
    final support = math.max(
      neutral == null ? 0.0 : candidates.neutralQ,
      skin == null ? 0.0 : _C.wbSkinQ,
    );
    final confidence = (0.4 + 0.6 * agree + 0.25 * support).clamp(0.0, 1.0);

    // Strength: warm light that leaves skin in its window is ambience.
    final warm = estimate.a > _C.warmAmbienceA;
    var strength = _C.wbStrength;
    if (warm && warmIntent) {
      strength = _C.wbStrengthGolden;
    } else if (warm && skinOk) {
      strength = _C.wbStrengthWarmInterior;
    } else if (warm && skin == null) {
      strength = _C.wbStrengthWarmNoFaces;
    }
    if (alreadyEdited && (skin == null || skinOk)) strength = 0;
    if (styleStrength != null) strength = math.min(strength, styleStrength);
    var corrA = strength * confidence * estimate.a;
    var corrM = strength * confidence * estimate.m;

    // Skin-locus check.
    if (skin != null) {
      if (skinOk) {
        // Never push good skin out of its window.
        corrA = corrA.clamp(skin.a - skin.aHigh, skin.a - _C.skinALow);
        corrM = corrM.clamp(skin.m - _C.skinMHigh, skin.m - _C.skinMLow);
      } else {
        // Skin is off: move it at least to the window edge, never away.
        corrA = _towards(corrA, skin.outside.a);
        corrM = _towards(corrM, skin.outside.m);
      }
    }
    final wide = skin == null || !skinOk;
    final coolMax = wide ? _C.tempMaxWide : _C.tempMax;
    final warmMax = wide ? _C.tempMaxWide : _C.tempMaxWarming;
    final gMax = wide ? _C.tintMaxWide : _C.tintMax;
    var temp = (-100 * corrA).clamp(-coolMax, warmMax).toDouble();
    var tint = (200 * corrM).clamp(-gMax, gMax).toDouble();
    final deadT = skinOk ? _C.wbDeadTempSkinOk : _C.wbDeadTemp;
    final deadG = skinOk ? _C.wbDeadTintSkinOk : _C.wbDeadTint;
    if (temp.abs() < deadT) temp = 0;
    if (tint.abs() < deadG) tint = 0;
    final WbVerdict verdict;
    if (temp == 0 && tint == 0) {
      final cast = estimate.a.abs() > 0.1 || estimate.m.abs() > 0.05;
      verdict = skinOk && cast ? WbVerdict.skinLooksRight : WbVerdict.leftAlone;
    } else if (warm && strength < _C.wbStrength) {
      verdict = WbVerdict.keptWarmth;
    } else {
      verdict = WbVerdict.corrected;
    }
    return WbSolution(
      temp: temp,
      tint: tint,
      confidence: confidence,
      verdict: verdict,
      estimate: estimate,
    );
  }

  /// A correction that covers at least [needed] (same sign) and never moves
  /// the other way.
  static double _towards(double proposed, double needed) {
    if (needed == 0) return proposed;
    if (needed > 0) return math.max(proposed, needed);
    return math.min(proposed, needed);
  }

  static _SkinCast? _skinCast(List<FaceRead> faces) {
    if (faces.isEmpty) return null;
    var a = 0.0, m = 0.0, hi = 0.0, w = 0.0;
    for (final f in faces) {
      final k = f.region.weight;
      a += k * f.skin.a;
      m += k * f.skin.m;
      hi += k * _C.skinAHigh;
      w += k;
    }
    return _SkinCast(a / w, m / w, hi / w);
  }
}

/// Weighted skin chromaticity and its distance outside the skin window.
class _SkinCast {
  const _SkinCast(this.a, this.m, this.aHigh);

  final double a;
  final double m;
  final double aHigh;

  /// How far skin sits outside its window (0 inside): the least cast the
  /// light must carry.
  Cast get outside => Cast(
    a < _C.skinALow
        ? a - _C.skinALow
        : a > aHigh
        ? a - aHigh
        : 0,
    m < _C.skinMLow
        ? m - _C.skinMLow
        : m > _C.skinMHigh
        ? m - _C.skinMHigh
        : 0,
  );
}
