import 'dart:math' as math;

import 'rgb.dart';

/// CIE L*a*b* (D65 white).
class Lab {
  const Lab(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;

  double get chroma => math.sqrt(a * a + b * b);

  /// Hue angle in degrees, 0..360.
  double get hue {
    final h = math.atan2(b, a) * 180 / math.pi;
    return h < 0 ? h + 360 : h;
  }
}

const double _xn = 0.95047;
const double _yn = 1.0;
const double _zn = 1.08883;
const double _delta = 6 / 29;

double _f(double t) => t > _delta * _delta * _delta
    ? math.pow(t, 1 / 3).toDouble()
    : t / (3 * _delta * _delta) + 4 / 29;

double _fInv(double t) =>
    t > _delta ? t * t * t : 3 * _delta * _delta * (t - 4 / 29);

/// CIE L* from relative luminance Y (0..1).
double lStarFromY(double y) => 116 * _f(y / _yn) - 16;

/// Relative luminance Y from L*.
double yFromLStar(double l) => _yn * _fInv((l + 16) / 116);

/// Linear sRGB (D65) → CIELAB.
Lab linearSrgbToLab(double r, double g, double b) {
  final x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b;
  final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
  final z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b;
  final fx = _f(x / _xn), fy = _f(y / _yn), fz = _f(z / _zn);
  return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// CIELAB → linear sRGB (unclamped).
Rgb labToLinearSrgb(Lab lab) {
  final fy = (lab.l + 16) / 116;
  final fx = fy + lab.a / 500;
  final fz = fy - lab.b / 200;
  final x = _xn * _fInv(fx), y = _yn * _fInv(fy), z = _zn * _fInv(fz);
  return Rgb(
    3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
    -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
    0.0556434 * x - 0.2040259 * y + 1.0572252 * z,
  );
}
