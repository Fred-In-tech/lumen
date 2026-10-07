import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';

/// A warm-highlights / teal-shadows look, like a cinematic `.cube`.
CubeLut tealOrangeLut({int size = 33}) => CubeLut.fromFunction(size, (r, g, b) {
  final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return (
    r + 0.06 * l - 0.05 * (1 - l),
    g + 0.01 * l + 0.02 * (1 - l),
    b - 0.06 * l + 0.06 * (1 - l),
  );
}, title: 'Teal & Orange');

/// A strongly non-linear LUT: exercises the trilinear interpolation
/// between grid points (inverted red, squared green, rooted blue, cross
/// talk).
CubeLut twistLut({int size = 9}) => CubeLut.fromFunction(
  size,
  (r, g, b) =>
      (1 - r * 0.9, g * g * 0.8 + 0.1 * b, math.sqrt(b) * 0.9 + 0.05 * r),
  title: 'Twist',
);

LutRef refOf(CubeLut lut, {double amount = 100}) =>
    LutRef(hash: lut.contentHash, name: lut.title, amount: amount);
