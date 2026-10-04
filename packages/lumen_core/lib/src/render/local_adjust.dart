/// Local (mask) adjustments for `develop.frag` / [DevelopKernel]: per-pixel
/// sums Σ coverage_i × local_i and the analytic local tone stage. Written to
/// port line-by-line to GLSL (see `localSums()` / `localTone()` there).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'engine_constants.dart';
import 'tone_lut.dart';
import 'uniform_layout.dart';

/// Offsets into the 12 local sums ([kLocalParams] order).
abstract final class LocalIndex {
  static const exposure = 0;
  static const temp = 1;
  static const tint = 2;
  static const saturation = 3;
  static const highlights = 4;
  static const shadows = 5;
  static const clarity = 6;
  static const texture = 7;
  static const dehaze = 8;
  static const contrast = 9;
  static const whites = 10;
  static const blacks = 11;
}

/// Number of active masks packed in [f] (0 = no local adjustments).
int activeMaskCount(Float32List f) => f[DevelopIndex.maskGrid + 2].toInt();

/// out[k] = Σ_i coverage[i] · local_i[k] for the 12 local params.
void accumulateLocal(Float32List f, Float64List coverage, Float64List out) {
  out.fillRange(0, 12, 0);
  final n = activeMaskCount(f);
  for (var i = 0; i < n; i++) {
    final c = coverage[i];
    if (c == 0) continue;
    final base = DevelopIndex.mask(i);
    for (var k = 0; k < 12; k++) {
      out[k] += c * f[base + k];
    }
  }
}

/// Local white-balance gains (R, G, B) for summed normalized temp/tint,
/// matching `whiteBalanceGains` (κt, κg) as a multiplier on the globals.
(double, double, double) localWbGains(double temp, double tint) => (
  math.pow(2, 0.5 * kWbKappaT * temp).toDouble(),
  math.pow(2, -kWbKappaG * tint).toDouble(),
  math.pow(2, -0.5 * kWbKappaT * temp).toDouble(),
);

/// Local contrast S-curve then whites/blacks levels on an encoded value;
/// [c], [w], [b] are normalized (−1..1) and reuse the tone-LUT formulas.
double localTone(double x, double c, double w, double b) {
  var y = x.clamp(0.0, 1.0);
  if (c != 0) y = contrastCurve(y, c * 100);
  if (w != 0 || b != 0) y = levelsCurve(y, w * 100, b * 100);
  return y;
}
