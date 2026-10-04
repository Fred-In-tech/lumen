#version 460 core
// Lumen portrait retouch pass R (research 07 §3.1-3.9), between denoise N
// and develop D, in SOURCE space. CPU twin: lumen_core
// retouch/retouch_kernel.dart (face steps 1-15) and
// retouch/backdrop_kernel.dart (step 16) map 1:1; constants are the
// literals of retouch/kernel_constants.dart, wrinkle codes are
// retouch/wrinkle_zones.dart. Uniforms: render/retouch_pass.dart
// (318 floats). Untouched pixels output the source texel unchanged.
#include <flutter/runtime_effect.glsl>
#include "lib/common.glsl"

precision highp float;

uniform vec2 uSize;            // 0-1   pass size (px)
uniform vec4 uTile;            // 2-5   pass offset xy in the source, full wh
uniform vec4 uMapInfo;         // 6-9   map grid W, H, face count, 0
uniform vec4 uFaceInfo0;         // 10-13 face 0: teeth cap L, active, IOD, lip gloss L
uniform vec4 uFaceInfo1;         // 14-17 face 0: lip chroma gain, lip L shift, blush a, blush b
uniform vec4 uFaceInfo2;         // 18-21 face 0: right iris x, y, left iris x, y (map px)
uniform vec4 uFaceInfo3;         // 22-25 face 1: teeth cap L, active, IOD, lip gloss L
uniform vec4 uFaceInfo4;         // 26-29 face 1: lip chroma gain, lip L shift, blush a, blush b
uniform vec4 uFaceInfo5;         // 30-33 face 1: right iris x, y, left iris x, y (map px)
uniform vec4 uFaceInfo6;         // 34-37 face 2: teeth cap L, active, IOD, lip gloss L
uniform vec4 uFaceInfo7;         // 38-41 face 2: lip chroma gain, lip L shift, blush a, blush b
uniform vec4 uFaceInfo8;         // 42-45 face 2: right iris x, y, left iris x, y (map px)
uniform vec4 uFaceInfo9;         // 46-49 face 3: teeth cap L, active, IOD, lip gloss L
uniform vec4 uFaceInfo10;        // 50-53 face 3: lip chroma gain, lip L shift, blush a, blush b
uniform vec4 uFaceInfo11;        // 54-57 face 3: right iris x, y, left iris x, y (map px)
uniform vec4 uFaceInfo12;        // 58-61 face 4: teeth cap L, active, IOD, lip gloss L
uniform vec4 uFaceInfo13;        // 62-65 face 4: lip chroma gain, lip L shift, blush a, blush b
uniform vec4 uFaceInfo14;        // 66-69 face 4: right iris x, y, left iris x, y (map px)
uniform vec4 uFaceInfo15;        // 70-73 face 5: teeth cap L, active, IOD, lip gloss L
uniform vec4 uFaceInfo16;        // 74-77 face 5: lip chroma gain, lip L shift, blush a, blush b
uniform vec4 uFaceInfo17;        // 78-81 face 5: right iris x, y, left iris x, y (map px)
uniform vec4 uFaceInfo18;        // 82-85 face 6: teeth cap L, active, IOD, lip gloss L
uniform vec4 uFaceInfo19;        // 86-89 face 6: lip chroma gain, lip L shift, blush a, blush b
uniform vec4 uFaceInfo20;        // 90-93 face 6: right iris x, y, left iris x, y (map px)
uniform vec4 uFaceInfo21;        // 94-97 face 7: teeth cap L, active, IOD, lip gloss L
uniform vec4 uFaceInfo22;        // 98-101 face 7: lip chroma gain, lip L shift, blush a, blush b
uniform vec4 uFaceInfo23;        // 102-105 face 7: right iris x, y, left iris x, y (map px)
uniform vec4 uBackdropInfo0;    // 106-109 backdrop W, H, active, tau L
uniform vec4 uBackdropInfo1;    // 110-113 median backdrop L, a, b, tau C
uniform vec4 uRetouch;          // 114-117 face count, any active, spot ramp, 0
uniform vec4 uFace0;             // 118-121 face 0: smooth, texture gain, even, red-eye
uniform vec4 uFace1;             // 122-125 face 0: dark circles, bags, lid protect, shine
uniform vec4 uFace2;             // 126-129 face 0: eye whites, iris, red vein, glare
uniform vec4 uFace3;             // 130-133 face 0: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace4;             // 134-137 face 0: mole, lips, blush, wrinkle crow's feet
uniform vec4 uFace5;             // 138-141 face 0: wrinkle forehead, frown, smile, marionette
uniform vec4 uFace6;             // 142-145 face 1: smooth, texture gain, even, red-eye
uniform vec4 uFace7;             // 146-149 face 1: dark circles, bags, lid protect, shine
uniform vec4 uFace8;             // 150-153 face 1: eye whites, iris, red vein, glare
uniform vec4 uFace9;             // 154-157 face 1: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace10;            // 158-161 face 1: mole, lips, blush, wrinkle crow's feet
uniform vec4 uFace11;            // 162-165 face 1: wrinkle forehead, frown, smile, marionette
uniform vec4 uFace12;            // 166-169 face 2: smooth, texture gain, even, red-eye
uniform vec4 uFace13;            // 170-173 face 2: dark circles, bags, lid protect, shine
uniform vec4 uFace14;            // 174-177 face 2: eye whites, iris, red vein, glare
uniform vec4 uFace15;            // 178-181 face 2: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace16;            // 182-185 face 2: mole, lips, blush, wrinkle crow's feet
uniform vec4 uFace17;            // 186-189 face 2: wrinkle forehead, frown, smile, marionette
uniform vec4 uFace18;            // 190-193 face 3: smooth, texture gain, even, red-eye
uniform vec4 uFace19;            // 194-197 face 3: dark circles, bags, lid protect, shine
uniform vec4 uFace20;            // 198-201 face 3: eye whites, iris, red vein, glare
uniform vec4 uFace21;            // 202-205 face 3: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace22;            // 206-209 face 3: mole, lips, blush, wrinkle crow's feet
uniform vec4 uFace23;            // 210-213 face 3: wrinkle forehead, frown, smile, marionette
uniform vec4 uFace24;            // 214-217 face 4: smooth, texture gain, even, red-eye
uniform vec4 uFace25;            // 218-221 face 4: dark circles, bags, lid protect, shine
uniform vec4 uFace26;            // 222-225 face 4: eye whites, iris, red vein, glare
uniform vec4 uFace27;            // 226-229 face 4: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace28;            // 230-233 face 4: mole, lips, blush, wrinkle crow's feet
uniform vec4 uFace29;            // 234-237 face 4: wrinkle forehead, frown, smile, marionette
uniform vec4 uFace30;            // 238-241 face 5: smooth, texture gain, even, red-eye
uniform vec4 uFace31;            // 242-245 face 5: dark circles, bags, lid protect, shine
uniform vec4 uFace32;            // 246-249 face 5: eye whites, iris, red vein, glare
uniform vec4 uFace33;            // 250-253 face 5: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace34;            // 254-257 face 5: mole, lips, blush, wrinkle crow's feet
uniform vec4 uFace35;            // 258-261 face 5: wrinkle forehead, frown, smile, marionette
uniform vec4 uFace36;            // 262-265 face 6: smooth, texture gain, even, red-eye
uniform vec4 uFace37;            // 266-269 face 6: dark circles, bags, lid protect, shine
uniform vec4 uFace38;            // 270-273 face 6: eye whites, iris, red vein, glare
uniform vec4 uFace39;            // 274-277 face 6: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace40;            // 278-281 face 6: mole, lips, blush, wrinkle crow's feet
uniform vec4 uFace41;            // 282-285 face 6: wrinkle forehead, frown, smile, marionette
uniform vec4 uFace42;            // 286-289 face 7: smooth, texture gain, even, red-eye
uniform vec4 uFace43;            // 290-293 face 7: dark circles, bags, lid protect, shine
uniform vec4 uFace44;            // 294-297 face 7: eye whites, iris, red vein, glare
uniform vec4 uFace45;            // 298-301 face 7: teeth bright, teeth desat, acne, freckle
uniform vec4 uFace46;            // 302-305 face 7: mole, lips, blush, wrinkle crow's feet
uniform vec4 uFace47;            // 306-309 face 7: wrinkle forehead, frown, smile, marionette
uniform vec4 uBackdropParams;   // 310-313 clean, unify, luminance, strays
uniform vec4 uClothesParams;    // 314-317 clothes wrinkles, lint, active, 0

uniform sampler2D uSource;     // 0: sRGB source (FilterQuality.none)
uniform sampler2D uB1;         // 1: W x H bands (sRGB, dithered), FilterQuality.none
uniform sampler2D uB2;         // 2
uniform sampler2D uB3;         // 3
uniform sampler2D uBh;         // 4: 2W x H heal deltas (low | high)
uniform sampler2D uRegionA;    // 5: 2W x H skin, under-eye, lash | mouth, sclera, iris
uniform sampler2D uRegionB;    // 6: 2W x H lips, blush, wrinkle dL | face id, spot code, wrinkle zone
uniform sampler2D uBackdropMap; // 7: 3W' x 2H' image atlas E | G | fold / U | weights | lint

out vec4 fragColor;

// Manual bilinear over texel centres (RetouchMaps._bilinear); needs the
// locals lo, hi (clamped texel coords) and f in scope. OFF = tile * W.
#define TAP(TEX, X, Y, SZ) texture(TEX, (vec2(X, Y) + 0.5) / (SZ)).rgb
#define BILERP(TEX, OFF, SZ) mix( \
    mix(TAP(TEX, lo.x + (OFF), lo.y, SZ), TAP(TEX, hi.x + (OFF), lo.y, SZ), f.x), \
    mix(TAP(TEX, lo.x + (OFF), hi.y, SZ), TAP(TEX, hi.x + (OFF), hi.y, SZ), f.x), \
    f.y)

// Heal weight of a spot code (blemish_types.dart spotSelection). Kind 3
// holds whole-patch heals: 193 = clipped shine core (shine fill weight),
// 194 = glasses glare (glare slider).
float spotSel(float code, float acne, float freckle, float mole,
              float shineFill, float glare) {
  if (code < 0.5) return 0.0;
  float c = code - 1.0;
  float kind = floor(c / 64.0);
  float q = c - kind * 64.0;
  if (kind > 2.5) {
    return code < 193.5 ? shineFill : (code < 194.5 ? glare : 0.0);
  }
  if (q > 62.5) return 1.0;
  float slider = kind < 0.5 ? acne : (kind < 1.5 ? freckle : mole);
  if (slider <= 0.0) return 0.0;
  return clamp((slider - q / 62.0) / uRetouch.z, 0.0, 1.0);
}

// Wrinkle slider weight of a zone code (wrinkle_zones.dart
// wrinkleZoneWeight): w = (forehead, frown, smile, marionette).
float zoneWeight(float code, vec4 w, float crowsFeet) {
  if (code < 0.5) return 0.0;
  if (code < 64.5) return mix(w.x, w.y, (code - 1.0) / 63.0);
  if (code < 128.5) return mix(w.z, w.w, (code - 65.0) / 63.0);
  return code < 129.5 ? crowsFeet : 0.0;
}

vec3 bandLab(vec3 srgb) {
  return linSrgbToOklab(srgbDecode(srgb));
}

// Face steps 1-15 (retouch_kernel.dart _face): writes o, false when no
// face effect touches the pixel.
bool faceRetouch(vec2 uv, vec3 li, inout vec3 o) {
  vec2 W = uMapInfo.xy;
  vec2 A = vec2(2.0 * W.x, W.y);
  // 1. Face row: nearest face id (0 = no face), spot code, wrinkle zone.
  vec2 nt = clamp(floor(uv * W), vec2(0.0), W - 1.0);
  vec3 ids = texture(uRegionB, (vec2(nt.x + W.x, nt.y) + 0.5) / A).rgb;
  float fid = floor(ids.r * 255.0 + 0.5);
  if (fid < 0.5) return false;
  vec4 r0;
  vec4 r1;
  vec4 r2;
  vec4 r3;
  vec4 r4;
  vec4 r5;
  vec4 info0;
  vec4 info1;
  vec4 info2;
  if (fid < 1.5) {
    r0 = uFace0; r1 = uFace1; r2 = uFace2;
    r3 = uFace3; r4 = uFace4; r5 = uFace5;
    info0 = uFaceInfo0; info1 = uFaceInfo1; info2 = uFaceInfo2;
  } else if (fid < 2.5) {
    r0 = uFace6; r1 = uFace7; r2 = uFace8;
    r3 = uFace9; r4 = uFace10; r5 = uFace11;
    info0 = uFaceInfo3; info1 = uFaceInfo4; info2 = uFaceInfo5;
  } else if (fid < 3.5) {
    r0 = uFace12; r1 = uFace13; r2 = uFace14;
    r3 = uFace15; r4 = uFace16; r5 = uFace17;
    info0 = uFaceInfo6; info1 = uFaceInfo7; info2 = uFaceInfo8;
  } else if (fid < 4.5) {
    r0 = uFace18; r1 = uFace19; r2 = uFace20;
    r3 = uFace21; r4 = uFace22; r5 = uFace23;
    info0 = uFaceInfo9; info1 = uFaceInfo10; info2 = uFaceInfo11;
  } else if (fid < 5.5) {
    r0 = uFace24; r1 = uFace25; r2 = uFace26;
    r3 = uFace27; r4 = uFace28; r5 = uFace29;
    info0 = uFaceInfo12; info1 = uFaceInfo13; info2 = uFaceInfo14;
  } else if (fid < 6.5) {
    r0 = uFace30; r1 = uFace31; r2 = uFace32;
    r3 = uFace33; r4 = uFace34; r5 = uFace35;
    info0 = uFaceInfo15; info1 = uFaceInfo16; info2 = uFaceInfo17;
  } else if (fid < 7.5) {
    r0 = uFace36; r1 = uFace37; r2 = uFace38;
    r3 = uFace39; r4 = uFace40; r5 = uFace41;
    info0 = uFaceInfo18; info1 = uFaceInfo19; info2 = uFaceInfo20;
  } else if (fid < 8.5) {
    r0 = uFace42; r1 = uFace43; r2 = uFace44;
    r3 = uFace45; r4 = uFace46; r5 = uFace47;
    info0 = uFaceInfo21; info1 = uFaceInfo22; info2 = uFaceInfo23;
  } else {
    return false;
  }
  if (info0.y < 0.5) return false;
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
  float dW = rb0.b * 0.2;  // kWrinkleRangeL
  float shineFill = clamp((r1.w - 0.5) / 0.4, 0.0, 1.0);
  float sel = spotSel(floor(ids.g * 255.0 + 0.5), r3.z, r3.w, r4.x,
                      shineFill, r2.w);
  // 3. Effect weights; untouched pixels keep the source exactly.
  float s = r0.x * skin;
  float ev = r0.z * skin;
  float tex = (r0.y - 1.0) * skin;
  float ue = ra0.g * (1.0 - r1.z * lash);
  float dc = r1.x * ue;
  float bg = r1.y * ue;
  float sh = r1.w * skin;
  float teeth = mouth * (r3.x + r3.y);
  float sw = r2.x * ra1.g;
  float rv = r2.z * ra1.g;
  float iw = r2.y * ra1.b;
  float lw = r4.y * rb0.r;
  float bw = r4.z * rb0.g;
  // Wrinkle removal: zone slider plus a share of Smooth, capped (§3.4).
  float wEff = 0.0;
  if (dW > 0.0) {
    float zw = zoneWeight(floor(ids.b * 255.0 + 0.5), r5, r4.w);
    wEff = 0.85 * clamp(zw + 0.5 * s, 0.0, 1.0);  // kWrinkleMax, kWrinkleSmooth
  }
  // Red-eye: analytic discs around the iris centres (map px).
  float re = 0.0;
  if (r0.w > 0.0) {
    vec2 pm = uv * W;
    float rad = 0.11 * info0.z;  // kRedEyeRadiusIod
    float d = min(length(pm - info2.xy), length(pm - info2.zw));
    re = r0.w * (1.0 - smoothstep(0.8 * rad, rad, d));
  }
  if (s == 0.0 && ev == 0.0 && tex == 0.0 && dc == 0.0 && bg == 0.0 &&
      sh == 0.0 && wEff == 0.0 && teeth == 0.0 && sw == 0.0 && rv == 0.0 &&
      iw == 0.0 && sel == 0.0 && lw == 0.0 && bw == 0.0 && re == 0.0) {
    return false;
  }
  // 4. OkLab of the source and the bands; healed low band (§3.3).
  vec3 l1 = bandLab(BILERP(uB1, 0.0, W));
  vec3 l2 = bandLab(BILERP(uB2, 0.0, W));
  vec3 l3 = bandLab(BILERP(uB3, 0.0, W));
  vec3 range = vec3(0.25, 0.1, 0.1);
  vec3 dLow = (BILERP(uBh, 0.0, A) * 255.0 - 128.0) / 127.0 * range;
  vec3 dHigh = (BILERP(uBh, W.x, A) * 255.0 - 128.0) / 127.0 * range;
  vec3 fine = li - l1 + sel * dHigh;
  l1 += sel * dLow;
  // 5. Three bands, amplitude-selective mid suppression (§3.1). B1 is
  // wrinkle-filled, so fine.x + dW is the fine band without detected
  // wrinkles; the wrinkle comes back as (1 - wEff) * dW (§3.4).
  vec3 mid = l1 - l2;
  float thr = r0.x > 0.6 ? 0.025 : 0.035;  // mapAmpThreshold(smooth)
  float keep = smoothstep(thr, 2.5 * thr, abs(mid.x));
  float midK = 1.0 - clamp(s * (1.0 - keep), 0.0, 1.0);
  float fineK = 1.0 + tex;
  o.x = l2.x + mid.x * midK + (fine.x + dW) * fineK - (1.0 - wEff) * dW;
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
      o.x = min(o.x, max(li.x, info0.x));
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
  // 13. Lips: chroma toward the face's natural target (hue and texture
  // kept), slight deepening; gloss clearly above the lip P95 skipped.
  if (lw > 0.0) {
    float w = lw * (1.0 - smoothstep(info0.w + 0.02, info0.w + 0.08, li.x));
    float k = 1.0 + w * (info1.x - 1.0);
    o.y *= k;
    o.z *= k;
    o.x += w * info1.y;
  }
  // 14. Blush: chroma toward the face's blush colour relative to the
  // local skin reference, slight darkening (§3.9).
  if (bw > 0.0) {
    o.y += bw * 0.35 * (info1.z - l3.y);
    o.z += bw * 0.35 * (info1.w - l3.z);
    o.x *= 1.0 - 0.03 * bw;
  }
  // 15. Red-eye: strongly red pupils in the eye discs lose their colour
  // and darken; brown irises, skin and the catchlight do not qualify.
  if (re > 0.0) {
    float w = re * smoothstep(0.05, 0.10, li.y) *
              smoothstep(0.0, 0.04, li.y - li.z) *
              (1.0 - smoothstep(0.80, 0.92, li.x));
    o.y *= 1.0 - w;
    o.z *= 1.0 - w;
    o.x *= 1.0 - 0.5 * w;
  }
  return true;
}

// Image atlas taps: tile (OX, OY) of the 3W x 2H atlas (backdrop_maps.dart).
#define BTAP(X, Y) texture(uBackdropMap, (vec2(X, Y) + 0.5) / BA).rgb
#define BBILERP(OX, OY) mix( \
    mix(BTAP(blo.x + (OX), blo.y + (OY)), BTAP(bhi.x + (OX), blo.y + (OY)), bf.x), \
    mix(BTAP(blo.x + (OX), bhi.y + (OY)), BTAP(bhi.x + (OX), bhi.y + (OY)), bf.x), \
    bf.y)

// Signed atlas bytes (retouch_maps.dart decodeSigned): 128 is zero.
vec3 decodeSigned(vec3 v, vec3 range) {
  return (v * 255.0 - 128.0) / 127.0 * range;
}

// 16. Backdrop and clothes (image scope, backdrop_kernel.dart): adds the
// Clean / stray-hair blend, the Unify shift and the clothing wrinkle /
// lint change to o; false when untouched.
bool backdropRetouch(vec2 uv, vec3 li, inout vec3 o) {
  bool backdropOn = uBackdropInfo0.z > 0.5;
  bool clothesOn = uClothesParams.z > 0.5;
  if (!backdropOn && !clothesOn) return false;
  vec2 BW = uBackdropInfo0.xy;
  vec2 BA = vec2(3.0, 2.0) * BW;
  vec2 blo;
  vec2 bhi;
  vec2 bf;
  maskTaps(uv, BW, blo, bhi, bf);
  bool touched = false;
  if (backdropOn) {
    vec3 wts = BBILERP(BW.x, BW.y);
    float mixW = max(uBackdropParams.x * wts.r, uBackdropParams.w * wts.b);
    float matte = wts.g;
    bool unify = matte > 0.0 &&
        (uBackdropParams.y > 0.0 || uBackdropParams.z != 0.0);
    if (mixW > 0.0) {
      vec3 e = bandLab(BBILERP(0.0, 0.0));
      vec3 g = bandLab(BBILERP(BW.x, 0.0));
      vec3 r = li - g;
      vec3 tau = vec3(uBackdropInfo0.w, uBackdropInfo1.w, uBackdropInfo1.w);
      vec3 t = e + r / (1.0 + abs(r) / tau);
      o += mixW * (t - li);
    }
    if (unify) {
      vec3 u = bandLab(BBILERP(0.0, BW.y));
      o += matte * (uBackdropParams.y * (uBackdropInfo1.xyz - u) +
                    vec3(uBackdropParams.z, 0.0, 0.0));
    }
    touched = mixW > 0.0 || unify;
  }
  if (clothesOn) {
    // Tiles (2, 0): removable fold field D; (2, 1): lint fill delta.
    vec3 fold = decodeSigned(BBILERP(2.0 * BW.x, 0.0), vec3(0.2, 0.08, 0.08));
    vec3 lint = decodeSigned(BBILERP(2.0 * BW.x, BW.y), vec3(0.6, 0.15, 0.15));
    bool clothes =
        (uClothesParams.x > 0.0 && any(greaterThan(abs(fold), vec3(1e-6)))) ||
        (uClothesParams.y > 0.0 && any(greaterThan(abs(lint), vec3(1e-6))));
    if (clothes) {
      o += uClothesParams.y * lint - uClothesParams.x * fold;
      touched = true;
    }
  }
  return touched;
}

void main() {
  vec2 uv = (FlutterFragCoord().xy + uTile.xy) / uTile.zw;
  vec3 src = texture(uSource, uv).rgb;
  fragColor = vec4(src, 1.0);
  if (uRetouch.y < 0.5 || uSize.x < 0.5) return;
  vec3 li = bandLab(src);
  vec3 o = li;
  bool face = faceRetouch(uv, li, o);
  bool backdrop = backdropRetouch(uv, li, o);
  if (!face && !backdrop) return;
  fragColor = vec4(srgbEncode(oklabToLinSrgb(o)), 1.0);
}
