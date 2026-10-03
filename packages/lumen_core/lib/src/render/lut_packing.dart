/// 16-bit value ⇄ two 8-bit channels (R = high byte, G = low byte).
///
/// Packed textures are always opaque (A = 255) so premultiplication can never
/// corrupt them, and they are sampled with `FilterQuality.none` at texel
/// centers. The shader unpacks with `dot(rg, vec2(65280, 255)) / 65535`.
library;

import 'dart:typed_data';

/// Normalized 0..1 → 16-bit integer (clamped, rounded).
int quantize16(double v) {
  if (v.isNaN || v <= 0) return 0;
  if (v >= 1) return 65535;
  return (v * 65535).round();
}

double dequantize16(int q) => q / 65535;

int packHi(int q) => (q >> 8) & 0xff;
int packLo(int q) => q & 0xff;

int unpackBytes16(int hi, int lo) => (hi << 8) | lo;

/// Bytes → normalized value, exactly as the shader computes it.
double unpackNormalized(int hi, int lo) => unpackBytes16(hi, lo) / 65535;

/// Packs [values] (normalized) into an RGBA8888 plane: R=hi, G=lo,
/// B=[blue] (or 0), A=255.
Uint8List packPlane16(List<double> values, {List<int>? blue}) {
  if (blue != null && blue.length != values.length) {
    throw ArgumentError('blue length ${blue.length} != ${values.length}');
  }
  final out = Uint8List(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    final q = quantize16(values[i]);
    final o = i * 4;
    out[o] = packHi(q);
    out[o + 1] = packLo(q);
    out[o + 2] = blue == null ? 0 : blue[i];
    out[o + 3] = 255;
  }
  return out;
}
