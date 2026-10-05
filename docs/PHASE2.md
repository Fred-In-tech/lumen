# Phase 2: Evoto-class AI retouching, AI masks, object removal

> **Goal (founder, 2026-10-03):** replicate Evoto (evoto.ai). Put photos in, and the AI retouches everything: skin smoothing, blemishes, eye bags, teeth, eyes, face shaping, background cleanup, color. Every result stays adjustable, and edits sync across a whole shoot.
> **Inputs:** `docs/research/06-evoto-teardown.md` (product), `docs/research/07-portrait-retouch-tech.md` (CV tech + model licenses), research 03 (on-device models).
> **Reference links reviewed:** evoto.ai (target product); `evolution-foundation/evo-ai` (agent orchestration, Apache-2.0: pattern only, for the analyze → retouch → verify loop); `meetpateltech/AI-Infinity` (tool directory, competitor list); `rozon/pixieset-downloader` (archiving your own client galleries; shows the shoot → retouch → deliver workflow; not integrated).

## Architecture decisions

### Pipeline
```
original ──► RETOUCH STAGE (pixel layer, cached) ──► DEVELOP (GPU uber shader: global + masked local) ──► FINISH ──► view/export
             heal & remove patches                    masks = 8-bit coverage atlases (≤8 masks,
             skin smoothing / blemishes / eye bags      2 RGBA textures, source-uv space)
             teeth / eyes / makeup (masked color ops)
             face & body reshaping (warp field)
```

- **Retouch stage = CPU-first, pure Dart in `lumen_core`.** One implementation is the source of truth for preview, thumbnails, batch and export, and it's testable without a GPU. It runs in an isolate at preview resolution (≤2560) and at full resolution on export, and is re-run only when retouch parameters change. Its output becomes the develop shader's source texture, so global sliders stay 60 fps.
- **Non-destructive document:** `settings.retouch` stores per-face parameters, global skin parameters, heal/remove strokes and reshaping parameters. Generated pixels (object removal) are cached as PNG patches under `assets/<id>/retouch/` and referenced by id. Undo removes the entry.
- **Masks** (Lightroom-style): Subject / Sky / Background / People / Face-skin (AI rasters), plus Linear / Radial / Brush (vector). Each mask has local adjustments for exposure, contrast, highlights, shadows, whites, blacks, temp, tint, saturation, texture, clarity and dehaze. Rasterized in `lumen_core` (`MaskRasterizer`) and applied per pixel in the uber shader with an identical CPU reference.
- **AI models run on-device** (ONNX Runtime / LiteRT; CoreML on Apple). That means $0 per photo, private, works offline, and fits a credit-based SaaS margin. A cloud path stays possible through the gateway for heavy generative features (background extension), behind the same interfaces as `ai_ondevice/on_device_ai.dart`. Models download on first use, with SHA-256 checks, and are listed in `docs/MODEL_LICENSES.md`.
- **Every model must be commercially licensed, including its training data.** Banned: CelebAMask-HQ-trained face parsers, InsightFace weights, BRIA RMBG, and anything else non-commercial.

## Decisions since research 07 (2026-10-03)
- **Runtime:** `flutter_litert` 3.9.3 (pinned; supply-chain review in `docs/LICENSES.md`). The MediaPipe models run on the classic `Interpreter`. MI-GAN only runs through `CompiledModel` (LiteRT Next), so the backend uses CompiledModel first and Interpreter as the fallback.
- **Models (user-approved download):** BlazeFace short- and full-range and the FaceMesh V2 landmarker are bundled (3.9 MB). Selfie Multiclass (16.4 MB) and MI-GAN (16.3 MB) download on first use. Hashes are pinned in `docs/MODEL_LICENSES.md`, and tensor contracts are asserted in `app/test/ai/ondevice/litert_model_contract_test.dart`.
  - Measured on this Mac's CPU: detection 7 ms, mesh 10 ms, multiclass 144 ms, MI-GAN 794 ms per 512² fill.
  - The full-range detector input is **192²** (2304 anchors), not 128².
  - The Hair Segmenter is **deferred**: it needs MediaPipe custom ops that the runtime lacks.
- **Retouch engine:** a GPU pre-pass `R` with CPU-built maps, plus a pure-Dart CPU twin in `lumen_core` (research 07 §3.0). Group sliders stay uniform-only during drags (face-index map + per-face uniform table).
- **Privacy:** face geometry lives only in the local `cache/face.json`, never in `edit.json`. No embeddings, so "Individual" is per photo (person id = faceKey).
- **Data model:** `settings.portrait` (`PortraitSettings`) holds group, individual and image-scope values. Heal/remove ops will live in `settings.heal` (ordered, non-destructive, patches at original resolution).

## Workstreams (status)
| # | Workstream | Status |
|---|---|---|
| W1 | Masks engine: model, rasterizer, shader + CPU local adjustments, atlases, overlay | ✅ done (`b20cbcb`), parity max 1/255 |
| W2 | Research: Evoto teardown (06) | ✅ done |
| W3 | Research: portrait-retouch tech + licenses (07) | ✅ done |
| W4 | On-device inference: LiteRT backend, ModelStore (SHA-256, resume, disk guard, LRU), FaceAnalyzer, face cache | ✅ done (`5797750`), faces wired to Portrait (`3bf39dc`) |
| W5 | Retouch core: face regions, skin parser, RetouchMaps, blemish heal, CPU kernel, uniforms | ✅ done (`381adb0`, wrinkles/makeup/shine `2b55422`, spot editor `5c740a3`) |
| W6 | Object removal core: push-pull, Telea, PatchMatch, crop/feather/detail pipeline, heal ops | ✅ done (`1e70950`), app plumbing (`e3f76b6`) |
| W7a | Portrait module UI: group tabs, Individual, sections, Auto Retouch, face boxes, tags | ✅ done; live retouch (`d502a61`) |
| W7b | Masks module UI + canvas tools (linear/radial/brush, overlay) | ✅ done (`8661617`) |
| W7c | Remove tool UI + heal/clone brushes + MI-GAN adapter + export/paste of heal ops | ✅ done (`21f386d`) |
| W8 | GPU `retouch.frag` pass mirroring the W5 CPU kernel + render-graph integration | ✅ done (`102aca0`), parity max 1/255 |
| W9 | AI masks (Subject, Background, Face skin, Hair, Clothing) from Selfie Multiclass | ✅ done (`d7f6a91`, `585fd33`); Sky needs a cloud model |
| W10 | Face reshape (MLS warp in `develop`) + liquify | ✅ done (`90e029c`, UI `a8380b3`), parity ≤ 3/255 |
| W11 | Backdrop cleanup (clean, unify, luminance, stray hairs) + red-eye | ✅ done (`716c5ec`) |
| W12 | Automatic start-to-finish: need-scaled Auto Retouch, Auto = colour + retouch, batch/import/sync, portrait presets | ✅ done (`1653c62`) |
| W13 | Smart Cull + headshot crop | ✅ done (`e0a32ee`), batch headshot (`a8380b3`) |
| W14 | Hold-to-compare per section, control search, Manual Tuning Pen (skin) | ✅ compare (`e0041d9`), search (`e05d00f`), pen (`a8380b3`, `d194507`) |
| W15 | AI Color Match (reference look → sliders, single + batch) | ✅ done (`467f019`) |
| W16 | Background swap / blur behind the person matte (pass B), export + paste | ✅ done (`6ec4fe7`, `9fd2c71`) |
| W17 | Glasses glare + clothing de-wrinkle / lint | ✅ done (`ebf7119`, `82e0369`) |

### Evoto parity (research 06 §5)
- **P0: all done.** Face detection, group tags and per-face/group sliders; blemish removal that keeps freckles; skin smoothing; dark circles and eye bags with lid protection; face shine; eyes (iris, whites, red veins, red-eye); teeth; clean backdrop, unify lighting and banding; Manual Tuning Pen (skin); character-aware presets, selective sync, hold-to-compare; glasses glare; stray hairs on plain backdrops.
- **P1, done:** wrinkle zones, even skin tone, face reshape, manual liquify and healing, AI Color Match, backdrop changer, auto headshot crop, basic makeup, clothing de-wrinkle, culling.
- **Open (needs a decision or the cloud):**
  - Body reshape needs the MediaPipe Pose model (5.8 MB, needs download approval).
  - Unifying face-to-body complexion.
  - Hair tools beyond AI Hair masks with local sliders.
  - Generative tools (expand, smile, sky replacement), which need a cloud sidecar plus a license review.
  - Style training and gallery delivery.
| X1 | Export, batch and thumbnails honour heal ops, retouch maps and AI mask rasters; live heal preview | ✅ done (`4abc91f`) |
| P1 | Privacy hardening: face caches + models excluded from OS backups (iOS/macOS `isExcludedFromBackup` via `lumen/backup` channel + startup sweep; Android `dataExtractionRules`/`fullBackupContent` exclude `assets/` and `models/`) | ✅ done; BIPA legal review still open (user) |
| F1 | Real-GPU fixes (2026-10-04): retouch rendered white on Metal; `\` typed into the prompt bar instead of comparing | ✅ fixed, see below |

### Real-device verification (2026-10-04)
- **White frames on Metal.** An Impeller/Metal fragment shader with about 32 or more separate `uniform` declarations renders solid white. There is no error, and the headless `flutter_tester` renderer does not show it. The masks commit (`b20cbcb`) pushed `develop.frag` and `retouch.frag` over that limit. All shaders now pack runs of `vec4` uniforms into arrays (`uVec0[n]`, with `#define` aliases), which keeps the float layout. `test/architecture_test.dart` keeps every shader at 24 or fewer declarations.
- **Focus.** On desktop, a Flutter `TextField` keeps focus when you click elsewhere. The prompt bar now drops focus on `onTapOutside`, and the editor takes keyboard focus back whenever nothing else holds it, so `\`, `Z` and the other shortcuts always reach it.
- **On-device suites** (`flutter test integration_test/<file> -d macos`, one file per run on desktop):
  - `phase2_on_device_test.dart`: retouch, mask, warp and backdrop GPU-vs-CPU parity on the real GPU.
  - `portrait_flow_test.dart`: imports `docs/samples/sample_portrait.jpg` (a drawn portrait with acne spots), opens it, detects the face, runs Auto Retouch, checks the frame is a real photo, checks a strong retouch changes only face pixels, then clicks the prompt bar and the photo and holds `\`.
  - Screenshots are in `docs/verification/phase2/`.

### Studio redesign and RAW (2026-10-04)
- **UI:** light "Studio" look and the Auto / Manual split, specified in `docs/DESIGN.md` §0. Portrait panel regrouped into Skin / Face / Shape / Scene with Auto Retouch on top. Screenshots: `docs/verification/studio/`.
- **Camera RAW import (macOS, iOS):** CR3, CR2, DNG, NEF, ARW and RAF import through Apple's built-in RAW decoder (`CIRAWFilter`, channel `lumen/raw`); nothing was installed. The untouched RAW is kept in `originals/`, and a developed sRGB JPEG (quality 0.98, camera EXIF kept, GPS and serial numbers dropped) in `renditions/` feeds the editor and export through `CatalogRepository.readPixelSource`. Checked with a real 45 MP Canon R5 `.cr3` (`integration_test/raw_import_test.dart`, run with `--dart-define=LUMEN_RAW_SAMPLE=<path inside the app container>`).
  - Limits: Android and Windows show "RAW photos aren't supported on this device yet"; they need a bundled decoder such as LibRaw (needs install approval). CR2 is covered by unit tests only (no sample file).

### Auto Enhance v2 (2026-10-04)
The one-click (and on-import) edit was rebuilt on how professionals work (research 09 §1–2; what the old one did wrong: research 10). Code: `packages/lumen_core/lib/src/auto/enhance_*.dart`, `skin_*.dart`, `frame_measure.dart`; constants with their calibration notes in `enhance_constants.dart`.

- **What it does**, in this order, each stage measured on a rendered 256-px proxy:
  1. **White balance** is a confidence-weighted vote (shades-of-grey, grey-edge, white-patch, near-neutral objects, skin outside its window) with a skin-locus check. Skin already in its window plus a small correction means "leave it". A warm cast is corrected only in part (0.35 at golden hour, 0.5 with faces, 0.65 with nobody in frame); a cool cast is corrected at 0.8. Necks, arms and hands are kept out of the vote so skin is not read as "warm light".
  2. **Exposure** is anchored on lit skin when faces are known. Each face gets a tone-adaptive target band from its luminance relative to the scene white (never from its own brightness). Inside the band nothing moves; outside, it is moved to just inside the band. Deep skin is never pushed towards a light-skin target, the lightest face of a group is never pushed over its band, and what the darker faces still lack goes to Shadows. Without faces: median against a scene-adaptive key with an accept band, damped. Per-scene caps: portrait −1.0…+2.0 EV, other −1.5…+2.5.
  3. **Highlights / shadows / whites / blacks** come from clip statistics (P99.9 white point 0.97, P0.1 black point 0.02), with hot skin and bright fabric protected. Light that is blown as shot keeps its white (never grey); a white stretch never undoes a highlight pull.
  4. **Contrast** pivots on middle grey and is never negative unless the light is harsh (hard-lit faces, or both ends clipped without faces).
  5. **Vibrance / saturation** with portrait caps (+12 / +3) and no boost when skin is already rich or the frame already has vivid colour.
  6. **Guardrails:** every delta scaled by a confidence, tiny deltas zeroed, and an explicit "Already looks good: no changes needed" outcome. Low-key and high-key scenes keep their key. Files an editor already wrote get 0.4 of every move and no white balance.
- **Faces:** the app passes face *boxes* from the local face cache into the solve (`features/ai/auto_faces.dart` → `AiPhotoContext.faces` → `AutoEditInput.faces`). Nothing about faces is written into the edit. Where face analysis cannot run (web, missing models) the solver works from the whole frame.
- **Styles** (Natural, Vibrant, Moody, …) and the AI amount slider layer on top exactly as before; a style's key shift also moves the skin bands (≤ ±6 L\*).
- **"What I changed"** reasons now say why in the photo's terms ("to bring faces up to a natural level", "to ease the warm cast and keep its mood"), and the intent line says what was left alone.
- **Float-ready:** measurements read `LinearPixels` (linear floats, values above 1.0 allowed), so a float RAW pipeline can feed them without change. The solver's renders are still the 8-bit CPU reference.
- **How it was evaluated:**
  - `test/auto/enhance_portrait_test.dart`: painted portraits from four skin reflectances (deep to light) under/over-exposed, on bright and dark backgrounds, in tungsten, blue and green light, golden hour, high key with a white dress, low key, and a mixed-tone group. Judged on the CPU reference render (skin L\* in band, skin hue in its window, clipping), not only on slider values.
  - `test/auto/enhance_properties_test.dart`: caps never exceeded, deterministic, batch = single, every change explained, "no changes" outcome.
  - `test/auto/enhance_units_test.dart`: each building block, including float pixels above 1.0. `test/auto/local_auto_tone_test.dart`: scenes without faces (successor of the PLAN §9 checks 17–23, rewritten where the new behaviour differs on purpose).
  - Real photos (the user's own, not in the repo): the Canon R5 portrait of research 10 and an iPhone DNG of a cargo van, old vs new side by side, plus ±EV and colour-cast variants of the portrait. Portrait: old `temp −32, tint −6, contrast −20, highlights −30, shadows +18, whites +42, blacks −6, vibrance +20`; new `highlights −14, shadows +14, whites +9`, with "skin tones look right, so the light was kept as shot".
- **Known limits:**
  - Skin tone class needs a white reference in the frame. Without one the band is the union of all classes and exposure moves by at most +0.5 EV for faces, so an under-exposed light-skinned face on a dark background is only partly lifted. A sclera/teeth reference from the face mesh would fix this.
  - The solver proxy is 8-bit: negative exposure is limited to −0.6 EV when light is blown as shot, and positive exposure cannot recover what is not there.
  - The solve runs on the uncropped, unwarped frame (so faces map to pixels); a tight crop does not change the result.
  - No per-series white-balance consistency yet (each photo is solved alone), no HSL skin nudges, no detail stage (sharpen masking, noise).
  - Style thumbnails in the editor are solved without faces, so a thumbnail can differ slightly from the applied result on portraits.
  - Constants are calibrated on synthetic scenes and two real photos; a larger real set is needed before calling them final.

### High bit depth: RAW in 32-bit float (2026-10-04)
- **What changed:** on macOS and iOS, camera RAW, 16-bit PNG and 10-bit HEIC are edited on a float path instead of the 8-bit rendition. The native side renders Apple's default RAW look with the extended dynamic range kept (`CIRAWFilter.extendedDynamicRangeAmount`, channel `lumen/raw`: `floatInfo` / `floatRender` / `floatRelease`) into float32 extended sRGB; heal, denoise, retouch and backdrop run in `rgbaFloat32` targets without clamping; develop decodes the headroom, so Exposure, White balance, Highlights and Shadows work on real sensor latitude. Full description, measurements and limits: `docs/HIGH_BIT_DEPTH.md`.
- **Measured on the 45 MP Canon R5 `.cr3`:** 2.4 stops above display white in the source. At Exposure −2 the light bulb region shows 131 luminance levels (sd 47.5) against 47 (sd 7.8) on the 8-bit rendition path; at Highlights −100, 113 against 55. Slider frames stay at 1–3 ms (interactive) and 3–5 ms (full quality) at the 1708 × 2560 preview. The full-resolution export renders from 12 float source windows of 4.2 MP (about 194 MB of GPU memory at a time instead of a 0.9 GB float image) in 7.4–8.1 s against 5.4–6.3 s on the 8-bit path (one run: 12.4 s; opening the photo takes 0.9–4.9 s against 0.2 s, depending on how busy the machine is).
- **Fallbacks:** a start-up probe (`HbdCapability`) checks float upload, float render targets, float filtering and readback; where it fails, on Android / Windows / web (no float decoder) and in the CPU renderer, photos keep the 8-bit rendition path. 8-bit photos are untouched.
- **Info panel:** "Bit depth" (from the file header, recorded at import as `CatalogEntry.bitDepth`; a RAW that does not declare it shows "RAW") and "Editing: 32-bit float" / "8-bit".
- **Tests:** CPU twins in `lumen_core` (`float_develop_test.dart`), GPU-vs-CPU parity and windowed export (`app/test/engine/float_*_test.dart`: run with `flutter test --enable-impeller`; skipped, not failed, under default headless Skia), on device `integration_test/float_engine_on_device_test.dart` and `integration_test/float_raw_test.dart` (real RAW with `--dart-define=LUMEN_RAW_SAMPLE=…`).
- **Limits:** Apple ProRAW gets float precision but no extra headroom; healed pixels and retouch maps are 8-bit; output files are 8-bit; iOS not built or run yet.

## Retouch engine v2 (2026-10-04)

Rebuilt to `docs/research/09-pro-editing-workflows.md` §3–§5 after the diagnosis in `docs/research/10-auto-diagnosis.md`. The architecture is unchanged (per-photo maps built once off the UI thread, pass R in source space, slider drags are uniform-only, CPU twin with parity tests). What the maps hold and what the pass does are new.

### Design
- **The pass is a sum.** `out = src + Σ slider · mask · Δ`. Every skin slider has a precomputed OkLab delta (its change at 100) in a signed 8-bit atlas: Smooth, Shine, heal, dark circles, eye bags, Even tone, iris, veins (`RetouchDelta`, `retouch_maps.dart`). The shader (`retouch.frag`) and its CPU twin (`retouch_kernel.dart`) only add them. The deltas are built from the bands above the pore band, so **no slider value can attenuate pores**, and they are smooth, so preview and export sample the same field.
- **Skin masks are decided by the pixels** (`skin_mask.dart`). The 478-point mesh is a loose prior only: on turned or tilted heads it sits several millimetres off. A pixel is skin when its colour fits this face's own skin (robust per-face fit, any tone), it is not clearly darker than the skin around it (hair, brows, lashes, nostrils), it is not hair-textured, and it is connected to the middle of the face. The effect mask is eroded, then feathered with a guided filter. Toward the hairline the lightness reference is carried outward from the inner face, so dark hair next to deep skin of the same hue is still rejected.
- **Bands** (`band_split.dart`): five components by difference of low-passes at σ = 0.006 / 0.020 / 0.065 / 0.22 IOD. The two widest are masked (normalised) blurs over skin, which removes halos at the hairline, jaw and nostrils. Amplitude selectivity per band keeps strong structure (creases, shadows).
- **Smooth** (`skin_deltas.dart`): at 100 removes at most 30 % of B1, 75 % of B2, 40 % of B3 (lightness), scaled by region (nose 0.6, upper lip 0.5, chin 0.8, under-eye 0.7), by hair texture and by face size. The slider is `(v/100)^1.2`.
- **Shine** (`shine_model.dart`): the specular layer is separated with the dichromatic model (`I = d·skin + m·light`, light colour fitted per face) and removed up to 75 % at 100, never below the surrounding skin, with the colour underneath pulled to the skin around it. Clipped cores are still filled by push-pull (from Shine 20 on).
- **Even tone**: chroma only, excursions from the local skin colour (red 75 %, other 50 %, cheek blush guarded), mean face colour preserved. **Under-eye**: lift toward the cheek below the zone with its colour (70 % / 60 % on light skin, 55 % / 70 % on dark skin), crease kept, only on skin-like pixels.
- **Eyes, teeth**: limits of 09 §4.9 (iris +15 % chroma, sclera a −50 % b −40 % near the iris only, teeth b −60 % and never above `min(sclera P90, 0.92)`). Closed or squinting eyes get no eye work.
- **Blemishes** (`blemish_detect.dart`): 3 σ floor plus absolute contrast, on the skin core only, never inside a highlight; red spots heal, dark marks need more evidence and heal from slider 30, moles and freckles are kept, at most 40 heals per face. The keep / remove spot model is unchanged.
- **Auto Retouch** (`auto/retouch_needs.dart`, `PortraitPresets.valuesFor`): values = measured need × the top of each range, 0 when nothing is needed. Iris is never automatic. Small faces are gated in the maps (Smooth off below 32 px of IOD, colour work off below 20 px).

### Deviations from research 09
- One slider value per group, set from the **neediest** face, instead of one value per face: effects are proportional to what they correct (band amplitude, specular amount, colour excursion), so faces that need less change less, and the All tab keeps working as a master.
- Shine uses the dichromatic split instead of an L / chroma pull, and one cap (75 %) for every tone instead of 60 % / 40 %: with the colour restored the dark-skin result is not ashy (see the metrics), and 40 % left the primary test photo visibly shiny.
- No demographic or make-up classifiers, no smile detection, no verify-and-retry loop. Wrinkle softening has one ceiling (65 %) instead of a per-zone table.
- Skin outside the face oval (neck, ears, hands) is not retouched: without a segmentation model there is no safe way to find it.
- The Smooth need reads the working band (B2) only; the constants of §4.4 were recalibrated on the synthetic set and the real photo.

### Evaluation
`packages/lumen_core/test/retouch/retouch_quality_test.dart` runs the §5.2 metrics on synthetic faces of light, medium and deep skin with specular highlights, make-up shimmer, pimples, a mole and continuous unevenness (generator: `test/retouch/support/synthetic_portrait.dart`, metrics incl. CIEDE2000: `support/quality_metrics.dart`). Results (all sliders at 100 / Auto):

| Metric | Gate | Light | Medium | Deep |
|---|---|---|---|---|
| Pore-band retention TR0 (100 / Auto) | ≥ 0.85 / ≥ 0.92 | 0.978 / 0.994 | 0.980 / 0.993 | 0.980 / 0.993 |
| Mid-band reduction (100 / Auto) | ≤ 0.78 | 0.40 / 0.12 | 0.55 / 0.24 | 0.64 / 0.40 |
| ΔE00 of mean skin colour, Smooth + Even at 100 | ≤ 1.0 | 0.07 | 0.02 | 0.11 |
| ΔE00 of mean skin colour, everything at 100 | ≤ 3.0 | 0.25 | 0.94 | 2.66 |
| Mean skin ΔL (Smooth + Even) | −0.005…+0.003 | −0.0006 | +0.0002 | +0.0016 |
| Halo: hair ring outside the hairline | ≤ 0.3 L* | 0.000 | 0.000 | 0.000 |
| Halo: skin edge vs skin inside | ≤ 1.0 L* | 0.19 | 0.04 | 0.18 |
| Shine: hot-spot excess removed at 100 | 30–85 % | 51 % | 69 % | 67 % |
| Shine: hue of the spot vs matte skin | ≤ 6° | 0.3° | 0.0° | 0.8° |
| Blemish precision / recall (4 pimples, 1 mole) | ≥ 0.9 / ≥ 0.75 | 1.0 / 1.0 | 1.0 / 1.0 | 1.0 / 1.0 |
| Clean skin, sliders at 60: mean ΔE00 | ≤ 0.3 | 0.012 | 0.020 | 0.004 |

The mean-colour limit of 2.0 in 09 §4.13 holds for everything except Shine at 100 on deep skin with large highlights (2.66): taking a hot patch down is a change of the mean by design.

Real photo (the user's Canon R5 RAW, two deep-skin faces, make-up, forehead and nose shine; not in the repo): `integration_test` on the real GPU confirmed the retouch is drawn on the first settled frame, Auto Retouch after Reset all sets values, 7 spot candidates instead of 101 (none healed by Auto), forehead highlight L 0.835 → 0.754 on Auto and 0.718 at Shine 100 with chroma moving toward the skin, lashes / brows / lips / hair / earrings unchanged, export at 5464×8192 matching the preview (mean abs difference 1.4 / 255 after JPEG and resampling).

### Performance
Real photo, 2 faces, maps 1366×2048: map build 0.85 s (AOT, one isolate; 0.9 s in a debug build). A portrait slider change re-records pass R + develop in 1–2 ms on the UI thread; new maps upload in about 35 ms. CPU twin over the 2560 px preview: 37 ms.

### Limits
- Analysis runs on the 2560 px decode, so on a 45 MP file a face that is 15 % of the frame is analysed at about 70 px of IOD: bands finer than about 0.03 IOD and blemishes under about 8 full-resolution pixels are not seen (they are left untouched, never blurred). Analysing each face from a full-resolution crop would lift this.
- Tuned by eye on one real portrait (deep skin). Light and medium skin are covered by the synthetic set and the drawn sample only.
- Hair, beard and glasses are rejected by colour, darkness and texture, not by a parser: blond or grey hair close to the skin's colour and lightness can still be taken for skin (effects there are small: bands of hair are high-amplitude and kept).
- A dedicated face-parsing model would remove most of the mask heuristics (see the engine report).
