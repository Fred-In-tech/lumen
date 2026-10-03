#version 460 core
// Lumen develop uber pass (engine lumen-1). Every per-pixel op in float.
// CPU twin: packages/lumen_core/lib/src/render/develop_kernel.dart and
// color_ops.dart; uniform layout: uniform_layout.dart (94 floats).
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

uniform sampler2D uSource;      // 0: sRGB source (FilterQuality.low)
uniform sampler2D uAuxA;        // 1: RG baseMid, B dark (FilterQuality.none)
uniform sampler2D uAuxB;        // 2: RG meanB, B meanA (FilterQuality.none)
uniform sampler2D uCurveLut;    // 3: 1024x4 packed LUT (FilterQuality.none)

out vec4 fragColor;

// ---- Geometry (geometry_mapping.dart sourceUvFor) --------------------------
vec2 sourceUv(vec2 outUv) {
  vec2 c = mix(uCrop.xy, uCrop.zw, outUv);
  float k = mod(floor(uGeom.y + 0.5), 4.0);
  bool odd = k == 1.0 || k == 3.0;
  vec2 dims = odd ? uSrc.yx : uSrc.xy;
  if (uGeom.x != 0.0) {
    vec2 p = (c - 0.5) * dims;
    float ca = cos(uGeom.x);
    float sa = sin(uGeom.x);
    c = vec2(p.x * ca + p.y * sa, -p.x * sa + p.y * ca) / dims + 0.5;
  }
  if (uGeom.z > 0.5) c.x = 1.0 - c.x;
  if (uGeom.w > 0.5) c.y = 1.0 - c.y;
  if (k == 1.0) return vec2(c.y, 1.0 - c.x);
  if (k == 2.0) return vec2(1.0 - c.x, 1.0 - c.y);
  if (k == 3.0) return vec2(1.0 - c.y, c.x);
  return c;
}

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

vec3 colorOps(vec3 lab) {
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
  float k = 1.0 + uColor.y;
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
  vec2 suv = sourceUv(uv);
  if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
    fragColor = vec4(0.0);
    return;
  }
  // 2. Source -> linear.
  vec3 c = srgbDecode(texture(uSource, suv).rgb);
  float iSrc = normLogLuma(dot(c, REC709));
  vec4 ax = sampleAux(suv);
  // 3. White balance x exposure.
  c *= uWbExp.rgb * uWbExp.w;
  // 4. Dehaze.
  float dz = uHaze.x;
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
  if (uLocal.x != 0.0 || uLocal.y != 0.0) {
    float q = ax.w * iSrc + ax.z;
    float base = q * 16.0 - 14.0 + log2(uWbExp.w);
    float bn = srgbEncode1(exp2(base));
    float dEv = 1.5 * (uLocal.y * (1.0 - smoothstep(0.0, 0.55, bn)) +
                       uLocal.x * smoothstep(0.45, 1.0, bn));
    c *= exp2(dEv);
  }
  // 6. Clarity and texture.
  if (uLocal.z != 0.0 || uLocal.w != 0.0) {
    float ve = srgbEncode1(dot(c, REC709));
    float mid = clamp(1.0 - (2.0 * ve - 1.0) * (2.0 * ve - 1.0), 0.0, 1.0);
    float dl = uLocal.z * 0.8 * (iSrc - ax.x) * 16.0 * mid;
    if (uLocal.w != 0.0) {
      vec2 t = 1.0 / uSrc.xy;
      float blur = 4.0 * iSrc
        + lumaAt(suv + vec2(-t.x, -t.y)) + 2.0 * lumaAt(suv + vec2(0.0, -t.y))
        + lumaAt(suv + vec2(t.x, -t.y)) + 2.0 * lumaAt(suv + vec2(-t.x, 0.0))
        + 2.0 * lumaAt(suv + vec2(t.x, 0.0)) + lumaAt(suv + vec2(-t.x, t.y))
        + 2.0 * lumaAt(suv + vec2(0.0, t.y)) + lumaAt(suv + vec2(t.x, t.y));
      dl += uLocal.w * 0.6 * (iSrc - blur / 16.0) * 16.0;
    }
    c *= exp2(clamp(dl, -2.0, 2.0));
  }
  // 7. Composite tone LUT, hue preserving (RGBTone on max/min).
  float mx = max(c.r, max(c.g, c.b));
  float mn = min(c.r, min(c.g, c.b));
  float tmx = tone(mx);
  float tmn = tone(mn);
  if (mx - mn < 1e-6) {
    c = vec3(tmx);
  } else {
    c = tmn + (c - mn) * ((tmx - tmn) / (mx - mn));
  }
  // 8. R/G/B point curves in the encoded domain.
  if (uColor.w > 0.5) {
    vec3 e = srgbEncode(c);
    c = srgbDecode(vec3(lutLookup(1.0, e.r), lutLookup(2.0, e.g), lutLookup(3.0, e.b)));
  }
  // 9-12. OkLab color stages.
  c = oklabToLinSrgb(colorOps(linSrgbToOklab(c)));
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
