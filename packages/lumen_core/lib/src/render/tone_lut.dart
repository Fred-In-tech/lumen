import 'dart:math' as math;
import 'dart:typed_data';

import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import 'engine_constants.dart';
import 'lut_packing.dart';

/// Contrast S-curve in the encoded domain: a power curve on each side of
/// [kContrastPivot] with slope `2^(contrast/100)` at the pivot.
double contrastCurve(double x, double contrast) {
  final c = contrast.clamp(-100, 100) / 100;
  if (c == 0) return x;
  final g = math.pow(2, c * kContrastSlopeStops).toDouble();
  const p = kContrastPivot;
  final xc = x.clamp(0.0, 1.0);
  if (xc < p) return p * math.pow(xc / p, g).toDouble();
  return 1 - (1 - p) * math.pow((1 - xc) / (1 - p), g).toDouble();
}

/// Whites/blacks as levels (research 01 §6.2 reference model), encoded domain.
/// whites > 0 stretches input white `1 − 0.25·w` to 1, whites < 0 compresses
/// output white to `1 + 0.25·w`; blacks mirror this at the black end.
double levelsCurve(double x, double whites, double blacks) {
  final w = whites.clamp(-100, 100) / 100;
  final b = blacks.clamp(-100, 100) / 100;
  final wIn = w > 0 ? 1 - kLevelsRange * w : 1.0;
  final wOut = w < 0 ? 1 + kLevelsRange * w : 1.0;
  final bIn = b < 0 ? -kLevelsRange * b : 0.0;
  final bOut = b > 0 ? kLevelsRange * b : 0.0;
  final t = ((x - bIn) / (wIn - bIn)).clamp(0.0, 1.0);
  return bOut + (wOut - bOut) * t;
}

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Lightroom-style parametric curve: four raised-cosine zone bumps between
/// the split points (percent), tapered to keep the end points fixed.
double parametricCurve(
  double x, {
  required double shadows,
  required double darks,
  required double lights,
  required double highlights,
  required double splitShadow,
  required double splitMidtone,
  required double splitHighlight,
}) {
  final amounts = [shadows, darks, lights, highlights];
  if (amounts.every((a) => a == 0)) return x;
  final bounds = [
    0.0,
    splitShadow / 100,
    splitMidtone / 100,
    splitHighlight / 100,
    1.0,
  ];
  var delta = 0.0;
  for (var k = 0; k < 4; k++) {
    final lo = bounds[k], hi = bounds[k + 1];
    final hw = hi - lo;
    final d = x - (lo + hi) / 2;
    if (hw <= 0 || d.abs() >= hw) continue;
    delta += amounts[k] / 100 * 0.5 * (1 + math.cos(math.pi * d / hw));
  }
  final taper =
      _smoothstep(0, kParametricTaper, x) *
      _smoothstep(0, kParametricTaper, 1 - x);
  return (x + kParametricAmplitude * delta * taper).clamp(0.0, 1.0);
}

/// The baked tone LUT: row 0 = composite tone (contrast → whites/blacks →
/// parametric → master point curve), rows 1–3 = R/G/B point curves.
/// All rows map sRGB-encoded input to encoded output, 16-bit quantized.
class ToneLut {
  ToneLut._(this.values, this.curvesActive, this.key);

  /// Bakes the LUT for [s]. Only tone/curve params are read.
  factory ToneLut.bake(DevelopSettings s) {
    final values = Uint16List(kToneLutSize * kToneLutRows);
    final contrast = s.value(P.contrast);
    final whites = s.value(P.whites);
    final blacks = s.value(P.blacks);
    final master = s.curves.master;
    double composite(double x) {
      var y = contrastCurve(x, contrast);
      y = levelsCurve(y, whites, blacks);
      y = parametricCurve(
        y,
        shadows: s.value(P.curveShadows),
        darks: s.value(P.curveDarks),
        lights: s.value(P.curveLights),
        highlights: s.value(P.curveHighlights),
        splitShadow: s.value(P.splitShadow),
        splitMidtone: s.value(P.splitMidtone),
        splitHighlight: s.value(P.splitHighlight),
      );
      if (!master.isIdentity) y = master.evaluate(y * 255) / 255;
      return y;
    }

    _bakeRow(values, 0, composite);
    final channels = [s.curves.red, s.curves.green, s.curves.blue];
    for (var c = 0; c < 3; c++) {
      final curve = channels[c];
      _bakeRow(
        values,
        c + 1,
        curve.isIdentity ? (x) => x : (x) => curve.evaluate(x * 255) / 255,
      );
    }
    final active = channels.any((c) => !c.isIdentity);
    return ToneLut._(values, active, keyFor(s));
  }

  static void _bakeRow(Uint16List out, int row, double Function(double) f) {
    var prev = 0;
    for (var i = 0; i < kToneLutSize; i++) {
      final q = quantize16(f(i / (kToneLutSize - 1)));
      // Running max keeps every row monotone.
      prev = i == 0 ? q : math.max(prev, q);
      out[row * kToneLutSize + i] = prev;
    }
  }

  /// Cache key: changes only when a tone or curve parameter changes.
  static int keyFor(DevelopSettings s) => Object.hash(
    Object.hashAll([for (final id in _toneParams) s.value(id)]),
    s.curves,
  );

  static const _toneParams = [
    P.contrast,
    P.whites,
    P.blacks,
    P.curveShadows,
    P.curveDarks,
    P.curveLights,
    P.curveHighlights,
    P.splitShadow,
    P.splitMidtone,
    P.splitHighlight,
  ];

  /// Quantized entries, row-major (`row * kToneLutSize + i`).
  final Uint16List values;

  /// True when any R/G/B point curve is not identity.
  final bool curvesActive;

  final int key;

  double entry(int row, int i) => values[row * kToneLutSize + i] / 65535;

  /// Linear interpolation between two entries, exactly like `develop.frag`.
  double lookup(int row, double x) {
    final p = x.clamp(0.0, 1.0) * (kToneLutSize - 1);
    final i0 = p.floor();
    if (i0 >= kToneLutSize - 1) return entry(row, kToneLutSize - 1);
    final f = p - i0;
    return entry(row, i0) * (1 - f) + entry(row, i0 + 1) * f;
  }

  /// RGBA8888 bytes of the 1024×4 LUT texture (R=hi, G=lo, A=255).
  Uint8List toRgba() {
    final out = Uint8List(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      out[i * 4] = packHi(values[i]);
      out[i * 4 + 1] = packLo(values[i]);
      out[i * 4 + 3] = 255;
    }
    return out;
  }
}
