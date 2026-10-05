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
- **Measured on the 45 MP Canon R5 `.cr3`:** 2.4 stops above display white in the source. At Exposure −2 the light bulb region shows 131 luminance levels (sd 47.5) against 47 (sd 7.8) on the 8-bit rendition path; at Highlights −100, 113 against 55. Slider frames stay at 1–3 ms (interactive) and 3–5 ms (full quality) at the 1708 × 2560 preview. The full-resolution export renders from 12 float source windows of 4.2 MP (about 194 MB of GPU memory at a time instead of a 0.9 GB float image) in 7.4 s against 5.4 s on the 8-bit path.
- **Fallbacks:** a start-up probe (`HbdCapability`) checks float upload, float render targets, float filtering and readback; where it fails, on Android / Windows / web (no float decoder) and in the CPU renderer, photos keep the 8-bit rendition path. 8-bit photos are untouched.
- **Info panel:** "Bit depth" (from the file header, recorded at import as `CatalogEntry.bitDepth`; a RAW that does not declare it shows "RAW") and "Editing: 32-bit float" / "8-bit".
- **Tests:** CPU twins in `lumen_core` (`float_develop_test.dart`), GPU-vs-CPU parity and windowed export (`app/test/engine/float_*_test.dart`: run with `flutter test --enable-impeller`; skipped, not failed, under default headless Skia), on device `integration_test/float_engine_on_device_test.dart` and `integration_test/float_raw_test.dart` (real RAW with `--dart-define=LUMEN_RAW_SAMPLE=…`).
- **Limits:** Apple ProRAW gets float precision but no extra headroom; healed pixels and retouch maps are 8-bit; output files are 8-bit; iOS not built or run yet.
