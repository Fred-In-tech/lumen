#version 460 core
// Lumen backdrop composite pass B (source space, linear light): new
// background (blur / colour / gradient / image) behind the subject matte,
// spill removal at the edge, brightness match. CPU twin: lumen_core
// backdrop/backdrop_kernel.dart; uniforms: backdrop_uniforms.dart (46).
#include <flutter/runtime_effect.glsl>
#include "lib/common.glsl"

precision highp float;

uniform vec2 uSize;     // 0-1   pass size (px)
uniform vec4 uVec0[11];
#define uTile uVec0[0]  // 2-5   pass offset in the source, full wh
#define uMatte uVec0[1]  // 6-9   matte wh, mode (1 blur 2 colour 3 gradient 4 image), letterbox
#define uFill uVec0[2]  // 10-13 fill wh, plate A wh
#define uPlateB uVec0[3]  // 14-17 plate B wh, 0, 0
#define uColorA uVec0[4]  // 18-21 colour (sRGB 0..1)
#define uColorB uVec0[5]  // 22-25 colour 2
#define uGrad uVec0[6]  // 26-29 direction xy, frame aspect, extent
#define uFit uVec0[7]  // 30-33 plate uv scale xy
#define uSpill uVec0[8]  // 34-37 amount, old-backdrop chroma direction
#define uSpill2 uVec0[9]  // 38-41 new-background chroma direction
#define uMatch uVec0[10]  // 42-45 amount, gain

uniform sampler2D uSrcTex;     // 0: source (FilterQuality.none)
uniform sampler2D uMatteTex;   // 1: R coverage, G edge band, B depth
uniform sampler2D uFillTex;    // 2: old background, subject filled
uniform sampler2D uPlateATex;  // 3: near blur or backdrop image
uniform sampler2D uPlateBTex;  // 4: far blur

out vec4 fragColor;

// Manual bilinear over texel centres (backdrop_filters.dart sampleBytes).
#define BILINEAR(NAME, TEX) \
  vec3 NAME(vec2 uv, vec2 sz) { \
    vec2 lo; \
    vec2 hi; \
    vec2 f; \
    maskTaps(uv, sz, lo, hi, f); \
    vec3 a = texture(TEX, (lo + 0.5) / sz).rgb; \
    vec3 b = texture(TEX, (vec2(hi.x, lo.y) + 0.5) / sz).rgb; \
    vec3 c = texture(TEX, (vec2(lo.x, hi.y) + 0.5) / sz).rgb; \
    vec3 d = texture(TEX, (hi + 0.5) / sz).rgb; \
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y); \
  }

BILINEAR(sampleMatte, uMatteTex)
BILINEAR(sampleFill, uFillTex)
BILINEAR(samplePlateA, uPlateATex)
BILINEAR(samplePlateB, uPlateBTex)

void main() {
  vec2 uv = (FlutterFragCoord().xy + uTile.xy) / uTile.zw;
  vec3 src = texture(uSrcTex, uv).rgb;
  fragColor = vec4(src, 1.0);
  if (uMatte.z < 0.5 || uSize.x < 0.5) return;
  // 1-2. Matte; the subject interior keeps the source bit-exact.
  vec3 m = sampleMatte(uv, uMatte.xy);
  float al = m.r;
  float e = m.g;
  if (al >= 1.0 && e <= 0.0 && uMatch.x == 0.0) return;
  // 3. New background (linear).
  float mode = floor(uMatte.z + 0.5);
  vec3 bg;
  if (mode == 1.0) {
    vec3 n = srgbDecode(samplePlateA(uv, uFill.zw));
    vec3 fa = srgbDecode(samplePlateB(uv, uPlateB.xy));
    bg = n + (fa - n) * m.b;
  } else if (mode == 3.0) {
    vec2 p = vec2((uv.x - 0.5) * uGrad.z, uv.y - 0.5);
    float s = clamp(dot(p, uGrad.xy) / uGrad.w + 0.5, 0.0, 1.0);
    bg = srgbDecode(uColorA.rgb + (uColorB.rgb - uColorA.rgb) * s);
  } else if (mode == 4.0) {
    vec2 pu = (uv - 0.5) * uFit.xy + 0.5;
    if (uMatte.w > 0.5 &&
        (pu.x < 0.0 || pu.x > 1.0 || pu.y < 0.0 || pu.y > 1.0)) {
      bg = srgbDecode(uColorA.rgb);
    } else {
      bg = srgbDecode(samplePlateA(pu, uFill.zw));
    }
  } else {
    bg = srgbDecode(uColorA.rgb);
  }
  if (al <= 0.0) {
    fragColor = vec4(srgbEncode(bg), 1.0);  // pure background
    return;
  }
  // 4. Remove spill: un-mix the old backdrop, then its chroma in the band
  // (the un-mix weight is 0 below a = 0.02).
  vec3 F = srgbDecode(src);
  float spill = uSpill.x;
  if (spill > 0.0 && al < 1.0 && al > 0.02) {
    vec3 old = srgbDecode(sampleFill(uv, uFill.xy));
    float q = 1.0 - al;
    float inv = 1.0 / max(al, 0.15);
    float w = spill * smoothstep(0.02, 0.25, al);
    F += (clamp((F - q * old) * inv, 0.0, 1.0) - F) * w;
  }
  float we = spill * e;
  if (we > 0.0) {
    float y = dot(F, REC709);
    float k = max(0.0, dot(F - y, uSpill.yzw));
    F = max(F - we * k * uSpill.yzw + we * k * 0.5 * uSpill2.xyz, vec3(0.0));
  }
  // 5. Brightness match and the composite.
  float gain = 1.0 + uMatch.x * (uMatch.y - 1.0);
  fragColor = vec4(srgbEncode(F * gain * al + bg * (1.0 - al)), 1.0);
}
