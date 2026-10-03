import 'dart:math' as math;

import 'rgb.dart';

/// Björn Ottosson's OkLab (perceptual), from linear sRGB.
class Oklab {
  const Oklab(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;

  Oklch toLch() {
    var h = math.atan2(b, a) * 180 / math.pi;
    if (h < 0) h += 360;
    return Oklch(l, math.sqrt(a * a + b * b), h);
  }
}

/// Polar OkLab: lightness, chroma, hue in degrees (0..360).
class Oklch {
  const Oklch(this.l, this.c, this.h);

  final double l;
  final double c;
  final double h;

  Oklab toLab() {
    final rad = h * math.pi / 180;
    return Oklab(l, c * math.cos(rad), c * math.sin(rad));
  }
}

double _cbrt(double x) =>
    x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

Oklab linearSrgbToOklab(double r, double g, double b) {
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return Oklab(
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  );
}

Rgb oklabToLinearSrgb(Oklab o) {
  final l1 = o.l + 0.3963377774 * o.a + 0.2158037573 * o.b;
  final m1 = o.l - 0.1055613458 * o.a - 0.0638541728 * o.b;
  final s1 = o.l - 0.0894841775 * o.a - 1.2914855480 * o.b;
  final l = l1 * l1 * l1, m = m1 * m1 * m1, s = s1 * s1 * s1;
  return Rgb(
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  );
}
