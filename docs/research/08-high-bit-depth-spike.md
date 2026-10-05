# 08 · High-bit-depth spike: what Impeller can carry

Date: 2026-10-04 · Flutter 3.47.2 / Dart 3.13.2 · engine a804b26164 ·
macOS 26.4.1, Apple M1 Max, 64 GB · Impeller on Metal.

**Verdict.** Impeller carries 32-bit float RGBA end to end. A float image can
be uploaded, sampled by a `FragmentProgram` at full precision, rendered into a
float offscreen target with `Picture.toImageSync(targetFormat:
TargetPixelFormat.rgbaFloat32)`, chained through further passes and read back
with `ImageByteFormat.rawExtendedRgba128`. Measured on the real GPU: two passes
keep 1 048 576 of 1 048 576 ramp levels with zero error, values above 1.0 and
below 0 survive, and nothing converts or clamps colour on the way. A true
high-bit-depth RAW pipeline is feasible inside the existing pass architecture;
the fallbacks in question 8 are not needed on macOS.

Three traps were found (details below): `decodeImageFromPixelsSync` silently
gives 8 bits (or fails), the default upload target is half float rather than
float32, and the default headless `flutter test` (Skia) is 8-bit between passes.

All SDK paths are relative to `/Users/fvm/development/flutter/`. `ui/` means
`bin/cache/pkg/sky_engine/lib/ui/`, `eng/` means `engine/src/flutter/`.

## How it was measured

| What | File |
|---|---|
| On-GPU experiments | `app/integration_test/zz_hbd_spike_test.dart` |
| Spike shader (3 uniform declarations) | `app/shaders/spike_passthrough.frag` |
| Same experiments in headless `flutter_tester` | `app/test/zz_hbd_spike_headless_test.dart` |

```
cd app
flutter test integration_test/zz_hbd_spike_test.dart -d macos          # real Metal
flutter test test/zz_hbd_spike_headless_test.dart                      # headless Skia
flutter test --enable-impeller test/zz_hbd_spike_headless_test.dart    # headless Impeller
```

Test images: a ramp where pixel *i* holds R = i/(n-1), with n = 65 536
(256×256) and n = 1 048 576 (1024×1024); an 8-pixel strip of extended values
(4.0, -0.5, 1000, 1e-5, 131008, 0.18, 1, 0); and a synthetic scene with a
highlight up to 6.0 for the cost runs. "Levels" = distinct R values read back.
The integration test runs a debug (JIT) build; GPU and engine-side timings are
not affected by that, Dart loops are (AOT numbers are given separately).

Native CoreImage and AOT Dart timings came from two throwaway scripts kept
outside the repo (scratchpad); their numbers are quoted in 6 and 8.

## 1. Input: creating a `ui.Image` from high-precision pixels

**API surface.** `ui.PixelFormat` has `rgba8888`, `bgra8888`, `rgbaFloat32`,
`rFloat32` (`ui/painting.dart:1913-1932`). There is no 16-bit integer and no
half-float *input* format. `ui.TargetPixelFormat` has `dontCare`,
`rgbaFloat32`, `rFloat32` (`ui/painting.dart:1936-1945`) and is accepted by
`decodeImageFromPixels` (`:2700`), `ImageDescriptor.instantiateCodec`
(`:9025`) and `Picture.toImageSync` (`:8479-8483`).

**What the engine does with it** (Impeller):

- Float input is declared straight-alpha, sRGB-tagged
  (`eng/lib/ui/painting/image_descriptor.cc:160-169`).
- `targetFormat: dontCare` → F32 is converted to **half float**:
  `ChooseCompatibleColorType(kRGBA_F32) = kRGBA_F16`
  (`eng/lib/ui/painting/image_decoder_impeller.cc:96-99`), texture format
  `kR16G16B16A16Float` (`:297-298`).
- `targetFormat: rgbaFloat32` → stays float32, `kR32G32B32A32Float`
  (`:109-117`, `:301-302`).
- `rFloat32` → `rFloat32` is a zero-copy path (`:269-285`, fast path from `:355`).
- Alpha is premultiplied on upload (`HandlePremultiplication`, `:202-222`).
- Source and destination are both tagged sRGB, so the conversion is a pure
  format change: no gamut or transfer conversion (`:128-137`).

**Measured on Metal** (`rawUnmodified` readback reveals the texture's own
storage):

| Upload | Texture | `colorSpace` | 65 536-level ramp | 1 048 576-level ramp |
|---|---|---|---|---|
| `rgbaFloat32`, target `dontCare` | 8 B/px (half) | `extendedSRGB` | 7 169 levels, max err 2.44e-4 | 11 265 levels, max err 2.44e-4 |
| `rgbaFloat32`, target `rgbaFloat32` | 16 B/px | `sRGB` | 65 536, err 0 | 1 048 576, err 0 |
| `rFloat32` → `rFloat32` | single channel | | 65 536, err 0 (range -1..7 kept) | |
| `decodeImageFromPixelsSync(rgbaFloat32)` | **fails: "Image was null"** | | | |

Half float has a 10-bit mantissa: 1024 levels per stop at every brightness.
The max error of 2.44e-4 is half a step in the top stop (0.5..1.0).

Extended range straight through upload and readback:

| In | 4.0 | -0.5 | 1000 | 1e-5 | 131008 | 0.18 |
|---|---|---|---|---|---|---|
| target `dontCare` (half) | 4.0 | -0.5 | 1000 | 1.001358e-5 | **Infinity** | 0.1800537 |
| target `rgbaFloat32` | 4.0 | -0.5 | 1000 | 1e-5 | 131008 | 0.18 |

Values above 1.0 and negative values are kept by both. Half float overflows to
infinity above 65 504, which is irrelevant for photos (a RAW highlight is a few
units at most).

**Trap: `decodeImageFromPixelsSync`.** It accepts `PixelFormat.rgbaFloat32`
but uploads through a snapshot path whose texture format is hard-coded to
`kR8G8B8A8UNormInt` (`eng/shell/common/snapshot_controller_impeller.cc:191`,
reached from `eng/lib/ui/painting/pixel_deferred_image_gpu_impeller.cc:123-124`).
On Metal the float image came back null; on headless Impeller it produced a
4 B/px texture with 256 levels. Do not use it for float data.

## 2. Sampling in a FragmentProgram

A `sampler2D` bound with `setImageSampler` returns the texture's full
precision, unclamped. Measured on Metal, one pass-through pass into a float32
target:

| Source texture | Levels out (of 65 536 / 1 048 576) | Max error |
|---|---|---|
| float32 upload | 65 536 / 1 048 576 | 0 |
| half upload | 7 169 / 11 265 (= what the texture holds) | 2.44e-4 |
| 8-bit image, bytes (128, 64, 191) | reads 0.5019608, 0.2509804, 0.7490196 | exact |

Bilinear filtering works on both float formats on this GPU: a 2×1 texture
(0, 2) stretched to 8 px with `FilterQuality.low` gives 0, 0, 0.25, 0.75,
1.25, 1.75, 2, 2. Whether float32 is filterable on other GPUs is a
portability risk (section 7).

A float upload with rgb 0.8, alpha 0.5 is seen by the shader as 0.4
(premultiplied). Keep alpha at 1.0 for photo data.

## 3. Render targets

`Picture.toImageSync(w, h, targetFormat:)` is the only way to get a float
offscreen target from Dart:

- `ui/painting.dart:8479-8483`; native switch in
  `eng/lib/ui/painting/picture.cc:52-74`; mapped to
  `kR32G32B32A32Float` / `kR32Float` in
  `eng/shell/common/snapshot_controller_impeller.cc:51-63`.
- `Picture.toImage` (async, `ui/painting.dart:8456`) and `Scene.toImageSync`
  (`ui/compositing.dart:16`) take no format: 8-bit.
- There is **no half-float render target** option. The choice is 8-bit
  (`dontCare`) or float32.
- A float target is created without MSAA
  (`eng/impeller/display_list/dl_dispatcher.cc:1216-1218`, `:1245-1273`) and
  always with a full mip chain (`snapshot_controller_impeller.cc:64-67`,
  `generate_mips=true`), so it costs 16 × 4/3 = 21.3 B/px on the GPU.

**Measured on Metal: image → shader → toImageSync → shader → toImageSync**,
65 536-level and 1 048 576-level ramps (results identical in pattern):

| Upload | Target of both passes | Result storage | Two passes ×1 | Two passes -4 EV then +4 EV |
|---|---|---|---|---|
| float32 | `rgbaFloat32` | 16 B/px | **65 536 / 1 048 576 levels, err 0** | **65 536 / 1 048 576 levels, err 0** |
| half | `rgbaFloat32` | 16 B/px | 7 169 / 11 265 (source-limited), err 2.44e-4 | same, nothing further lost |
| float32 | `dontCare` | 4 B/px | 256 levels, err 0.5 of an 8-bit step | **17 levels**, err 8 of an 8-bit step |
| half | `dontCare` | 4 B/px | 256 levels | 17 levels |

The last column is the banding the user wants gone: pulling exposure down four
stops and back through an 8-bit intermediate leaves 17 levels; through a
float32 intermediate it is lossless.

`TargetPixelFormat.rFloat32` also works as a target (65 536 levels when
resampled into an RGBA float target; G and B read 0). It cannot be read back
directly: `toByteData` throws "Failed to get color type from pixel format"
(no R32F entry in `eng/lib/ui/painting/image_encoding_impeller.cc:21-37`).
Useful for single-channel maps (masks, log-luma) at 4 B/px with float
precision.

## 4. Readback

`eng/lib/ui/painting/image_encoding.cc:223-236`. Measured on a float32 image
(from upload and from `toImageSync`):

| `ImageByteFormat` | Result |
|---|---|
| `rawExtendedRgba128` | 16 B/px, float32 straight alpha, **exact, extended range kept** |
| `rawUnmodified` | the texture's own format: 16 B/px for float32, 8 B/px (half) for a default float upload, 4 B/px for an 8-bit target |
| `rawRgba`, `rawStraightRgba` | 4 B/px, 8-bit |
| `png` | 8-bit PNG |

`rawExtendedRgba128` works on images produced by `toImageSync` on Impeller
(every float measurement in this document went through it). There is no 16-bit
integer readback; convert the floats in Dart for a 16-bit TIFF/PNG export.

## 5. Colour, clamping, extended range between passes

No implicit colour conversion or clamping was observed anywhere on Impeller.

| Path, input (0.5, 0.25, 0.75) float | Output |
|---|---|
| upload → readback | 0.5, 0.25, 0.75 |
| upload → shader → float32 target | 0.5, 0.25, 0.75 |
| upload → `drawImage` → float32 target | 0.5, 0.25, 0.75 |
| upload → shader → 8-bit target | bytes 128, 64, 191 (a linear→sRGB conversion would give 188, 137, 225) |
| upload → `drawImage` → 8-bit target | bytes 128, 64, 191 |

So a float texture is neither "linear" nor "sRGB" to Impeller: the numbers are
passed through as written. The `colorSpace` getter reports `extendedSRGB` for
half-float images and `sRGB` for float32 ones
(`image_encoding_impeller.cc:262-275`), but that label changed no pixel value
in any test. The encoding is entirely the app's convention.

**The 4.0 × 0.25 test** (pass 1 ×1 into the intermediate, pass 2 ×0.25 into
float32), on Metal:

| Intermediate | 4.0 | -0.5 | 1000 | 1e-5 | 131008 | 0.18 |
|---|---|---|---|---|---|---|
| float32 (float32 upload) | **1.0** | -0.125 | 250 | 2.5e-6 | 32752 | 0.045 |
| float32 (half upload) | **1.0** | -0.125 | 250 | 2.503395e-6 | Infinity | 0.04501343 |
| 8-bit (`dontCare`) | 0.25 | 0 | 0.25 | 0 | 0.25 | 0.04509804 |

Highlights above 1.0 and negative (out-of-gamut) values survive between passes
when the intermediate is float32, and are clamped to 0..1 when it is 8-bit.

Note for the existing shaders: `srgbEncode1` in `app/shaders/lib/common.glsl`
clamps to 0..1. Any pass that must keep highlights has to stop clamping at its
output.

## 6. Cost

Measured on Metal (M1 Max). "Pass" = draw + mip chain + a 1-pixel sync so the
GPU work is finished. Average of 5 after a warm-up.

| | 2048×1366 (2.8 MP) | 4096×2731 (11.2 MP) | 8192×5464 (44.8 MP) |
|---|---|---|---|
| Float32List in Dart | 42.7 MB | 170.7 MB | 683.0 MB |
| Upload float → half texture (`dontCare`) | 32 ms | 94 ms | 403 ms |
| Upload float → float32 texture | 25 ms | 88 ms | 463 ms |
| One pass, float → float32 target | 3.4 ms | 13.6 ms | 58–81 ms |
| One tone-map pass, float → 8-bit target | 1.6 ms | 4.2 ms | 18–19 ms |
| Readback float32 (`rawExtendedRgba128`) | 16 ms | 63 ms | 330–570 ms |
| Readback 8-bit result | 2.5 ms | 8–10 ms | 58–65 ms |
| *8-bit baseline: upload / pass / readback* | *5.3 / 1.5 / 2.5 ms* | *12 / 3.8 / 8.5 ms* | *83 / 15 / 45 ms* |

Bytes per pixel actually used (from `rawUnmodified`, plus the mip chain the
engine always allocates):

| Image | Base | With mips | At 2048 px | At 45 MP |
|---|---|---|---|---|
| 8-bit upload or target | 4 | 5.3 | 15 MB | 228 MB |
| Float upload, default (half) | 8 | 10.7 | 30 MB | 455 MB |
| Float upload, `rgbaFloat32` | 16 | 21.3 | 57 MB | 911 MB |
| Float32 render target | 16 | 21.3 | 57 MB | 911 MB |

Process RSS rose from 1.26 GB to 4.0 GB over the 45 MP run (the test's own
683 MB list, upload copies, readback copies). Upload makes several transient
CPU copies (immutable buffer, converted bitmap, premultiplied bitmap).

**Reading.** At preview size float is cheap: a float pass costs about 2 ms more
than an 8-bit one and a whole float chain fits in a few hundred MB. A
full-frame float32 chain at 45 MP works on this 64 GB machine but is not
shippable: each live image is 0.9 GB, and the chain holds several.

What is practical at 45 MP:

1. **Tile the export** (the engine already has `renderTiled` and 4096 tiles in
   the retouch and backdrop paths). A 2048² float32 target is 89 MB with mips,
   a 4096² one 358 MB. Only the final per-tile output needs to leave the GPU.
2. **Source as half float** via the default upload: 455 MB for the whole frame,
   or upload the source in tiles as well.
3. **Float32 only where it matters.** The last pass writes 8-bit (or float for
   a 16-bit file) so nothing float is read back at full size unless the user
   exports 16-bit.

Half-float *targets* would halve this but are not available from Dart.

**Packing 16 bits into two 8-bit channels** was measured as well (question 8b).

## 7. Portability (source reading only, NOT verified on devices)

Everything below except the headless rows is unverified.

| Platform | Renderer | Expectation |
|---|---|---|
| iOS | Impeller / Metal | Same code path as macOS. `kR32G32B32A32Float` → `MTLPixelFormatRGBA32Float` (`eng/impeller/renderer/backend/metal/formats_mtl.h:115-131`). Risk: linear filtering of 32-bit float textures is not guaranteed on all iOS GPUs; memory budgets are far smaller than on a Mac. |
| Android | Impeller / Vulkan | Formats map to `eR32G32B32A32Sfloat`, `eR16G16B16A16Sfloat`, `eR32Sfloat` (`eng/impeller/renderer/backend/vulkan/formats_vk.h:164-179`). Risk: float32 as a colour attachment and float32 linear filtering are optional Vulkan features on mobile GPUs; no capability check for them was found in the engine. |
| Android fallback | Impeller / OpenGL ES | `GL_RGBA32F` / `GL_RGBA16F` / `GL_R32F` (`eng/impeller/renderer/backend/gles/formats_gles.cc:108-121`, render buffer formats `texture_gles.cc:346-348`). Risk: rendering to float needs `EXT_color_buffer_float`, filtering needs `OES_texture_float_linear`; no check for either was found. Likely to fail on some devices. |
| Windows | Impeller on OpenGL ES via ANGLE, enabled by default (`eng/shell/platform/windows/flutter_windows_engine.cc:197`, compositor `compositor_opengl.cc`) | Same GLES path as above, on ANGLE/D3D11. Unverified. |
| Skia (any platform with Impeller off) | | `toImageSync` ignores `targetFormat` and always makes an 8-bit image (`eng/lib/ui/painting/picture.cc:99-100`). |

**Headless `flutter_tester` (measured on this Mac):**

| Command | Renderer | Result |
|---|---|---|
| `flutter test` (default; `--enable-software-rendering`, `packages/flutter_tools/lib/src/test/flutter_tester_device.dart:113-115`) | Skia, software | Float upload and direct readback are exact (16 B/px), but every pass output is 8-bit: 256 levels after one pass, 17 after the ±4 EV pair, 4.0 clamps to 1.0, `targetFormat` ignored. `decodeImageFromPixelsSync` throws "not implemented on Skia". `rFloat32` upload fails. |
| `flutter test --enable-impeller` (`eng/shell/testing/tester_main.cc:53-70`) | Impeller | Identical to Metal for every precision test: float32 chain lossless (65 536 / 1 048 576 levels, err 0), half upload 7 169 / 11 265, 4.0 × 0.25 = 1.0, bilinear float OK. Only difference: `decodeImageFromPixelsSync` gave a silent 8-bit image instead of null. |

Consequence for the CPU-vs-GPU parity tests: float parity suites must run with
`--enable-impeller` (and on device). Under the default headless run they would
compare a float CPU twin against an 8-bit GPU chain.

Because of the unverified rows, the pipeline should probe at start-up (upload
an 8×1 float strip, two passes, read back, check 4.0 × 0.25 = 1.0 and a
non-8-bit level) and fall back to the 8-bit chain when the probe fails.

## 8. Fallbacks, evaluated honestly

Not needed on macOS, but relevant as the fallback for devices that fail the
probe.

**(a) Precision-critical steps on the CPU or natively, then the 8-bit chain.**

| Float tone-map of a 2048×1366 frame (white balance, exposure, highlight shoulder, shadow lift, curve LUT, sRGB encode) | Time |
|---|---|
| Dart, UI isolate, debug JIT | 92 ms |
| Dart, `Isolate.run` (copies the 42.7 MB input), debug JIT | 101 ms |
| Dart AOT, single isolate | 58 ms |
| Dart AOT, `Isolate.run` | 65 ms |
| Dart AOT at 45 MP | 0.96 s |
| CoreImage: tone-map of a cached linear half-float preview → RGBA8 | 5–24 ms |
| CoreImage: re-develop from the RAW file with a new exposure (new `CIRAWFilter`, 2048 px) | 460–490 ms |
| Upload of the 8-bit result to the GPU | 6 ms |
| *For comparison: the same tone-map as one GPU pass from a float texture* | *1.6 ms* |

Dart is 10–15 fps at preview size on a fast Mac: usable as a reference twin
and a last-resort fallback, not as the interactive path. CoreImage on a cached
linear image is interactive but macOS/iOS only and would duplicate the tone
maths in a third implementation (GLSL, Dart, CoreImage). Re-developing from
the RAW per slider move is far too slow. And every later local adjustment
would still run on 8-bit data, so masks and local exposure would still band.

**(b) Two 8-bit channels = 16 bits through the existing chain.** Measured on
Metal with R = high byte, G = low byte, `FilterQuality.none`:

| Two passes | Levels | Max error |
|---|---|---|
| ×1 then ×1 | 65 536 / 65 536 | 0 |
| -4 EV then +4 EV | 4 097 / 65 536 | 8 of a 16-bit step |

It works bit-exactly, and the second row is simply the limit of a 16-bit
integer (same loss a real 16-bit pipeline has). But the cost in this codebase
is high:

- RGB at 16 bits needs 6 bytes, so two RGBA8 outputs per pass. A
  `FragmentProgram` has one output, so **every pass runs twice**.
- Every image sampler becomes two. `develop.frag` has 7 samplers and 9 uniform
  declarations today; that stays under the limit of 24, but only just once the
  aux maps are doubled too.
- Packed bytes cannot be filtered by the GPU: every bilinear tap becomes four
  fetches per texture and a manual blend (the `BILINEAR` macro pattern in
  `backdrop.frag`), on two textures. Mips are meaningless.
- No headroom above 1.0 unless a fixed scale is baked in, which spends bits.

**Recommendation for the fallback:** where the float probe fails, keep the
current 8-bit pipeline fed by a well-exposed 8-bit rendition (today's
behaviour) and show RAW recovery as limited on that device. Do not build (b).
Build (a) in Dart only as the reference twin it has to be anyway.

## Native handover from CIRAWFilter

Measured with a standalone Swift script on a real 45 MP Canon CR3
(`CIRAWFilter`, `boostAmount = 0`, gamut mapping off,
`extendedDynamicRangeAmount = 2`, `CIContext` working space extended linear
sRGB, `render(_:toBitmap:...)`):

| Output | Size | Render (first / repeat) | Write file | Highlights |
|---|---|---|---|---|
| 2048 px, `RGBAh` half | 21 MB | 672 / 19 ms (first call includes pipeline warm-up) | 6 ms | max 3.13, 1.3 % of pixels above 1.0 |
| 2048 px, `RGBAf` float32 | 42 MB | 78 / 13 ms | 10 ms | max 3.13 |
| 2048 px, `RGBA16` unorm | 21 MB | 36 / 19 ms | 5 ms | **clipped at 1.0** (the same 1.3 % of pixels) |
| Full 5464×8192, `RGBAh` | 341 MB | 757 / 249 ms | 247 ms | max 3.6 |
| Full, `RGBAf` | 683 MB | 382 / 304 ms | 590 ms | max 3.6 |

Conclusions:

- A real RAW has data above 1.0 (here up to 3.6× white). **uint16 RGBA throws
  it away**; the handover must be float.
- Dart's only high-precision input is `PixelFormat.rgbaFloat32`. A half-float
  file would be half the size but Dart would have to expand it to float32
  before upload (there is no half input format and no `Float16List`).
- **Cheapest layout: little-endian float32 RGBA, alpha 1.0, extended linear
  sRGB, row-major, no padding**, written by `CIContext.render(toBitmap:,
  format: .RGBAf)`. Dart reads the bytes and hands them to
  `ImageDescriptor.raw(pixelFormat: rgbaFloat32)` without touching them.
- Preview: one 2048 px buffer (42.7 MB; 13 ms to render, 10 ms to write,
  25–32 ms to upload).
- Export: do not materialise 683 MB. Have the native side render the tile the
  export renderer is about to process (CoreImage renders any sub-rectangle), as
  float32 strips or tiles of 64–270 MB.
- A file under the app's temp directory avoids a large platform-channel copy on
  the UI thread; a binary channel would also work for the preview size. Not
  measured through a channel.

## Recommended architecture

**Principle: same passes, same order, float storage. Scene-linear float from
the RAW up to and including develop; 8-bit only at the very end.**

1. **Source.** For RAW, the native developer produces scene-linear, extended
   range float32 (above). For JPEG/HEIC/PNG nothing changes: 8-bit upload.
   Preview source: upload with `targetFormat: rgbaFloat32` (57 MB with mips at
   2048 px, lossless). Use `ImageDescriptor.raw` + `instantiateCodec`, never
   `decodeImageFromPixelsSync`.
2. **Passes that become float** (`toImageSync(..., targetFormat:
   rgbaFloat32)`) when the source is float: heal, denoise, `retouch.frag`,
   `backdrop.frag`, i.e. everything upstream of develop, so develop still sees
   highlights and deep shadows. `runPass` gains a target-format argument;
   8-bit sources keep `dontCare` and today's behaviour bit for bit.
3. **Develop** reads float and does the precision-critical work (white
   balance, exposure, highlight and shadow recovery, tone curve) in float. It
   is the natural place to bring the image into display range.
4. **Finish** writes the 8-bit display image as today, ideally with a small
   dither so the final quantisation does not band. For a 16-bit export the
   last pass targets float32 and is read back per tile with
   `rawExtendedRgba128`.
5. **Encoding convention between float passes.** Two options:
   - *Scene-linear* in the float textures. Each shader's
     `srgbDecode(texture(...))` at the input and `srgbEncode(...)` at the
     output become conditional (a uniform flag: source is linear float). This
     is the correct long-term form.
   - *Unclamped sRGB-encoded* values in float textures. Smallest diff (only
     the clamp in `srgbEncode1` changes) but the sRGB curve is not meaningful
     above 1.0.
   Recommended: scene-linear, behind one flag per pass, so the 8-bit path is
   untouched.
6. **Preview vs export.** Preview: full float chain at ≤ 2048 px, about 57 MB
   per live float image, a few ms per pass. Export: tiled (2048–4096), source
   tiles supplied by the native side on demand or one half-float source
   (455 MB), float32 tile targets (89–358 MB each), 8-bit or float tile out.
7. **Single-channel maps** (aux log-luma, masks) can use `rFloat32` targets
   where 8 bits are not enough: 4 B/px, float precision, but no direct
   readback.
8. **CPU reference twins** (`lumen_core`): add a float buffer type
   (`Float32List`, 4 channels, straight alpha, same row order as `RgbaBuffer`)
   and float versions of the kernels for the float path; keep `RgbaBuffer`
   twins for the 8-bit path. Store through `Float32List` so the twin rounds to
   float32 like the GPU. Parity is then a float tolerance (start around 1e-4
   relative and tighten from measurements), not N/255. Run float parity with
   `flutter test --enable-impeller` and in the on-device suites.
9. **Capability probe** at start-up selects float or 8-bit pipeline (section 7).

**Expected memory, preview at 2048×1366:** float source 57 MB + up to four
cached float intermediates 228 MB + 8-bit output 15 MB ≈ 300 MB GPU, plus the
42.7 MB Dart list during upload. Today's 8-bit equivalent is about 90 MB.

## Risks

- **Other platforms are unverified.** Float32 render targets and float32
  filtering are optional on mobile GPUs and under GLES/ANGLE, and the engine
  does not check. The probe and the 8-bit fallback are mandatory.
- **Float32 filtering.** Develop samples its source with `FilterQuality.low`.
  A half-float *uploaded* source is the safer thing to filter; float32
  intermediates may need nearest sampling plus manual bilinear on some GPUs.
- **Forced mip chains** on every float target: +33 % memory and a mip
  generation per pass that the pipeline does not use. Not controllable from
  Dart.
- **No half-float targets.** If memory on iOS/Android is too tight for
  float32 intermediates there is no cheaper float target; only smaller tiles.
- **The API is young.** `TargetPixelFormat` exists to serve single-channel
  float use cases; behaviour could change between Flutter releases. The spike
  test doubles as a regression test: keep a trimmed version in the on-device
  suite.
- **Existing shaders clamp** (`srgbEncode1`, and possibly LUT lookups indexed
  by an encoded 0..1 value such as the tone-curve LUT in `develop.frag`).
  Moving highlight handling ahead of any LUT indexed on 0..1 is real design
  work, not covered here.
- **Uniform limit.** Not affected by float (no extra samplers), unlike the
  packed-16 alternative.
- **Parity tests** under the default headless runner cannot see the float
  path at all.

## Not verified

- iOS, Android (Vulkan and GLES), Windows: source reading only.
- Which backend headless `--enable-impeller` used on this Mac (the tester
  chooses Vulkan unless told otherwise per `tester_main.cc`; not confirmed at
  run time).
- True GPU memory in use (figures are computed from measured bytes per pixel
  and the engine's mip policy, not read from Metal).
- Passing the float buffer through a platform channel rather than a file.
- A real float version of any production shader, and the uniform-limit
  behaviour with float targets on a shader as large as `develop.frag`.
- Release-mode timings in the app (GPU numbers should hold; the Dart numbers
  have AOT equivalents above).
- Behaviour when the float image exceeds the max texture size (the engine
  scales the target down, `snapshot_controller_impeller.cc:31-48`).
- Wide-gamut output to the display (the final image here is 8-bit sRGB).

## Spike files to remove later

- `app/shaders/spike_passthrough.frag`
- its line in `app/pubspec.yaml` under `flutter: shaders:`
- `app/integration_test/zz_hbd_spike_test.dart`
- `app/test/zz_hbd_spike_headless_test.dart`
