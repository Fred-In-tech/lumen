import 'dart:math' as math;

/// IEC 61966-2-1 sRGB decode (encoded 0..1 → linear 0..1).
double srgbToLinear(double c) {
  if (c <= 0.04045) return c / 12.92;
  return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// sRGB encode (linear → encoded), clamped to 0..1.
double linearToSrgb(double c) {
  if (c <= 0) return 0;
  if (c >= 1) return 1;
  if (c <= 0.0031308) return c * 12.92;
  return 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
}

/// sRGB encode without the upper clamp: values above 1.0 continue on the
/// same curve (extended sRGB); negative input gives 0. Equal to
/// [linearToSrgb] inside 0..1. `common.glsl srgbEncodeExt1`.
double linearToSrgbExtended(double c) {
  if (c <= 0) return 0;
  if (c <= 0.0031308) return c * 12.92;
  return 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
}

/// Lookup table: 8-bit sRGB byte → linear value.
final List<double> kSrgbByteToLinear = List<double>.unmodifiable(
  List<double>.generate(256, (b) => srgbToLinear(b / 255)),
);
