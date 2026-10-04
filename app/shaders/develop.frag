#version 460 core
// Lumen develop uber pass (engine lumen-1). Every per-pixel op in float.
// CPU twin: packages/lumen_core/lib/src/render/develop_kernel.dart and
// color_ops.dart; local masks: local_adjust.dart; uniform layout:
// uniform_layout.dart (194 floats).
#include <flutter/runtime_effect.glsl>
#include "lib/common.glsl"

precision highp float;

uniform vec2 uOutSize;          // 0-1   pass size (px)
uniform vec4 uTile;             // 2-5   tile offset xy, full output wh
uniform vec4 uCrop;             // 6-9   l, t, r, b (normalized, oriented)
uniform vec4 uGeom;             // 10-13 angle rad, rotate90, flipH, flipV
uniform vec4 uSrc;              // 14-17 source wh, aux wh
uniform vec4 uWbExp;            // 18-21 gains rgb, 2^exposure
uniform vec4 uLocal;            // 22-25 highlights, shadows, clarity, texture
uniform vec4 uHaze;             // 26-29 dehaze, airlight rgb (linear)
uniform vec4 uColor;            // 30-33 vibrance, saturation, bw, curvesActive
uniform vec4 uHslHue0;          // 34-37
uniform vec4 uHslHue1;          // 38-41
uniform vec4 uHslSat0;          // 42-45
uniform vec4 uHslSat1;          // 46-49
uniform vec4 uHslLum0;          // 50-53
uniform vec4 uHslLum1;          // 54-57
uniform vec4 uGradeShadows;     // 58-61 OkLab a, b, lum, 0
uniform vec4 uGradeMidtones;    // 62-65
uniform vec4 uGradeHighlights;  // 66-69
uniform vec4 uGradeGlobal;      // 70-73
uniform vec4 uGradeParams;      // 74-77 blending, balance, 0, 0
uniform vec4 uBwMix0;           // 78-81
uniform vec4 uBwMix1;           // 82-85
uniform vec4 uVignette;         // 86-89 amount, midpoint, roundness, feather
uniform vec4 uVignette2;        // 90-93 highlights, aspect, showClipping, 0
uniform vec4 uMaskGrid;         // 94-97 mask grid wh, active count, 0
uniform vec4 uMask0A;           // 98-109: exposure EV, temp, tint, sat
uniform vec4 uMask0B;           //   highlights, shadows, clarity, texture
uniform vec4 uMask0C;           //   dehaze, contrast, whites, blacks
uniform vec4 uMask1A;           // 110-121: exposure EV, temp, tint, sat
uniform vec4 uMask1B;           //   highlights, shadows, clarity, texture
uniform vec4 uMask1C;           //   dehaze, contrast, whites, blacks
uniform vec4 uMask2A;           // 122-133: exposure EV, temp, tint, sat
uniform vec4 uMask2B;           //   highlights, shadows, clarity, texture
uniform vec4 uMask2C;           //   dehaze, contrast, whites, blacks
uniform vec4 uMask3A;           // 134-145: exposure EV, temp, tint, sat
uniform vec4 uMask3B;           //   highlights, shadows, clarity, texture
uniform vec4 uMask3C;           //   dehaze, contrast, whites, blacks
uniform vec4 uMask4A;           // 146-157: exposure EV, temp, tint, sat
uniform vec4 uMask4B;           //   highlights, shadows, clarity, texture
uniform vec4 uMask4C;           //   dehaze, contrast, whites, blacks
uniform vec4 uMask5A;           // 158-169: exposure EV, temp, tint, sat
uniform vec4 uMask5B;           //   highlights, shadows, clarity, texture
uniform vec4 uMask5C;           //   dehaze, contrast, whites, blacks
uniform vec4 uMask6A;           // 170-181: exposure EV, temp, tint, sat
uniform vec4 uMask6B;           //   highlights, shadows, clarity, texture
uniform vec4 uMask6C;           //   dehaze, contrast, whites, blacks
uniform vec4 uMask7A;           // 182-193: exposure EV, temp, tint, sat
uniform vec4 uMask7B;           //   highlights, shadows, clarity, texture
uniform vec4 uMask7C;           //   dehaze, contrast, whites, blacks

uniform sampler2D uSource;      // 0: sRGB source (FilterQuality.low)
uniform sampler2D uAuxA;        // 1: RG baseMid, B dark (FilterQuality.none)
uniform sampler2D uAuxB;        // 2: RG meanB, B meanA (FilterQuality.none)
uniform sampler2D uCurveLut;    // 3: 1024x4 packed LUT (FilterQuality.none)
uniform sampler2D uMasks0;      // 4: masks 0-3 atlas (2w x h, FilterQuality.none)
uniform sampler2D uMasks1;      // 5: masks 4-7 atlas

out vec4 fragColor;

// ---- Aux maps: manual bilinear over texel centers (AuxMaps.sample) ---------
vec2 auxTapA(vec2 t) {
  vec4 s = texture(uAuxA, (t + 0.5) / uSrc.zw);
  return vec2(unpack16(s.rg), s.b);
}

vec2 auxTapB(vec2 t) {
  vec4 s = texture(uAuxB, (t + 0.5) / uSrc.zw);
  return vec2(unpack16(s.rg), s.b);
}

// Returns (baseMid, dark, meanB, meanA).
vec4 sampleAux(vec2 uv) {
  vec2 p = uv * uSrc.zw - 0.5;
  vec2 i0 = floor(p);
  vec2 f = p - i0;
  vec2 lo = clamp(i0, vec2(0.0), uSrc.zw - 1.0);
  vec2 hi = clamp(i0 + 1.0, vec2(0.0), uSrc.zw - 1.0);
  vec2 a = mix(mix(auxTapA(lo), auxTapA(vec2(hi.x, lo.y)), f.x),
               mix(auxTapA(vec2(lo.x, hi.y)), auxTapA(hi), f.x), f.y);
  vec2 b = mix(mix(auxTapB(lo), auxTapB(vec2(hi.x, lo.y)), f.x),
               mix(auxTapB(vec2(lo.x, hi.y)), auxTapB(hi), f.x), f.y);
  return vec4(a, b);
}

// ---- Mask atlases: left tile RGB = masks 4k..4k+2, right tile R = 4k+3 ----
vec4 maskTap0(vec2 t) {
  vec2 size = vec2(2.0 * uMaskGrid.x, uMaskGrid.y);
  return vec4(texture(uMasks0, (t + 0.5) / size).rgb,
              texture(uMasks0, (t + vec2(uMaskGrid.x + 0.5, 0.5)) / size).r);
}

vec4 maskTap1(vec2 t) {
  vec2 size = vec2(2.0 * uMaskGrid.x, uMaskGrid.y);
  return vec4(texture(uMasks1, (t + 0.5) / size).rgb,
              texture(uMasks1, (t + vec2(uMaskGrid.x + 0.5, 0.5)) / size).r);
}

// Local sums (local_adjust.dart accumulateLocal): A = exposure, temp, tint,
// sat; B = highlights, shadows, clarity, texture; C = dehaze, contrast,
// whites, blacks.
void localSums(vec2 uv, out vec4 lA, out vec4 lB, out vec4 lC) {
  lA = vec4(0.0);
  lB = vec4(0.0);
  lC = vec4(0.0);
  if (uMaskGrid.z < 0.5) return;
  vec2 lo;
  vec2 hi;
  vec2 f;
  maskTaps(uv, uMaskGrid.xy, lo, hi, f);
  vec4 c0 = bilerp(maskTap0(lo), maskTap0(vec2(hi.x, lo.y)),
                   maskTap0(vec2(lo.x, hi.y)), maskTap0(hi), f);
  vec4 c1 = vec4(0.0);
  if (uMaskGrid.z > 4.5) {
    c1 = bilerp(maskTap1(lo), maskTap1(vec2(hi.x, lo.y)),
                maskTap1(vec2(lo.x, hi.y)), maskTap1(hi), f);
  }
  lA = c0.x * uMask0A + c0.y * uMask1A + c0.z * uMask2A + c0.w * uMask3A +
       c1.x * uMask4A + c1.y * uMask5A + c1.z * uMask6A + c1.w * uMask7A;
  lB = c0.x * uMask0B + c0.y * uMask1B + c0.z * uMask2B + c0.w * uMask3B +
       c1.x * uMask4B + c1.y * uMask5B + c1.z * uMask6B + c1.w * uMask7B;
  lC = c0.x * uMask0C + c0.y * uMask1C + c0.z * uMask2C + c0.w * uMask3C +
       c1.x * uMask4C + c1.y * uMask5C + c1.z * uMask6C + c1.w * uMask7C;
}

// ---- Tone LUT (ToneLut.lookup) ---------------------------------------------
float lutTap(float i, float row) {
  return unpack16(texture(uCurveLut, vec2((i + 0.5) / 1024.0, (row + 0.5) / 4.0)).rg);
}

float lutLookup(float row, float x) {
  float p = clamp(x, 0.0, 1.0) * 1023.0;
  float i0 = floor(p);
  float f = p - i0;
  float i1 = min(i0 + 1.0, 1023.0);
  return mix(lutTap(i0, row), lutTap(i1, row), f);
}

float tone(float x) {
  return srgbDecode1(lutLookup(0.0, srgbEncode1(x)));
}

float lumaAt(vec2 uv) {
  return normLogLuma(dot(srgbDecode(texture(uSource, uv).rgb), REC709));
}

// ---- Color stages (color_ops.dart) ----------------------------------------
float bandW(float h, float c, float lw, float rw) {
  float d = mod(h - c + 540.0, 360.0) - 180.0;
  float w = d >= 0.0 ? rw : lw;
  float ad = abs(d);
  return ad >= w ? 0.0 : 0.5 * (1.0 + cos(3.14159265358979 * ad / w));
}

// Band centers 25 55 100 140 195 255 295 335 (kHslBandCenters).
vec4 bandsA(float h) {
  return vec4(bandW(h, 25.0, 50.0, 30.0), bandW(h, 55.0, 30.0, 45.0),
              bandW(h, 100.0, 45.0, 40.0), bandW(h, 140.0, 40.0, 55.0));
}

vec4 bandsB(float h) {
  return vec4(bandW(h, 195.0, 55.0, 60.0), bandW(h, 255.0, 60.0, 40.0),
              bandW(h, 295.0, 40.0, 40.0), bandW(h, 335.0, 40.0, 50.0));
}

vec3 colorOps(vec3 lab, float sat) {
  float l = lab.x;
  float c = length(lab.yz);
  float h = okHue(lab.yz);
  // 9. HSL mixer.
  vec4 wA = bandsA(h);
  vec4 wB = bandsB(h);
  float dh = dot(wA, uHslHue0) + dot(wB, uHslHue1);
  float ds = dot(wA, uHslSat0) + dot(wB, uHslSat1);
  float dl = dot(wA, uHslLum0) + dot(wB, uHslLum1);
  float chromaW = smoothstep(0.0, 0.06, c);
  h += dh * 30.0 * chromaW;
  c *= max(0.0, 1.0 + ds * chromaW);
  l *= 1.0 + 0.3 * dl * chromaW;
  // 10. Vibrance then saturation.
  float k = 1.0 + sat;
  if (uColor.x > 0.0) {
    float lowSat = 1.0 - smoothstep(0.0, 0.25, c);
    float skin = smoothstep(10.0, 20.0, h) * (1.0 - smoothstep(75.0, 85.0, h));
    k *= 1.0 + uColor.x * lowSat * (1.0 - 0.6 * skin);
  } else {
    k *= 1.0 + uColor.x;
  }
  c *= max(k, 0.0);
  float hr = radians(h);
  vec2 ab = c * vec2(cos(hr), sin(hr));
  // 11. Color grading.
  float lc = clamp(l, 0.0, 1.0);
  float pivot = 0.5 - 0.3 * uGradeParams.y;
  float width = 0.12 + 0.33 * uGradeParams.x;
  float ws = 1.0 - smoothstep(pivot - width, pivot + 0.5 * width, lc);
  float wh = smoothstep(pivot - 0.5 * width, pivot + width, lc);
  float wm = exp(-(lc - pivot) * (lc - pivot) / (2.0 * width * width));
  float sum = max(ws + wm + wh, 1.0);
  ws /= sum;
  wm /= sum;
  wh /= sum;
  vec3 zone = ws * uGradeShadows.xyz + wm * uGradeMidtones.xyz +
              wh * uGradeHighlights.xyz + uGradeGlobal.xyz;
  float fade = clamp(4.0 * l, 0.0, 1.0);
  ab += zone.xy * fade;
  l *= 1.0 + 0.25 * zone.z;
  // 12. B&W mix.
  if (uColor.z > 0.5) {
    float h2 = okHue(ab);
    float mixv = dot(bandsA(h2), uBwMix0) + dot(bandsB(h2), uBwMix1);
    l *= 1.0 + 0.5 * mixv * smoothstep(0.0, 0.08, length(ab));
    ab = vec2(0.0);
  }
  return vec3(l, ab);
}

// 13. Post-crop vignette, paint style in the encoded domain.
vec3 vignette(vec3 e, vec2 uv) {
  float amount = uVignette.x;
  if (amount == 0.0) return e;
  vec2 p = abs(uv * 2.0 - 1.0);
  float aspect = uVignette2.y;
  vec2 asp = vec2(aspect, 1.0) / max(aspect, 1.0);
  p *= mix(vec2(1.0), asp, max(uVignette.z, 0.0));
  float n = 2.0 + 6.0 * max(-uVignette.z, 0.0);
  float d = pow(pow(p.x, n) + pow(p.y, n), 1.0 / n);
  float mid = 0.35 + 0.9 * uVignette.y;
  float fe = max(uVignette.w, 0.02) * 0.8;
  float m = smoothstep(mid - fe, mid + fe, d);
  if (amount < 0.0) {
    float protect = uVignette2.x * smoothstep(0.5, 1.0, dot(e, REC709));
    return e * (1.0 + amount * m * (1.0 - protect));
  }
  return e + (1.0 - e) * amount * m;
}

void main() {
  // 1. Output pixel -> output uv -> source uv.
  vec2 px = min(FlutterFragCoord().xy, uOutSize);
  vec2 uv = (px + uTile.xy) / uTile.zw;
  vec2 suv = sourceUvFrom(uv, uCrop, uGeom, uSrc.xy);
  if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
    fragColor = vec4(0.0);
    return;
  }
  // 2. Source -> linear.
  vec3 c = srgbDecode(texture(uSource, suv).rgb);
  float iSrc = normLogLuma(dot(c, REC709));
  vec4 ax = sampleAux(suv);
  // Local (mask) sums: effective value = global + sum(coverage * local).
  vec4 lA;
  vec4 lB;
  vec4 lC;
  localSums(suv, lA, lB, lC);
  // 3. White balance x exposure (+ local exposure / temp / tint gains).
  c *= uWbExp.rgb * uWbExp.w;
  if (lA.x != 0.0 || lA.y != 0.0 || lA.z != 0.0) {
    c *= vec3(exp2(0.5 * lA.y), exp2(-0.5 * lA.z), exp2(-0.5 * lA.y)) *
         exp2(lA.x);
  }
  // 4. Dehaze.
  float dz = uHaze.x + lC.x;
  if (dz != 0.0) {
    vec3 A = uHaze.yzw;
    float aDark = srgbEncode1(min(A.r, min(A.g, A.b)));
    float ratio = clamp(ax.y / max(aDark, 1e-3), 0.0, 1.0);
    float tr = max(1.0 - 0.95 * abs(dz) * ratio, 0.1);
    if (dz > 0.0) {
      c = max((c - A) / tr + A, vec3(0.0));
    } else {
      c = mix(c, A, 0.4 * -dz * (1.0 - tr));
    }
  }
  // 5. Shadows / highlights from the guided base.
  float hl = uLocal.x + lB.x;
  float sh = uLocal.y + lB.y;
  float cl = uLocal.z + lB.z;
  float tx = uLocal.w + lB.w;
  if (hl != 0.0 || sh != 0.0) {
    float q = ax.w * iSrc + ax.z;
    float base = q * 16.0 - 14.0 + log2(uWbExp.w) + lA.x;
    float bn = srgbEncode1(exp2(base));
    float dEv = 1.5 * (sh * (1.0 - smoothstep(0.0, 0.55, bn)) +
                       hl * smoothstep(0.45, 1.0, bn));
    c *= exp2(dEv);
  }
  // 6. Clarity and texture.
  if (cl != 0.0 || tx != 0.0) {
    float ve = srgbEncode1(dot(c, REC709));
    float mid = clamp(1.0 - (2.0 * ve - 1.0) * (2.0 * ve - 1.0), 0.0, 1.0);
    float dl = cl * 0.8 * (iSrc - ax.x) * 16.0 * mid;
    if (tx != 0.0) {
      vec2 t = 1.0 / uSrc.xy;
      float blur = 4.0 * iSrc
        + lumaAt(suv + vec2(-t.x, -t.y)) + 2.0 * lumaAt(suv + vec2(0.0, -t.y))
        + lumaAt(suv + vec2(t.x, -t.y)) + 2.0 * lumaAt(suv + vec2(-t.x, 0.0))
        + 2.0 * lumaAt(suv + vec2(t.x, 0.0)) + lumaAt(suv + vec2(-t.x, t.y))
        + 2.0 * lumaAt(suv + vec2(0.0, t.y)) + lumaAt(suv + vec2(t.x, t.y));
      dl += tx * 0.6 * (iSrc - blur / 16.0) * 16.0;
    }
    c *= exp2(clamp(dl, -2.0, 2.0));
  }
  // 7. Composite tone LUT, hue preserving (RGBTone on max/min).
  float mx = max(c.r, max(c.g, c.b));
  float mn = min(c.r, min(c.g, c.b));
  c = hueTone(c, mx, mn, tone(mx), tone(mn));
  // 7b. Local contrast / whites / blacks (analytic, hue-preserving).
  vec3 cwb = clamp(lC.yzw, -1.0, 1.0);
  if (cwb.x != 0.0 || cwb.y != 0.0 || cwb.z != 0.0) {
    float x = max(c.r, max(c.g, c.b));
    float n = min(c.r, min(c.g, c.b));
    c = hueTone(c, x, n, srgbDecode1(localTone(srgbEncode1(x), cwb)),
                srgbDecode1(localTone(srgbEncode1(n), cwb)));
  }
  // 8. R/G/B point curves in the encoded domain.
  if (uColor.w > 0.5) {
    vec3 e = srgbEncode(c);
    c = srgbDecode(vec3(lutLookup(1.0, e.r), lutLookup(2.0, e.g), lutLookup(3.0, e.b)));
  }
  // 9-12. OkLab color stages.
  c = oklabToLinSrgb(colorOps(linSrgbToOklab(c), uColor.y + lA.w));
  // 13. Encode, vignette, clipping overlay.
  vec3 e = vignette(srgbEncode(c), uv);
  if (uVignette2.z > 0.5) {
    float m = max(e.r, max(e.g, e.b));
    if (m >= 254.5 / 255.0) {
      e = vec3(1.0, 0.0, 0.0);
    } else if (m <= 0.5 / 255.0) {
      e = vec3(0.0, 0.0, 1.0);
    }
  }
  fragColor = vec4(clamp(e, 0.0, 1.0), 1.0);
}
