#version 460 core
// Lumen portrait retouch pass R (research 07 §3.1-3.9), between denoise N
// and develop D, in SOURCE space. CPU twin: lumen_core
// retouch/retouch_kernel.dart (steps 1-12 map 1:1); constants are the
// literals of retouch/kernel_constants.dart. Uniforms: render/retouch_pass.dart
// (206 floats). Untouched pixels output the source texel unchanged.
#include <flutter/runtime_effect.glsl>
#include "lib/common.glsl"

precision highp float;

uniform vec2 uSize;            // 0-1   pass size (px)
uniform vec4 uTile;            // 2-5   pass offset xy in the source, full wh
uniform vec4 uMapInfo;         // 6-9   map grid W, H, face count, 0
uniform vec4 uFaceInfo0;      // 10-13 teeth cap L, has maps, IOD, active
uniform vec4 uFaceInfo1;      // 14-17 teeth cap L, has maps, IOD, active
uniform vec4 uFaceInfo2;      // 18-21 teeth cap L, has maps, IOD, active
uniform vec4 uFaceInfo3;      // 22-25 teeth cap L, has maps, IOD, active
uniform vec4 uFaceInfo4;      // 26-29 teeth cap L, has maps, IOD, active
uniform vec4 uFaceInfo5;      // 30-33 teeth cap L, has maps, IOD, active
uniform vec4 uFaceInfo6;      // 34-37 teeth cap L, has maps, IOD, active
uniform vec4 uFaceInfo7;      // 38-41 teeth cap L, has maps, IOD, active
uniform vec4 uRetouch;           // 42-45 face count, any active, spot ramp, 0
uniform vec4 uFace0;          // 46-49 face 0: smooth, texture gain, even, amp threshold
uniform vec4 uFace1;          // 50-53 face 0: dark circles, bags, lid protect, shine
uniform vec4 uFace2;          // 54-57 face 0: eye whites, iris, red vein, 0
uniform vec4 uFace3;          // 58-61 face 0: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace4;          // 62-65 face 0: mole, wrinkle, lips, blush
uniform vec4 uFace5;          // 66-69 face 1: smooth, texture gain, even, amp threshold
uniform vec4 uFace6;          // 70-73 face 1: dark circles, bags, lid protect, shine
uniform vec4 uFace7;          // 74-77 face 1: eye whites, iris, red vein, 0
uniform vec4 uFace8;          // 78-81 face 1: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace9;          // 82-85 face 1: mole, wrinkle, lips, blush
uniform vec4 uFace10;         // 86-89 face 2: smooth, texture gain, even, amp threshold
uniform vec4 uFace11;         // 90-93 face 2: dark circles, bags, lid protect, shine
uniform vec4 uFace12;         // 94-97 face 2: eye whites, iris, red vein, 0
uniform vec4 uFace13;         // 98-101 face 2: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace14;         // 102-105 face 2: mole, wrinkle, lips, blush
uniform vec4 uFace15;         // 106-109 face 3: smooth, texture gain, even, amp threshold
uniform vec4 uFace16;         // 110-113 face 3: dark circles, bags, lid protect, shine
uniform vec4 uFace17;         // 114-117 face 3: eye whites, iris, red vein, 0
uniform vec4 uFace18;         // 118-121 face 3: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace19;         // 122-125 face 3: mole, wrinkle, lips, blush
uniform vec4 uFace20;         // 126-129 face 4: smooth, texture gain, even, amp threshold
uniform vec4 uFace21;         // 130-133 face 4: dark circles, bags, lid protect, shine
uniform vec4 uFace22;         // 134-137 face 4: eye whites, iris, red vein, 0
uniform vec4 uFace23;         // 138-141 face 4: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace24;         // 142-145 face 4: mole, wrinkle, lips, blush
uniform vec4 uFace25;         // 146-149 face 5: smooth, texture gain, even, amp threshold
uniform vec4 uFace26;         // 150-153 face 5: dark circles, bags, lid protect, shine
uniform vec4 uFace27;         // 154-157 face 5: eye whites, iris, red vein, 0
uniform vec4 uFace28;         // 158-161 face 5: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace29;         // 162-165 face 5: mole, wrinkle, lips, blush
uniform vec4 uFace30;         // 166-169 face 6: smooth, texture gain, even, amp threshold
uniform vec4 uFace31;         // 170-173 face 6: dark circles, bags, lid protect, shine
uniform vec4 uFace32;         // 174-177 face 6: eye whites, iris, red vein, 0
uniform vec4 uFace33;         // 178-181 face 6: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace34;         // 182-185 face 6: mole, wrinkle, lips, blush
uniform vec4 uFace35;         // 186-189 face 7: smooth, texture gain, even, amp threshold
uniform vec4 uFace36;         // 190-193 face 7: dark circles, bags, lid protect, shine
uniform vec4 uFace37;         // 194-197 face 7: eye whites, iris, red vein, 0
uniform vec4 uFace38;         // 198-201 face 7: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace39;         // 202-205 face 7: mole, wrinkle, lips, blush

uniform sampler2D uSource;     // 0: sRGB source (FilterQuality.none)
uniform sampler2D uB1;         // 1: W x H bands (sRGB), FilterQuality.none
uniform sampler2D uB2;         // 2
uniform sampler2D uB3;         // 3
uniform sampler2D uBh;         // 4: 2W x H heal deltas (low | high)
uniform sampler2D uRegionA;    // 5: 2W x H skin, under-eye, lash | mouth, sclera, iris
uniform sampler2D uRegionB;    // 6: 2W x H lips, blush, wrinkle | face id, spot code

out vec4 fragColor;

// Manual bilinear over texel centres (RetouchMaps._bilinear); needs the
// locals lo, hi (clamped texel coords) and f in scope. OFF = tile * W.
#define TAP(TEX, X, Y, SZ) texture(TEX, (vec2(X, Y) + 0.5) / (SZ)).rgb
#define BILERP(TEX, OFF, SZ) mix( \
    mix(TAP(TEX, lo.x + (OFF), lo.y, SZ), TAP(TEX, hi.x + (OFF), lo.y, SZ), f.x), \
    mix(TAP(TEX, lo.x + (OFF), hi.y, SZ), TAP(TEX, hi.x + (OFF), hi.y, SZ), f.x), \
    f.y)

// Heal weight of a spot code (blemish_types.dart spotSelection).
float spotSel(float code, float acne, float freckle, float mole) {
  if (code < 0.5) return 0.0;
  float c = code - 1.0;
  float kind = floor(c / 64.0);
  float q = c - kind * 64.0;
  if (q > 62.5) return 1.0;
  float slider = kind < 0.5 ? acne : (kind < 1.5 ? freckle : mole);
  if (slider <= 0.0) return 0.0;
  return clamp((slider - q / 62.0) / uRetouch.z, 0.0, 1.0);
}

vec3 bandLab(vec3 srgb) {
  return linSrgbToOklab(srgbDecode(srgb));
}

void main() {
  vec2 uv = (FlutterFragCoord().xy + uTile.xy) / uTile.zw;
  vec3 src = texture(uSource, uv).rgb;
  fragColor = vec4(src, 1.0);
  if (uRetouch.y < 0.5 || uSize.x < 0.5) return;
  vec2 W = uMapInfo.xy;
  vec2 A = vec2(2.0 * W.x, W.y);
  // 1. Face row: nearest face id (0 = no face) and spot code.
  vec2 nt = clamp(floor(uv * W), vec2(0.0), W - 1.0);
  vec2 ids = texture(uRegionB, (vec2(nt.x + W.x, nt.y) + 0.5) / A).rg;
  float fid = floor(ids.r * 255.0 + 0.5);
  if (fid < 0.5) return;
  vec4 r0;
  vec4 r1;
  vec4 r2;
  vec4 r3;
  vec4 r4;
  vec4 info;
  if (fid < 1.5) {
    r0 = uFace0; r1 = uFace1; r2 = uFace2;
    r3 = uFace3; r4 = uFace4; info = uFaceInfo0;
  } else if (fid < 2.5) {
    r0 = uFace5; r1 = uFace6; r2 = uFace7;
    r3 = uFace8; r4 = uFace9; info = uFaceInfo1;
  } else if (fid < 3.5) {
    r0 = uFace10; r1 = uFace11; r2 = uFace12;
    r3 = uFace13; r4 = uFace14; info = uFaceInfo2;
  } else if (fid < 4.5) {
    r0 = uFace15; r1 = uFace16; r2 = uFace17;
    r3 = uFace18; r4 = uFace19; info = uFaceInfo3;
  } else if (fid < 5.5) {
    r0 = uFace20; r1 = uFace21; r2 = uFace22;
    r3 = uFace23; r4 = uFace24; info = uFaceInfo4;
  } else if (fid < 6.5) {
    r0 = uFace25; r1 = uFace26; r2 = uFace27;
    r3 = uFace28; r4 = uFace29; info = uFaceInfo5;
  } else if (fid < 7.5) {
    r0 = uFace30; r1 = uFace31; r2 = uFace32;
    r3 = uFace33; r4 = uFace34; info = uFaceInfo6;
  } else if (fid < 8.5) {
    r0 = uFace35; r1 = uFace36; r2 = uFace37;
    r3 = uFace38; r4 = uFace39; info = uFaceInfo7;
  } else {
    return;
  }
  if (info.w < 0.5) return;
  // 2. Regions (bilinear, 0..1).
  vec2 lo;
  vec2 hi;
  vec2 f;
  maskTaps(uv, W, lo, hi, f);
  vec3 ra0 = BILERP(uRegionA, 0.0, A);
  vec3 ra1 = BILERP(uRegionA, W.x, A);
  vec3 rb0 = BILERP(uRegionB, 0.0, A);
  float skin = ra0.r;
  float lash = ra0.b;
  float mouth = ra1.r;
  float sel = spotSel(floor(ids.g * 255.0 + 0.5), r3.z, r3.w, r4.x);
  // 3. Effect weights; untouched pixels keep the source exactly.
  float s = r0.x * skin;
  float ev = r0.z * skin;
  float tex = (r0.y - 1.0) * skin;
  float ue = ra0.g * (1.0 - r1.z * lash);
  float dc = r1.x * ue;
  float bg = r1.y * ue;
  float sh = r1.w * skin;
  float wr = r4.y * rb0.b;
  float teeth = mouth * (r3.x + r3.y);
  float sw = r2.x * ra1.g;
  float rv = r2.z * ra1.g;
  float iw = r2.y * ra1.b;
  if (s == 0.0 && ev == 0.0 && tex == 0.0 && dc == 0.0 && bg == 0.0 &&
      sh == 0.0 && wr == 0.0 && teeth == 0.0 && sw == 0.0 && rv == 0.0 &&
      iw == 0.0 && sel == 0.0) {
    return;
  }
  // 4. OkLab of the source and the bands; healed low band (§3.3).
  vec3 li = bandLab(src);
  vec3 l1 = bandLab(BILERP(uB1, 0.0, W));
  vec3 l2 = bandLab(BILERP(uB2, 0.0, W));
  vec3 l3 = bandLab(BILERP(uB3, 0.0, W));
  vec3 range = vec3(0.25, 0.1, 0.1);
  vec3 dLow = (BILERP(uBh, 0.0, A) * 255.0 - 128.0) / 127.0 * range;
  vec3 dHigh = (BILERP(uBh, W.x, A) * 255.0 - 128.0) / 127.0 * range;
  vec3 fine = li - l1 + sel * dHigh;
  l1 += sel * dLow;
  // 5. Three bands, amplitude-selective mid suppression (§3.1, §3.4).
  vec3 mid = l1 - l2;
  float thr = r0.w;
  float keep = smoothstep(thr, 2.5 * thr, abs(mid.x));
  float midK = 1.0 - clamp(s * (1.0 - keep) + 0.85 * wr, 0.0, 1.0);
  float fineK = (1.0 + tex) * (1.0 - 0.3 * wr);
  vec3 o;
  o.x = l2.x + mid.x * midK + fine.x * fineK;
  // 6. Tone evening: base chroma toward the skin reference (§3.2).
  o.y = l2.y + ev * (l3.y - l2.y) + mid.y * midK + fine.y * fineK;
  o.z = l2.z + ev * (l3.z - l2.z) + mid.z * midK + fine.z * fineK;
  // 7. Under-eye: dark circles and bags, lid-protected (§3.5).
  if (dc > 0.0 || bg > 0.0) {
    o.x += dc * 0.8 * max(0.0, l3.x - l2.x);
    o.y += dc * 0.6 * (l3.y - l2.y);
    o.z += dc * 0.6 * (l3.z - l2.z);
    float flatten = bg * 0.7 * midK * (1.0 - keep);
    o.x += bg * 0.4 * (l3.x - l2.x) - flatten * mid.x;
    o.y -= flatten * mid.y;
    o.z -= flatten * mid.z;
  }
  // 8. Shine: bright, desaturated relative to the skin reference (§3.8).
  if (sh > 0.0) {
    float rel = l1.x - l3.x;
    float c1 = length(l1.yz);
    float c3 = max(length(l3.yz), 1e-3);
    float w = sh * smoothstep(0.03, 0.10, rel) *
              (1.0 - smoothstep(0.6, 0.95, c1 / c3));
    o.x -= w * 0.7 * rel;
    o.y += (l3.y - o.y) * w * 0.5;
    o.z += (l3.z - o.z) * w * 0.5;
  }
  // 9. Teeth: mouth, bright, not red; never above the sclera (§3.6).
  if (teeth > 0.0) {
    float tm = mouth * smoothstep(0.55, 0.72, li.x) *
               (1.0 - smoothstep(0.035, 0.08, li.y));
    if (tm > 0.0) {
      float td = r3.y * tm;
      float tb = r3.x * tm;
      o.z *= 1.0 - 0.85 * td;
      o.y *= 1.0 - 0.40 * td;
      o.x += 0.10 * tb * (1.0 - o.x);
      o.x = min(o.x, max(li.x, info.x));
    }
  }
  // 10. Eye whites: less red/yellow, slight lift (§3.7).
  if (sw > 0.0) {
    float w = sw * smoothstep(0.45, 0.62, li.x);
    o.y *= 1.0 - 0.7 * w;
    o.z *= 1.0 - 0.4 * w;
    o.x += 0.05 * w * (1.0 - o.x);
  }
  // 11. Red veins: fine-scale a* excess over the base.
  if (rv > 0.0) {
    float w = rv * smoothstep(0.35, 0.5, li.x);
    float vein = max(0.0, li.y - l2.y);
    o.y -= 0.9 * w * vein;
    o.x += 0.9 * w * max(0.0, l2.x - li.x) * smoothstep(0.004, 0.02, vein);
  }
  // 12. Iris: local contrast, chroma, small lift; keeps catchlights.
  if (iw > 0.0) {
    float w = iw * (1.0 - smoothstep(0.85, 0.95, li.x));
    o.x += 0.6 * w * (li.x - l2.x) + 0.03 * w;
    o.y *= 1.0 + 0.35 * w;
    o.z *= 1.0 + 0.35 * w;
  }
  fragColor = vec4(srgbEncode(oklabToLinSrgb(o)), 1.0);
}
