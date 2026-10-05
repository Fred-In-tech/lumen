/// CPU reference of `retouch.frag` (research 09 §4). Each numbered step
/// maps 1:1 to the shader: OkLab of linear sRGB, deltas sampled in source
/// uv, per-face rows selected by the nearest face id. The
/// image-scope backdrop change (`backdrop_kernel.dart`) is added on top of
/// the face result, both computed from the same source pixel.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../color/srgb.dart';
import '../render/rgba_buffer.dart';
import 'backdrop_kernel.dart';
import 'blemish_types.dart';
import 'filters.dart';
import 'kernel_constants.dart';
import 'lab_planes.dart';
import 'retouch_maps.dart';
import 'retouch_uniforms.dart';
import 'wrinkle_map.dart';

class RetouchKernel {
  RetouchKernel(this.maps, this.uniforms)
    : _active = List.generate(
        kMaxRetouchFaces,
        (k) => retouchSlotActive(maps, uniforms, k),
      ),
      _info = List.generate(kMaxRetouchFaces, maps.faceInSlot),
      _bd = BackdropKernel(maps.backdrop, uniforms.backdrop);

  final RetouchMaps maps;
  final RetouchUniforms uniforms;
  final List<bool> _active;
  final List<RetouchFaceInfo?> _info;
  final BackdropKernel _bd;
  final Float64List _t = Float64List(12);
  final Float64List _c = Float64List(3);
  final Float64List _li = Float64List(3);
  final Float64List _d = Float64List(3);
  final Float64List _o = Float64List(3);

  /// True when face [slot] has maps and a non-identity row.
  bool isActive(int slot) =>
      slot >= 0 && slot < _active.length && _active[slot];

  /// True when backdrop effects run (every pixel must be visited).
  bool get backdropActive => _bd.active;

  /// Shades one pixel with source bytes `(r, g, b)` at source uv `(u, v)`
  /// into `out[o..o+2]`. Returns false (and writes nothing) when no effect
  /// touches the pixel, so the caller keeps the source bit-exact.
  bool retouchPixel(
    int r,
    int g,
    int b,
    double u,
    double v,
    Uint8List out,
    int o,
  ) {
    // 1. Face row (nearest face id; 0 = no face).
    final slot = maps.nearest(RetouchChannel.faceId, u, v) - 1;
    final face = isActive(slot) && _face(slot, r, g, b, u, v);
    // 15. Backdrop (image scope), added to the face result.
    final backdrop = _bd.weights(u, v);
    if (!face && !backdrop) return false;
    final oo = _o, li = _li;
    if (!face) {
      final lut = kSrgbByteToLinear;
      linearToOklab(lut[r], lut[g], lut[b], li, 0);
      oo[0] = li[0];
      oo[1] = li[1];
      oo[2] = li[2];
    }
    if (backdrop) _bd.apply(u, v, li, oo);
    oklabToSrgbBytes(oo[0], oo[1], oo[2], out, o, _c);
    return true;
  }

  /// Face steps 2–14 into [_o] (and the source OkLab into [_li]); false
  /// when no face effect touches the pixel.
  bool _face(int slot, int r, int g, int b, double u, double v) {
    final p = uniforms.row(slot);
    // 2. Regions (bilinear, 0..1).
    final t = _t;
    maps.sampleTile(maps.regionA, 0, u, v, t, 0);
    maps.sampleTile(maps.regionA, 1, u, v, t, 3);
    maps.sampleTile(maps.regionB, 0, u, v, t, 6);
    final skin = t[0] / 255, underEye = t[1] / 255, lash = t[2] / 255;
    final mouth = t[3] / 255, sclera = t[4] / 255, irisM = t[5] / 255;
    final lipsM = t[6] / 255, blushM = t[7] / 255;
    final dW = decodeWrinkle(t[8]);
    final sel = spotSelection(
      maps.nearest(RetouchChannel.spotCode, u, v),
      p.acne,
      p.freckle,
      p.mole,
      p.shineFill,
      p.glare,
    );
    // 3. Effect weights; untouched pixels keep the source exactly.
    final s = p.smooth * skin, ev = p.even * skin;
    final tex = (p.textureGain - 1) * skin;
    final ue = underEye * (1 - p.lidProtect * lash);
    final dc = p.darkCircles * ue, bg = p.bags * ue;
    final sh = p.shine * skin;
    final teeth = mouth * (p.teethBrightness + p.teethDesaturate);
    final sw = p.whites * sclera, rv = p.redVein * sclera;
    final iw = p.iris * irisM, lw = p.lips * lipsM, bw = p.blush * blushM;
    // Red-eye: analytic discs around the iris centres (map px).
    var re = 0.0;
    if (p.redEye > 0) {
      final f = _info[slot]!;
      final px = u * maps.width, py = v * maps.height;
      final rad = kRedEyeRadiusIod * f.iod;
      final d = math.min(
        _hypot(px - f.eyeRightX, py - f.eyeRightY),
        _hypot(px - f.eyeLeftX, py - f.eyeLeftY),
      );
      re = p.redEye * (1 - smoothstep(kRedEyeEdge * rad, rad, d));
    }
    // Wrinkle removal: zone slider (nearest zone code) plus a share of
    // Smooth, capped at kWrinkleMax (§4.10).
    final wEff = dW > 0
        ? kWrinkleMax *
              clamp01(
                p.wrinkleWeight(
                      maps.nearest(RetouchChannel.wrinkleZone, u, v),
                    ) +
                    kWrinkleSmooth * s,
              )
        : 0.0;
    if (s == 0 && ev == 0 && tex == 0 && dc == 0 && bg == 0 && sh == 0) {
      if (wEff == 0 && teeth == 0 && sw == 0 && rv == 0 && iw == 0) {
        if (sel == 0 && lw == 0 && bw == 0 && re == 0) return false;
      }
    }
    // 4. OkLab of the source; every skin effect is `weight · Δ` added to
    // it (the deltas are band-limited, so pores are never attenuated).
    final li = _li, d = _d, oo = _o;
    final lut = kSrgbByteToLinear;
    linearToOklab(lut[r], lut[g], lut[b], li, 0);
    oo[0] = li[0];
    oo[1] = li[1];
    oo[2] = li[2];
    // 5. Spot heal, wrinkle fill.
    if (sel > 0) {
      maps.sampleDelta(RetouchDelta.heal, u, v, d, 0);
      oo[0] += sel * d[0];
      oo[1] += sel * d[1];
      oo[2] += sel * d[2];
    }
    oo[0] += wEff * dW;
    // 6. Smooth (mid bands) and Shine (specular layer).
    if (s > 0) {
      maps.sampleDelta(RetouchDelta.smooth, u, v, d, 0);
      oo[0] += s * d[0];
      oo[1] += s * d[1];
      oo[2] += s * d[2];
    }
    if (sh > 0) {
      maps.sampleDelta(RetouchDelta.shine, u, v, d, 0);
      oo[0] += sh * d[0];
      oo[1] += sh * d[1];
      oo[2] += sh * d[2];
    }
    // 7. Texture: gain on the source's fine band.
    if (tex != 0) {
      _bandLab(maps.low, u, v, d);
      oo[0] += tex * (li[0] - d[0]);
      oo[1] += tex * (li[1] - d[1]);
      oo[2] += tex * (li[2] - d[2]);
    }
    // 8. Even tone (chroma only) and eye bags (L only) share a tile.
    if (ev > 0 || bg > 0) {
      maps.sampleDelta(RetouchDelta.bagEven, u, v, d, 0);
      oo[0] += bg * d[0];
      oo[1] += ev * d[1];
      oo[2] += ev * d[2];
    }
    // 9. Dark circles: toward the cheek, lightness with its colour.
    if (dc > 0) {
      maps.sampleDelta(RetouchDelta.darkCircles, u, v, d, 0);
      oo[0] += dc * d[0];
      oo[1] += dc * d[1];
      oo[2] += dc * d[2];
    }
    // 10. Teeth: mouth ∩ bright ∩ not red; never above the cap (§4.9).
    if (teeth > 0) {
      final tm =
          mouth *
          smoothstep(kTeethLLo, kTeethLHi, li[0]) *
          (1 - smoothstep(kTeethRedLo, kTeethRedHi, li[1]));
      if (tm > 0) {
        final td = p.teethDesaturate * tm, tb = p.teethBrightness * tm;
        oo[2] *= 1 - kTeethYellowCut * td;
        oo[1] *= 1 - kTeethRedCut * td;
        oo[0] += math.min(kTeethMaxLift, kTeethLift * (1 - oo[0])) * tb;
        oo[0] = math.min(oo[0], math.max(li[0], _info[slot]!.teethCapL));
      }
    }
    // 11. Eye whites: less red / yellow, tiny lift; red veins; iris.
    if (sw > 0) {
      final w = sw * smoothstep(kScleraLLo, kScleraLHi, li[0]);
      oo[1] *= 1 - kScleraRedCut * w;
      oo[2] *= 1 - kScleraYellowCut * w;
      oo[0] = math.min(
        oo[0] + kScleraLift * w * (1 - oo[0]),
        math.max(li[0], kScleraMaxL),
      );
    }
    if (rv > 0 || iw > 0) {
      maps.sampleDelta(RetouchDelta.eyes, u, v, d, 0);
      if (rv > 0) {
        final w = rv * smoothstep(kVeinLLo, kVeinLHi, li[0]);
        oo[1] += w * d[1];
        oo[0] += w * d[2];
      }
      if (iw > 0) {
        final w = iw * (1 - smoothstep(kIrisCatchLo, kIrisCatchHi, li[0]));
        oo[0] += w * (d[0] + kIrisLift);
        oo[1] *= 1 + kIrisChroma * w;
        oo[2] *= 1 + kIrisChroma * w;
      }
    }
    // 12. Lips: chroma toward the face's natural target (hue and texture
    // kept), slight deepening; gloss above the lip P95 is skipped (§3.9).
    if (lw > 0) {
      final f = _info[slot]!;
      final w =
          lw *
          (1 -
              smoothstep(
                f.lipGlossL + kLipGlossStart,
                f.lipGlossL + kLipGlossEnd,
                li[0],
              ));
      final k = 1 + w * (f.lipChromaGain - 1);
      oo[1] *= k;
      oo[2] *= k;
      oo[0] += w * f.lipShiftL;
    }
    // 13. Blush: the face's blush shift, slight darkening (§3.9).
    if (bw > 0) {
      final f = _info[slot]!;
      oo[1] += bw * f.blushA;
      oo[2] += bw * f.blushB;
      oo[0] *= 1 - kBlushDarken * bw;
    }
    // 14. Red-eye: strongly red pupils in the eye discs lose their colour
    // and darken; brown irises, skin and the catchlight do not qualify.
    if (re > 0) {
      final w =
          re *
          smoothstep(kRedEyeALo, kRedEyeAHi, li[1]) *
          smoothstep(0, kRedEyeHueSpan, li[1] - li[2]) *
          (1 - smoothstep(kRedEyeCatchLo, kRedEyeCatchHi, li[0]));
      oo[1] *= 1 - w;
      oo[2] *= 1 - w;
      oo[0] *= 1 - kRedEyeDarken * w;
    }
    return true;
  }

  static double _hypot(double x, double y) => math.sqrt(x * x + y * y);

  /// Bilinear band sample (sRGB bytes) → OkLab, like the shader.
  void _bandLab(Uint8List tex, double u, double v, Float64List out) {
    maps.sampleRgb(tex, u, v, _c, 0);
    linearToOklab(
      bandByteToLinear(_c[0]),
      bandByteToLinear(_c[1]),
      bandByteToLinear(_c[2]),
      out,
      0,
    );
  }
}

/// Applies the retouch pass to [src] (any size; maps are sampled in uv).
///
/// Returns [src] itself (bit-exact, same instance) when the pass changes
/// nothing ([retouchPassActive]); otherwise a new buffer in which only
/// pixels touched by an effect differ.
RgbaBuffer applyRetouch(RgbaBuffer src, RetouchMaps maps, RetouchUniforms u) {
  if (!retouchPassActive(maps, u)) return src;
  final kernel = RetouchKernel(maps, u);
  final out = src.copy();
  final w = src.width, h = src.height, d = src.data;
  if (kernel.backdropActive) {
    for (var y = 0; y < h; y++) {
      final v = (y + 0.5) / h;
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        kernel.retouchPixel(
          d[o],
          d[o + 1],
          d[o + 2],
          (x + 0.5) / w,
          v,
          out.data,
          o,
        );
      }
    }
    return out;
  }
  for (final f in maps.faces) {
    if (!kernel.isActive(f.slot)) continue;
    final x0 = (f.rect.x0 * w / maps.width).floor().clamp(0, w);
    final x1 = (f.rect.x1 * w / maps.width).ceil().clamp(0, w);
    final y0 = (f.rect.y0 * h / maps.height).floor().clamp(0, h);
    final y1 = (f.rect.y1 * h / maps.height).ceil().clamp(0, h);
    for (var y = y0; y < y1; y++) {
      final v = (y + 0.5) / h;
      for (var x = x0; x < x1; x++) {
        final o = (y * w + x) * 4;
        kernel.retouchPixel(
          d[o],
          d[o + 1],
          d[o + 2],
          (x + 0.5) / w,
          v,
          out.data,
          o,
        );
      }
    }
  }
  return out;
}
