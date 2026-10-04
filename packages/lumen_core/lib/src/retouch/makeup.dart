/// Lip colour and blush (research 07 §3.9, natural-target variant: no
/// swatch, no hue jump).
///
/// * **Lips** keep their own hue. Chroma scales toward a natural target
///   (`C_mean · kLipChromaBoost`, capped at [kLipChromaMax], never below
///   the current mean), and L deepens a little. Both are applied as a
///   scale/offset, so the lip gradient and texture stay; gloss highlights
///   clearly above the lip P95 L are skipped.
/// * **Blush** is an oriented Gaussian at the cheek apple (landmark 50 /
///   280, along 205→123 / 425→352) times skin. Its colour is this face's
///   skin chroma lifted toward the lip hue (or a soft rose without lips).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'face_frame.dart';
import 'face_mesh.dart';
import 'lab_planes.dart';
import 'map_rect.dart';
import 'skin_model.dart';

/// Blush Gaussian σ along / across the cheek axis (IOD units).
const double kBlushMajorIod = 0.17;
const double kBlushMinorIod = 0.10;

/// Lip target: chroma × this, at most [kLipChromaMax]; L deepened by
/// [kLipDeepenL] but not below [kLipMinL].
const double kLipChromaBoost = 1.35;
const double kLipChromaMax = 0.17;
const double kLipDeepenL = 0.04;
const double kLipMinL = 0.35;

/// Lip pixels above this L percentile are gloss and keep their colour.
const double kLipGlossPercentile = 0.95;

/// Blush chroma = skin chroma + lift, clamped; hue = the lip hue clamped
/// to a natural rose-to-coral range (OkLab hue, radians).
const double kBlushChromaLift = 0.04;
const double kBlushChromaMin = 0.07;
const double kBlushChromaMax = 0.13;
const double kBlushHueMin = 0.0;
const double kBlushHueMax = 0.75;
const double kBlushDefaultHue = 0.35;

/// Minimum lip pixels (weight > 0.5) for lip statistics.
const int kMinLipPixels = 24;

/// Per-face makeup targets (packed into `uFaceInfo`).
class MakeupTargets {
  const MakeupTargets({
    required this.glossL,
    required this.lipChromaGain,
    required this.lipShiftL,
    required this.blushA,
    required this.blushB,
  });

  /// Lip P95 L: brighter lip pixels are gloss.
  final double glossL;

  /// Chroma scale at Lip colour 100 (≥ 1).
  final double lipChromaGain;

  /// L offset at Lip colour 100 (≤ 0).
  final double lipShiftL;

  /// Blush target OkLab a, b.
  final double blushA;
  final double blushB;
}

/// Blush weight over `f.rect`: two oriented Gaussians times [skin].
Float32List blushMap(FaceFrame f, Float32List skin) {
  final rect = f.rect, out = Float32List(rect.area);
  final sMaj = kBlushMajorIod * f.iod, sMin = kBlushMinorIod * f.iod;
  for (final (apple, axis) in [
    (FaceMesh.rightCheekApple, FaceMesh.rightCheekAxis),
    (FaceMesh.leftCheekApple, FaceMesh.leftCheekAxis),
  ]) {
    final c = f.p(apple), a0 = f.p(axis[0]), a1 = f.p(axis[1]);
    var dx = a1.x - a0.x, dy = a1.y - a0.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) continue;
    dx /= len;
    dy /= len;
    final reach = 3 * sMaj;
    final box = MapRect.around(c.x, c.y, reach, reach, rect.x1, rect.y1);
    final x0 = math.max(box.x0, rect.x0), x1 = math.min(box.x1, rect.x1);
    final y0 = math.max(box.y0, rect.y0), y1 = math.min(box.y1, rect.y1);
    for (var y = y0; y < y1; y++) {
      var i = rect.index(x0, y);
      for (var x = x0; x < x1; x++, i++) {
        final px = x + 0.5 - c.x, py = y + 0.5 - c.y;
        final along = px * dx + py * dy, across = -px * dy + py * dx;
        final g = math.exp(
          -0.5 *
              (along * along / (sMaj * sMaj) + across * across / (sMin * sMin)),
        );
        final v = g * skin[i];
        if (v > out[i]) out[i] = v;
      }
    }
  }
  return out;
}

/// Lip statistics and blush colour of one face. [lips] is the lip weight
/// over `lab.rect`.
MakeupTargets makeupTargets(
  LabPlanes lab,
  Float32List lips,
  SkinColorModel skin,
) {
  var sl = 0.0, sa = 0.0, sb = 0.0, sc = 0.0;
  final ls = <double>[];
  for (var i = 0; i < lips.length; i++) {
    if (lips[i] <= 0.5) continue;
    final a = lab.a[i], b = lab.b[i];
    sl += lab.l[i];
    sa += a;
    sb += b;
    sc += math.sqrt(a * a + b * b);
    ls.add(lab.l[i]);
  }
  final skinC = math.sqrt(skin.meanA * skin.meanA + skin.meanB * skin.meanB);
  final blushC = (skinC + kBlushChromaLift).clamp(
    kBlushChromaMin,
    kBlushChromaMax,
  );
  if (ls.length < kMinLipPixels) {
    return MakeupTargets(
      glossL: 1,
      lipChromaGain: 1,
      lipShiftL: 0,
      blushA: blushC * math.cos(kBlushDefaultHue),
      blushB: blushC * math.sin(kBlushDefaultHue),
    );
  }
  final n = ls.length;
  final meanL = sl / n, meanC = sc / n;
  ls.sort();
  final targetC = math.max(
    meanC,
    math.min(meanC * kLipChromaBoost, kLipChromaMax),
  );
  final hue = math.atan2(sb / n, sa / n).clamp(kBlushHueMin, kBlushHueMax);
  return MakeupTargets(
    glossL: ls[((n - 1) * kLipGlossPercentile).round()],
    lipChromaGain: meanC > 1e-4 ? targetC / meanC : 1,
    lipShiftL: math.min(0.0, math.max(kLipMinL, meanL - kLipDeepenL) - meanL),
    blushA: blushC * math.cos(hue),
    blushB: blushC * math.sin(hue),
  );
}
