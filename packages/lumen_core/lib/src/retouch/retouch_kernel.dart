/// CPU reference of `retouch.frag` (research 07 §3.1–3.9). Each numbered
/// step maps 1:1 to the shader: OkLab of linear sRGB, bands sampled in
/// source uv, per-face rows selected by the nearest face id.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../color/srgb.dart';
import '../render/rgba_buffer.dart';
import 'blemish_types.dart';
import 'filters.dart';
import 'kernel_constants.dart';
import 'lab_planes.dart';
import 'retouch_maps.dart';
import 'retouch_uniforms.dart';

class RetouchKernel {
  RetouchKernel(this.maps, this.uniforms)
    : _active = List.generate(
        kMaxRetouchFaces,
        (k) => !uniforms.row(k).isIdentity && maps.faceInSlot(k) != null,
      ),
      _capL = List.generate(
        kMaxRetouchFaces,
        (k) => maps.faceInSlot(k)?.teethCapL ?? 1.0,
      );

  final RetouchMaps maps;
  final RetouchUniforms uniforms;
  final List<bool> _active;
  final List<double> _capL;
  final Float64List _t = Float64List(12);
  final Float64List _c = Float64List(3);
  final Float64List _li = Float64List(3);
  final Float64List _l1 = Float64List(3);
  final Float64List _l2 = Float64List(3);
  final Float64List _l3 = Float64List(3);
  final Float64List _o = Float64List(3);

  /// True when face [slot] has maps and a non-identity row.
  bool isActive(int slot) =>
      slot >= 0 && slot < _active.length && _active[slot];

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
    if (!isActive(slot)) return false;
    final p = uniforms.row(slot);
    // 2. Regions (bilinear, 0..1).
    final t = _t;
    maps.sampleTile(maps.regionA, 0, u, v, t, 0);
    maps.sampleTile(maps.regionA, 1, u, v, t, 3);
    maps.sampleTile(maps.regionB, 0, u, v, t, 6);
    final skin = t[0] / 255, underEye = t[1] / 255, lash = t[2] / 255;
    final mouth = t[3] / 255, sclera = t[4] / 255, irisM = t[5] / 255;
    final wrinkle = t[8] / 255;
    final sel = spotSelection(
      maps.nearest(RetouchChannel.spotCode, u, v),
      p.acne,
      p.freckle,
      p.mole,
    );
    // 3. Effect weights; untouched pixels keep the source exactly.
    final s = p.smooth * skin, ev = p.even * skin;
    final tex = (p.textureGain - 1) * skin;
    final ue = underEye * (1 - p.lidProtect * lash);
    final dc = p.darkCircles * ue, bg = p.bags * ue;
    final sh = p.shine * skin, wr = p.wrinkle * wrinkle;
    final teeth = mouth * (p.teethBrightness + p.teethDesaturate);
    final sw = p.whites * sclera, rv = p.redVein * sclera;
    final iw = p.iris * irisM;
    if (s == 0 && ev == 0 && tex == 0 && dc == 0 && bg == 0 && sh == 0) {
      if (wr == 0 && teeth == 0 && sw == 0 && rv == 0 && iw == 0 && sel == 0) {
        return false;
      }
    }
    // 4. OkLab of the source and the bands; healed low band (§3.3).
    final li = _li, l1 = _l1, l2 = _l2, l3 = _l3;
    final lut = kSrgbByteToLinear;
    linearToOklab(lut[r], lut[g], lut[b], li, 0);
    _bandLab(maps.b1, u, v, l1);
    _bandLab(maps.b2, u, v, l2);
    _bandLab(maps.b3, u, v, l3);
    maps.sampleTile(maps.bh, 0, u, v, t, 0);
    maps.sampleTile(maps.bh, 1, u, v, t, 9);
    final fineL = li[0] - l1[0] + sel * decodeSigned(t[9], kHealRangeL);
    final fineA = li[1] - l1[1] + sel * decodeSigned(t[10], kHealRangeA);
    final fineB = li[2] - l1[2] + sel * decodeSigned(t[11], kHealRangeB);
    l1[0] += sel * decodeSigned(t[0], kHealRangeL);
    l1[1] += sel * decodeSigned(t[1], kHealRangeA);
    l1[2] += sel * decodeSigned(t[2], kHealRangeB);
    // 5. Three bands, amplitude-selective mid suppression (§3.1, §3.4).
    final midL = l1[0] - l2[0], midA = l1[1] - l2[1], midB = l1[2] - l2[2];
    final thr = p.ampThreshold;
    final keep = smoothstep(thr, kKeepRamp * thr, midL.abs());
    final midK = 1 - clamp01(s * (1 - keep) + kWrinkleMid * wr);
    final fineK = (1 + tex) * (1 - kWrinkleFine * wr);
    final oo = _o;
    oo[0] = l2[0] + midL * midK + fineL * fineK;
    // 6. Tone evening: base chroma toward the skin reference (§3.2).
    oo[1] = l2[1] + ev * (l3[1] - l2[1]) + midA * midK + fineA * fineK;
    oo[2] = l2[2] + ev * (l3[2] - l2[2]) + midB * midK + fineB * fineK;
    // 7. Under-eye: dark circles and bags, lid-protected (§3.5).
    if (dc > 0 || bg > 0) {
      oo[0] += dc * kDarkCircleLift * math.max(0.0, l3[0] - l2[0]);
      oo[1] += dc * kDarkCircleChroma * (l3[1] - l2[1]);
      oo[2] += dc * kDarkCircleChroma * (l3[2] - l2[2]);
      final flat = bg * kBagMid * midK * (1 - keep);
      oo[0] += bg * kBagBase * (l3[0] - l2[0]) - flat * midL;
      oo[1] -= flat * midA;
      oo[2] -= flat * midB;
    }
    // 8. Shine: bright, desaturated relative to the skin reference (§3.8).
    if (sh > 0) {
      final rel = l1[0] - l3[0];
      final c1 = math.sqrt(l1[1] * l1[1] + l1[2] * l1[2]);
      final c3 = math.max(math.sqrt(l3[1] * l3[1] + l3[2] * l3[2]), 1e-3);
      final w =
          sh *
          smoothstep(kShineRelLo, kShineRelHi, rel) *
          (1 - smoothstep(kShineDesatLo, kShineDesatHi, c1 / c3));
      oo[0] -= w * kShinePull * rel;
      oo[1] += (l3[1] - oo[1]) * w * kShineChroma;
      oo[2] += (l3[2] - oo[2]) * w * kShineChroma;
    }
    // 9. Teeth: mouth ∩ bright ∩ not red; never above the sclera (§3.6).
    if (teeth > 0) {
      final tm =
          mouth *
          smoothstep(kTeethLLo, kTeethLHi, li[0]) *
          (1 - smoothstep(kTeethRedLo, kTeethRedHi, li[1]));
      if (tm > 0) {
        final td = p.teethDesaturate * tm, tb = p.teethBrightness * tm;
        oo[2] *= 1 - kTeethYellowCut * td;
        oo[1] *= 1 - kTeethRedCut * td;
        oo[0] += kTeethLift * tb * (1 - oo[0]);
        oo[0] = math.min(oo[0], math.max(li[0], _capL[slot]));
      }
    }
    // 10. Eye whites: less red/yellow, slight lift (§3.7).
    if (sw > 0) {
      final w = sw * smoothstep(kScleraLLo, kScleraLHi, li[0]);
      oo[1] *= 1 - kScleraRedCut * w;
      oo[2] *= 1 - kScleraYellowCut * w;
      oo[0] += kScleraLift * w * (1 - oo[0]);
    }
    // 11. Red veins: fine-scale a* excess over the base (research 06 P0 #6).
    if (rv > 0) {
      final w = rv * smoothstep(kVeinLLo, kVeinLHi, li[0]);
      final vein = math.max(0.0, li[1] - l2[1]);
      oo[1] -= kVeinCut * w * vein;
      oo[0] +=
          kVeinCut *
          w *
          math.max(0.0, l2[0] - li[0]) *
          smoothstep(kVeinLiftLo, kVeinLiftHi, vein);
    }
    // 12. Iris: local contrast, chroma, small lift; keeps catchlights.
    if (iw > 0) {
      final w = iw * (1 - smoothstep(kIrisCatchLo, kIrisCatchHi, li[0]));
      oo[0] += kIrisContrast * w * (li[0] - l2[0]) + kIrisLift * w;
      oo[1] *= 1 + kIrisChroma * w;
      oo[2] *= 1 + kIrisChroma * w;
    }
    // TODO(retouch step 8): lips recolour (rb.r) and blush (rb.g), §3.9.
    oklabToSrgbBytes(oo[0], oo[1], oo[2], out, o, _c);
    return true;
  }

  /// Bilinear band sample (sRGB bytes) → OkLab, like the shader.
  void _bandLab(Uint8List tex, double u, double v, Float64List out) {
    maps.sampleRgb(tex, u, v, _c, 0);
    linearToOklab(_dec(_c[0]), _dec(_c[1]), _dec(_c[2]), out, 0);
  }

  static double _dec(double byteValue) {
    final k = byteValue.round();
    if (k == byteValue) return kSrgbByteToLinear[k];
    return srgbToLinear(byteValue / 255);
  }
}

/// Applies the retouch pass to [src] (any size; maps are sampled in uv).
///
/// Returns [src] itself (bit-exact, same instance) when [u] is the
/// identity or there are no faces; otherwise a new buffer in which only
/// pixels touched by an effect differ.
RgbaBuffer applyRetouch(RgbaBuffer src, RetouchMaps maps, RetouchUniforms u) {
  if (u.isIdentity || !maps.hasFaces) return src;
  final kernel = RetouchKernel(maps, u);
  final out = src.copy();
  final w = src.width, h = src.height, d = src.data;
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
