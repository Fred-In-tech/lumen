# 02 · Editor Engine Research: Real-Time Non-Destructive Photo Editing

**Project:** Lumen, an AI-powered photo editor in the style of Lightroom
**Date:** 2026-10-03
**Status:** Research. No app code yet.
**Stack note:** The research started for a Next.js/WebGL target. The stack has since moved to **Flutter 3.47 (Dart, Impeller)** for macOS, iOS, Android and Windows. The shader math, pipeline order, data model and licensing findings apply to both. Section 9 (**Flutter implementation**) is the plan for the current stack. The web-specific notes (WebGL2/WebGPU, workers) stay in as reference, because Flutter web is a possible later target.

> **Licensing legend:** ✅ commercial-safe (MIT / Apache-2.0 / BSD / ISC / zlib / DNG SDK license) · ⚠️ weak copyleft (LGPL / MPL / CDDL: usable with compliance work) · ⛔ strong copyleft (GPL / AGPL: **ideas only, never copy code**) · ❓ no license (all rights reserved: do not copy).

---

## 0. TL;DR: recommendations

1. **Don't clone an editor. Build our own GPU render graph.** No permissively licensed project gives us a Lightroom-grade engine. The best permissive references are **RAWmakase** (MIT; measured Lightroom parity tables, an XMP preset parser and design docs), **vkdt** (BSD-2; GLSL local-Laplacian, guided-filter and dehaze kernels; a few files are GPLv3) and the **Adobe DNG SDK** (permissive Adobe license; the reference exposure ramp, the ACR3 default tone curve, hue-preserving RGB tone and Temperature/Tint↔xy conversion). RapidRAW (AGPL), darktable and RawTherapee (GPL) are **ideas only**.
2. **Working space: linear ProPhoto RGB (D50) in half-float or higher.** This matches Lightroom, the DNG SDK and the presets. Display-referred work (curves, LUTs, grain) happens after an explicit output transform.
3. **Architecture:** low-resolution *analysis* passes produce the guided-filter base, clarity band, dehaze transmission and statistics. One per-pixel *uber* pass does all the point operations. A *finish* pass does sharpening, vignette and grain. Results are cached per stage and keyed by a hash of their parameters, so most slider moves re-run a single full-screen pass.
4. **Pipeline order:** geometry → NR → WB/calibration → exposure ramp → dehaze → shadows/highlights → clarity/texture → one composite **hue-preserving 1D tone LUT** (base curve + contrast + whites/blacks + master curve) → RGB curves → HSL/vibrance/saturation (OkLCh) → color grading (linear gains by luminance) → output transform plus gamut compression → 3D LUT → sharpen → vignette → grain → dither.
5. **Flutter (section 9):** use `FragmentProgram` multi-pass via `PictureRecorder` + `toImageSync(targetFormat: TargetPixelFormat.rgbaFloat32)` for float intermediates. Encode the 1D curve as an N×1 image and the 3D LUT as a 2D strip with manual trilinear sampling. **Always pass `FilterQuality.low`** to `setImageSampler`, because the default is nearest. Compute the histogram on the CPU from a 256-px readback in an isolate. Export by tiles.
6. **Decoding:** use OS decoders wherever possible (ImageIO/CIRAWFilter on Apple, ImageDecoder on Android 9+, WIC on Windows). That way HEVC patent costs stay with the OS vendor. **LibRaw** through FFI covers RAW on the other platforms: take the **CDDL-1.0** option on iOS, where LGPL dynamic-linking rules are awkward. **piex** (Apache-2.0) extracts the embedded preview instantly, and the **`exif`** package (MIT) reads metadata.
7. **Data model:** a versioned JSON `EditDocument` with `schemaVersion` and a pinned `engineVersion` (like Lightroom's ProcessVersion). Presets are sparse patches. History stores **forward and inverse patches, not full snapshots**: Lightroom's own catalog spends about 50% of its space on full-snapshot history. Virtual copies are variants that point to one content-hashed original. Lightroom `.xmp` import is a bonus, following the mapping table in §8.5.
8. **Naming flag (CMO hat):** a GPL Lightroom alternative called **"LumenPhotoStudio"** already exists on GitHub (kachamo/LumenPhotoStudio, created 2026). Run a trademark and naming check before launch.

---

## 1. Existing open-source editors: what to clone or borrow

### 1.1 Web / cross-platform engines and editors

| Project | URL | License | Stars · last push | Tech | Reusable for Lumen | Verdict |
|---|---|---|---|---|---|---|
| **RAWmakase** | github.com/pch/rawmakase | ✅ MIT | 214 · 2026-10 (new, very active) | Rust, wgpu WGSL, LibRaw, Little CMS | Measured Lightroom-parity data: Contrast/Whites/Blacks curves, Shadows/Highlights via a guided filter on log-luminance (radius 3.2% of the long edge, ε=1.5 log2²), color-mixer HSV tables in linear ProPhoto, grading as luminance-dependent linear gains, an XMP preset parser, preview-pyramid and stage-cache design | **Top reference.** Port algorithms and tables with attribution. Caveats: young project, one maintainer, and tables fitted to Adobe renders (a functional measurement; low risk, but note it) |
| **vkdt** | github.com/hanatos/vkdt | ✅ BSD-2 by default, ⛔ some files GPLv3 (OpenDRT, parts of `shared/oetf.glsl`, hdrmerge; `filmsim` profile is CC BY-SA) | 612 · 2026-10 | Vulkan GLSL compute | `llap` (fast local Laplacian for clarity/shadows/highlights), `guided`, `dehaze` (dark channel prior), `grain`, `denoise`, `demosaic`, `curves` | **Best permissive GLSL source.** Port kernels after checking each file's header |
| **Adobe DNG SDK** | helpx.adobe.com (DNG SDK 1.7.1); mirror android.googlesource.com/platform/external/dng_sdk | ✅ DNG SDK License (royalty-free; use/modify/distribute "for any purpose"; keep notices) | Adobe, 2026-06 build | C++ | `dng_function_exposure_ramp`, `dng_function_exposure_tone`, `dng_tone_curve_acr3_default` (1025-entry table), `RefBaselineRGBTone` (hue-preserving), `dng_temperature` (Robertson table, `kTintScale=-3000`), DCP profile application | **Port these functions.** Gives the "Lightroom default look" legally |
| mini-photo-editor + mini-gl | github.com/xdadda/mini-photo-editor, /mini-gl | ✅ MIT | 589 / 37 · 2025–26 | WebGL2, linear-sRGB, P3, curves, histogram, heal (Telea) | Plumbing ideas (filter chaining, curves spline). Adjustments are color-matrix approximations, 8-bit only | Reference only |
| glfx.js | github.com/evanw/glfx.js | ✅ MIT | 3.5k · 2023 (inactive) | WebGL1 | Shader snippets: curves texture, denoise, unsharp mask, vibrance, vignette | Snippet mine only |
| PixiJS filters v6 | github.com/pixijs/filters | ✅ MIT | 1.1k · 2026 | **GLSL and WGSL** pairs | Kawase/Gaussian blur, ColorMap (LUT) and Adjustment filters, written for both languages | Snippet mine |
| Filerobot Image Editor | github.com/scaleflex/filerobot-image-editor | ✅ MIT | 1.9k · 2026-06 | React + Konva (Canvas2D) | Crop, annotate and finetune UI ideas | Not an engine |
| TOAST UI Image Editor | github.com/nhn/tui.image-editor | ✅ MIT | 7.7k · **archived** | Fabric.js | Nothing | Avoid |
| miniPaint | github.com/viliusle/miniPaint | ✅ MIT | 3.5k · 2026-04 | Canvas2D, jQuery | Layer UX ideas | Not an engine |
| Photon | github.com/silvia-odwyer/photon | ✅ Apache-2.0 | 3.9k · 2026-09 | Rust→WASM, CPU, 8-bit | CPU utilities | Not real-time capable |
| Graphite (rawkit) | github.com/GraphiteEditor/Graphite | ✅ Apache-2.0 / rawkit MIT OR Apache | 27k · 2026-10 | Rust | `rawkit` raw decoder (Sony ARW only so far) | Watch. A permissive LibRaw alternative, but immature |
| Khronos PBR Neutral | github.com/KhronosGroup/ToneMapping | ✅ Apache-2.0 | 117 · 2026-09 | GLSL + .cube | A display transform with highlight rolloff | Optional display transform |
| LightZone | github.com/ktgw0316/LightZone | ✅ BSD-3 | 414 · 2026-09 | Java | "ZoneMapper" tone UI, relight ideas | Ideas / porting OK |
| PhotoDemon | github.com/tannerhelland/PhotoDemon | ✅ BSD-style | 2.4k · 2026-08 | VB6 | CPU algorithms (vibrance, shadows/highlights) | Ideas / porting OK |
| **RapidRAW** | github.com/CyberTimon/RapidRAW | ⛔ **AGPL-3.0** | 10.3k · 2026-10 | Tauri, Rust, wgpu WGSL | Full Lightroom-like pipeline (AgX, masks, AI) | **Ideas only.** The AGPL network clause would force us to open-source Lumen |
| darktable | github.com/darktable-org/darktable | ⛔ GPL-3.0 | 13.2k | C/OpenCL | filmic/sigmoid, color balance rgb, diffuse-or-sharpen | Ideas only |
| RawTherapee / ART | github.com/RawTherapee/RawTherapee, artraweditor/ART | ⛔ GPL-3.0 | 4.2k / 487 | C++ | Demosaic and CIECAM ideas | Ideas only |
| Filmulator | github.com/CarVac/filmulator-gui | ⛔ GPL-3.0 | 764 | C++ | Film-development tone model | Ideas only |
| Open Display Transform | github.com/jedypod/open-display-transform | ⛔ GPL-3.0 | 525 | DCTL/GLSL | OpenDRT | Ideas only |
| LumenPhotoStudio | github.com/kachamo/LumenPhotoStudio | ⛔ GPL-3.0 | 2 · 2026-08 | n/a | Nothing | **Name collision.** See TL;DR #8 |

### 1.2 Supporting libraries (codecs, color, metadata)

| Library | License | Use |
|---|---|---|
| LibRaw 0.22.x | ⚠️ LGPL-2.1 **or** CDDL-1.0 (your choice) | RAW decoding and demosaicing |
| `libraw-wasm` (npm) / `ssssota/libraw.wasm` | ⚠️ wrapper ISC / MIT + LibRaw | Web builds. ❓ `ybouane/LibRaw-Wasm` repo has **no license file**, so don't copy its wrapper code |
| `flutter_libraw` (pub) | ⚠️ wrapper MIT + LibRaw | FFI wrapper, v0.0.2, very early |
| piex (Google) | ✅ Apache-2.0 | Embedded-preview extraction from RAW files (fast) |
| rawler (dnglab), rawloader, rawspeed | ⚠️ LGPL-2.1 | Alternative RAW decoders |
| dcraw.js | ⛔ GPL-2.0 | **Avoid** |
| libheif / libheif-js / heic-to | ⚠️ LGPL-3.0 (+ HEVC patents) | HEIC on the web only. `heic2any` says "MIT" but bundles LGPL libheif |
| exifr (JS) | ✅ MIT | EXIF/XMP/ICC/IPTC on the web (last release 2024, stable) |
| ExifReader (JS) | ⚠️ MPL-2.0 | Alternative |
| Little CMS / `lcms-wasm` | ✅ MIT | ICC conversions |
| jSquash (MozJPEG, AVIF, WebP, OxiPNG WASM) | ✅ Apache-2.0 | Web export encoders |
| UTIF.js / fast-png / geotiff.js | ✅ MIT | 16-bit TIFF/PNG on the web |
| Oklab reference code | ✅ public domain / MIT | Perceptual color math |

---

## 2. Engine architecture (backend-agnostic)

```
 decode (worker/isolate) ──► Source: linear ProPhoto, half/float, + resolution pyramid
                                  │
       ┌──────────────────────────┼────────────────────────────────────┐
       ▼                          ▼                                    ▼
 [A] ANALYSIS (fixed low-res,   [B] DETAIL PRE-PASS (view res)       CPU stats
     512–1024 px long edge)         • Noise reduction (≥ 1:1/export)  (histogram readback:
   • log2 Y                         • Texture band (DoG of log Y)      percentiles, airlight,
   • guided-filter base (S/H)       • Clarity base                     auto-tone, clipping)
   • dehaze dark channel → t(x)
       │                          │
       └────────────┬─────────────┘
                    ▼
 [C] UBER PASS (one full-screen fragment shader, all point ops, reads A/B as textures,
     1D tone LUT, RGB curve LUT, 3D LUT)
                    ▼
 [D] FINISH PASS: luma USM sharpen → post-crop vignette (paint style) → grain → dither
                    ▼
               viewport / export tile / histogram downsample
```

**Key rules**

- **Resolution independence.** Global-context passes (A) always run at a fixed analysis resolution and are upsampled bilinearly. The fit preview, 100% regions and export tiles therefore get the *same* local tone result with no seams. RAWmakase uses this approach and computes its local-tone base on a 512-px copy.
- **Stage caching.** Each pass output is keyed by a hash of the parameters it reads. The log-domain bases don't depend on exposure: exposure only adds a constant in log2, so the detail term `L − base` is unchanged and exposure moves never recompute (A). Typical slider moves re-run only (C) and (D).
- **Coalescing.** Keep one pending render request. Drop stale results by generation ID. Render at reduced scale while dragging and at full quality on release.
- **One resample.** Crop, rotate, flip, perspective and lens distortion are a single inverse mapping applied when the first pass samples the source.
- **Context-loss safe.** Keep the CPU-side source (Float16 or Uint16) so GPU resources can be rebuilt.

---

## 3. Color foundations (portable GLSL subset)

Every snippet below uses a **portable subset** that compiles on Flutter's `FragmentProgram` (impellerc), WebGL2 GLSL ES 3.00 and (after translation) WGSL. That means: float, `vec2/3/4` and `sampler2D` uniforms only; two-argument `texture()` only; no `uint` or `bool` uniforms; no `texelFetch`; no `sampler3D`; constant loop bounds; no uniform arrays (pack them into `vec4`s).

**Matrix convention:** pass every 3×3 matrix as three `vec3` row uniforms and apply it with `dot`. That removes any column-major ambiguity.

```glsl
// ---- prelude (Flutter) ----
#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;
out vec4 fragColor;
// ---- (WebGL2 prelude would be: #version 300 es / precision highp float; out vec4 fragColor;) ----

const vec3 PP_Y = vec3(0.2880748, 0.7118352, 0.0000899); // ProPhoto (D50) luminance row

vec3 mul3(vec3 r0, vec3 r1, vec3 r2, vec3 c) { return vec3(dot(r0, c), dot(r1, c), dot(r2, c)); }

// IEC 61966-2-1 sRGB transfer, sign-extended so negative/HDR values survive
vec3 srgbEncode(vec3 c) {
  vec3 a = abs(c);
  vec3 lo = 12.92 * a;
  vec3 hi = 1.055 * pow(a, vec3(1.0 / 2.4)) - 0.055;
  return sign(c) * mix(hi, lo, step(a, vec3(0.0031308)));
}
vec3 srgbDecode(vec3 c) {
  vec3 a = abs(c);
  vec3 lo = a / 12.92;
  vec3 hi = pow((a + 0.055) / 1.055, vec3(2.4));
  return sign(c) * mix(hi, lo, step(a, vec3(0.04045)));
}
float srgbEncode1(float x) { return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1.0/2.4) - 0.055; }
```

**Matrices (computed with Bradford adaptation; rows shown)**

| Transform | Row 0 | Row 1 | Row 2 |
|---|---|---|---|
| linear sRGB (D65) → linear ProPhoto (D50) | 0.5292770, 0.3301545, 0.1405685 | 0.0983659, 0.8734707, 0.0281634 | 0.0168753, 0.1176594, 0.8654652 |
| linear ProPhoto → linear sRGB | 2.0343808, −0.7276358, −0.3067451 | −0.2288257, 1.2317425, −0.0029168 | −0.0085588, −0.1532667, 1.1618255 |
| linear ProPhoto → linear Display P3 | 1.6325756, −0.3797716, −0.2528040 | −0.1537004, 1.1667025, −0.0130021 | 0.0103932, −0.0628073, 1.0524141 |
| ProPhoto → XYZ (D50) | 0.7977666, 0.1351813, 0.0313477 | 0.2880748, 0.7118352, 0.0000899 | 0, 0, 0.8251046 |
| Bradford M | 0.8951, 0.2664, −0.1614 | −0.7502, 1.7135, 0.0367 | 0.0389, −0.0685, 1.0296 |
| Bradford M⁻¹ | 0.9869929, −0.1470543, 0.1599627 | 0.4323053, 0.5183603, 0.0492912 | −0.0085287, 0.0400428, 0.9684867 |

**Oklab / OkLCh** (Ottosson; public domain or MIT) is used for the HSL mixer, vibrance and saturation. Convert ProPhoto → linear sRGB *without clamping* first, then use the published matrices:

```glsl
vec3 linSrgbToOklab(vec3 c) {
  vec3 lms = vec3(dot(vec3(0.4122214708, 0.5363325363, 0.0514459929), c),
                  dot(vec3(0.2119034982, 0.6806995451, 0.1073969566), c),
                  dot(vec3(0.0883024619, 0.2817188376, 0.6299787005), c));
  lms = sign(lms) * pow(abs(lms), vec3(1.0/3.0));
  return vec3(dot(vec3(0.2104542553,  0.7936177850, -0.0040720468), lms),
              dot(vec3(1.9779984951, -2.4285922050,  0.4505937099), lms),
              dot(vec3(0.0259040371,  0.7827717662, -0.8086757660), lms));
}
vec3 oklabToLinSrgb(vec3 L) {
  vec3 lms = vec3(L.x + 0.3963377774*L.y + 0.2158037573*L.z,
                  L.x - 0.1055613458*L.y - 0.0638541728*L.z,
                  L.x - 0.0894841775*L.y - 1.2914855480*L.z);
  lms = lms * lms * lms;
  return vec3(dot(vec3( 4.0767416621, -3.3077115913,  0.2309699292), lms),
              dot(vec3(-1.2684380046,  2.6097574011, -0.3413193965), lms),
              dot(vec3(-0.0041960863, -0.7034186147,  1.7076147010), lms));
}
```

---

## 4. Adjustment-by-adjustment math

Lightroom's slider ranges are kept in the data model (for example −100..100). The CPU normalizes them to the shader units shown here, so curves and constants can be re-tuned without a data migration.

### 4.1 White balance: Temperature / Tint

- **RAW:** apply WB as camera-space channel multipliers *before* the camera→ProPhoto matrix. The decoder caches as-shot demosaiced camera RGB, and Lumen re-multiplies (RAWmakase approach). For Lightroom-compatible Kelvin/Tint, port DNG SDK `dng_temperature` (Robertson isotemperature table, tint offset = Tint / −3000 in CIE 1960 uv).
- **JPEG/HEIC/TIFF:** Lightroom stores relative `crs:IncrementalTemperature/IncrementalTint` (−100..100). Map this to a source white xy, then apply a Bradford CAT to D50 inside ProPhoto. The CPU builds one 3×3 matrix.

```dart
// CPU (Dart): Kim et al. 2002 cubic-spline Planckian locus (1667–25000 K), plus tint along the uv normal.
List<double> planckianXY(double T) {
  final t = T, t2 = t*t, t3 = t2*t;
  final x = t <= 4000
      ? -0.2661239e9/t3 - 0.2343589e6/t2 + 0.8776956e3/t + 0.179910
      : -3.0258469e9/t3 + 2.1070379e6/t2 + 0.2226347e3/t + 0.240390;
  final x2 = x*x, x3 = x2*x;
  final y = t <= 2222 ? -1.1063814*x3 - 1.34811020*x2 + 2.18555832*x - 0.20219683
          : t <= 4000 ? -0.9549476*x3 - 1.37418593*x2 + 2.09137015*x - 0.16748867
          :              3.0817580*x3 - 5.87338670*x2 + 3.75112997*x - 0.37001483;
  return [x, y];
}
// WB matrix (ProPhoto space): M = XYZ→PP · Bradford⁻¹ · diag(LMS_D50 / LMS_src) · Bradford · PP→XYZ
// The user's Temperature = the assumed scene illuminant. Higher K → warmer image after adaptation.
// JPEG mapping (tunable): K = 1e6 / (1e6/6500 - incrementalTemp * 1.5)   // ±150 mired at ±100
```

```glsl
uniform vec3 uWB0; uniform vec3 uWB1; uniform vec3 uWB2;   // WB × calibration, pre-multiplied on CPU
vec3 applyWB(vec3 c) { return mul3(uWB0, uWB1, uWB2, c); }
```

### 4.2 Exposure (stops) and the DNG exposure ramp

Exposure is a linear gain of `2^EV`. The DNG SDK then subtracts a small black level with a **quadratic toe** (the "exposure ramp"). RAWmakase fitted the black level as 0.0015 × 2^EV scene-linear to match Camera Raw. Unlike the SDK, keep values above 1 so the tone curve can roll highlights off.

```glsl
uniform float uExpGain;          // 2^EV
uniform vec4  uRamp;             // x=black, y=radius, z=qScale, w=slope   (CPU per DNG SDK formulas)
float ramp(float x) {
  if (x <= uRamp.x - uRamp.y) return 0.0;
  if (x >= uRamp.x + uRamp.y) return (x - uRamp.x) * uRamp.w;   // no clamp: keep headroom
  float y = x - (uRamp.x - uRamp.y);
  return uRamp.z * y * y;
}
vec3 applyExposure(vec3 c) {
  c *= uExpGain;
  return vec3(ramp(c.r), ramp(c.g), ramp(c.b));
}
// CPU: slope = 1/(white-black); radius = min(0.5*black, (1/16)/slope); qScale = slope/(4*radius)
```

For negative exposure, the DNG SDK's `dng_function_exposure_tone` darkens with a quadratic that still maps white to white (x≤0.25: x·2^EV; otherwise a·x²+b·x+c with a=16/9·(1−s), b=s−a/2, c=1−a−b). Bake this into the tone LUT (§4.6).

### 4.3 Dehaze (dark channel prior; simple alternative)

The physical model is **I = J·t + A·(1−t)**. In the analysis pass, at 512 px:

1. `dark = min(R/A_r, G/A_g, B/A_b)` → separable **min-filter** (rows, then columns; patch about 15 px).
2. **Airlight A:** read back a small dark-channel image and average the RGB of the brightest 0.1%.
3. `t = 1 − 0.95·dark`, refined with a guided filter (radius about 40 px, ε≈1e-3) guided by gray.

```glsl
uniform sampler2D uTrans; uniform vec3 uAirlight; uniform float uDehaze;  // -1..1
vec3 applyDehaze(vec3 c, vec2 uv) {
  float t = texture(uTrans, uv).r;
  if (uDehaze >= 0.0) {
    float tt = max(mix(1.0, t, uDehaze), 0.1);
    return max((c - uAirlight) / tt + uAirlight, vec3(0.0));
  }
  float tt = mix(1.0, t, -uDehaze);              // negative = add haze
  return c * tt + uAirlight * (1.0 - tt);
}
```

*Simpler alternative:* RAWmakase measured that Lightroom's Dehaze is "mostly a per-photo tone curve with a spatial residual". A v1 can ship as a contrast/black-point curve plus a little saturation and add the DCP spatial part later.
*Patent:* the dark channel prior's US patent **US8340461B2 (Microsoft)** shows status "Expired – Fee Related". Other jurisdictions were not checked.

### 4.4 Highlights / Shadows (luminance-masked local tone mapping)

Decompose log-luminance into an **edge-aware base** (guided filter) and detail. Apply gain computed from the *base* only, so local detail and contrast survive and the guided filter keeps halos low.

**Analysis passes (guided filter, self-guided):** `I = log2(max(Y,1e-6))` → `meanI = box(I)`, `meanII = box(I²)` → `a = var/(var+ε)`, `b = meanI − a·meanI` → `box(a), box(b)`. Store `(meanA, meanB)` and evaluate `q = meanA·I + meanB` in the uber pass at full resolution. That is a cheap edge-aware upsample. Parameters from RAWmakase's Lightroom fit: radius **3.2% of the long edge**, **ε = 1.5** (log2 units²). Keys: **Shadows** anchored to the 99th luminance percentile, **Highlights** to the median.

```glsl
uniform sampler2D uGF;           // rg = (meanA, meanB) of guided filter on log2 Y (analysis res)
uniform vec4 uSH;                // x=shadows(-1..1) y=highlights(-1..1) z=keyLo(log2) w=keyHi(log2)
vec3 applyShadowsHighlights(vec3 c, vec2 uv) {
  float Y = max(dot(c, PP_Y), 1e-6);
  float L = log2(Y);
  vec2 ab = texture(uGF, uv).rg;
  float B = ab.x * L + ab.y;                                   // edge-aware base
  float wS = 1.0 - smoothstep(uSH.z - 4.0, uSH.z + 1.0, B);    // shadow region of base
  float wH = smoothstep(uSH.w - 1.0, uSH.w + 2.5, B);          // highlight region
  float gainStops = uSH.x * 1.6 * wS + uSH.y * 1.5 * wH;       // tunable maxima
  // compress: don't push shadows past mid or highlights below mid
  gainStops = uSH.x > 0.0 ? min(gainStops, max(0.0, (uSH.w - B))) : gainStops;
  return c * exp2(gainStops);                                  // ratio-preserving (hue/sat kept)
}
```

The constants are tunable. Calibrate them against Lightroom renders the way RAWmakase's `camera-raw-sweep.py` and `lightroom-scorecard.py` do, or port its MIT `local_tone_data.rs` tables. A higher-quality upgrade is vkdt's **fast local Laplacian** (`llap`, BSD-2), which handles clarity, shadows and highlights in one operator.

### 4.5 Clarity and Texture (multi-pass local contrast)

- **Clarity:** mid-frequency local contrast. Use a large-radius edge-aware base (guided filter or Gaussian of log Y; radius about 1–2% of the long edge, at preview resolution). Boost detail mostly in the midtones. Negative values smooth.
- **Texture:** band-pass detail (DoG). At full resolution σ₁≈1 px and σ₂≈4 px; scale both by the preview ratio. This skips the finest noise band.

```glsl
uniform sampler2D uClarityBase;  // r = blurred log2 Y (clarity radius)
uniform sampler2D uTexBand;      // r = G(σ1)(log2 Y) - G(σ2)(log2 Y)
uniform vec2 uCT;                // x=clarity(-1..1) y=texture(-1..1)
vec3 applyClarityTexture(vec3 c, vec2 uv) {
  float Y = max(dot(c, PP_Y), 1e-6);
  float L = log2(Y);
  float detail = L - texture(uClarityBase, uv).r;
  float mid = exp(-pow(L - log2(0.18), 2.0) / (2.0 * 2.5 * 2.5));   // midtone bell, σ≈2.5 stops
  float dStops = uCT.x * 0.7 * detail * mid + uCT.y * 1.2 * texture(uTexBand, uv).r;
  return c * exp2(dStops);
}
```

Separable Gaussian blur (pre-pass). Use constant taps and a uniform step so large radii work on a downsampled input:

```glsl
uniform sampler2D uSrc; uniform vec2 uDir; uniform float uSigma;  // uDir = texel * direction * step
const int TAPS = 24;
vec4 gauss(vec2 uv) {
  vec4 acc = vec4(0.0); float wsum = 0.0;
  for (int i = -TAPS; i <= TAPS; i++) {
    float x = float(i);
    float w = exp(-x * x / (2.0 * uSigma * uSigma));
    acc += texture(uSrc, uv + uDir * x) * w; wsum += w;
  }
  return acc / wsum;
}
```

The **box filter** for the guided filter is the same code with `w = 1`. For radii above about 24 taps, downsample first; the base is low-frequency anyway.

### 4.6 Tone: contrast (S-curve around mid-gray), whites/blacks, base curve, master point curve, as **one hue-preserving 1D LUT**

The CPU composes everything into one monotone 1D LUT. The shader applies it with the DNG SDK's **RGBTone** method: tone the max and min channels, then interpolate the middle channel by its relative position. That preserves hue, unlike per-channel curves.

`LUT(x_lin) = decode( master( blacksWhites( contrast( encode( baseCurve(x_lin) ) ) ) ) )`

- `baseCurve`: the ACR3 default (DNG SDK table, composed with `exposure_tone` for negative EV) or our own filmic sigmoid with a shoulder for x > 1 (or Khronos PBR Neutral).
- `contrast`: a symmetric power S-curve around a pivot in the encoded domain. Mid-gray 0.18 linear ≈ 0.46 sRGB-encoded; Lightroom's measured pivot is 0.41–0.51.
- `blacks/whites`: endpoint moves with a soft toe/shoulder (the same quadratic-knee idea as the exposure ramp).
- `master`: the user's point curve (monotone cubic, Fritsch–Carlson) plus Lightroom's parametric curve (Shadows/Darks/Lights/Highlights with three split points).

```dart
// CPU (Dart): curve building blocks, all in sRGB-encoded [0,1]
double contrastCurve(double x, double amt /*-1..1*/, {double p = 0.46}) {
  final g = math.pow(2.0, amt * 1.0);                // slope at pivot
  return x < p ? p * math.pow(x / p, g) : 1 - (1 - p) * math.pow((1 - x) / (1 - p), g);
}
double blacksCurve(double x, double b /*-1..1*/) {
  if (b >= 0) return x + b * 0.06 * math.pow(1 - x, 4);            // lift deep shadows
  final t = -b * 0.06;                                              // crush: soft toe
  final r = t * 0.5; if (x <= t - r) return 0;
  if (x >= t + r) return (x - t) / (1 - t);
  final y = x - (t - r); return y * y / (4 * r * (1 - t));
}
double whitesCurve(double x, double w) => 1 - blacksCurve(1 - x, -w); // mirrored
// Bake a 4096-entry LUT indexed by u = srgbEncode(x_lin) (perceptual spacing); store linear output.
```

```glsl
uniform sampler2D uToneLUT;      // 4096x1, r = linear output; index = srgb-encoded input
float toneLUT(float xLin) {
  float u = clamp(srgbEncode1(max(xLin, 0.0)), 0.0, 1.0);
  return texture(uToneLUT, vec2((u * 4095.0 + 0.5) / 4096.0, 0.5)).r;
}
vec3 rgbTone(vec3 c) {                       // DNG SDK RefBaselineRGBTone equivalent
  float mx = max(c.r, max(c.g, c.b));
  float mn = min(c.r, min(c.g, c.b));
  float tmx = toneLUT(mx), tmn = toneLUT(mn);
  if (mx - mn < 1e-6) return vec3(tmx);
  vec3 f = (c - mn) / (mx - mn);             // min→0, max→1, mid→ratio
  return tmn + (tmx - tmn) * f;
}
```

**Per-channel R/G/B curves** (`ToneCurvePV2012Red/Green/Blue`) are applied in the encoded domain, per channel, from a second LUT (RGB in one N×1 image):

```glsl
uniform sampler2D uRGBCurves;    // 1024x1: r,g,b channels = per-channel curves (encoded→encoded)
vec3 rgbCurves(vec3 cLin) {
  vec3 e = clamp(srgbEncode(cLin), 0.0, 1.0);
  vec3 s = (e * 1023.0 + 0.5) / 1024.0;
  e = vec3(texture(uRGBCurves, vec2(s.r, 0.5)).r,
           texture(uRGBCurves, vec2(s.g, 0.5)).g,
           texture(uRGBCurves, vec2(s.b, 0.5)).b);
  return srgbDecode(e);
}
```

### 4.7 HSL mixer: 8 bands with smooth hue weighting (OkLCh)

Band centers in **OkLCh hue degrees**. These are fully saturated sRGB colors at HSV 0/30/60/120/180/240/270/300, measured: Red **29.2**, Orange **52.8**, Yellow **109.8**, Green **142.5**, Aqua **194.8**, Blue **264.1**, Purple **293.8**, Magenta **328.4**.

The weights form a **partition of unity**: each band falls to zero at its neighbors' centers through `smoothstep`, and because S(t) + S(1−t) = 1, any two adjacent weights sum to 1. Everything is vectorized over two `vec4`s, so there is no dynamic indexing. Per-band left and right half-widths are precomputed on the CPU.

```glsl
uniform vec4 uCenterA, uCenterB;   // radians, bands 0-3, 4-7
uniform vec4 uLeftA, uLeftB;       // c_i - c_{i-1}  (radians)
uniform vec4 uRightA, uRightB;     // c_{i+1} - c_i
uniform vec4 uHueA, uHueB;         // hue shift per band (radians, LR ±100 → ±~30°)
uniform vec4 uSatA, uSatB;         // -1..1
uniform vec4 uLumA, uLumB;         // -1..1
const float TAU = 6.28318530718;
vec4 bandW(float h, vec4 c, vec4 lw, vec4 rw) {
  vec4 d = mod(vec4(h) - c + 0.5 * TAU, vec4(TAU)) - 0.5 * TAU;   // signed circular distance
  vec4 wl = 1.0 - smoothstep(vec4(0.0), lw, -d);
  vec4 wr = 1.0 - smoothstep(vec4(0.0), rw,  d);
  return mix(wl, wr, step(vec4(0.0), d));
}
vec3 hslMixer(vec3 lab) {                     // lab = Oklab
  float C = length(lab.yz);
  if (C < 1e-5) return lab;
  float h = atan(lab.z, lab.y);
  vec4 wA = bandW(h, uCenterA, uLeftA, uRightA);
  vec4 wB = bandW(h, uCenterB, uLeftB, uRightB);
  float dh = dot(wA, uHueA) + dot(wB, uHueB);
  float ds = dot(wA, uSatA) + dot(wB, uSatB);
  float dl = dot(wA, uLumA) + dot(wB, uLumB);
  float chromaW = smoothstep(0.0, 0.06, C);   // protect neutrals and noise
  float h2 = h + dh * chromaW;
  float C2 = C * max(0.0, 1.0 + ds * chromaW);
  float L2 = lab.x * exp2(dl * 0.5 * chromaW);
  return vec3(L2, C2 * cos(h2), C2 * sin(h2));
}
```

*Parity note:* RAWmakase found Lightroom's mixer behaves like an **HSV lookup in linear ProPhoto** and ships MIT measured tables (36 hues × 6 sats × 6 values). Start with the OkLCh version above (smooth and perceptual), then optionally swap in a 3D-LUT-style table for closer parity.

### 4.8 Vibrance vs Saturation

- **Saturation:** a uniform chroma scale.
- **Vibrance:** boosts low-chroma colors more, protects skin (orange hues) and never clips already-saturated colors.

```glsl
uniform vec2 uSatVib;            // x = saturation (-1..1), y = vibrance (-1..1)
vec3 satVib(vec3 lab) {
  float C = length(lab.yz);
  float hDeg = degrees(atan(lab.z, lab.y));
  float lowSat = 1.0 - smoothstep(0.0, 0.25, C);
  float skin = exp(-pow((hDeg - 55.0) / 22.0, 2.0));      // OkLCh ~orange/skin
  float vib = uSatVib.y > 0.0 ? uSatVib.y * lowSat * (1.0 - 0.6 * skin) : uSatVib.y;
  float k = max(0.0, (1.0 + uSatVib.x) * (1.0 + vib));
  return vec3(lab.x, lab.yz * k);
}
```

### 4.9 Color grading (shadows / midtones / highlights / global wheels)

RAWmakase measured Lightroom's grading as **per-channel linear-ProPhoto gains that depend only on luminance**. The CPU converts each wheel's (hue, sat) into a unit-luminance tint gain: OkLCh(0.7, 0.1, hue) → ProPhoto, normalized by Y, then `tint = 1 + (rgbN − 1)·sat`.

```glsl
uniform vec3 uTintS, uTintM, uTintH, uTintG;   // linear gains (1,1,1 = neutral)
uniform vec4 uGradeLum;                         // shadows, mid, high, global (-1..1)
uniform vec2 uBlendBal;                         // x = blending 0..1 (LR default .5), y = balance -1..1
vec3 colorGrade(vec3 c) {
  float l = clamp(srgbEncode1(max(dot(c, PP_Y), 0.0)), 0.0, 1.0);   // perceptual luminance
  float pivot = 0.5 - 0.3 * uBlendBal.y;
  float width = mix(0.12, 0.45, uBlendBal.x);
  float wS = 1.0 - smoothstep(pivot - width, pivot + width * 0.5, l);
  float wH = smoothstep(pivot - width * 0.5, pivot + width, l);
  float wM = exp(-pow(l - pivot, 2.0) / (2.0 * width * width));
  float sum = max(wS + wM + wH, 1.0); wS /= sum; wM /= sum; wH /= sum;
  vec3 g = mix(vec3(1.0), uTintS, wS) * mix(vec3(1.0), uTintM, wM) * mix(vec3(1.0), uTintH, wH) * uTintG;
  float lumStops = 0.5 * (uGradeLum.x * wS + uGradeLum.y * wM + uGradeLum.z * wH + uGradeLum.w);
  return c * g * exp2(lumStops);
}
```

### 4.10 Output transform and gamut compression

ProPhoto → display (sRGB or P3) creates negative and >1 values for saturated colors. Desaturate toward a gray of the same luminance, with an analytic bound:

```glsl
vec3 gamutCompress(vec3 c) {               // c = linear display RGB
  float Y = clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
  vec3 d = c - Y;
  vec3 kLo = mix(vec3(1.0), Y / max(Y - c, vec3(1e-6)), step(c, vec3(0.0)));
  vec3 kHi = mix(vec3(1.0), (1.0 - Y) / max(c - Y, vec3(1e-6)), step(vec3(1.0), c));
  float k = min(1.0, min(min(min(kLo.r, kLo.g), kLo.b), min(min(kHi.r, kHi.g), kHi.b)));
  return Y + d * k;
}
```

### 4.11 3D LUT (.cube)

The `.cube` format (Adobe Cube LUT spec 1.0) has `LUT_3D_SIZE N`, optional `DOMAIN_MIN/MAX` and N³ rows with **red changing fastest**. Apply it display-referred (sRGB-encoded) by default, with an `amount` blend and a per-LUT "input space" setting (sRGB, log, linear).

With native 3D textures (WebGL2/WebGPU), use `coord = (x·(N−1)+0.5)/N` and hardware trilinear filtering. Flutter has no `sampler3D`, so it uses the 2D strip variant in §9.1.

### 4.12 Post-crop vignette

Lightroom parameters: Amount −100..100, Midpoint, Roundness, Feather, Highlights, and Style (Highlight Priority, Color Priority, Paint Overlay). The vignette is computed in crop coordinates, so it follows the crop. **Highlight priority** = multiply in *linear* before the tone LUT, so highlights roll off naturally. **Paint overlay** = blend toward black or white in the finish pass.

```glsl
uniform vec4 uCrop;              // crop rect in uv: x0,y0,x1,y1
uniform vec4 uVig;               // x amount(-1..1) y midpoint(0..1) z roundness(-1..1) w feather(0..1)
uniform vec2 uVig2;              // x highlights protect(0..1) y crop aspect (w/h)
float vignetteMask(vec2 uv) {
  vec2 p = abs((uv - uCrop.xy) / (uCrop.zw - uCrop.xy) * 2.0 - 1.0);
  vec2 asp = vec2(uVig2.y, 1.0) / max(uVig2.y, 1.0);
  p *= mix(vec2(1.0), asp, max(uVig.z, 0.0));             // +roundness → circle
  float n = 2.0 + 6.0 * max(-uVig.z, 0.0);                 // -roundness → rectangle
  float d = pow(pow(p.x, n) + pow(p.y, n), 1.0 / n);
  float mid = mix(0.35, 1.25, uVig.y);
  float f = max(uVig.w, 0.02) * 0.8;
  return smoothstep(mid - f, mid + f, d);
}
vec3 applyVignetteLinear(vec3 c, vec2 uv) {               // highlight-priority style
  float m = vignetteMask(uv);
  if (uVig.x < 0.0) {
    float protect = uVig2.x * smoothstep(0.5, 1.0, dot(c, PP_Y));
    return c * mix(1.0 + uVig.x * m, 1.0, protect);
  }
  return c * (1.0 + uVig.x * m * 1.5);
}
```

### 4.13 Grain (Amount, Size, Roughness)

Grain is computed from **full-resolution pixel coordinates**, so the pattern is identical in preview and export. Amplitude is reduced by the preview scale, matching what a resized export would show (RAWmakase approach). It is applied display-referred and strongest in the midtones, *after* sharpening. The float hash avoids `uint` (unsupported in Flutter); it follows the style of Dave Hoskins' "Hash without Sine" (MIT).

```glsl
uniform vec4 uGrain;             // x amount(0..1) y size(px, full-res) z roughness(0..1) w seed
uniform vec3 uFullRes;           // xy = full-res image size, z = preview→full scale
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash12(i), b = hash12(i + vec2(1, 0)), c = hash12(i + vec2(0, 1)), d = hash12(i + vec2(1, 1));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}
vec3 applyGrain(vec3 e, vec2 uv) {                        // e = display-encoded
  vec2 px = uv * uFullRes.xy / max(uGrain.y, 0.5) + uGrain.w * 17.0;
  float n = vnoise(px) * (1.0 - 0.5 * uGrain.z) + vnoise(px * 2.03 + 7.1) * 0.5 * uGrain.z;
  float l = dot(e, vec3(0.2126, 0.7152, 0.0722));
  float amp = uGrain.x * 0.10 * 4.0 * l * (1.0 - l) / sqrt(max(uFullRes.z, 1.0));
  return e + n * amp;
}
```

### 4.14 Sharpening (Amount, Radius, Detail, Masking)

Unsharp mask on **luminance** in the encoded domain, so it adds no color fringes. **Detail** soft-limits overshoot to control halos. **Masking** is an edge mask from the gradient of the blurred luma. Run it at output resolution: radius scaled for the preview, after resizing for export.

```glsl
uniform sampler2D uImg;          // display-encoded RGB
uniform sampler2D uBlurY;        // gaussian(radius) of encoded luma
uniform vec4 uSharp;             // x amount(0..1.5) y detail(0..1) z masking(0..1)
uniform vec2 uTexel;
vec3 sharpen(vec2 uv) {
  vec3 c = texture(uImg, uv).rgb;
  float y = dot(c, vec3(0.2126, 0.7152, 0.0722));
  float hp = y - texture(uBlurY, uv).r;
  float lim = mix(0.02, 0.25, uSharp.y);
  hp = lim * tanh(hp / lim);                              // halo suppression
  float gx = texture(uBlurY, uv + vec2(uTexel.x, 0.0)).r - texture(uBlurY, uv - vec2(uTexel.x, 0.0)).r;
  float gy = texture(uBlurY, uv + vec2(0.0, uTexel.y)).r - texture(uBlurY, uv - vec2(0.0, uTexel.y)).r;
  float t = uSharp.z * 0.08;
  float edge = uSharp.z > 0.0 ? smoothstep(t, t + 0.02, length(vec2(gx, gy))) : 1.0;
  return c + vec3(uSharp.x * edge * hp);
}
```

### 4.15 Noise reduction (bilateral approximation)

Run noise reduction **early, on linear data**, so clarity and sharpening don't amplify noise. Convert to Oklab and handle the two parts separately:

- **Color NR:** a large-radius cross-bilateral blur of *a, b*, guided by L.
- **Luminance NR:** a bilateral blur of L. **Detail** maps to the range sigma; **Contrast** blends some of the original back.

Separable bilateral filtering is an approximation (slight diagonal artifacts) and is acceptable for v1. Upgrade later to a guided filter or non-local means at 1:1, and eventually to AI denoise (ONNX Runtime, MIT, or a Core ML / NNAPI model).

```glsl
uniform sampler2D uLab;          // Oklab of linear input
uniform vec2 uDir;               // texel*direction
uniform vec3 uNR;                // x = spatial sigma (taps), y = range sigma (L), z = mode 0=chroma 1=luma
const int R = 8;
vec4 bilateral(vec2 uv) {
  vec3 c0 = texture(uLab, uv).xyz;
  vec3 acc = vec3(0.0); float wsum = 0.0;
  for (int i = -R; i <= R; i++) {
    vec3 ci = texture(uLab, uv + uDir * float(i)).xyz;
    float ws = exp(-float(i * i) / (2.0 * uNR.x * uNR.x));
    float wr = exp(-pow(ci.x - c0.x, 2.0) / (2.0 * uNR.y * uNR.y));
    acc += ci * ws * wr; wsum += ws * wr;
  }
  vec3 f = acc / wsum;
  return uNR.z < 0.5 ? vec4(c0.x, f.yz, 1.0) : vec4(f.x, c0.yz, 1.0);
}
```

---

## 5. Recommended pipeline order

| # | Stage | Domain | Pass | Why here |
|---|---|---|---|---|
| 0 | Decode → linear ProPhoto (ICC/camera matrix) | linear | upload | Single working space |
| 1 | Geometry: crop, rotate, flip, perspective, lens | sampling | first pass | One resample |
| 2 | Noise reduction | linear / Oklab | pre-pass | Before anything amplifies noise |
| 3 | White balance + calibration (3×3) | linear | uber | Physically a linear operation |
| 4 | Exposure + DNG exposure ramp (black toe) | linear | uber | Scene-referred gain |
| 5 | Vignette (highlight-priority style) | linear | uber | Behaves like light falloff |
| 6 | Dehaze (DCP) | linear | uber + analysis | Haze model is linear radiance |
| 7 | Shadows / Highlights (guided base) | log Y | uber + analysis | Local tone before the global curve (Lightroom-like) |
| 8 | Clarity / Texture | log Y | uber + pre-pass | Local contrast |
| 9 | Composite 1D tone LUT (base curve, contrast, whites/blacks, master curve) via **RGBTone** | linear → encoded → linear | uber | Hue-preserving and one lookup |
| 10 | R/G/B point curves | encoded | uber | Matches Lightroom curve semantics |
| 11 | HSL mixer → saturation/vibrance | OkLCh | uber | RAWmakase measured: mixer and grading run *after* the tone curves |
| 12 | Color grading | linear gains | uber | Same measurement |
| 13 | Output transform ProPhoto → sRGB/P3 + gamut compression + encode | display | uber | |
| 14 | 3D LUT (creative) | encoded | uber | LUTs are usually display-referred |
| 15 | Sharpen (luma USM) | encoded | finish | Needs neighbors; after tone |
| 16 | Vignette (paint-overlay style) | encoded | finish | |
| 17 | Grain | encoded | finish | Never sharpen grain |
| 18 | Dither (±0.5/255) → 8-bit display | encoded | finish | Prevents banding |
| H | Histogram from the stage-18 output, downsampled | | readback | |

---

## 6. Performance strategy

### 6.1 Sizes and budgets

- A 24 MP image takes **192 MB** as RGBA16F, 384 MB as RGBA32F and 96 MB as RGBA8. Never keep a full-resolution multi-texture chain resident.
- **Preview:** viewport × devicePixelRatio, capped at about 2560–3840 px on desktop and about 1440–2048 px on phones. 4.4 MP RGBA16F is about 35 MB per texture, roughly 200 MB for the whole chain.
- **1:1 zoom:** render only the visible region from a tile cache of the full-resolution source, with an apron equal to the largest spatial kernel radius.
- **Max texture size (WebGL2 survey):** Android has 77% of devices at ≥8192 and only 4% at ≥16384. iOS has 98% at ≥16384. Overall, 85% are at ≥16384. A 45–61 MP sensor (≥8256 px) **must** be tiled.
- **Export:** tiles of about 2048² plus an apron (≈32–64 px). Global operators come from the shared low-res analysis textures, so there are no seams. Read back each tile, assemble in a worker or isolate, then encode.

### 6.2 Histogram

| Approach | How | Notes |
|---|---|---|
| **CPU readback (recommended baseline; portable to Flutter)** | Downsample the final render to about 256 px, read back RGBA8, bin R/G/B/luma in a worker or isolate | About 65k pixels, under 1–2 ms. Throttle to 10–15 Hz while dragging. Also yields clipping counts and the percentiles for auto-tone and dehaze airlight |
| WebGL2 GPU scatter | `gl.POINTS` with `gl_VertexID` → `texelFetch` → bin position; additive blending into a 256×1 R32F target | Needs EXT_color_buffer_float (99.7%) **and EXT_float_blend (93.6% overall; iOS only 54%)** |
| WebGPU compute | Workgroup-shared atomic bins → global atomics | Fastest. Also enables GPU percentile reduction |

### 6.3 WebGL2 vs WebGPU in 2026 (web-target reference)

| | WebGL2 | WebGPU |
|---|---|---|
| Coverage | Effectively universal | Baseline since Jan 2026: Chrome/Edge 113+ desktop; Android 12+ (Chrome 121) on Adreno 600+/Mali-G78+; **Safari 26** (macOS/iOS/iPadOS/visionOS); Firefox 141 (Windows), 145/147 (macOS). Linux is partial; no Firefox on Android |
| Float targets | RGBA16F renderable + filterable (EXT_color_buffer_float 99.7%). RGBA32F linear filtering needs OES_texture_float_linear (iOS ~46%) | rgba16float in core. `float32-filterable` is optional (iOS 42%, Android 68%) |
| Compute | No (render-to-texture GPGPU) | Compute, storage buffers, atomics |
| Workers | OffscreenCanvas + WebGL (Safari 17+; Ventura caveat) | Yes |
| Color | `drawingBufferColorSpace='display-p3'` (Chrome 104+, Safari 16.4+, Firefox 132+). `unpackColorSpace` is **not in Safari** | Canvas configure colorSpace |

*Rule of thumb (web):* use RGBA16F intermediates, keep the shaders in the portable subset above, and add a WebGPU backend for compute-heavy features.

---

## 7. RAW, HEIC and EXIF (platform-neutral findings)

**RAW**

1. **Instant display:** extract the embedded full-size JPEG preview, with **piex** (Apache-2.0) or LibRaw `unpack_thumb()`. Show it immediately while the real decode runs.
2. **Full decode:** **LibRaw 0.22** (LGPL-2.1 *or* CDDL-1.0). Configure linear output (`gamm = 1/1`), `no_auto_bright`, 16-bit, camera-space output (`output_color=0`) or ProPhoto, plus the camera matrices (`rgb_cam`/`cam_xyz`), `cam_mul`/`pre_mul` and the black/white levels. Do WB and the matrix ourselves so they stay non-destructive and instant. Use `half_size` for a fast first render and AHD/DHT for final quality.
   - **Compliance:** LGPL needs a replaceable, separately linked library, source availability and notices. **CDDL-1.0 is file-level copyleft:** publish only the LibRaw files (and our changes to them), and **static linking is fine**. Choose CDDL where static linking is needed (iOS).
3. **Avoid** dcraw-derived GPL code (dcraw.js), plus RawTherapee and darktable code.
4. **SaaS later:** run LibRaw natively server-side. GPL CLIs run server-side are not "distribution", but keep them out of the product to stay clean. **AGPL is never allowed.**

**HEIC.** HEVC is patent-encumbered. Access Advance waives royalties for application-layer *software* decoders on general-purpose CPUs, but **other pools (Via LA, Technicolor) give no such waiver**. sharp refuses to ship HEVC for this reason. **Prefer OS decoders** (the OS vendor carries the license). Shipping libheif/libde265 (LGPL-3.0) needs a legal review.

**EXIF.** Use `exif` (Dart, MIT) or `exifr` (JS, MIT). Read orientation, camera and lens, ISO, exposure, ICC and XMP (including any existing `crs:` develop settings).

---

## 8. Non-destructive edit data model

### 8.1 How Lightroom does it (what to copy, what to avoid)

- Develop settings are the **`crs:` namespace** (`http://ns.adobe.com/camera-raw-settings/1.0/`), written in `.xmp` sidecars or the catalog. They carry a **`ProcessVersion`** (for example 11.0 for PV2012 and later) that pins rendering behavior, so old edits never change look after an engine upgrade.
- Presets are **sparse**. Omitted settings keep their current value and an explicit 0 resets (RAWmakase verified this on 921 presets).
- The Lightroom Classic catalog (SQLite) stores history in `Adobe_libraryImageDevelopHistoryStep` with **full settings text per step**. Analysis by Points in Focus found history is **about 50% of catalog pages**. **Lesson: store patches, not snapshots.**
- A virtual copy is an independent image record that shares only the underlying file.

### 8.2 Lumen `EditDocument` (versioned JSON)

```jsonc
{
  "schema": "lumen.edit",
  "schemaVersion": 1,                 // data-shape version → migrations
  "engineVersion": "1.0",             // rendering "process version" → pinned per edit
  "assetId": "sha256:9f2c…",          // content hash of the untouched original
  "variantId": "v_01J…",              // 'master' or virtual copy id
  "parentVariantId": null,
  "settings": {
    "wb":    { "mode": "asShot", "temperature": 5500, "tint": 0, "incremental": null },
    "tone":  { "exposure": 0.0, "contrast": 0, "highlights": 0, "shadows": 0, "whites": 0, "blacks": 0 },
    "presence": { "texture": 0, "clarity": 0, "dehaze": 0, "vibrance": 0, "saturation": 0 },
    "curve": {
      "parametric": { "shadows": 0, "darks": 0, "lights": 0, "highlights": 0, "splits": [25, 50, 75] },
      "point": { "master": [[0,0],[255,255]], "red": [[0,0],[255,255]], "green": [[0,0],[255,255]], "blue": [[0,0],[255,255]] }
    },
    "hsl": { "hue": {"red":0,"orange":0,"yellow":0,"green":0,"aqua":0,"blue":0,"purple":0,"magenta":0},
             "sat": {}, "lum": {} },
    "grade": { "shadows": {"h":0,"s":0,"l":0}, "midtones": {"h":0,"s":0,"l":0},
               "highlights": {"h":0,"s":0,"l":0}, "global": {"h":0,"s":0,"l":0}, "blending": 50, "balance": 0 },
    "detail": { "sharpen": {"amount":40,"radius":1.0,"detail":25,"masking":0},
                "nr": {"luminance":0,"lumDetail":50,"lumContrast":0,"color":25,"colorDetail":50,"colorSmoothness":50} },
    "effects": { "vignette": {"amount":0,"midpoint":50,"roundness":0,"feather":50,"highlights":0,"style":"highlightPriority"},
                 "grain": {"amount":0,"size":25,"roughness":50,"seed":0} },
    "lut": null,                      // { "assetId": "...", "amount": 1.0, "inputSpace": "srgb" }
    "geometry": { "crop": [0,0,1,1], "angle": 0, "flipH": false, "orientation": 1, "aspect": "original" },
    "profile": { "name": "Lumen Standard" },
    "masks": []                       // future: local adjustments { mask:{type,...}, settings:{sparse} }
  },
  "history": { "cursor": 3, "entries": [
    { "id": "h3", "label": "Exposure +0.70", "at": "2026-10-03T10:00:00Z",
      "patch":   [{ "op": "replace", "path": "/settings/tone/exposure", "value": 0.7 }],
      "inverse": [{ "op": "replace", "path": "/settings/tone/exposure", "value": 0.0 }] }
  ]},
  "snapshots": [ { "id": "s1", "name": "Before grade", "settings": { /* full copy */ } } ],
  "createdAt": "…", "updatedAt": "…"
}
```

**Rules**

- **Undo/redo:** use RFC 6902 forward and inverse patches with a cursor. **Coalesce a slider drag into one entry** on pointer-up. A new edit after undo truncates the redo tail.
- **Virtual copy:** a new variant document with the same `assetId` and a copy of `settings` (history optional).
- **Snapshot:** a named immutable full `settings` copy (rare and small).
- **Preset:** `{ name, group, uuid, version, supports:{color,mono,raw,nonRaw}, amountSupported, settings: DeepPartial<Settings> }`, applied as a sparse merge. "Amount" interpolates numeric fields between current and preset values.
- **Versioning:** `schemaVersion` drives migrations. `engineVersion` is **never** silently upgraded; offer "Update to current engine" the way Lightroom's process-version prompt does.
- **Storage (Flutter):** a local SQLite catalog (Drift or sqlite3), with originals referenced by path plus content hash and previews in an app cache directory. Cloud sync can come later.

### 8.3–8.5 Lightroom XMP import mapping (bonus)

Parse with namespace awareness. Settings can appear as **attributes or child elements**. Curves are `rdf:Seq` lists of `"x, y"` strings on a 0–255 scale.

| `crs:` key | Lumen field | Notes |
|---|---|---|
| `ProcessVersion`, `Version` | info | Warn if PV < 10 (PV2012 semantics assumed) |
| `WhiteBalance` (As Shot/Auto/Custom), `Temperature`, `Tint` | `wb.*` | RAW Kelvin |
| `IncrementalTemperature`, `IncrementalTint` | `wb.incremental` | Non-RAW (−100..100) |
| `Exposure2012`, `Contrast2012`, `Highlights2012`, `Shadows2012`, `Whites2012`, `Blacks2012` | `tone.*` | |
| `Texture`, `Clarity2012`, `Dehaze`, `Vibrance`, `Saturation` | `presence.*` | |
| `ToneCurvePV2012`, `…Red/Green/Blue` | `curve.point.*` | Extend missing endpoints |
| `ParametricShadows/Darks/Lights/Highlights`, `ParametricShadowSplit/MidtoneSplit/HighlightSplit` | `curve.parametric` | |
| `HueAdjustment{Red…Magenta}`, `SaturationAdjustment…`, `LuminanceAdjustment…` | `hsl.*` | 8 bands |
| `SplitToningShadowHue/Saturation` | `grade.shadows.h/s` | Shadows and highlights **hue/sat live in SplitToning keys** |
| `ColorGradeShadowLum` | `grade.shadows.l` | |
| `ColorGradeMidtoneHue/Sat/Lum` | `grade.midtones` | |
| `SplitToningHighlightHue/Saturation`, `ColorGradeHighlightLum` | `grade.highlights` | |
| `ColorGradeGlobalHue/Sat/Lum`, `ColorGradeBlending`, `SplitToningBalance` | `grade.global`, `blending`, `balance` | Legacy split-toning without ColorGrade keys implies Blending 100 |
| `Sharpness`, `SharpenRadius`, `SharpenDetail`, `SharpenEdgeMasking` | `detail.sharpen` | |
| `LuminanceSmoothing`, `LuminanceNoiseReductionDetail/Contrast`, `ColorNoiseReduction`, `…Detail`, `…Smoothness` | `detail.nr` | |
| `PostCropVignetteAmount/Midpoint/Feather/Roundness/Style/HighlightContrast` | `effects.vignette` | |
| `GrainAmount`, `GrainSize`, `GrainFrequency` (roughness), `GrainSeed` | `effects.grain` | |
| `ConvertToGrayscale` | `profile.mono` | |
| `HasCrop`, `CropTop/Left/Bottom/Right/Angle` | `geometry` | |
| `CameraProfile`, `Look` (struct: Name, Amount, Parameters), `RGBTable`, `LookTable` | `profile` | Adobe profiles and creative RGB tables can't be reproduced. **Report them, don't fake them** |
| `MaskGroupBasedCorrections`, `RetouchAreas`, `PointColors` | (future) | Report as unsupported in v1 |

---

## 9. Flutter implementation (current stack: Flutter 3.47, Impeller)

### 9.1 `FragmentProgram` / `FragmentShader`: dialect, limits, multi-pass, LUTs

**Dialect.** GLSL from `#version 460 core` down to 100, compiled ahead of time by **impellerc**. Every shader needs `#include <flutter/runtime_effect.glsl>`, should use `FlutterFragCoord()` (not `gl_FragCoord`) and writes `out vec4 fragColor`, which must be **premultiplied**. Shaders are declared under `flutter: shaders:` in `pubspec.yaml` and loaded with `FragmentProgram.fromAsset`.

**Documented limitations (official docs):**

- No UBOs or SSBOs.
- **`sampler2D` is the only sampler type**, so there is no `sampler3D` and no `usampler`.
- Only two-argument `texture(sampler, uv)` is allowed: no `texelFetch`, no LOD or bias variants.
- No extra varyings.
- Precision hints are ignored on Skia (web).
- **No unsigned ints and no bools**, so use float hashes (§4.13).
- Custom tile modes aren't supported (clamp only).
- On OpenGL ES, flip `uv.y` under `#ifdef IMPELLER_TARGET_OPENGLES`.

**Uniforms.** The documented types are `float`, `vec2/3/4` (set one component at a time with `setFloat` or `getUniformFloat(name, i)`) and `sampler2D` (via `setImageSampler`). Float and sampler indices are counted separately.

- **Matrices and arrays:** pass them as `vec3`/`vec4` rows (§3, §4.7). Matrix and array uniforms aren't in the current type list, so don't rely on them.
- **Uniform count:** no hard limit is documented. Check the reflection output with `impellerc --runtime-stage-metal … | flatc --json`. The uber shader above needs about 40 vec4s, well within the 224-vec4 WebGL2 minimum that applies on web.
- **Derivatives (`dFdx`/`fwidth`)** aren't in the supported list. **Avoid them.** All snippets in §3–4 already do.
- **Loops:** use constant bounds. SkSL (web) requires them.

**Sampling gotcha.** `setImageSampler(int index, Image image, {FilterQuality filterQuality = FilterQuality.none})` defaults to **nearest**. Pass `FilterQuality.low` (bilinear) for LUTs, the analysis textures (guided base, transmission, blur) and the source.

**Multi-pass chaining (blur, guided filter, clarity).** Each pass renders to a `ui.Image`:

```dart
ui.Image runPass(ui.FragmentShader s, int w, int h,
                 {ui.TargetPixelFormat fmt = ui.TargetPixelFormat.rgbaFloat32}) {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..shader = s);
  final pic = rec.endRecording();
  final img = pic.toImageSync(w, h, targetFormat: fmt);   // GPU-resident, no CPU roundtrip
  pic.dispose();
  return img;   // caller disposes when the cache entry is evicted
}
// blurH: s.setImageSampler(0, src, filterQuality: FilterQuality.low); s.setFloat(..dir..)
// final blurred = runPass(blurV..setImageSampler(0, runPass(blurH, w, h)), w, h);
```

- `Picture.toImageSync(w, h, {targetFormat})` accepts `TargetPixelFormat.rgbaFloat32` (or `rFloat32` for single-channel log-luminance). **Use float targets for all intermediates.** Log values are negative and the guided filter's variance needs precision; the default `dontCare` format is typically 8-bit and causes banding. Float support per backend is **not documented**. Verify on Metal, Vulkan and GLES (Android fallback), and on web (CanvasKit/skwasm, where it likely falls back). As a fallback, encode log Y as `(L+16)/20` into 8-bit for the base only.
- Images from `toImageSync` are GPU-resident. Cache them per stage (§2) and `dispose()` them deliberately; GPU memory is the scarce resource.
- `ImageFilter.shader(...)` (Impeller only, **not on web**) can apply the finish pass directly to the viewport widget. The canvas `Paint.shader` path works on every backend.
- `package:shader_buffers` (Apache-2.0) is a ready-made multi-pass, Shadertoy-style buffer chain, and `flutter_shaders` (BSD-3) provides `ShaderBuilder`/`AnimatedSampler` helpers. Both are good references for this plumbing.

**1D curve LUT.** Bake on the CPU into a `Float32List` of size N×1×4 (r = master or composite tone, g/b free, or use r,g,b for per-channel curves). Upload with `ui.decodeImageFromPixels(bytes, N, 1, ui.PixelFormat.rgbaFloat32, cb, targetFormat: ...)`, or `rgba8888` if float pixel upload isn't available on a backend. Sample at `vec2((x*(N-1)+0.5)/N, 0.5)` with `FilterQuality.low`. This is exactly `toneLUT()` / `rgbCurves()` in §4.6.

**3D LUT as a 2D strip.** Lay N slices of N×N side by side along x, giving an (N·N)×N image: `x = r + b·N`, `y = g`. This maps directly from the `.cube` order (red fastest, then green, then blue). Interpolate manually: bilinear inside a slice comes from the hardware, and blue is interpolated between two slices.

```glsl
uniform sampler2D uLut2D;  // (N*N) x N, FilterQuality.low
uniform vec2 uLutN;        // x = N, y = amount
vec3 lut3D(vec3 c) {       // c = encoded 0..1 (after DOMAIN remap on CPU)
  float N = uLutN.x;
  c = clamp(c, 0.0, 1.0);
  float b = c.b * (N - 1.0);
  float b0 = floor(b), b1 = min(b0 + 1.0, N - 1.0), fb = b - b0;
  float u = (c.r * (N - 1.0) + 0.5);                 // texel-center within slice
  float v = (c.g * (N - 1.0) + 0.5) / N;
  vec3 s0 = texture(uLut2D, vec2((u + b0 * N) / (N * N), v)).rgb;
  vec3 s1 = texture(uLut2D, vec2((u + b1 * N) / (N * N), v)).rgb;
  return mix(c, mix(s0, s1, fb), uLutN.y);
}
```

A 33³ LUT is 1089×33 and a 65³ LUT is 4225×65, both under every max texture size. Store it as float when possible; 8-bit is acceptable for 33³ creative LUTs, but add dithering.

### 9.2 Platform support (2026)

| Platform | Renderer | Fragment shaders | Notes |
|---|---|---|---|
| **iOS** | Impeller (Metal); Skia removed in 3.29 | ✅ | Wide-gamut (P3) capable |
| **macOS** | **Impeller default since 3.47** (Metal) | ✅ | Opt out with `--no-enable-impeller` |
| **Android** | Impeller (Vulkan; GLES fallback); default on API 29+ since 3.27; opt-out deprecated in 3.38 | ✅ | Handle the GLES uv.y flip. Test float render targets on Mali/Adreno |
| **Windows** | **Impeller default since 3.47** (Vulkan) | ✅ | Can be disabled in `windows/runner/main.cpp` (`ImpellerSwitch::Disabled`) |
| **Web** | CanvasKit (dart2js, all browsers) or skwasm (dart2wasm, Blink only); HTML renderer removed in 3.29 | ✅ via SkSL translation (canvas `Paint.shader`); ❌ `ImageFilter.shader` (Impeller-only) | Precision hints ignored. Treat as secondary |

**Flutter GPU** (`flutter_gpu`, BSD-3) is a low-level Impeller HAL API in "early preview, no API stability" that requires Impeller. Revisit it later for true multi-target or compute work. Don't build v1 on it.

### 9.3 Histogram and full-resolution export in Dart

**Histogram**

1. After the finish pass, run a cheap downsample shader into about 256×N px (`toImageSync`, `rgba8888`).
2. `await img.toByteData(format: ui.ImageByteFormat.rawRgba)`.
3. Bin in `Isolate.run(...)` or `compute()`. Pass `TransferableTypedData` to avoid copies. 256×170 pixels takes under about 2 ms, so the main isolate is also fine at 10–15 Hz.
4. Produce R, G, B and luma bins, clipping counts (≥254 / ≤1) and the percentiles used by auto-tone, the shadows/highlights keys and the dehaze airlight.

GPU scatter isn't possible with fragment-only shaders, and a gather shader (256 output texels × fixed-count loop) works but brings no benefit at this size.

**Full-resolution export (tiled)**

1. Keep the decoded source in CPU memory (Float32 or Uint16 linear). Split it into tiles of about 2048² plus an apron.
2. Upload each tile with `decodeImageFromPixels(..., PixelFormat.rgbaFloat32)`. Run the **same** pass chain with tile-offset uniforms, so analysis textures are sampled at global uv. Read back with `toByteData(format: ImageByteFormat.rawExtendedRgba128)` (float) for 16-bit output, or `rawRgba` for 8-bit.
3. Crop the apron and copy into a full-frame `Uint8List`/`Uint16List` in an isolate.
4. **Encode:**
   - **JPEG/HEIC:** platform encoders (ImageIO on Apple, `Bitmap.compress` on Android, WIC on Windows), via `flutter_image_compress` (MIT) or a small FFI/plugin. They are much faster than pure Dart.
   - **16-bit TIFF/PNG:** `package:image` (MIT, pure Dart) in an isolate. It is slower, but it's the only cross-platform 16-bit path.
   - **Metadata:** copy EXIF and embed the ICC profile (sRGB, P3 or Adobe RGB). Strip the old thumbnail and maker-note offsets.
5. Show progress per tile and support cancellation.

### 9.4 Image decoding in Flutter

| Format | Path | License |
|---|---|---|
| JPEG / PNG / WebP / GIF / BMP | Built into the engine (`instantiateImageCodec`), 8-bit. For 16-bit PNG/TIFF use `package:image` (MIT) | engine BSD-3 / image MIT |
| **HEIC/HEIF** | Not built into the Flutter codec. Use **OS decoders** through `heic2png` (MIT; iOS, macOS, Android 9+, Windows, Linux) or `platform_image_converter` (MIT; ImageIO/BitmapFactory/WIC). Windows needs Microsoft's HEIF/HEVC extensions | MIT wrappers. HEVC patents are covered by the OS vendor |
| **RAW, fast** | Embedded JPEG preview via **piex** (Apache-2.0, C++ over FFI) or LibRaw `unpack_thumb()` | Apache-2.0 |
| **RAW, full (Apple)** | **ImageIO / Core Image `CIRAWFilter`** through a small platform channel. Apple's own RAW engine returns linear float output for the supported camera list | OS API |
| **RAW, full (Android/Windows; also Apple fallback)** | **LibRaw via `dart:ffi`**. `flutter_libraw` (MIT wrapper, v0.0.2, very early) is a starting point; plan to own the binding. Use **CDDL-1.0** for static linking on iOS | ⚠️ LGPL-2.1 / CDDL-1.0 |
| **EXIF** | **`exif`** (pub, MIT; JPEG/TIFF/HEIC/RAW-TIFF containers), `native_exif` (MIT; iOS/Android native), `exif_reader` (MIT) | MIT |

Use `file_picker` (MIT) or `image_picker` (Apache-2.0 / BSD-3) to import, and `photo_manager` (Apache-2.0) for library access.

### 9.5 Open-source Flutter photo editors and shader repos

| Package / repo | License | Pub likes / stars | What it is | Borrow? |
|---|---|---|---|---|
| **pro_image_editor** (hm21/pro_image_editor) | ✅ BSD-3 | 594 likes / 392★, 2026-10 | Full editor UI: crop/rotate, paint, text, emoji, stickers, filters, "tune" (brightness/contrast/saturation), blur. All six platforms | **UI and UX shell** (crop, paint, layers, desktop UX). Its color adjustments are `ColorFilter` matrices (8-bit, not linear), so **not the engine** |
| image_editor_plus | ✅ MIT | 318 likes | Simpler editor UI | Light reference |
| image_editor (fluttercandies) | ✅ Apache-2.0 | 370 likes / 452★ | Native crop/flip/rotate/color-matrix plugin | Export-time geometry ideas |
| `image` (brendan-duncan) | ✅ MIT | 1758 likes / 1.3k★ | Pure-Dart decode/encode/filters | **16-bit TIFF/PNG encoding**, CPU fallback |
| flutter_shaders (jonahwilliams) | ✅ BSD-3 | 127★ | `FragmentProgram` utilities | Plumbing patterns |
| shader_buffers | ✅ Apache-2.0 | 60 likes | Multi-pass shader buffer chains | **Multi-pass pattern** |
| crop_your_image / extended_image | ✅ Apache-2.0 / MIT | 583 / 2030 likes | Crop and zoom-pan viewers | Viewer and crop widgets |
| flutter_image_compress | ✅ MIT | 1824 likes | Native encoders | Export encoding |
| photofilters, colorfilter_generator | ✅ MIT | n/a | Matrix "Insta" filters | Not useful for pro-grade editing |
| flutter_gpu | ✅ BSD-3 | preview | Low-level Impeller API | Watch |

**Bottom line for Flutter:**

- Use **pro_image_editor** for chrome and tools if helpful.
- Build the **engine** as our own `FragmentProgram` render graph, with the math from §3–5 and kernels ported from vkdt (BSD-2) and the DNG SDK, plus RAWmakase's measured parity data (MIT).
- Use OS decoders for HEIC and Apple RAW, LibRaw (CDDL) via FFI elsewhere, piex for previews, the `exif` package for metadata and platform encoders for export.

---

## 10. Licensing risk register

| Risk | Severity | Mitigation |
|---|---|---|
| Copying RapidRAW (AGPL), darktable/RawTherapee/ART/Filmulator/OpenDRT (GPL) code | **High** | Clean-room: read for ideas, write our own. Note provenance in PRs |
| vkdt files that are GPLv3 (OpenDRT, parts of `oetf.glsl`, hdrmerge) | Medium | Check each file header before porting |
| LibRaw (LGPL/CDDL), libheif (LGPL-3.0) | Medium | Separate module, notices, publish source of those libraries and any changes. Prefer CDDL for LibRaw static linking |
| HEVC patents (HEIC decode) | Medium | Use OS decoders. Legal review before bundling libde265 |
| Repos with no license (`ybouane/LibRaw-Wasm`) | Medium | Don't copy |
| Measured Adobe parity tables (RAWmakase, MIT) | Low | They are functional measurements under MIT. Attribute, and run a counsel check |
| DNG SDK ports | Low | Keep Adobe notices (license requires it) |
| Algorithm patents (dark channel prior US8340461B2 lapsed for fees; guided-filter derivatives exist, e.g. US9286663B2) | Low–Med | Quick freedom-to-operate search before launch |
| "Lumen" name collision | Medium (brand) | Trademark search |

---

## 11. Sources

**Engines and repos:** [RAWmakase](https://github.com/pch/rawmakase) (docs: tone-controls, color-mixer, color-pipeline, xmp-presets, parity-gaps, preview-performance) · [vkdt](https://github.com/hanatos/vkdt) · [RapidRAW](https://github.com/CyberTimon/RapidRAW) · [darktable](https://github.com/darktable-org/darktable) · [RawTherapee](https://github.com/RawTherapee/RawTherapee) · [ART](https://github.com/artraweditor/ART) · [Filmulator](https://github.com/CarVac/filmulator-gui) · [glfx.js](https://github.com/evanw/glfx.js) · [Filerobot](https://github.com/scaleflex/filerobot-image-editor) · [tui.image-editor](https://github.com/nhn/tui.image-editor) · [miniPaint](https://github.com/viliusle/miniPaint) · [Photon](https://github.com/silvia-odwyer/photon) · [PixiJS filters](https://github.com/pixijs/filters) · [mini-photo-editor](https://github.com/xdadda/mini-photo-editor) / [mini-gl](https://github.com/xdadda/mini-gl) · [Graphite/rawkit](https://github.com/GraphiteEditor/Graphite) · [LightZone](https://github.com/ktgw0316/LightZone) · [PhotoDemon](https://github.com/tannerhelland/PhotoDemon) · [Khronos ToneMapping](https://github.com/KhronosGroup/ToneMapping) · [open-display-transform](https://github.com/jedypod/open-display-transform) · [LumenPhotoStudio](https://github.com/kachamo/LumenPhotoStudio)

**Color and algorithms:** [DNG SDK mirror (dng_render.cpp, dng_reference.cpp, dng_temperature.cpp)](https://android.googlesource.com/platform/external/dng_sdk/) · [Adobe DNG page](https://helpx.adobe.com/camera-raw/desktop/dng-and-file-formats/digital-negative.html) · [Oklab (Ottosson)](https://bottosson.github.io/posts/oklab/) · [Guided Image Filtering (He et al.)](https://people.csail.mit.edu/kaiming/eccv10/index.html) · [Dark channel prior paper](https://people.csail.mit.edu/kaiming/publications/pami10dehaze.pdf) · [US8340461B2](https://patents.google.com/patent/US8340461) · [US9286663B2](https://patents.google.com/patent/US9286663) · [Local Laplacian Filters (Paris et al.)](https://people.csail.mit.edu/sparis/publi/2011/siggraph) · [Fast Local Laplacian (Aubry et al.)](https://imagine.enpc.fr/~aubrym/projects/llf/supplementary_material/additional_results.html)

**Formats and metadata:** [Adobe XMP crs namespace](https://developer.adobe.com/xmp/docs/xmp-namespaces/crs/) · [ExifTool XMP tags](https://exiftool.org/TagNames/XMP.html) · [ExifToolGui field list](https://github.com/FrankBijnen/ExifToolGui) · [Points in Focus: Lightroom catalog analysis](https://www.pointsinfocus.com/blog/2016/05/lightroom-8-years-later-a-critical-look-at-virtual-copies) · [Cube LUT discussion](https://forum.blackmagicdesign.com/viewtopic.php?p=232952)

**Decoders and licenses:** [LibRaw](https://www.libraw.org/) · [LibRaw GitHub](https://github.com/LibRaw/LibRaw) · [ybouane/LibRaw-Wasm](https://github.com/ybouane/LibRaw-Wasm) · [ssssota/libraw.wasm](https://github.com/ssssota/libraw.wasm) · [libheif](https://github.com/strukturag/libheif) · [libheif-js](https://github.com/catdad-experiments/libheif-js) · [heic2any](https://github.com/alexcorvi/heic2any) · [heic-to](https://github.com/hoppergee/heic-to) · [exifr](https://github.com/MikeKovarik/exifr) · [piex](https://github.com/google/piex) · [dnglab](https://github.com/dnglab/dnglab) · [rawloader](https://github.com/pedrocr/rawloader) · [rawspeed](https://github.com/darktable-org/rawspeed) · [dcraw.js](https://github.com/zfedoran/dcraw.js) · [sharp HEIF/HEVC stance](https://github.com/lovell/sharp/issues/1105) · [Access Advance HEVC licensing](https://accessadvance.com/topic-what-do-we-license/) · [HEVC Advance software royalty waiver](https://blog.beamr.com/2016/11/30/patent-pool-hevc-advance-responds-announces-royalty-free-hevc-software/) · [Chrome HEIC status](https://www.testmuai.com/learning-hub/heif-browser-support/) · [JPEG XL in Chrome 145](https://www.phoronix.com/news/Chrome-145-Released)

**GPU and web platform:** [WebGPU implementation status](https://github.com/gpuweb/gpuweb/wiki/implementation-status) · [Frontier Web APIs 2026](https://www.utsubo.com/blog/frontier-web-apis-2026-production-ready) · [EXT_color_buffer_float](https://web3dsurvey.com/webgl2/extensions/EXT_color_buffer_float) · [OES_texture_float_linear](https://web3dsurvey.com/webgl2/extensions/OES_texture_float_linear) · [EXT_float_blend](https://web3dsurvey.com/webgl2/extensions/EXT_float_blend) · [MAX_TEXTURE_SIZE](https://web3dsurvey.com/webgl2/parameters/MAX_TEXTURE_SIZE) · [WebGPU float32-filterable](https://web3dsurvey.com/webgpu/features/float32-filterable) · [WebGL2 histogram Q&A](https://webgl2fundamentals.org/webgl/lessons/webgl-qna-how-can-i-create-a-16bit-historgram-of-16bit-data.html) · [drawingBufferColorSpace (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/WebGLRenderingContext/drawingBufferColorSpace) · [unpackColorSpace (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/WebGLRenderingContext/unpackColorSpace) · [OffscreenCanvas (web.dev)](https://web.dev/articles/offscreen-canvas) · [Float16Array (MDN)](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Float16Array)

**Flutter:** [Fragment shaders guide](https://docs.flutter.dev/ui/design/graphics/fragment-shaders) · [setImageSampler](https://api.flutter.dev/flutter/dart-ui/FragmentShader/setImageSampler.html) · [Picture.toImageSync](https://api.flutter.dev/flutter/dart-ui/Picture/toImageSync.html) · [TargetPixelFormat](https://api.flutter.dev/flutter/dart-ui/TargetPixelFormat.html) · [Flutter 3.47 Impeller default on desktop](https://startdebugging.net/2026/08/flutter-3-47-impeller-default-renderer-on-desktop/) · [Impeller mandatory on iOS/Android](https://ecorpit.com/impeller-mandatory-flutter-android-ios-2026/) · [Flutter GPU](https://flutter.googlesource.com/mirrors/flutter/+show/HEAD/docs/engine/impeller/Flutter-GPU.md) · [Web renderers](https://docs.flutter.dev/platform-integration/web/renderers.html) · [CanvasKit vs skwasm 2026](https://startdebugging.net/2026/09/canvaskit-vs-skwasm-for-flutter-web-in-2026/) · [pro_image_editor](https://github.com/hm21/pro_image_editor) · [image](https://github.com/brendan-duncan/image) · [flutter_image_editor](https://github.com/fluttercandies/flutter_image_editor) · [flutter_shaders](https://github.com/jonahwilliams/flutter_shaders) · [heic2png](https://pub.dev/packages/heic2png) · [platform_image_converter](https://pub.dev/packages/platform_image_converter) · pub.dev license tags for `exif`, `native_exif`, `exif_reader`, `flutter_libraw`, `shader_buffers`, `image_editor_plus`, `flutter_image_compress`, `crop_your_image`, `extended_image`, `photo_manager`, `file_picker`, `image_picker`, `flutter_gpu` (queried 2026-10-03)
