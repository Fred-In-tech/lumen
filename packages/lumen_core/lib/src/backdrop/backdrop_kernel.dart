/// CPU twin of `backdrop.frag` (pass `B`, source space, linear light):
///
/// 1. Coverage `a`, edge band `e`, depth `d` from the matte (bilinear).
/// 2. Pixels fully inside the subject (a = 1, e = 0) with no brightness
///    match keep the source bit-exact.
/// 3. New background: blur (near/far plates mixed by depth), colour,
///    gradient (sRGB mix along the angle) or image (fitted, letterboxed).
/// 4. Remove spill: un-mix the old backdrop from soft edges with the filled
///    old background, then take the old backdrop's chroma out of the edge
///    band (half of it is replaced by the new background's chroma).
/// 5. Brightness match, then `out = F·a + B·(1 − a)`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../color/srgb.dart';
import '../model/backdrop_change.dart';
import '../render/rgba_buffer.dart';
import 'backdrop_assets.dart';
import 'backdrop_filters.dart';
import 'backdrop_uniforms.dart';

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// sRGB decode at 1/16-byte steps (interpolated in between: within 1e-6 of
/// `srgbToLinear(v / 255)`), for bilinearly sampled byte values.
final Float64List _fineDecode = Float64List.fromList([
  for (var i = 0; i <= 255 * 16 + 1; i++) srgbToLinear(i / (255 * 16)),
]);

double _dec(double byteValue) {
  final x = byteValue * 16;
  final i = x.floor();
  if (i < 0) return 0;
  if (i >= 255 * 16) return 1;
  return _fineDecode[i] + (_fineDecode[i + 1] - _fineDecode[i]) * (x - i);
}

/// [src] with the backdrop [b] composited (any size: the assets are
/// sampled in source uv). Returns [src] itself when [b] is off.
RgbaBuffer applyBackdrop(RgbaBuffer src, BackdropAssets a, BackdropChange b) {
  if (b.isNone) return src;
  final f = BackdropUniforms.pack(a, b, width: src.width, height: src.height);
  final out = src.copy();
  final k = _BackdropKernel(a, f);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final o = (y * src.width + x) * 4;
      k.shade(
        src.data[o],
        src.data[o + 1],
        src.data[o + 2],
        (x + 0.5) / src.width,
        (y + 0.5) / src.height,
        out.data,
        o,
      );
    }
  }
  return out;
}

class _BackdropKernel {
  _BackdropKernel(this.a, this.f)
    : _colorR = srgbToLinear(f[18]),
      _colorG = srgbToLinear(f[19]),
      _colorB = srgbToLinear(f[20]);

  final BackdropAssets a;
  final Float32List f;
  final Float64List _t = Float64List(3);

  /// Colour (solid / letterbox), linear.
  final double _colorR;
  final double _colorG;
  final double _colorB;

  void shade(int r, int g, int b, double u, double v, Uint8List out, int o) {
    final m = a.matte, t = _t;
    sampleBytes(m.rgba, m.width, m.height, u, v, t);
    final al = t[0] / 255, e = t[1] / 255, d = t[2] / 255;
    final spill = f[34], match = f[42];
    if (al >= 1 && e <= 0 && match == 0) return; // bit-exact subject
    final mode = f[8].round();
    // 3. New background (linear).
    double br, bg, bb;
    switch (mode) {
      case 1:
        sampleBytes(a.plateA.rgba, a.plateA.width, a.plateA.height, u, v, t);
        final nr = _dec(t[0]), ng = _dec(t[1]), nb = _dec(t[2]);
        sampleBytes(a.plateB.rgba, a.plateB.width, a.plateB.height, u, v, t);
        br = nr + (_dec(t[0]) - nr) * d;
        bg = ng + (_dec(t[1]) - ng) * d;
        bb = nb + (_dec(t[2]) - nb) * d;
      case 3:
        final px = (u - 0.5) * f[28], py = v - 0.5;
        final s = ((px * f[26] + py * f[27]) / f[29] + 0.5).clamp(0.0, 1.0);
        br = srgbToLinear(f[18] + (f[22] - f[18]) * s);
        bg = srgbToLinear(f[19] + (f[23] - f[19]) * s);
        bb = srgbToLinear(f[20] + (f[24] - f[20]) * s);
      case 4:
        final pu = (u - 0.5) * f[30] + 0.5, pv = (v - 0.5) * f[31] + 0.5;
        if (f[9] > 0.5 && (pu < 0 || pu > 1 || pv < 0 || pv > 1)) {
          br = _colorR;
          bg = _colorG;
          bb = _colorB;
        } else {
          sampleBytes(
            a.plateA.rgba,
            a.plateA.width,
            a.plateA.height,
            pu,
            pv,
            t,
          );
          br = _dec(t[0]);
          bg = _dec(t[1]);
          bb = _dec(t[2]);
        }
      default:
        br = _colorR;
        bg = _colorG;
        bb = _colorB;
    }
    if (al <= 0) {
      // Pure background: the subject term is zero.
      out[o] = linearToByte(br);
      out[o + 1] = linearToByte(bg);
      out[o + 2] = linearToByte(bb);
      return;
    }
    // 4. Remove spill (its weight is 0 below a = 0.02).
    var fr = kSrgbByteToLinear[r], fg = kSrgbByteToLinear[g];
    var fb = kSrgbByteToLinear[b];
    if (spill > 0 && al < 1 && al > 0.02) {
      sampleBytes(a.fill.rgba, a.fill.width, a.fill.height, u, v, t);
      final q = 1 - al, inv = 1 / math.max(al, 0.15);
      final w = spill * _smoothstep(0.02, 0.25, al);
      fr += (((fr - q * _dec(t[0])) * inv).clamp(0.0, 1.0) - fr) * w;
      fg += (((fg - q * _dec(t[1])) * inv).clamp(0.0, 1.0) - fg) * w;
      fb += (((fb - q * _dec(t[2])) * inv).clamp(0.0, 1.0) - fb) * w;
    }
    final we = spill * e;
    if (we > 0) {
      final y = 0.2126 * fr + 0.7152 * fg + 0.0722 * fb;
      final k = math.max(
        0.0,
        (fr - y) * f[35] + (fg - y) * f[36] + (fb - y) * f[37],
      );
      fr = math.max(0.0, fr - we * k * f[35] + we * k * 0.5 * f[38]);
      fg = math.max(0.0, fg - we * k * f[36] + we * k * 0.5 * f[39]);
      fb = math.max(0.0, fb - we * k * f[37] + we * k * 0.5 * f[40]);
    }
    // 5. Brightness match and the composite.
    final gain = 1 + match * (f[43] - 1);
    out[o] = linearToByte(fr * gain * al + br * (1 - al));
    out[o + 1] = linearToByte(fg * gain * al + bg * (1 - al));
    out[o + 2] = linearToByte(fb * gain * al + bb * (1 - al));
  }
}
