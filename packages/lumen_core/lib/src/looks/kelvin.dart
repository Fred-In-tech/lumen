/// Absolute white balance (Kelvin) → Lumen's relative Temp.
library;

import 'dart:math' as math;

import '../render/engine_constants.dart';

/// The "as shot" white balance an absolute Lightroom temperature is read
/// against: daylight / flash, what most portrait and wedding RAWs are shot
/// under. A preset's 6500 K becomes "warmer than daylight by 1000 K".
const double kLightroomReferenceKelvin = 5500;

/// Linear sRGB (Y = 1) of a Planckian light at [kelvin] (1667–25000 K),
/// from the Kim et al. cubic fit of the Planckian locus in CIE xy.
(double r, double g, double b) planckianLinearSrgb(double kelvin) {
  final t = kelvin.clamp(1667.0, 25000.0);
  final t2 = t * t, t3 = t2 * t;
  final x = t <= 4000
      ? -0.2661239e9 / t3 - 0.2343589e6 / t2 + 0.8776956e3 / t + 0.179910
      : -3.0258469e9 / t3 + 2.1070379e6 / t2 + 0.2226347e3 / t + 0.240390;
  final x2 = x * x, x3 = x2 * x;
  final y = t <= 2222
      ? -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683
      : t <= 4000
      ? -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867
      : 3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483;
  final bx = x / y, bz = (1 - x - y) / y;
  return (
    3.2406 * bx - 1.5372 - 0.4986 * bz,
    -0.9689 * bx + 1.8758 + 0.0415 * bz,
    0.0557 * bx - 0.2040 + 1.0570 * bz,
  );
}

/// Lumen Temp (−100…100) equivalent to setting a RAW's white balance to
/// [kelvin] when it was shot at [reference]: the change of the R/B gain
/// ratio in stops, scaled by Lumen's ±100 = ±[kWbKappaT] stop.
/// Higher Kelvin (correcting for bluer light) warms, as in Lightroom.
double kelvinToRelativeTemp(
  double kelvin, {
  double reference = kLightroomReferenceKelvin,
}) {
  double rb(double k) {
    final (r, _, b) = planckianLinearSrgb(k);
    return r / b;
  }

  final stops = math.log(rb(reference) / rb(kelvin)) / math.ln2;
  return (100 * stops / kWbKappaT).clamp(-100.0, 100.0);
}

/// Lightroom's absolute Tint (−150…150, raw files) → Lumen Tint
/// (−100…100): same direction (positive = magenta), range scaled.
double absoluteTintToRelative(double tint) =>
    (tint * 100 / 150).clamp(-100.0, 100.0);
