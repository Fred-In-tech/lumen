# High bit depth: editing RAW in 32-bit float

Date: 2026-10-04 · Flutter 3.47.2 · macOS 26.4.1, Apple M1 Max · Impeller on Metal.
Background and raw measurements of what Impeller can carry:
`docs/research/08-high-bit-depth-spike.md`.

## What it is

Until now a camera RAW was developed once, at import, into an 8-bit JPEG
rendition. Everything brighter than display white was clipped and the
shadows were quantised to 8 bits before any slider moved, so Exposure and
Highlights could only turn clipped white into grey.

On the **float path** the editor develops a float preview of the file
itself, and the export renders from float windows of it:

```
file ──► native decode ──► float32 texture ──► heal ► denoise ► retouch ► backdrop ──► DEVELOP ──► finish ──► frame
         (CoreImage)       sRGB-encoded,        all in rgbaFloat32 targets,            decodes to linear:    8-bit
                           extended range       output not clamped                     exposure, WB, highlights,
                                                                                       shadows on real headroom
```

**Representation.** A float source is a 32-bit float RGBA texture holding
**sRGB-encoded values with extended range**: 0..1 means what a byte / 255
means on the 8-bit path, values above 1.0 are highlights brighter than
display white, nothing is clamped. Alpha is 1. Every pass already treats its
source as sRGB-encoded and decodes it to linear inside, so all passes keep
their meaning and 8-bit sources keep today's path untouched. The CPU twin is
`FloatBuffer` (`packages/lumen_core/lib/src/render/float_buffer.dart`).

Negative values (colours outside sRGB) travel through the pre-passes but
develop decodes them as 0, exactly like the 8-bit path clips them.

## Which photos use it

| Source | Float path | Headroom above white |
|---|---|---|
| Camera RAW (CR3, CR2, DNG, NEF, ARW, RAF, …) on macOS / iOS | yes | yes: Apple's extended-range rendering (measured 2.4 stops on a Canon R5 CR3) |
| Apple ProRAW DNG (files with a local tone map) | yes | no: default rendering in float (see "Native decode") |
| 16-bit PNG, 10 / 12-bit HEIC / AVIF on macOS / iOS | yes | none in the file; full precision |
| JPEG, WebP, 8-bit PNG / HEIC | no | (8-bit path, unchanged) |
| Anything on Android, Windows, Linux, web | no | no float decoder there yet |
| Any photo on a device that fails the float probe, or in the CPU fallback renderer | no | 8-bit rendition, as before |

`FloatSources.open(assetId)` (`app/lib/import/float_sources.dart`) decides:
the catalog entry must be RAW or store more than 8 bits (`isHighBitDepth`),
the catalog must keep originals as files (`OriginalFileLocator`), and the
platform decoder must accept the file. `floatEditingProvider(assetId)` adds
the device probe; the photo info panel shows the result:

- **Bit depth**: "14-bit RAW", "10-bit RAW", "16-bit", … read from the file
  header at import (`sniffBitDepth`: PNG IHDR, HEIF `pixi` / codec
  configuration, `BitsPerSample` of the sensor directory of TIFF-based RAW).
  A RAW that does not declare it (Canon CR3) shows "RAW": no number is
  invented. Stored as the nullable `CatalogEntry.bitDepth`; older catalogs
  load without it.
- **Editing**: "32-bit float" on the float path, "8-bit" otherwise.

The JPEG rendition stays: thumbnails at import, face and mask analysis, the
CPU fallback, export EXIF, and every device without the float path use it.

## Native decode (`lumen/raw` channel)

`FloatDeveloper` in `app/macos/Runner/MainFlutterWindow.swift` and
`app/ios/Runner/AppDelegate.swift` (Apple frameworks only):

| Method | Arguments | Reply |
|---|---|---|
| `floatInfo` | `input` (path) | `width`, `height` (full, upright), `shoulderKnee`, `highlightGain` |
| `floatRender` | `input`, `fullWidth`, `fullHeight`, `x`, `y`, `width`, `height` | `pixels`: little-endian float32 RGBA, extended sRGB (encoded), alpha 1, upright, rows top to bottom; `ms`: decoder time |
| `floatRelease` | `input` | drops the cached decoder of that file |

`floatRender` renders the photo scaled to `fullWidth × fullHeight` and
returns one window of it. The preview asks for the whole photo at preview
size; the export asks for one window per output tile at export size.
Pixels cross the channel as one `Float32List`; nothing is written to disk.
The original is read by path inside the app container.

**RAW rendering.** `CIRAWFilter` with Apple's defaults (camera white
balance, default boost and tone curve: the look of the JPEG rendition) and
`extendedDynamicRangeAmount = 2`, rendered into `CGColorSpace.extendedSRGB`
float. Measured on a 45 MP Canon R5 CR3 (standalone Swift harness, then in
the app):

- With the default `extendedDynamicRangeAmount = 0` the output tops out at
  1.05 (encoded). With 2 it reaches **2.07 encoded = 5.4× display white =
  2.4 stops**; 11 % of the pixels of the sample are above white.
- Below 0.9 (encoded) the extended rendering equals the default one: max
  difference 0.0034, mean 0.00003 (0..1 scale).
- Above that the default rendering rolls highlights off and then clips: by
  the brightest channel, identity up to about 0.86, reaching 1.0 at about
  1.15. The extended rendering has no roll-off. A quadratic shoulder with
  knee 0.86 (white at `2 − knee` = 1.14) reproduces Apple's curve within
  0.007, so **develop applies that shoulder itself** for these sources
  (`HbdProfile.rawExtended`, see "Develop"). The unedited photo then looks
  like the rendition, and pulling Exposure or Highlights down brings the
  real data out of the shoulder instead of grey.
- **Apple ProRAW** (files where `CIRAWFilter.isLocalToneMapSupported` is
  true) is different: its extended rendering drops the local tone map and
  changes the whole picture (mean difference 0.08 below 0.8). Those files
  keep the default rendering (`extendedDynamicRangeAmount = 0`) in float:
  full precision, but no more highlight headroom than the rendition has
  (0.28 stops on the sample). `floatInfo` then reports a zero profile.

**Other formats.** `CIImage(contentsOf:)` with the orientation applied,
converted to extended sRGB float (Lanczos when scaled down). A generated
16-bit PNG comes back with 4096 of 4096 ramp levels, a 10-bit HEIC with
1020. HDR gain maps of HEIC are not applied (the SDR base is decoded).

**Caching and cost.** The `CIRAWFilter` of a file and size stays cached
(two files at most: the open photo and one being exported). A decode at a
new size is a fresh RAW decode: about 0.6 s for the 45 MP CR3; the same
size again takes 20–80 ms; a full-resolution window about 90 ms. Calls run
on the serial RAW queue inside a `userInitiated` activity, so a hidden
window is not throttled by App Nap. These are the times on an otherwise
idle machine. With other heavy jobs running (load average 8–12 during
development), and for a few seconds right after importing a 45 MP RAW, the
same decodes took 2–4 s.

Sensor bit depth: ImageIO reports only the decode depth (16) for RAW, and
for CR3 the 8-bit depth of the embedded JPEG, so it is not used. The value
shown comes from the file's own raw directory where one exists.

## What each pass does differently

Uniform declarations did not change (the Metal limit, `architecture_test`).

| Pass | Float sources | 8-bit sources |
|---|---|---|
| Heal | The 8-bit patches are composed into a premultiplied overlay (`composeHealOverlay`) and drawn over the float source into a float32 target (`compositeOverlay`). Pixels no patch covers keep their float values; patched pixels carry 8-bit data. | unchanged (CPU composite) |
| Denoise `denoise.frag` | float32 target; the final `clamp(…, 0, 1)` is gone | same shader: an 8-bit target clamps on store, as the explicit clamp did |
| Retouch `retouch.frag` | float32 target; output through `srgbEncodeExt` (no upper clamp); `uMapInfo.w = 1` makes the source the pass window (export) | identical inside 0..1 |
| Backdrop `backdrop.frag` | float32 target; output through `srgbEncodeExt`; the spill un-mix clamps to `max(1, F)` instead of 1; `uPlateB.z = 1` makes the source the pass window | identical inside 0..1 |
| Develop `develop.frag` | decodes the extended source (`srgbDecode` continues above 1.0), so white balance, exposure, dehaze, highlights, shadows, clarity and local adjustments act on real headroom; `uSrcWin` maps source uv into a source window; `uGradeParams.z` (shoulder knee) and `.w` (highlight gain) from the source's `HbdProfile` | `uSrcWin = 0, 0, 1, 1`, knee and gain 0: bit-identical |
| Finish `finish.frag` | unchanged: develop and finish write the 8-bit frame | unchanged |

**Develop details.**

- *Shoulder.* The composite tone step is `lut(S(encodeExt(x)))` instead of
  `lut(clamp(encode(x)))`: `S` (`highlightShoulder`, `shoulder()` in
  `common.glsl`) is identity up to the knee, a quadratic roll-off that
  reaches 1.0 at `2 − knee`, and 1.0 beyond. With knee 0 (PNG, HEIC,
  ProRAW, every 8-bit source) it is the plain clamp. Whatever is still above
  the shoulder after exposure, highlights and shadows clips in the tone LUT
  as before.
- *Highlights.* The guided base that drives Shadows / Highlights comes from
  the aux maps, which are now built from float data for float sources
  (`AuxMaps.computeFloat`): log luma keeps luminance up to 4× white
  (`normLogLuma`), so the base and the clarity base represent highlights
  above white. For sources with headroom Highlights also gets
  `highlightGain` (0.5 EV) per stop the base sits above white, up to two
  stops: −100 moves a region at 4× white by −2.5 EV, down to the knee.
- *Aux maps under a backdrop swap* are still the 8-bit ones of the
  composite (see "Known limits").

**Render targets.** `runPass` / `_run` take a target format
(`kFloatTarget = TargetPixelFormat.rgbaFloat32`, the only float target
`Picture.toImageSync` offers); `runDenoise`, `runRetouch`, `runBackdrop`,
`runDevelop` and `renderTiled` expose it as `float:`. Float images are
uploaded with `ImageDescriptor.raw` + `instantiateCodec(targetFormat:)`
(`uploadFloat`) and read back with `rawExtendedRgba128` (`readFloat`).

**In the editor** (`GpuPhotoRenderer`): the float preview is decoded at the
size the 8-bit preview would have. `before`, the analysis proxy and the
8-bit pixels that heals and backdrop mattes are computed from are that float
preview developed with default settings, so before / after and all 8-bit
consumers line up with the frames exactly.

## Capability probe and fallbacks

`HbdCapability.probe(shaders)` (`app/lib/engine/hbd_capability.dart`) runs
one tiny round trip per process, on first use, and caches the answer:

1. upload a float32 strip (4.0, a level between two 8-bit steps, 0, 2.0)
   and read it back;
2. two shader passes into float32 targets; the values must survive (no
   clamp, no 8-bit storage);
3. stretch a 2-pixel float texture with bilinear filtering (develop samples
   its source that way) and check the interpolated values.

Any failure or exception answers false. Then, and in every one of these
cases, the photo opens on the 8-bit rendition path exactly as before:

- the probe fails (default headless Skia, GPUs without float colour
  attachments or float filtering);
- the platform has no float decoder (Android, Windows, Linux, web);
- the catalog has no file for the original, or the decoder rejects it;
- the float decode throws, or its size does not match the pixel source;
- the shaders cannot load (CPU fallback renderer).

The export has the same gates and falls back to the 8-bit export when the
float one returns nothing or its decoder fails. Nothing on this path can
render a white frame: the shaders have the same uniform declarations as
before.

## Export

A 45 MP photo in float32 is 0.9 GB per image on the GPU with the mip chain
the engine always allocates, and the chain would hold several. The float
export therefore never has the whole photo on the GPU
(`ExportRenderer.renderFloat`, wired by `gpuFloatExport`):

1. The source is rendered at its **virtual size**
   (`ExportRenderer.floatSourceSize`): the full size, capped at 8192, scaled
   so the output long edge matches a long-edge export. Source and output
   then have the same pixel density.
2. For each output tile (2048², plus a 4 px apron when the finish pass
   runs) the **source window** it samples is computed
   (`sourceWindowFor`): the bounding box of the tile through crop,
   straighten, flips and quarter turns, grown by the warp range and by a
   6 px margin for the filter taps (bilinear 1, texture 3×3 1, denoise 5×5
   2), clipped to the photo.
3. The native side renders exactly that window in float; it is uploaded as
   float32.
4. The heal overlay crop, denoise, retouch and backdrop run **on the
   window** (retouch and backdrop sample their maps at the full-source uv
   and take the window as their source).
5. Develop renders the tile from the window (`uSrcWin`), finish follows,
   and only the 8-bit tile is read back.

Aux maps, masks and the warp field are resolution independent and shared by
all tiles, so there are no seams: the windowed export equals a single pass
over the whole float source (max difference 1/255 on the GPU, also with
retouch and with a backdrop swap running per window; with straighten +
denoise + finish 2/255, mean 0.001).

Tiles shrink (2048 → 1024 → …) until every window is at most 16 MP, which
only happens with extreme warp ranges.

**Measured, 45 MP Canon R5 CR3 (5464 × 8192), exposure −1.5, highlights
−60, JPEG q90, M1 Max, debug build:**

| | Float path | 8-bit path |
|---|---|---|
| Tiles | 12 of 2048² | 12 of 2048² |
| Largest source window | 4.2 MP (67 MB as float32) | (whole photo: 45 MP, 179 MB + mips on the GPU) |
| Estimated peak GPU memory per tile | **~194 MB** (two live float32 windows with mips + the 8-bit tile targets) | ~240 MB (8-bit source with mips) + tiles |
| Native decode of the 12 windows | 1.1–1.2 s (5.9 s in one run, see below) | |
| Upload + passes + readback | 0.4 s | |
| Whole export incl. JPEG encode | **7.4–8.1 s** (12.4 s in the slow run) | 5.4–6.3 s |
| Process RSS (peak during the run) | 1.84 GB | (same run) |
| Brightest block of the exported file | 155 levels, sd 41.6, mean 232 | 58 levels, sd 8.5, mean 153 (clipped white turned grey) |

Native decode times varied between runs on the development machine (other
heavy jobs were running): five runs gave 1.1–1.2 s for the 12 windows, one
gave 5.9 s. The GPU figure is computed from pixel counts (16 B/px × 4/3), not read
from Metal. CPU memory is dominated by the full 8-bit output frame
(179 MB), one window in transit (67 MB, copied by the channel) and the JPEG
encoder.

## Measured on the real file

`app/integration_test/float_raw_test.dart` with the Canon R5 CR3 (a bare
light bulb and a white curtain in frame), preview 1708 × 2560:

| | Float path | 8-bit rendition path |
|---|---|---|
| Headroom | peak 2.07 encoded = 5.4× white = **2.4 stops**; 11.3 % of pixels above white | none (clipped at 1.0) |
| Exposure −2, most clipped block (the bulb) | **131 levels, sd 47.5** | 47 levels, sd 7.8 |
| Highlights −100, same block | **113 levels, sd 39.8** | 55 levels, sd 7.8 |
| Exposure −2, brightest blocks (curtain) | 20–23 levels, sd 6.0 | 9–11 levels, sd 2.2–2.4 |
| Highlights −100, brightest blocks | 22–27 levels, sd 6.9 | 10–16 levels, sd 2.7–3.4 |
| Open | 0.9–1.0 s in three runs, 3.8–4.9 s in four (one RAW decode at preview size; the decode time varied with machine load) | 0.2 s (JPEG rendition) |
| Slider drag frame (interactive, half size) | 1.2–2.1 ms | 1.3–2.1 ms |
| Full-quality frame | 2.8–5.1 ms | 2.9–5.4 ms |

Default look, float path against the rendition (same preview size): mean
difference 0.93/255. Pixels differing by more than 8/255: 0.8 % below the
roll-off, 0.16 % inside it, 4.6 % of the clipped ones (the shoulder keeps
hue where Apple clips per channel), 18 % of edge pixels (the two decodes
are downscaled by different resamplers, which is also why `before` is
taken from the float preview).

Synthetic checks (CPU twin and GPU agree):

- a ramp from 1× to 4× white at −2 EV: 119 output levels, monotone; the
  8-bit rendition of it: 1 level;
- the darkest 2 % of the range at +3 EV: 30 levels from float, 6 from 8
  bits (also through a real 16-bit PNG and the native decoder);
- two float passes keep 65 536 of 65 536 ramp levels with zero error.

## CPU twins and tests

| What | Where | Runs |
|---|---|---|
| `FloatBuffer`, `renderReferenceFloat`, `DevelopKernel.float`, `AuxMaps.computeFloat`, shoulder, windows | `packages/lumen_core/test/render/float_develop_test.dart`, `float_support_test.dart` | `dart test` |
| 8-bit-equivalent float input gives the same bytes as the 8-bit path | same | `dart test` |
| GPU vs CPU parity of the float develop path (max 1/255 measured, limit 3), float pre-passes, heal overlay, headroom, precision | `app/test/engine/float_path_test.dart` | `flutter test --enable-impeller`, on device |
| Windowed export equals the single pass | `app/test/engine/float_export_test.dart` | same |
| Renderer and export wiring, fallbacks, channel contract, sources, info panel, bit depth | `app/test/features/float_render_test.dart`, `float_sources_test.dart`, `app/test/import/bit_depth_test.dart` | default `flutter test` (the probe is forced on where needed) |
| On the real GPU | `app/integration_test/float_engine_on_device_test.dart` | `flutter test integration_test/float_engine_on_device_test.dart -d macos` |
| Real files | `app/integration_test/float_raw_test.dart` | `-d macos --dart-define=LUMEN_RAW_SAMPLE=<path inside the app container>` |

Default headless `flutter test` (Skia) has no float render targets: the
float engine suites mark themselves skipped there, they do not fail.

## Known limits

- **Not verified on iOS, Android, Windows.** iOS shares the code and the
  probe but was not built or run. Android and Windows have no float decoder
  and keep the 8-bit path; their GPUs would also have to pass the probe.
- **Apple ProRAW gets no extra headroom** (see "Native decode"), and its
  decodes are slower (about 1.5 s per new size, not cached by CoreImage).
- **Healed pixels are 8-bit.** Patches come from the 8-bit inpainting
  pipeline; a patch over a blown highlight holds clipped data.
- **Backdrop swap + spatial sliders.** While a backdrop change is active
  and Highlights / Shadows / Clarity / Dehaze are used, develop reads the
  aux maps of the composite, which are built on the CPU from 8-bit data;
  the clarity base then does not know about highlights above white on the
  subject.
- **Retouch maps are 8-bit** (bands, regions): retouched skin keeps float
  precision and highlights as detail on top of 8-bit bands.
- **Colours outside sRGB** are clipped at develop, as on the 8-bit path
  (the output is 8-bit sRGB). No wide-gamut or HDR output yet.
- **Output is 8-bit** (JPEG / PNG / WebP). `runDevelop(float: true)`
  exists for a future 16-bit export.
- **The preview of a float photo is a float32 texture** on the GPU:
  1708 × 2560 is 93 MB with mips, and each active float pre-pass (denoise,
  retouch, backdrop) caches one more image of that size. Half-float upload
  would halve the source; half-float render targets are not available from
  Dart.
- **Open is slower** by one RAW decode (about 0.7 s for 45 MP on an idle
  machine; 3–4 s were measured under load and right after importing the
  file). The frame appears when the decode is done; there is no 8-bit
  preview shown first.
- **TIFF** import is not supported (the decoder would handle 16-bit TIFF).
- The shoulder constants were measured on one Canon CR3 and one ProRAW DNG.
  Other cameras go through the same `CIRAWFilter` rendering, but were not
  measured.
