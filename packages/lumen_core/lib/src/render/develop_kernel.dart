/// CPU port of `develop.frag`: shades one output pixel. Each numbered stage
/// matches the shader (PLAN.md §1.6) so GPU/CPU parity tests can hold the
/// §6.3 thresholds.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../color/luminance.dart';
import '../color/oklab.dart';
import '../color/srgb.dart';
import 'aux_maps.dart';
import 'color_ops.dart';
import 'engine_constants.dart';
import 'geometry_mapping.dart';
import 'local_adjust.dart';
import 'mask_rasterizer.dart';
import 'rgba_buffer.dart';
import 'tone_lut.dart';
import 'uniform_layout.dart';

class DevelopKernel {
  DevelopKernel(this.src, this.f, this.lut, this.aux, [MaskAtlases? masks])
    : masks = masks ?? MaskAtlases.empty(),
      _colorActive = colorOpsActive(f),
      _toneIdentity = _isIdentityRow(lut),
      _hasLocal = activeMaskCount(f) > 0;

  final RgbaBuffer src;
  final Float32List f;
  final ToneLut lut;
  final AuxMaps aux;
  final MaskAtlases masks;
  final bool _colorActive;
  final bool _hasLocal;
  final Float64List _cov = Float64List(kMaxRenderedMasks);
  final Float64List _loc = Float64List(12);
  final Float64List _rgb = Float64List(3);
  final bool _toneIdentity;
  final Float64List _e = Float64List(3);
  final Float64List _lab = Float64List(3);

  static bool _isIdentityRow(ToneLut lut) {
    for (var i = 0; i < kToneLutSize; i++) {
      if (lut.values[i] != (i / (kToneLutSize - 1) * 65535).round()) {
        return false;
      }
    }
    return true;
  }

  /// Bilinear source sample (encoded 0..1), like `FilterQuality.low`.
  void _sample(double u, double v, Float64List out) {
    final w = src.width, h = src.height, d = src.data;
    final px = u * w - 0.5, py = v * h - 0.5;
    final fx0 = px.floorToDouble(), fy0 = py.floorToDouble();
    final fx = px - fx0, fy = py - fy0;
    final x0 = fx0.toInt().clamp(0, w - 1);
    final y0 = fy0.toInt().clamp(0, h - 1);
    if (fx == 0 && fy == 0) {
      final o = (y0 * w + x0) * 4;
      for (var c = 0; c < 3; c++) {
        out[c] = d[o + c] / 255;
      }
      return;
    }
    final x1 = (fx0.toInt() + 1).clamp(0, w - 1);
    final y1 = (fy0.toInt() + 1).clamp(0, h - 1);
    final o00 = (y0 * w + x0) * 4, o10 = (y0 * w + x1) * 4;
    final o01 = (y1 * w + x0) * 4, o11 = (y1 * w + x1) * 4;
    for (var c = 0; c < 3; c++) {
      final top = d[o00 + c] + (d[o10 + c] - d[o00 + c]) * fx;
      final bot = d[o01 + c] + (d[o11 + c] - d[o01 + c]) * fx;
      out[c] = (top + (bot - top) * fy) / 255;
    }
  }

  static double _decode(double e) {
    final k = e * 255;
    final r = k.roundToDouble();
    if (k == r && r >= 0 && r <= 255) return kSrgbByteToLinear[r.toInt()];
    return _fastDecode(e);
  }

  double _logLumaAt(double u, double v) {
    _sample(u, v, _e);
    return normalizedLogLuma(
      relativeLuminance(_decode(_e[0]), _decode(_e[1]), _decode(_e[2])),
    );
  }

  double _tone(double x) => _fastDecode(lut.lookup(0, _fastEncode(x)));

  /// Shades output pixel ([x], [y]) of this pass into [out] (encoded RGBA).
  void shade(int x, int y, Float64List out) {
    const t = DevelopIndex.tile;
    // 1. Output pixel → output uv → source uv.
    final u = (x + 0.5 + f[t]) / f[t + 2];
    final v = (y + 0.5 + f[t + 1]) / f[t + 3];
    final (su, sv) = sourceUvFor(u, v, f);
    if (su < 0 || su > 1 || sv < 0 || sv > 1) {
      out.fillRange(0, 4, 0);
      return;
    }
    // 2. Source → linear.
    _sample(su, sv, _e);
    var r = _decode(_e[0]), g = _decode(_e[1]), b = _decode(_e[2]);
    final iSrc = normalizedLogLuma(relativeLuminance(r, g, b));
    // Local (mask) sums: effective value = global + Σ coverage_i × local_i.
    final l = _loc;
    if (_hasLocal) {
      masks.sampleAll(su, sv, _cov);
      accumulateLocal(f, _cov, l);
    }
    const lo = DevelopIndex.local, hz = DevelopIndex.haze;
    final dz = f[hz] + l[LocalIndex.dehaze];
    final hl = f[lo] + l[LocalIndex.highlights];
    final sh = f[lo + 1] + l[LocalIndex.shadows];
    final cl = f[lo + 2] + l[LocalIndex.clarity];
    final tx = f[lo + 3] + l[LocalIndex.texture];
    final ax = (dz != 0 || hl != 0 || sh != 0 || cl != 0)
        ? aux.sample(su, sv)
        : null;
    // 3. White balance × exposure.
    const wb = DevelopIndex.wbExp;
    r *= f[wb] * f[wb + 3];
    g *= f[wb + 1] * f[wb + 3];
    b *= f[wb + 2] * f[wb + 3];
    final ev = l[LocalIndex.exposure];
    if (ev != 0 || l[LocalIndex.temp] != 0 || l[LocalIndex.tint] != 0) {
      final (gr, gg, gb) = localWbGains(l[LocalIndex.temp], l[LocalIndex.tint]);
      final k = math.pow(2, ev).toDouble();
      r *= gr * k;
      g *= gg * k;
      b *= gb * k;
    }
    // 4. Dehaze.
    if (dz != 0 && ax != null) {
      final aR = f[hz + 1], aG = f[hz + 2], aB = f[hz + 3];
      final aDark = linearToSrgb(math.min(aR, math.min(aG, aB)));
      final ratio = (ax.dark / math.max(aDark, 1e-3)).clamp(0.0, 1.0);
      final tr = math.max(1 - kDehazeOmega * dz.abs() * ratio, kDehazeTMin);
      if (dz > 0) {
        r = math.max((r - aR) / tr + aR, 0.0);
        g = math.max((g - aG) / tr + aG, 0.0);
        b = math.max((b - aB) / tr + aB, 0.0);
      } else {
        final m = kDehazeNegMix * -dz * (1 - tr);
        r += (aR - r) * m;
        g += (aG - g) * m;
        b += (aB - b) * m;
      }
    }
    // 5. Shadows / highlights from the guided base.
    if ((hl != 0 || sh != 0) && ax != null) {
      final q = ax.meanA * iSrc + ax.meanB;
      final base = q * kLogLumaRange - kLogLumaOffset + _log2(f[wb + 3]) + ev;
      final bn = _fastEncode(math.pow(2, base).toDouble());
      final dEv =
          kShStops *
          (sh * (1 - smoothstep(kShShadowEdge1, kShShadowEdge0, bn)) +
              hl * smoothstep(kShHighlightEdge0, kShHighlightEdge1, bn));
      final k = math.pow(2, dEv).toDouble();
      r *= k;
      g *= k;
      b *= k;
    }
    // 6. Clarity (vs. baseMid) and texture (vs. 3×3 source blur).
    if (cl != 0 || tx != 0) {
      final ve = _fastEncode(relativeLuminance(r, g, b));
      final mid = (1 - (2 * ve - 1) * (2 * ve - 1)).clamp(0.0, 1.0);
      var dl = 0.0;
      if (cl != 0 && ax != null) {
        dl += cl * kClarityGain * (iSrc - ax.baseMid) * kLogLumaRange * mid;
      }
      if (tx != 0) {
        final du = 1 / f[DevelopIndex.src], dv = 1 / f[DevelopIndex.src + 1];
        var blur = 4 * iSrc;
        for (final (ox, oy, w) in _texTaps) {
          blur += w * _logLumaAt(su + ox * du, sv + oy * dv);
        }
        dl += tx * kTextureGain * (iSrc - blur / 16) * kLogLumaRange;
      }
      final k = math.pow(2, dl.clamp(-kLocalMaxStops, kLocalMaxStops));
      r *= k;
      g *= k;
      b *= k;
    }
    // 7. Composite tone LUT, hue-preserving (RGBTone on max/min).
    // The CPU skips an identity LUT only when it is a no-op (0 ≤ c ≤ 1);
    // out-of-range values still get the hue-preserving clamp.
    final mx = math.max(r, math.max(g, b));
    final mn = math.min(r, math.min(g, b));
    _rgb
      ..[0] = r
      ..[1] = g
      ..[2] = b;
    if (!_toneIdentity || mx > 1 || mn < 0) {
      _hueTone(_rgb, mx, mn, _tone(mx), _tone(mn));
    }
    // 7b. Local contrast / whites / blacks (analytic, hue-preserving).
    final lcn = l[LocalIndex.contrast].clamp(-1.0, 1.0);
    final lwh = l[LocalIndex.whites].clamp(-1.0, 1.0);
    final lbl = l[LocalIndex.blacks].clamp(-1.0, 1.0);
    if (lcn != 0 || lwh != 0 || lbl != 0) {
      final x = math.max(_rgb[0], math.max(_rgb[1], _rgb[2]));
      final n = math.min(_rgb[0], math.min(_rgb[1], _rgb[2]));
      double t(double v) =>
          _fastDecode(localTone(_fastEncode(v), lcn, lwh, lbl));
      _hueTone(_rgb, x, n, t(x), t(n));
    }
    r = _rgb[0];
    g = _rgb[1];
    b = _rgb[2];
    // 8. R/G/B point curves in the encoded domain.
    if (f[DevelopIndex.color + 3] > 0.5) {
      r = _fastDecode(lut.lookup(1, _fastEncode(r)));
      g = _fastDecode(lut.lookup(2, _fastEncode(g)));
      b = _fastDecode(lut.lookup(3, _fastEncode(b)));
    }
    // 9–12. OkLab color stages.
    final localSat = l[LocalIndex.saturation];
    if (_colorActive || localSat != 0) {
      final lab = linearSrgbToOklab(r, g, b);
      _lab
        ..[0] = lab.l
        ..[1] = lab.a
        ..[2] = lab.b;
      applyColorOps(_lab, f, saturation: f[DevelopIndex.color + 1] + localSat);
      final c = oklabToLinearSrgb(Oklab(_lab[0], _lab[1], _lab[2]));
      r = c.r;
      g = c.g;
      b = c.b;
    }
    // 13. Encode, vignette, clipping overlay.
    _e
      ..[0] = _fastEncode(r)
      ..[1] = _fastEncode(g)
      ..[2] = _fastEncode(b);
    applyVignette(_e, u, v, f);
    if (f[DevelopIndex.vignette2 + 2] > 0.5) _clipOverlay(_e);
    for (var c = 0; c < 3; c++) {
      out[c] = _e[c].clamp(0.0, 1.0);
    }
    out[3] = 1;
  }

  static const _texTaps = [
    (-1.0, -1.0, 1.0),
    (0.0, -1.0, 2.0),
    (1.0, -1.0, 1.0),
    (-1.0, 0.0, 2.0),
    (1.0, 0.0, 2.0),
    (-1.0, 1.0, 1.0),
    (0.0, 1.0, 2.0),
    (1.0, 1.0, 1.0),
  ];

  static double _log2(double x) => math.log(x) / math.ln2;

  /// RGBTone: maps max→[tmx], min→[tmn], the middle channel by its relative
  /// position (keeps hue). In place on [c].
  static void _hueTone(
    Float64List c,
    double mx,
    double mn,
    double tmx,
    double tmn,
  ) {
    if (mx - mn < 1e-6) {
      c.fillRange(0, 3, tmx);
      return;
    }
    final s = (tmx - tmn) / (mx - mn);
    for (var i = 0; i < 3; i++) {
      c[i] = tmn + (c[i] - mn) * s;
    }
  }

  // CPU-only speedups: sRGB transfer through 4097-entry tables with linear
  // interpolation (max error < 2e-5, far below the 1/255 parity budget).
  static const int _tableSize = 4096;
  static final Float64List _encTable = Float64List.fromList([
    for (var i = 0; i <= _tableSize; i++) linearToSrgb(i / _tableSize),
  ]);
  static final Float64List _decTable = Float64List.fromList([
    for (var i = 0; i <= _tableSize; i++) srgbToLinear(i / _tableSize),
  ]);

  static double _interp(Float64List t, double x) {
    if (!(x > 0)) return t[0];
    if (x >= 1) return t[_tableSize];
    final p = x * _tableSize;
    final i = p.toInt();
    final f = p - i;
    return t[i] + (t[i + 1] - t[i]) * f;
  }

  /// Linear → encoded, clamped to 0..1.
  static double _fastEncode(double x) => _interp(_encTable, x);

  /// Encoded (0..1) → linear.
  static double _fastDecode(double e) => _interp(_decTable, e);

  static void _clipOverlay(Float64List e) {
    final mx = math.max(e[0], math.max(e[1], e[2]));
    if (mx >= 254.5 / 255) {
      e
        ..[0] = 1
        ..[1] = 0
        ..[2] = 0;
    } else if (mx <= 0.5 / 255) {
      e
        ..[0] = 0
        ..[1] = 0
        ..[2] = 1;
    }
  }
}
