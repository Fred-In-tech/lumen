# 07 — Portrait retouching, AI masks and object removal: technology plan

> **Status:** research and design, 2026-10-03. **Scope:** Evoto-style portrait retouching, Lightroom-style AI masks and object removal for Lumen (Flutter 3.47; macOS, iOS, Android, Windows), all of it **sellable commercially**.
> **Reads with:** `docs/PLAN.md` §1.6 (engine), §1.10 (on-device AI), §2.2 (masks schema), `docs/research/03-browser-ai-tools.md` (model and license review), and the engine code in `app/lib/engine/`, `packages/lumen_core/lib/src/render/`, `packages/lumen_core/lib/src/model/mask.dart`.
> **Markers** (same as 03): ✅ **verified** this session against a model card, the official repo, the HF API, pub.dev or an HTTP `HEAD` of the file. 🔶 **unverified**: from docs, memory or my own inference; test before relying on it. ⛔ not commercially usable. ⚠️ usable, but needs legal review.
> **Where this disagrees with PLAN.md**, it is a *proposal*. The changes it proposes are listed in §8.

---

## 0. TL;DR decisions

| Topic | Decision | Why |
|---|---|---|
| Face detection | **MediaPipe BlazeFace** (short-range inside the Face Landmarker bundle, plus **full-range** `blaze_face_full_range.tflite` 1.08 MB for group and wide shots) | Apache-2.0 model cards ✅, trained on Google-collected data (no WIDER FACE), < 1.1 MB |
| Landmarks | **MediaPipe Face Landmarker** (`face_landmarker.task`, 3.76 MB ✅, 478 points including iris) | Apache-2.0 ✅. One mesh topology gives every region polygon the retouch needs |
| Face/skin parsing | **No CelebAMask-HQ model.** Use a hybrid: **MediaPipe Selfie Multiclass** (16.4 MB ✅, classes background, hair, body-skin, face-skin, clothes, accessories, Apache-2.0 ✅) run per face crop, **plus** landmark polygons, **plus** a per-face colour skin model, refined with a guided filter | Every BiSeNet/SegFormer face parser is trained on CelebAMask-HQ or LaPa, which are both non-commercial ⛔ |
| Retouch algorithms | **Classical, on the GPU, no generative model**: 3-band frequency separation with amplitude-selective smoothing, frequency-separated spot healing (push-pull), and OkLab colour ops in a new **retouch pre-pass `R`**. Face reshaping is an **MLS warp field** sampled inside `develop` | Real-time sliders, deterministic, no model or training-data liability, works offline |
| Object removal | **MI-GAN** (MIT; LiteRT fp16 16.3 MB ✅ or ONNX pipeline 28.1 MB) on-device. **LaMa** (Apache-2.0, 208 MB) runs **in the cloud** by default. **Zero-download fallback:** push-pull for spots, Telea for thin holes, PatchMatch for the rest | The quality, size and disk trade-off on this dev Mac (≈ 3.5 GB free) |
| Local adjustments | Up to 8 masks as **two RGBA8 textures (4 masks each) in source-uv**, with per-mask deltas as uniforms, applied **inside the existing `develop` uber pass** | Keeps the "one float pass, 8-bit storage" engine invariant. Budget: 7 samplers, ≈ 230 floats (§4.4) |
| Runtime | **Proposal: `flutter_litert` (LiteRT) is the primary on-device runtime** for Phase 2 (MediaPipe models are native `.tflite`; MI-GAN, MODNet and Real-ESRGAN have LiteRT ports). `flutter_onnxruntime` is added only for models with no LiteRT port (LaMa, BiRefNet, EdgeTAM, skyseg), or those go to the cloud | Natives are bundled on all four platforms; the minimum OS stays lower (iOS 13 ✅ vs ORT's iOS 16 / macOS 14); Metal/CoreML/GPU delegates; one runtime |
| Cloud | Dart gateway (auth, rate limit, metering) → **Python sidecar** (FastAPI + onnxruntime-gpu on an L4-class GPU) for LaMa HQ, HQ masks and future generative fill | Evoto itself is **hybrid**: some algorithms run locally, but it "relies on algorithms and computing resources in the Evoto cloud" ✅ (Evoto Trust Center) |
| Privacy | **Never persist raw landmarks in `edit.json`.** Keep them in a local, non-synced cache. No face recognition and no embeddings | A "scan of face geometry" is a biometric identifier under Illinois BIPA (see 04 §faces). ⚠️ legal review |

**Total retouch model footprint:** about 4.8 MB bundled (Face Landmarker + full-range detector), about 17 MB fetched on the first Retouch (Selfie Multiclass + Hair Segmenter), and about 16 MB on the first Remove (MI-GAN fp16). That is under 40 MB in total, well inside the dev machine's disk budget.

---

## 1. Face pipeline

### 1.1 Options and licenses

| Model | Files (size) | Input | Output | License (weights) | Training data | Verdict |
|---|---|---|---|---|---|---|
| **MediaPipe Face Landmarker** | `face_landmarker.task` **3,758,596 B** ✅ (zip bundle: `face_detector.tflite` + `face_landmarks_detector.tflite` + `face_blendshapes.tflite` 🔶) | detector 128² (BlazeFace card ✅; the Landmarker page says 192², which conflicts 🔶), mesh **256²** ✅ ("cropped face with 25 % margin on each side") | **478** 3-D landmarks ✅ (468 mesh + 10 iris), face flag, 52 blendshapes | **Apache-2.0** ✅ (FaceMesh V2, BlazeFace and Blendshape model cards) | Google-captured smartphone images across 17 geographic regions ✅ (card) | **Pick** |
| BlazeFace short-range | `blaze_face_short_range.tflite` **229,746 B** ✅ | 128×128, float in [−1, 1] ✅ | box + 6 keypoints (eyes, nose tip, mouth, 2 tragions) ✅ | Apache-2.0 ✅ | Google | Inside the bundle. Its card puts faces "further than 2 meters" out of scope ✅ |
| **BlazeFace full-range** | `blaze_face_full_range.tflite` **1,083,786 B** ✅ (file updated 2026-03-11 ✅) | 128² per the docs page 🔶 (the older full-range model was 192²); read it from the tensor | same | Apache-2.0 🔶 (family card; full-range card not fetched) | Google | **Pick** for photos (group, half-body, back camera) |
| YuNet (OpenCV Zoo) | `face_detection_yunet_2023mar.onnx` **232,589 B** ✅; LiteRT port `yunet_fp16.tflite` 256,228 B ✅ | dynamic (10–300 px faces ✅) | box + 5 landmarks | MIT ✅ (LiteRT repo is tagged BSD-3 ✅, which is inconsistent) | **WIDER FACE**, which HF lists as **CC-BY-NC-ND-4.0** ✅ | ⚠️ Fallback only (data provenance) |
| RetinaFace (biubug6 PyTorch) | ~1.7 MB (mobilenet0.25) 🔶 | any | box + 5 | code MIT 🔶 | WIDER FACE (NC) | ⚠️ Same issue, no gain over BlazeFace |
| **SCRFD / InsightFace** (any model) | — | — | — | ⛔ "The training data containing the annotation (and the models trained with these data) are available for **non-commercial research purposes only**" ✅ (InsightFace README) | — | ⛔ Never ship |
| Apple Vision `VNDetectFaceLandmarksRequest` | OS | — | 76-point constellation 🔶 | OS API | — | Not used: a different topology per platform breaks parity |
| ML Kit Face Mesh | Android only, beta 🔶 | — | 468 | ML Kit terms | — | Not used (same reason) |

**Decision:** one cross-platform stack (MediaPipe models via LiteRT), so landmarks, region masks and retouch results are identical on all four platforms.

### 1.2 Pipeline (our own wrapper, not the MediaPipe Tasks API; Tasks is not available for Flutter desktop)

1. **Detect** on a downscaled copy (long edge 512–768) with the **full-range** detector. For group shots (more than 4 faces, or faces under 4 % of the long edge), also run 2×2 tiles with 25 % overlap. Decode the anchors with SSD decoding and use **weighted NMS** (IoU 0.3), as MediaPipe does. Short-range anchors are 896 = 16×16×2 + 8×8×6, and the regressor has 16 values (box + 6 keypoints × xy) 🔶; read the tensor shapes at load and never hard-code them.
2. **Align**: roll = angle of the eye-to-eye keypoint line. Crop a square = box × 1.5 (the card asks for a 25 % margin each side ✅), rotated so the eyes are horizontal (the card tolerates 8° ✅). Sample from the **full-resolution source** (not the 512-px copy) with bilinear filtering → 256×256, float in [0, 1] 🔶 (read the normalization from the TFLite metadata).
3. **Landmarks**: run the mesh model, then map the 478 points back through the inverse affine to **source pixels** (and source-uv).
4. **Refine** (desktop, and any face over 25 % of the frame): recompute the crop from the first-pass landmarks (as MediaPipe's tracking mode does) and run the mesh again. Expect a small accuracy gain on stills 🔶.
5. **Reject** faces whose face flag is < 0.5, whose IOD (inter-ocular distance) is < 24 px in the source, or whose yaw is > 60°, with yaw estimated from the nose-tip offset relative to the eye midpoint. These get no automatic retouch. Masks and manual tools still work.
6. **Cost:** detector ≈ 3 ms, mesh ≈ 5–8 ms per face on Apple Silicon CPU/XNNPACK 🔶 (`face_detection_tflite` reports 3.5–8 ms per face ✅). Run it once per photo in a worker isolate and cache it (§1.5).

**Derived geometry** (used by every recipe below; all lengths are in units of **IOD** so the recipes work at any resolution):
- `IOD` = distance between the iris centres **468** and **473**.
- Face axis: from the eye midpoint to chin **152**. Roll = angle of 33→263.
- Iris radius r = mean distance from 468 to {469, 470, 471, 472} (and 473 to {474…477}).
- Face size class: small (IOD < 60 px), medium, or large (> 250 px). This picks the band sigmas in §3.

### 1.3 Landmark index map

Indices come from `mediapipe/python/solutions/face_mesh_connections.py` (fetched and cycle-ordered this session ✅). Under-eye rings, cheeks, forehead, nasolabial and crow's-feet sets were **checked against `canonical_face_model.obj`** ✅ (positions printed and mirror pairs computed). "R" means the subject's right, which appears on the image's **left** in a non-mirrored photo. MediaPipe's `RIGHT_EYE` contains 33/133 (canonical x < 0). **Pair sides with the mirror table, never by name** 🔶.

| Region | Subject's right | Subject's left | Notes |
|---|---|---|---|
| Face oval (closed, clockwise from the top) | `10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109` ✅ | (one loop) | The mesh top (10) sits at **mid-forehead, not the hairline** |
| Eye (closed loop) | `33, 246, 161, 160, 159, 158, 157, 173, 133, 155, 154, 153, 145, 144, 163, 7` ✅ | `263, 466, 388, 387, 386, 385, 384, 398, 362, 382, 381, 380, 374, 373, 390, 249` ✅ | Upper lid 246…173, lower lid 7…155 |
| Iris | centre **468**, ring `469, 470, 471, 472` ✅ | centre **473**, ring `474, 475, 476, 477` ✅ | Fit a circle; the lids occlude it, so intersect with the eye loop |
| Under-eye ring 2 (lid crease) | `130, 25, 110, 24, 23, 22, 26, 112, 243` ✅ | `359, 255, 339, 254, 253, 252, 256, 341, 463` ✅ | Rings move down and out monotonically (canonical y checked) |
| Under-eye ring 3 (tear trough) | `226, 31, 228, 229, 230, 231, 232, 233, 244` ✅ | `446, 261, 448, 449, 450, 451, 452, 453, 464` ✅ | |
| Under-eye ring 4 (upper cheek) | `35, 111, 117, 118, 119, 120, 121, 128, 245` ✅ | `265, 340, 346, 347, 348, 349, 350, 357, 465` ✅ | Under-eye region = lower lid → ring 4 |
| Eyebrow (polygon = lower edge + upper edge reversed) | lower `46, 53, 52, 65, 55`, upper `70, 63, 105, 66, 107` ✅ | lower `276, 283, 282, 295, 285`, upper `300, 293, 334, 296, 336` ✅ | Upper y > lower y verified |
| Lips outer (loop) | `61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146` ✅ | | Corners at 61 and 291 |
| Lips inner = mouth opening (loop) | `78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 308, 324, 318, 402, 317, 14, 87, 178, 88, 95` ✅ | | **Teeth candidate region** = inner loop. Lips = outer minus inner |
| Nose | ridge `168, 6, 197, 195, 5, 4, 1`; tip **1/4**; base `98, 97, 2, 326, 327`; alar R `4, 45, 220, 115, 48, 64, 98`; bridge side R `193, 122, 196, 3, 51` ✅ | alar L `4, 275, 440, 344, 278, 294, 327`; bridge side L `417, 351, 419, 248, 281` ✅ | Nose polygon (for nose slimming and smoothing exclusion) 🔶: `168, 417, 351, 419, 248, 281, 275, 440, 344, 278, 294, 327, 326, 2, 97, 98, 64, 48, 115, 220, 45, 51, 3, 196, 122, 193`. Validate in the debug overlay |
| Nostrils (exclude from smoothing) | ellipse fitted to `98, 64, 48, 115` | ellipse fitted to `327, 294, 278, 344` | 🔶 |
| Forehead (polygon) | `54, 103, 67, 109, 10, 338, 297, 332, 284, 301, 300, 293, 334, 296, 336, 9, 107, 66, 105, 63, 70, 71` ✅ | (one polygon) | Extend it up by 0.35 IOD along the face axis, then intersect with multiclass **face-skin** to reach the hairline |
| Glabella (frown lines) | `55, 107, 9, 336, 285, 8` ✅ | | |
| Crow's feet zone | hull of `130, 113, 124, 156, 139, 34, 143, 111, 31` ✅ | hull of `359, 342, 353, 383, 368, 264, 372, 340, 261` ✅ | |
| Nasolabial fold (polyline) | `129, 203, 206, 216, 212` ✅ | `358, 423, 426, 436, 432` ✅ | Draw it as a 0.10 IOD-wide stroke |
| Marionette line (polyline) | `57, 43, 202, 210, 169` ✅ | `287, 273, 422, 430, 394` ✅ | |
| Cheek apple (blush centre) | **50**; axis from 205 toward 123 ✅ | **280**; 425 toward 352 ✅ | Ellipse radii 0.45 × 0.28 IOD 🔶 |
| Jaw (slimming control points) | `93, 132, 58, 172, 136, 150, 149, 176, 148` ✅ | `323, 361, 288, 397, 365, 379, 378, 400, 377` ✅ | |
| Chin | `152` (menton), `175, 199, 200` (centre line), `171, 140, 32, 208` ✅ | `396, 369, 262, 428` ✅ | |

### 1.4 Rasterizing regions

Scanline-fill each polygon in a **pure-Dart `lumen_core` rasterizer** (CPU twin, deterministic, unit-testable from landmark JSON fixtures with no model). Use 4× supersampling, rasterize only inside the face bbox × 1.8, then feather with a 3-pass box blur of σ = 0.015 IOD. Work at the **retouch analysis resolution** `Rres` (§3.0).

### 1.5 What to persist (privacy)

- `edit.json` stores **only** slider values, per-face overrides keyed by a non-identifying `faceKey` (normalized bbox centre, rounded to 1/64), manual strokes and model versions.
- Landmarks, region maps and blemish candidates live in `assets/<id>/cache/face.json` and `cache/*.png`. These are local, **excluded from cloud sync, export and backup**, deletable, and rebuilt on demand in about 20 ms per face. ⚠️ Have counsel confirm that on-device face geometry which never leaves the device and is never used for identification is outside BIPA "collection".
- Never compute or store face embeddings. `face_detection_tflite` bundles MobileFaceNet recognition ✅; **do not use that part**.

---

## 2. Face and skin parsing

### 2.1 License landscape (why the obvious models are out)

| Option | License claim | Training data | Verdict |
|---|---|---|---|
| BiSeNet face-parsing (zllrunning) and every derivative, incl. `litert-community/BiSeNet-Face-Parsing-LiteRT` (52.6 MB, **tagged MIT** ✅) | code MIT | **CelebAMask-HQ**: "non-commercial research … not … exploit for any commercial purposes, any portion of the images and any portion of **derived data**" ✅ | ⛔ (the MIT tag does not cure the dataset terms) |
| `jonathandinu/face-parsing` (SegFormer-B5) | NVIDIA Source Code License (NC) + CelebAMask-HQ | ⛔ (03 §1d) | ⛔ |
| LaPa-trained parsers (FaRL/`facer` heads, AGRNet…) | code MIT | **LaPa**: "non-commercial purposes such as academic research…" ✅ | ⛔ |
| Sapiens (Meta) body-part seg | CC-BY-NC-4.0 (03) | — | ⛔ |
| **MediaPipe Selfie Multiclass 256×256** | **Apache-2.0** ✅ (model card, 2023-05-10) | Google; "thousands of samples with diverse identities" ✅; fairness-evaluated across Monk skin tones 1–10 and gender ✅ | ✅ **Pick.** The card says it is not for "applications that require pixel perfect masks" ✅, so refine it (§2.2) |
| **MediaPipe Hair Segmenter** | **Apache-2.0** ✅ | Google | ✅ Optional: hair edges and flyaways (§3.12). 781,618 B ✅, 512×512 ✅ |
| Apple Portrait **semantic segmentation mattes** (`AVSemanticSegmentationMatte` types hair, skin, teeth, glasses ✅) | OS data embedded in the photo | Apple | ✅ **Free bonus**: iPhone Portrait-mode HEICs carry these as auxiliary images (read via ImageIO `CGImageSourceCopyAuxiliaryDataInfoAtIndex`). Use them when present (Apple only) |
| SAM/EdgeTAM prompted with landmark boxes | Apache-2.0 weights (03) | SA-1B (research-licensed dataset) 🔶 | ⚠️ Optional refinement of hair or clothes later |

### 2.2 The commercial-safe hybrid parser (`FaceParser`)

For each accepted face:
1. **Multiclass on a face crop**, not the whole frame. Crop the face bbox × 2.2 (squared, axis-aligned) → 256×256 → 6 probability planes (`[1,256,256,6]` float ✅ card). Running per crop gives 4–20× more pixels per face than a whole-image pass. Multiclass is 217 ms CPU / 71 ms GPU per Google's own benchmark ✅ (the benchmark device is unspecified), so batch the faces.
2. **Upsample with a guided filter** against the source luma at `Rres` (r = 0.02 IOD, ε = 1e-3) → soft `faceSkin`, `bodySkin`, `hair`, `clothes`, `accessories` (glasses, earrings, hats).
3. **Colour skin model** (catches stray hair, glasses frames and make-up edges that multiclass misses). Sample OkLab from cheek patches (around 50/280, radius 0.15 IOD) and the forehead centre, excluding the top and bottom 10 % of L. Fit a mean μ and covariance Σ of (a, b), plus an L range. Then `pSkinColor = exp(−½·d²_Mahalanobis(ab))·smoothstep(Lp2 − 0.08, Lp2, L)`.
4. **Compose**:
   `skin = max(faceSkin, bodySkin) · mix(1, pSkinColor, 0.5) · (1 − hair) · (1 − accessories·0.8)` minus the feathered **protect** polygons: eyes (dilated 0.04 IOD), brows, lips outer, nostrils, and a 0.02 IOD band at the lash line.
5. Multi-person: multiclass has no instances, so assign each non-face skin pixel to the nearest face (Voronoi on face centres limited to body components connected to that face). Apple's `VNGeneratePersonInstanceMaskRequest` (iOS 17+, up to 4 people 🔶) can replace this on Apple.

### 2.3 Region maps produced (all 8-bit, source-uv, at `Rres`)

| Texture.channel | Region | Built from |
|---|---|---|
| `regionA.r` | **skin weight** (× per-face override multiplier, baked in) | §2.2 |
| `regionA.g` | **under-eye** | lower-lid loop → ring 4 polygon, minus a 0.03 IOD lash band, feathered 0.05 IOD |
| `regionA.b` | **mouth opening** (teeth candidate) | inner-lip loop, eroded 0.01 IOD |
| `regionA.a` | **sclera candidate** | eye loop minus iris disc (r × 1.05), eroded 0.005 IOD |
| `regionB.r` | **iris** | iris disc ∩ eye loop, minus pupil (r × 0.35) |
| `regionB.g` | **lips** | outer minus inner loop ∩ colour check (a* > skin μa + 0.02) |
| `regionB.b` | **blush** | oriented Gaussian ellipse at 50/280 × skin |
| `regionB.a` | **wrinkle map** | ridge detector (§3.4) × (forehead ∪ glabella ∪ crow's feet ∪ under-eye ∪ nasolabial ∪ marionette strokes) |

---

## 3. Retouch algorithms

### 3.0 Where retouch runs in the engine

```
original ──decode──► source (preview or export tile)
   │                    │
   │      heal patches  ▼   (Canvas drawImageRect of RGBA patches: §5.5)
   │               healed source ──► N denoise? ──► R retouch pre-pass ──► D develop (+warp, +masks) ──► F finish
   │                                                  ▲  ▲  ▲  ▲  ▲  ▲          ▲      ▲
   └─► once per photo (isolate, CPU twin in lumen_core):│  │  │  │  │  │          │      │
        FaceAnalysis → RetouchMaps: B1, B1heal-delta, B2, B3, regionA, regionB      warp   masks0/1
```

- **`R` = `retouch.frag`**, a source-space pre-pass that mirrors the existing NR pass `N` (`denoise.frag`). It outputs 8-bit sRGB at the source/preview size, is cached by a `RetouchUniforms.key`, and is **skipped when every retouch slider is 0**. Export runs it per tile on the full-resolution source, exactly like `N` (PLAN §1.6, step 4).
- **`RetouchMaps`** are built once per photo on the CPU in an isolate (same pattern as `AuxMaps.compute` ✅ in the code), **restricted to face bboxes × 1.8**, at `Rres` = the resolution where σ1 ≥ 1.25 texels, clamped to [1024, 2048] long edge. They are uploaded as RGBA8 and **sampled in source-uv**, so they are resolution independent. Preview and export match, and tiles have no seams (the same argument as AuxMaps).
  - `B1` = Gaussian(σ1 = 0.012 IOD) of the source: fine/mid split.
  - `B2` = guided filter (guide = OkLab L, r = 0.06 IOD, ε = 4e-4) of the source: edge-aware tone base.
  - `B3` = box³ blur (r = 0.25 IOD) over **skin pixels only** (normalized convolution: blur(skin·c)/blur(skin)): broad skin reference colour.
  - `Bh` = blemish-heal delta (§3.3) in OkLab, stored as `0.5 + Δ/(2·range)` with range (L, a, b) = (0.25, 0.1, 0.1) and alpha = spot mask.
  - Faces of different sizes get their own sigmas: process each face bbox with its own IOD, and on overlap the larger face wins.
- **Warp** (face reshape and liquify) is **not** in `R`. It is a displacement field applied in `develop`'s `sourceUv()` (§3.10), so source, aux, retouch and mask textures are all sampled at the same warped uv. They stay consistent, and geometry edits still never invalidate anything.
- Sampler budget for `R`: source, B1, B2, B3, Bh, regionA, regionB = **7** (≤ 8, see §4.4).

All recipes below run in **OkLab of linear sRGB** (`linSrgbToOklab` already exists in `lib/common.glsl` ✅). OkLab L is perceptual, so one threshold works in shadows and highlights.

### 3.1 Skin smoothing: 3-band frequency separation, amplitude-selective

Bands (per pixel, in OkLab): `fine = I − B1` (pores, fine hair, grain), `mid = B1 − B2` (blotches, bumps, acne swelling, small shadows), `base = B2` (form and lighting).

The key quality lever is **amplitude-selective** reduction of `mid`. Low-amplitude variations (blotches) are flattened. High-amplitude structure (nostril shadows, lid creases and jaw edges that leaked into the mask) is kept. That is the difference between "airbrushed plastic" and "retouched".

```glsl
// retouch.frag (excerpt). Flutter-safe: vec4 uniforms only, 2-arg texture().
uniform vec4 uSkin;    // smooth 0-1, textureKeep 0-1, even 0-1, ampThreshold (OkLab L, default 0.035)
uniform vec4 uFace1;   // underEye, teeth, sclera, iris (0-1)
uniform vec4 uFace2;   // shine, wrinkle, lips, blush (0-1)
uniform vec4 uLip;     // target OkLab L, a, b, 0
uniform vec4 uBlush;   // target OkLab L, a, b, 0
...
vec3 lI  = linSrgbToOklab(srgbDecode(texture(uSource, uv).rgb));
vec3 l1o = linSrgbToOklab(srgbDecode(texture(uB1, uv).rgb));   // original low band
vec3 l2  = linSrgbToOklab(srgbDecode(texture(uB2, uv).rgb));
vec3 l3  = linSrgbToOklab(srgbDecode(texture(uB3, uv).rgb));
vec4 bh  = texture(uBh, uv);                       // blemish heal: rgb = 0.5 + ΔOkLab/(2·range), a = spot alpha (§3.3)
vec3 l1  = l1o + (bh.rgb * 2.0 - 1.0) * bh.a * vec3(0.25, 0.1, 0.1);   // healed low band; range (L, a, b)
vec4 ra = texture(uRegionA, uv);
vec4 rb = texture(uRegionB, uv);

float s    = uSkin.x * ra.r;
vec3  fine = lI - l1o;                             // fine vs the ORIGINAL B1: pores survive healing
vec3  mid  = l1 - l2;                              // healed: the blemish leaves the mid band
float keep = smoothstep(uSkin.w, 2.5 * uSkin.w, abs(mid.x));         // big structure survives
float wr   = uFace2.y * rb.a;                                         // wrinkle boost (§3.4)
vec3  midO = mid * (1.0 - clamp(s * (1.0 - keep) + wr * 0.85, 0.0, 1.0));
vec3  fineO = fine * mix(1.0, mix(0.4, 1.1, uSkin.y), ra.r) * (1.0 - 0.3 * wr);
vec3  baseO = l2;
baseO.yz += uSkin.z * ra.r * (l3.yz - l2.yz);                         // tone evening (§3.2)
vec3  o = baseO + midO + fineO;
// ... §3.5–3.9 modify `o` ...
fragColor = vec4(clamp(srgbEncode(oklabToLinSrgb(o)), 0.0, 1.0), 1.0);
```

- **Sliders:** *Smooth* 0–100 → `uSkin.x = (v/100)^0.8` (more resolution at the low end). *Texture* 0–100 (default 70) → `uSkin.y`. *Even tone* 0–100 → `uSkin.z = 0.8·v/100`.
- When smooth > 0.6, also lower `ampThreshold` to 0.025 so medium bumps flatten too.
- **Never** smooth outside `skin`. Protect polygons are already baked into `regionA.r`.

### 3.2 Tone evening

The chroma of the edge-aware base is pulled toward the broad skin reference `B3` (same skin, averaged over 0.25 IOD). This evens blotchy redness, uneven tan lines and the yellow/red patches between nose and cheek, **without** changing overall skin colour or lighting (L is not touched). Shown in §3.1 (`baseO.yz`). An optional L evening at 0.3× strength can be added later; it flattens the face, so it stays off by default.

### 3.3 Blemish / acne detection and healing

**Detection** (CPU, isolate, per face, after normalizing the face crop to IOD = 160 px so the thresholds are scale-free):
1. Work on `L` and `a*` of the face crop. Compute DoG responses at σ ∈ {1.5, 2.5, 4.0} px (blob scales of 0.6–2.5 % IOD).
2. Local statistics: robust σ_L of the mid band in a 0.15 IOD window over skin (median absolute deviation × 1.4826).
3. Candidate = a scale-space minimum of DoG(L) with `−DoG/σ_L > k`, **or** a maximum of DoG(a*) with `DoG_a/σ_a > k` (red spots), **and** roundness (Hessian eigenvalue ratio < 3; rejects wrinkles and pores lines), **and** inside `skin`, more than 0.08 IOD from the eye/brow/lip/nostril polygons.
4. Score each spot with its z-score. Size = 1.4 × blob σ × √2.
5. **Moles:** dark (L < skin μL − 0.15), round, radius > 0.025 IOD → flagged `mole` and **kept by default** (a toggle removes them).
6. Store the candidates (centre, radius, score, kind) in the face cache. The slider only **selects** among them, so dragging needs no re-detection: `k = mix(4.0, 1.8, v/100)` and `maxRadius = mix(0.02, 0.06, v/100) · IOD`.

**Healing small spots: frequency-separated push-pull.** A blemish lives in the low/mid band. The pores on top of it are what make skin look real. So: replace **`B1` inside the spot** with a membrane interpolation from the ring around it, and **keep the original fine band**. Pores continue through the healed spot. This is the band-limited version of the Photoshop healing brush (a Poisson/membrane fill; Pérez et al. 2003).
1. Hole alpha α = soft disc (radius × 1.3, feather 30 %).
2. **Push-pull** (pull: 2×2 alpha-weighted average down to 1 px; push: upsample and fill where α < 1; Gortler et al. 1996) of `B1` with weights 1 − α. Cost: about 2·log₂(N) tiny passes, under 5 ms on the GPU or about 20 ms on the CPU per face crop 🔶.
3. Store `Δ = B1heal − B1` and α into `Bh` (§3.0). `R` adds Δ·α to `l1` (excerpt above).

**Larger spots and user strokes** (radius > 0.06 IOD, scars, stray hairs across the cheek): a **MI-GAN patch** (§5), stored as a heal op in the retouch layer. Then run the same fine-band reinjection on top: `patch = MI-GAN(low band) + donor fine band` from an offset skin area, chosen by minimum SSD of `B1` on the ring. This avoids MI-GAN's waxy texture at 512-px internal resolution.

**Manual heal brush:** a click or stroke → under 0.06 IOD uses push-pull (instant); above that, MI-GAN. Each dab is a heal op, so it can be undone or deleted individually.

### 3.4 Wrinkle softening

1. **Ridge map** on L of the face crop (IOD = 160 px): Hessian at σ_w ∈ {1.5, 2.5} px. A wrinkle is a dark valley, so use the largest eigenvalue λ₁ > 0 with |λ₁| ≫ |λ₂| (Frangi-style vesselness: `V = exp(−Rb²/2β²)·(1 − exp(−S²/2c²))`, β = 0.5, c = half the max S).
2. Multiply by the region masks: forehead, glabella, crow's feet, under-eye rings 1–3, nasolabial and marionette strokes (§1.3). The ridge detector only runs where wrinkles are expected, so it does not erode lip lines or hair.
3. Dilate by 0.01 IOD, feather, and store in `regionB.a`.
4. In `R`, the wrinkle map adds extra `mid` suppression and 30 % fine-band suppression (excerpt above, `wr`).
5. **Slider:** *Wrinkles* 0–100 → `uFace2.y = v/100`. A *Nasolabial* sub-slider is a second weight baked into the map (§3.13).
6. Deep folds have real shading. Softening must stay below 85 % or the face loses its form; that is why the clamp is there.

### 3.5 Under-eye: dark circles and bags

```glsl
float ue = uFace1.x * ra.g;
float dL = max(0.0, l3.x - l2.x);            // how much darker than the broad cheek/skin reference
o.x  += ue * 0.8 * dL;                        // lift the dark circle (never above the reference)
o.yz += ue * 0.6 * (l3.yz - l2.yz);           // remove the blue/purple cast
o    -= ue * 0.5 * (midO * (1.0 - keep));     // flatten the bag's mid-band shading (on top of §3.1)
```

`B3` is averaged over 0.25 IOD, which includes the cheek under ring 4, so the target is "this person's cheek colour". No per-face uniforms are needed. *Under-eye* slider 0–100 → `uFace1.x`.

### 3.6 Teeth whitening

Teeth = mouth opening ∩ bright ∩ not gum/tongue:

```glsl
float T = ra.b * smoothstep(0.55, 0.72, lI.x)          // bright (OkLab L) 🔶 tune on real photos
              * (1.0 - smoothstep(0.035, 0.08, lI.y));  // not red (gums, tongue, lip edge)
float tw = uFace1.y * T;
o.z *= 1.0 - 0.85 * tw;                                 // remove yellow (b*)
o.y *= 1.0 - 0.40 * tw;                                 // neutralize residual red
o.x += 0.06 * tw * (1.0 - o.x);                         // slight lift
```

**Naturalness cap:** the CPU passes `capL` = the minimum over faces of the sclera P90 L (from the face cache) in the spare lane `uLip.w`, and `o.x = min(o.x, max(lI.x, capL))`. Teeth never get brighter than the eye whites ("toilet-white" is the #1 complaint about cheap tools). *Teeth* slider 0–100 → `uFace1.y`.

### 3.7 Eyes: sclera whitening and iris enhancement

- **Sclera:** `S = ra.a * smoothstep(0.45, 0.62, lI.x)` (excludes lashes and lid shadow). `o.y *= 1 − 0.7·sw·S` (redness, i.e. veins, has a* > 0), `o.z *= 1 − 0.4·sw·S`, `o.x += 0.05·sw·S·(1 − o.x)`. Slider *Eye whites* → `uFace1.z`.
- **Iris:** `Ir = rb.r * (1 − smoothstep(0.85, 0.95, lI.x))` (keeps the catchlight). Local contrast `o.x += 0.6·iw·Ir·(lI.x − l2.x)`, chroma `o.yz *= 1 + 0.35·iw·Ir`, `o.x += 0.03·iw·Ir`. Slider *Iris* → `uFace1.w`.
- **Enlarge eyes** is geometry (§3.10), not colour.

### 3.8 Shine and oil reduction

Specular shine on skin is **bright relative to local skin** and **less saturated than skin**:

```glsl
float rel  = l1.x - l3.x;                                        // brighter than the broad base
float desat = 1.0 - smoothstep(0.6, 0.95, length(l1.yz) / max(length(l3.yz), 1e-3));
float Sh = ra.r * smoothstep(0.03, 0.10, rel) * desat;
float sh = uFace2.x * Sh;
o.x  -= sh * 0.7 * rel;                                          // pull L down toward the base
o.yz  = mix(o.yz, l3.yz, sh * 0.5);                             // restore skin chroma
```

Fine texture is kept, so the matte result still has pores. *Shine* slider 0–100 → `uFace2.x`. Clipped highlights (L ≈ 1) have no detail left, so above 50 % shine with clipped pixels, run push-pull fill of the shine core as a soft hole (the same machinery as §3.3).

### 3.9 Makeup: lip colour and blush

- **Lips** (`rb.g`): recolour in OkLCh and keep the texture. Shift the hue toward the target (shortest arc), scale chroma by `C_target/C_meanLip` (so the gradient and gloss stay), and nudge L by 30 % toward the target. Skip gloss highlights (L > lip P95). Slider *Lip colour amount* 0–100 plus a colour swatch → `uFace2.z`, `uLip`.
- **Blush** (`rb.b`, an oriented Gaussian at 50/280 along 205→123): `o.yz = mix(o.yz, uBlush.yz, 0.35·ba·rb.b)` and `o.x = mix(o.x, uBlush.x, 0.08·ba·rb.b)`. Slider *Blush* → `uFace2.w`.
- Eyeliner, eyeshadow and brows are later (the same polygons work, but the UX needs swatches and shapes).

### 3.10 Face reshaping and liquify: an MLS warp field sampled in `develop`

**Representation.** One **displacement field** in source-uv, stored as a packed 16-bit RGBA8 texture (RG = dx hi/lo, BA = dy hi/lo; value 0.5 = no move; range ±0.0625 uv). Size: 1024 long edge (2048 on desktop when the smallest face IOD is under 1.5 % of the long edge). It is sampled with `FilterQuality.none` and the same manual 4-tap bilinear as `sampleAux` ✅ (the existing code), and applied **first** in `develop`:

```glsl
uniform sampler2D uWarp;        // 1x1 neutral texture when unused
uniform vec4 uWarpInfo;         // w, h, range, enabled
vec2 warpUv(vec2 suv) {
  if (uWarpInfo.w < 0.5) return suv;
  vec4 t = sampleWarpBilinear(suv);                 // 4 texel-centre taps, unpack16 each, then mix
  return suv + (vec2(t.x, t.y) - 0.5) * 2.0 * uWarpInfo.z;
}
// main(): vec2 suv = warpUv(sourceUv(uv));   // source, aux, retouch and masks all use suv
```

**Building the field (CPU, isolate):**
- Slider-driven reshape uses **Moving Least Squares, similarity variant** (Schaefer, McPhail & Warren, SIGGRAPH 2006 ✅). Control points come from landmarks, moved by the sliders. Anchors (zero displacement): a ring of 24 points at 1.35 × face radius, the image corners, and **fixed feature points** (both eye loops, the nose ridge, the mouth corners) for sliders that should not move them.
- **Backward map directly:** evaluate MLS with `p` = *deformed* positions and `q` = *original* positions. That gives the source location for each output pixel, which is exactly what a fragment shader needs (the standard swap; an approximate inverse that is good for small moves).
- Evaluate on a grid with 6-px spacing over the face bbox × 1.6 and bilinearly fill the field. Cost is grid × control points ≈ 10⁴ × 60, about 5 ms per face 🔶.

```dart
// MLS similarity (backward). p = deformed control points, q = original. α = 1.
Offset mls(Offset v, List<Offset> p, List<Offset> q) {
  var ws = 0.0, ps = Offset.zero, qs = Offset.zero;
  final w = List<double>.filled(p.length, 0);
  for (var i = 0; i < p.length; i++) {
    final d2 = (p[i] - v).distanceSquared;
    if (d2 < 1e-9) return q[i];
    w[i] = 1 / d2; ws += w[i]; ps += p[i] * w[i]; qs += q[i] * w[i];
  }
  ps /= ws; qs /= ws;
  var mu = 0.0, a = 0.0, b = 0.0;
  for (var i = 0; i < p.length; i++) {
    final ph = p[i] - ps, qh = q[i] - qs;
    mu += w[i] * ph.distanceSquared;
    a  += w[i] * (ph.dx * qh.dx + ph.dy * qh.dy);
    b  += w[i] * (ph.dx * qh.dy - ph.dy * qh.dx);
  }
  a /= mu; b /= mu;                                  // M = [[a, b], [-b, a]]
  final d = v - ps;
  return Offset(d.dx * a - d.dy * b, d.dx * b + d.dy * a) + qs;
}
```

**Sliders.** s ∈ [−1, 1] and displacements are in IOD units; `n` = unit vector toward the face axis.

| Slider | Control points moved | Displacement |
|---|---|---|
| Face slim | jaw/cheek oval R `93, 132, 58, 172, 136` and L `323, 361, 288, 397, 365` | `0.06·s·w(y)·n`, with w peaking at 58/288 and fading to 0 at 234/454 and at 152 |
| V-line / jaw | `172, 136, 150, 149` and `397, 365, 379, 378` | inward `0.05·s`, plus up 0.02·s along the axis |
| Chin | `152, 148, 377, 176, 400` | along the axis `0.08·s` |
| Forehead | top oval `10, 338, 109, 297, 67` | along the axis `0.06·s` (only if the hairline is visible: multiclass hair above 10) |
| Nose slim | alar `48, 64, 98, 115, 129` and `278, 294, 327, 344, 358` | toward the nose axis `0.035·s` |
| Nose length | tip `1, 4` | along the axis `0.03·s` |
| Mouth width | `61, 291` | along the mouth axis `0.04·s` |
| **Eye size** | (not MLS) | radial **bulge** about the iris centre, R = 1.6 × eye half-width: `src = c + (p − c)·(1 − a·(1 − (r/R)²)²)`, a = 0.25·s (a > 0 magnifies; Gustafsson 1993-style local scaling) |

**Liquify brush** (forward-warp, bloat, pucker, reconstruct) writes into the **same field**: a CPU `Float32List` with dirty-rect re-pack and upload at ≤ 30 Hz. Strokes are stored as vectors in `retouch.liquify.strokes` and replayed on load (deterministic). The field is cached in `cache/warp.bin`.

**Guards:** cap |displacement| at 0.15 IOD. Background straight lines near the jaw are protected by the anchor ring, and §3.11 has the stronger version.

### 3.11 Body slimming: what is feasible

- **Feasible (Phase 3):** MediaPipe **Pose Landmarker lite** (`pose_landmarker_lite.task` **5,777,746 B** ✅, 33 landmarks, Apache-2.0 ✅ card) plus the person mask. Control points go on the **silhouette contour** at waist (between 11/12 and 23/24), hips and upper arms, pushed toward the body axis. Anchors sit 0.15 body-width outside the silhouette, plus on **straight background lines** found with an LSD/Hough pass in a band around the body (door frames and horizons are what give away a bad slim). The same MLS field, at 2048.
- **Limits:** the pose card lists "multiple people in an image" as out of scope ✅, so run it per person crop. Patterned clothes and backgrounds expose the warp. Ship **manual Body Liquify first** and auto "Slim body" after visual QA.
- **Not feasible on-device:** "reshape with generative background repair". That needs inpainting the uncovered background (MI-GAN on the strip, Phase 3+).

### 3.12 Glasses glare and flyaway hair

| Feature | Feasibility | Recipe |
|---|---|---|
| **Glasses glare** | **Medium: semi-auto.** There is no commercial-safe glare model (research models are NC or unclear 🔶) | Lens region = eye loop dilated 0.35 IOD ∩ (multiclass *accessories* or a user lasso). Glare = additive veil: **estimate the veil** as `B2_inside − pushpull(B2 from the lens boundary)`, clamp ≥ 0, subtract 80–100 %. **Clipped** glare (L > 0.97) → MI-GAN patch on the eye crop. Auto-suggest only when accessories coverage > 30 % of the eye region. Ship as a brush ("Reduce glare") first |
| **Flyaway hair** | **Good on plain studio backgrounds, poor on busy ones** | Hair alpha from **Hair Segmenter** (512²) or MODNet matting. Silhouette `S` = close/open (r = 0.05 IOD) + blur of the hair mask. Strays = (hair alpha ∨ thin-ridge detector on L) in the 0.15 IOD band **outside** `S`. Fill with background push-pull when the background variance in the band is low (σ_L < 0.02), else MI-GAN. Enable auto-mode only on low-variance backgrounds, and offer a "Hair cleanup" brush everywhere |
| Neck lines, stray hairs on skin | Good | Wrinkle ridge map on the body-skin region below the jaw, and heal ops respectively |

### 3.13 Sliders (UI 0–100) → internal parameters

Each slider becomes a `ParamId` (`retouch.*`) in `ParamRegistry`, so history, presets ("Studio headshot", "Natural"), copy/paste (new group `retouch`) and AI instructions ("soften her skin a bit") all work for free. Per-face overrides multiply the global value (baked into the region maps).

| Slider (default) | Param → shader | Mapping |
|---|---|---|
| Smooth skin (0) | `retouch.skin.smooth` → `uSkin.x` | `(v/100)^0.8`; also `ampThreshold = mix(0.035, 0.025, step(0.6, ·))` |
| Skin texture (70) | `retouch.skin.texture` → `uSkin.y` | fine-band gain `mix(0.4, 1.1, v/100)` |
| Even tone (0) | `retouch.skin.even` → `uSkin.z` | `0.8·v/100` |
| Blemishes (0) | `retouch.blemish` → CPU candidate selection | `k = mix(4.0, 1.8, v/100)`, `maxR = mix(0.02, 0.06, v/100)·IOD` |
| Wrinkles (0) / Nasolabial (0) | `retouch.wrinkle`, `retouch.nasolabial` → `uFace2.y`, map weight | linear |
| Under-eye (0) | `retouch.underEye` → `uFace1.x` | linear |
| Shine (0) | `retouch.shine` → `uFace2.x` | linear |
| Teeth (0), Eye whites (0), Iris (0) | → `uFace1.y/z/w` | linear |
| Lips, Blush (0) + colour | → `uFace2.z/w`, `uLip`, `uBlush` | linear |
| Face slim, Jaw, Chin, Forehead, Nose slim, Nose length, Mouth, Eye size (0, range −100…100) | `retouch.shape.*` → warp field | §3.10 table |

**Auto Retouch** = a preset over these sliders, scaled by detected need. For example, *Blemishes* is set from the candidate count, and *Under-eye* from `mean(dL)` in the under-eye region. The `AutoEditProvider` vision path can also return `retouch.*` deltas, because they are registry params.

### 3.14 Why not a learned retouch network (yet)

The public paired-retouch datasets are not commercial: **FFHQR** is "CC BY-NC-SA 4.0 … non-commercial" ✅, and FFHQ-derived data is BY-NC-SA. ABPN's CRHD-3K inputs are Unsplash photos, but the retouched targets and weights have unclear terms 🔶. CodeFormer is S-Lab non-commercial ⛔ (03). **Phase 3 route:** have hired retouchers label licensed portraits (model releases), train a small **slider/strength regressor** (it predicts *our* slider values, so it stays explainable and non-generative, in line with the 04 positioning "developed, not generated"), and optionally a local-correction net later.

---

## 4. AI masks (Lightroom-style)

### 4.1 Mask sources

| Mask | On-device model (commercial-safe) | Fast native path | Refinement |
|---|---|---|---|
| **Subject** | MODNet (Apache-2.0; LiteRT `modnet.tflite` 26.2 MB ✅ / ONNX q8 6.6 MB, 03) for people; BiRefNet_lite (MIT, 114 MB fp16) for objects → **cloud or optional download** | Apple `VNGenerateForegroundInstanceMaskRequest` (iOS 17+/macOS 14+); Android ML Kit Subject Segmentation (beta) (03 §8.2) | guided filter at mask resolution |
| **Background** | 1 − Subject | — | — |
| **Sky** | skyseg (MIT, 176 MB, 03) → **download or cloud**; Depth Anything (DA3-Small LiteRT exists ✅, license 🔶) as validator | — | guided filter + top-connectivity |
| **People** (+ parts: face skin, body skin, hair, eyebrows, sclera, iris, lips, teeth, clothes) | **Selfie Multiclass + Face Landmarker + Hair Segmenter** (§2), all Apache-2.0 | Apple `VNGeneratePersonInstanceMaskRequest` for instances; Portrait semantic mattes when present | §2.2 |
| **Object (click/box)** | EdgeTAM (Apache-2.0, ~40 MB, 03) or SAM2.1-tiny LiteRT (`litert-community` ✅) | — | guided filter |
| Brush / Linear / Radial | none (vector) | — | — |
| Colour / Luminance range (later) | none: computed from the source in the compose pass | — | — |

### 4.2 Representation

- **Every mask is 8-bit, single channel, in source-uv**, the same space as the AuxMaps, so geometry edits and export tiles reuse it unchanged (PLAN §1.6 ✅ invariant).
- Resolution `Mres`: long edge 2048 on desktop, 1536 on mobile. Each 8-bit channel at 2048 × 1365 is 2.8 MB. 256 levels are enough: a 1/255 mask step on a +2 EV local exposure is 0.008 EV.
- **Storage:**
  - AI mask outputs: an 8-bit PNG per component at `assets/<id>/masks/<maskId>_<n>.png` (already reserved in PLAN §2.2 as `maskRef`), with `{model, modelVersion}` recorded. Old edits are reproducible even after a model update.
  - Brush: vector strokes `{points (source-uv), radius (uv), feather, flow, erase}` in JSON, rasterized on load.
  - Linear/radial: analytic parameters (as in PLAN §2.2).
- **Components** (Lightroom's add/subtract/intersect): `shape.components: [{op: add|subtract|intersect, kind, params, ref?}]`. Old single-shape masks map to one `add` component (an additive change).
- **Schema hazard (fix now):** `LocalMask.fromJson` maps an unknown `kind` to `radial` (`orElse: () => MaskKind.radial` in `mask.dart` ✅). A mask written by a newer app (for example `people`) would **silently become a radial** in an older build. Make unknown kinds `unsupported`, rendered as off and kept round-trip, and add the kinds `background, people, object, color, luminance`.

### 4.3 Compose pass → two RGBA mask textures

1. **Raster combine** (CPU isolate or GPU, on component change only): AI rasters + brush raster per mask → one 8-bit raster per mask.
2. **`mask_compose.frag`** (GPU, cheap, re-run while dragging a gradient): per group of 4 masks, samplers = up to 4 per-mask rasters (a 1×1 black texture when absent). Uniforms per mask: one analytic component (linear `x0, y0, x1, y1` / radial `cx, cy, rx, ry, angle, feather`), the op, invert, and an enabled flag. Output RGBA = masks 0–3 (then 4–7). Dragging a linear gradient re-runs one compose pass (under 2 ms at 2048 🔶) plus `develop`.
3. Mask opacity is a uniform scale (§4.4), not baked in, so the opacity slider is uniform-only.

### 4.4 Local adjustments inside the existing `develop` uber pass

**Budget (FragmentProgram):** Flutter documents no explicit max: only `float/vec2-4` and `sampler2D` uniforms, no UBOs, two-argument `texture()` only ✅ (docs). The binding limits are the backends' minimum guarantees:
- **GLES ≥ 16 fragment texture units**. Impeller now validates the *combined* limit ✅ (engine commit e26b384, "Validate GLES texture units against the combined limit").
- WebGL2/GLES3 ≥ **224 fragment uniform vec4s** 🔶 (spec minimum). Vulkan `maxUniformBufferRange` ≥ 16 KB 🔶. Metal uses buffers.
- **Lumen budget per program: ≤ 8 samplers, ≤ 200 vec4.**

| `develop` today ✅ | + warp | + masks | Total |
|---|---|---|---|
| 94 floats, 4 samplers (source, auxA, auxB, curveLut) | +4 floats (`uWarpInfo`), +1 sampler | +4 floats (`uMaskInfo`: count, Mres w/h, 0) + **8 masks × 4 vec4 = 128 floats**, +2 samplers (`uMasks0`, `uMasks1`, `FilterQuality.low`) | **230 floats (57.5 vec4), 7 samplers** ✅ within budget |

Per-mask uniform block (4 × vec4; values are deltas in the global units, pre-scaled by opacity on the CPU):
- `uMkA` = exposure EV, temp, tint, contrast
- `uMkB` = highlights, shadows, whites, blacks
- `uMkC` = clarity, texture, dehaze, saturation
- `uMkD` = hue shift, tint colour OkLab a, b, tint amount

Sharpness and noise local adjustments go in `finish` later (+2 samplers there).

```glsl
// develop.frag additions (sketch; no uniform arrays: 8 masks unrolled by a generator)
vec4 m0 = texture(uMasks0, suv);          // masks 0-3
vec4 m1 = texture(uMasks1, suv);          // masks 4-7
vec4 LA = m0.x*uM0A + m0.y*uM1A + m0.z*uM2A + m0.w*uM3A + m1.x*uM4A + m1.y*uM5A + m1.z*uM6A + m1.w*uM7A;
vec4 LB = ...; vec4 LC = ...; vec4 LD = ...;   // same pattern
// step 3: c *= wbGains(LA.y, LA.z) * exp2(LA.x);           (local WB + exposure)
// step 4: dz = clamp(uHaze.x + LC.z, -1, 1)
// step 5: uLocal.xy + LB.xy (highlights, shadows on the guided base, already analytic)
// step 6: uLocal.zw + LC.xy (clarity, texture, already analytic)
// after step 7 (tone LUT is global): analytic local contrast/whites/blacks:
//   e = log2(Y/0.18); Y' = 0.18*exp2(e*(1+0.5*LA.w)); soft knees for whites/blacks from LB.zw
// after step 11: saturation LC.w (OkLCh chroma scale), hue LD.x (rotate ab), tint mix(ab, LD.yz, LD.w)
```

Almost every local control maps onto math `develop` already does analytically (WB gains, exposure, dehaze, the guided-base shadows/highlights, clarity/texture). Only contrast, whites and blacks need an analytic stand-in, because the global versions live in the tone LUT. Write a generator (`tool/gen_mask_uniforms.dart`) that emits the unrolled GLSL **and** the `uniform_layout.dart` index table, so the existing parity test (`pack().length == kDevelopFloatCount`) keeps guarding it. **Fallback** if a backend rejects 230 floats: move the per-mask deltas into a 16×8 packed-16-bit parameter texture (`FilterQuality.none`, 8th sampler).

---

## 5. Object removal

### 5.1 Models

| | **MI-GAN** (default) | **LaMa big-lama** (HQ) |
|---|---|---|
| License | MIT code + MIT weights ✅ (03); LiteRT port tagged MIT ✅ | Apache-2.0 ✅ (03) |
| Files | LiteRT `migan_fp16.tflite` **16,312,640 B** ✅; ONNX `migan_pipeline_v2.onnx` 28.1 MB (03) | ONNX `lama_fp32.onnx` 208 MB (03); OpenCV Zoo copy 92.6 MB 🔶 |
| I/O | **LiteRT:** input `[1,4,512,512]` float = concat(mask − 0.5, rgb·mask), rgb in [−1, 1]; **mask 1 = keep, 0 = erase**; output `[1,3,512,512]` in [−1, 1]; **the caller crops and resizes** ✅ (model card). **ONNX pipeline:** uint8 image + mask (255 = keep), any H×W, crop, resize and blend inside the graph ✅ (03) | float32 image `[1,3,512,512]` in 0–1, mask 1 = hole; output 0–255 float (03) |
| Speed | 289 ms (2048×1536 via the ONNX pipeline, M1 Max CPU ✅ 03); LiteRT Pixel 8a GPU ~6 ms / S26 GPU 26.6 ms ✅ (card) | 4.7 s per 512² CPU ✅ (03) → GPU or cloud |
| Quality | Good for small and medium holes; waxy on large textured holes | Better structure on large holes and repeating patterns |
| Training data | Places2 ⚠️ | Places2 ⚠️ |
| **Deployment** | **On-device, download on first Remove (16 MB)** | **Cloud by default.** Optional desktop download ("HQ offline") when ≥ 1 GB is free |

### 5.2 Cropping and tiling around the hole (both models)

1. Hole bbox `H` (in source px, from the user mask dilated by 6 px plus 1 % of the long edge).
2. Context crop side = `clamp(2.5 × max(Hw, Hh), 512, 2048)`, square, centred on `H` and shifted to stay inside the image (mirror-pad at the borders).
3. If the crop side is > 512: downscale the crop to 512 for the model, inpaint, then **upsample only the generated region** and blend it into the full-resolution crop with a 1.5 % feather.
4. **Detail restoration** for upsampled fills (a hybrid): synthesize the high-frequency band at full resolution with PatchMatch (§5.3), using the model output as the low-band guide. Matching grain/noise from the surrounding ring is essential, or the fill looks smeared at 24 MP.
5. Several disjoint holes → one crop each (batched for LiteRT). Overlapping crops → union.
6. The result is an **RGBA patch** = crop bbox, with alpha = feathered hole. That is what gets stored (§5.5).

### 5.3 Zero-download classical fallback (always available)

| Method | Use | Cost | Implementation |
|---|---|---|---|
| **Push-pull membrane** | Spots, thin wires on smooth sky/skin, shine cores | ms (GPU) | Shared with §3.3; `lumen_core` CPU twin |
| **Telea fast-marching** (Telea 2004) | Thin scratches, sensor dust | < 100 ms per crop 🔶 | Pure Dart, about 250 lines. Or `opencv_dart` 2.2.2 (Apache-2.0 ✅, prebuilt natives, `photo` module supported ✅) **if** OpenCV is adopted for other reasons. App size is the cost: modules are selectable via hooks ✅ |
| **PatchMatch** (Barnes et al. 2009) multi-scale fill | Medium holes on textured backgrounds; detail restoration in §5.2 | 1–3 s for a 1 MP crop in an isolate 🔶 | Pure Dart (random search + propagation, 7×7 patches, coarse-to-fine, 5 iterations per level) |

The UI picks automatically: hole area < 0.3 % of the image and thin → Telea; small round → push-pull; otherwise MI-GAN if downloaded, else PatchMatch; "HQ" → cloud LaMa.

### 5.4 Edge cases

- **Faces and people inside the hole:** MI-GAN and LaMa hallucinate badly here. Warn when the hole intersects a detected face.
- **Shadows of removed objects:** a "+ include shadow" option dilates the mask down-light (later). For now the user brushes it.
- **Disclosure:** mark AI-filled edits for C2PA/AI labelling, as PLAN §3.2 already requires for Remove.

### 5.5 Non-destructive "retouch layer" in the edit document

```json
"settings": {
  "retouch": {
    "version": 1,
    "values": { "retouch.skin.smooth": 40, "retouch.teeth": 25 },
    "faces": { "detector": "mp-blazeface-fr@2026-03", "landmarker": "mp-facemesh-v2@2023-05", "cache": "cache/face.json" },
    "perFace": { "f-0.42-0.31": { "retouch.skin.smooth": 0.5 } },
    "blemish": { "removed": [], "kept": ["c17"], "manual": ["h3"] },
    "liquify": { "strokes": [ { "tool": "push", "r": 0.02, "p": [[0.41, 0.33], [0.42, 0.34]] } ] },
    "heal": [
      { "id": "h3", "kind": "remove", "engine": "migan@fp16-1", "ai": true,
        "mask": { "strokes": [ { "r": 0.004, "p": [[0.61, 0.20], [0.63, 0.22]] } ] },
        "bbox": [3120, 1004, 812, 812], "patch": "retouch/h3.png", "srcSize": [6000, 4000], "createdAt": "…" },
      { "id": "h4", "kind": "clone", "engine": "copy", "src": [-0.05, 0.0],
        "mask": { "strokes": [ { "r": 0.006, "p": [[0.30, 0.71]] } ] }, "bbox": [1764, 2804, 96, 96], "patch": "retouch/h4.png" }
    ]
  }
}
```

- **Ordered list**: ops apply in order; each one can be deleted, hidden or reordered. History ops target `retouch.heal` as a whole list (as PLAN does for `masks`) and `retouch.values.*` per slider.
- **Patches** are RGBA PNGs at **original resolution, bbox only**, with the feathered alpha baked in. They regenerate deterministically from (source, mask, engine version). MI-GAN is deterministic for a fixed input, so a missing patch file is recomputed.
- **Compositing:** `healed source = source + patches` via `Canvas.drawImageRect` in op order (preview patches downscaled). Then `N` → `R` → `D` → `F`. **Re-run AuxMaps** when the healed area is > 0.5 % of the image, so the shadows/highlights base and dehaze stats do not "remember" the removed object (AuxMaps is under 10 ms ✅ per PLAN).
- **Export:** composite full-resolution patches onto the full-resolution decode before tiling. Patches are stored at original resolution, so there is no upscaling.
- **Copy/paste:** the `retouch` group copies **sliders only** by default (heal ops are image-specific); the full list is an opt-in checkbox.
- **Engine version:** retouch is an additive pass that is a no-op at defaults, so `engineVersion` stays `lumen-1` for unretouched documents. Documents using retouch store `retouch.version` and the model ids.

---

## 6. Runtime and delivery

### 6.1 Runtime choice

| | **`flutter_litert` 3.9.3** ✅ | `flutter_onnxruntime` 1.8.5 (03 ✅) |
|---|---|---|
| License | Apache-2.0 ✅ | MIT |
| Natives | **bundled on every platform** (Android AARs; iOS xcframeworks; macOS/Windows/Linux CMake prebuilts) ✅ | iOS/macOS via Pods/SPM; **Windows downloads the ORT zip at build time** (03) |
| Minimum OS | iOS **13** ✅; macOS 13 for NPU (Metal/CoreML on arm64) ✅. The app is at iOS 15 / macOS 12 today ✅ (pbxproj) | **iOS 16, macOS 14** (03) → forces a bump |
| Acceleration | Apple: **Metal, CoreML (ANE)**; Android: **GPU** (OpenGL/OpenCL), NPU (Qualcomm, about 104 MB of runtime per SoC ✅, skip); Windows/Linux: **XNNPACK CPU** only ✅ | Apple: CoreML EP; Android: XNNPACK/NNAPI; Windows: CPU (DirectML needs a custom DLL, 03) |
| Isolates | `IsolateInterpreter` (native) ✅ | method channel; background-isolate use 🔶 (03) |
| Models available | **MediaPipe (native)**, MI-GAN ✅, MODNet ✅, Real-ESRGAN x4v3 3.5 MB ✅, SAM2.1-tiny ✅, YuNet, NAFNet ✅, DA3-Small ✅ | everything in 03 (LaMa, BiRefNet, EdgeTAM, skyseg) |
| Risk | Single publisher (`hugo.ml`, also publishes `face_detection_tflite`) 🔶 | Active, more downloads |

**Decision (proposal):** Phase 2 retouch and masks use **`flutter_litert` only**. Keep the inference abstraction runtime-agnostic (`InferenceBackend` → `LiteRtBackend` now, `OrtBackend` later), so LaMa, BiRefNet and EdgeTAM can come via ORT **or** the cloud without touching features. `face_detection_tflite` (Apache-2.0 ✅) is a useful **reference** for BlazeFace anchors and mesh decoding, but it depends on `opencv_dart` and bundles a recognition model, so **do not depend on it**; port the ~300 lines of decoding.

**Delegates:** iOS/macOS arm64 → CoreML (fall back to Metal, then XNNPACK); Android → GPU (fall back to XNNPACK); Windows → XNNPACK; macOS x86_64 → XNNPACK. GPU delegates have thread affinity 🔶, so own one interpreter per model on a dedicated isolate (`IsolateInterpreter`) and never share it.

### 6.2 `ModelStore`: download on first use

- **Manifest compiled into the app** (`model_manifest.dart`): `{id, version, runtime, url (own CDN, versioned path), sha256, bytes, license, inputs}`. The pinned hash means a compromised CDN cannot swap a model.
- **Download** with `background_downloader` 9.6.3 (BSD-3/MIT ✅, all 5 platforms, resumable ✅) to `<appSupport>/models/<id>/<version>/<file>.part`. Verify **SHA-256 by streaming** (`package:crypto` chunked) → atomic rename → mark ready. A mismatch deletes the file and reports an error. Never run an unverified file.
- **Disk guard:** require free space ≥ 2 × the file size + 200 MB before starting. Per-platform budget (mobile 150 MB, desktop 500 MB) with LRU eviction of non-bundled models. iOS: set "exclude from backup" on the models directory (a platform channel; a re-download is cheap).
- **Bundled** (in the app binary): `face_landmarker.task` 3.76 MB + `blaze_face_full_range.tflite` 1.08 MB. Face detection is instant and offline, and it also improves auto-edit stats (`skinShare`, face exposure).
- **First use downloads:** Selfie Multiclass 16.4 MB (on first Retouch), Hair Segmenter 0.8 MB, MI-GAN 16.3 MB (first Remove), MODNet (first Select Subject on Windows/Android without a native path), Pose lite 5.8 MB (body tools).
- **This dev Mac** (≈ 3.5 GB free ✅ `df`): the whole retouch set is under 50 MB. **Do not** pull LaMa (208 MB), BiRefNet (114–224 MB) or skyseg (176 MB) here. Test them against the cloud sidecar or on another machine.
- Self-host mirrors and **re-export third-party conversions from the official weights** before launch (03 §7).

### 6.3 Isolates and frame budget

- Face analysis, parsing, RetouchMaps, blemish candidates and the MLS field: one `Isolate.run` chain per photo on open (target < 400 ms for a 2-face photo on M1, < 1.2 s on a mid-range phone 🔶). Show the photo immediately and enable the Retouch panel when ready.
- Inference: `IsolateInterpreter`. Pass pixels as `TransferableTypedData`. Decode/resize with `instantiateImageCodec(targetWidth:)` (03 §8.4).
- Slider drags touch **only uniforms** of `R`/`D` (60 Hz). Rebuilding the region maps (per-face override) or the warp field (shape sliders) is debounced to 80 ms in the isolate, with the old textures kept until the new ones arrive.

### 6.4 Cloud alternative

```
app ──HTTPS (crop + mask only, EXIF-free)──► lumen_server (Dart shelf: auth, rate limit, body limit, metering, credits)
                                               ├─ /v1/auto-edit, /v1/instruct ──► Claude (existing)
                                               └─ /v1/inpaint, /v1/mask/hq, /v1/retouch/hq ──► InferenceClient
                                                                    │ HTTP/gRPC on a private network
                                                                    ▼
                                         inference sidecar: Python 3.12 + FastAPI + onnxruntime-gpu (CUDA EP),
                                         models baked into the image (LaMa, BiRefNet, future generative fill)
                                         GPU serverless (Modal / RunPod / Cloud Run GPU, L4-class)
```

- **Why a sidecar and not Dart FFI:** ORT via `dart:ffi` in the shelf process is fine for **CPU** models (MI-GAN at 289 ms would do), but CUDA EP packaging, model tooling and future diffusion inpainting all live in Python. Keep the Dart gateway as the only public surface: it keeps auth, rate limits and metering, and the API key stays server-side (PLAN §1.4).
- **Contract:** `POST /v1/inpaint {crop: PNG/JPEG ≤ 2048², mask: PNG, quality: "hq"} → {patch: PNG, model, ms}`. Retention: none (processed in memory, not logged, not used for training), stated in the privacy policy (Evoto makes the same promises ✅).
- **Cost:** L4 rents at about **$0.44–0.80/GPU-hour** ✅ (2026 pricing round-ups); serverless per-second L4 is about $0.0001–0.00024/s ✅. LaMa 512² on an L4 is roughly 50–150 ms 🔶 → about **$0.00003 of GPU time per fill**. Real cost is dominated by cold starts and idle minimum instances. Price "HQ Remove" as 1 credit.
- **Future generative fill (server only):** check licenses first. FLUX.1 Fill [dev] is non-commercial ⛔ 🔶; SDXL/SD2 inpainting are OpenRAIL(++) with use restrictions ⚠️ 🔶; BRIA is paid ⛔ unless licensed.

### 6.5 On-device vs cloud, per feature

| Feature | Where | Model bytes | Why |
|---|---|---|---|
| Face detect + landmarks | **Device** (bundled) | 4.8 MB | Instant, private, needed everywhere |
| Skin/face parsing | **Device** | 16.4 MB | Private; per-crop 256² is enough |
| Skin smoothing, tone, blemish, wrinkles, under-eye, teeth, eyes, shine, makeup | **Device (shader + CPU)** | 0 | Real-time sliders; nothing to send |
| Face reshape, liquify | **Device** | 0 | Interactive |
| Body slim | **Device** (Phase 3) | 5.8 MB | Interactive |
| Spot heal (small) | **Device** (push-pull) | 0 | Instant |
| Remove (default) | **Device** (MI-GAN) | 16.3 MB | Fast, private |
| Remove HQ / large holes | **Cloud** (LaMa); desktop opt-in download | (208 MB) | Disk, speed |
| Generative fill / expand | **Cloud only**, later | — | Size, license, cost |
| Subject mask | **Device** (Apple Vision / ML Kit / MODNet); HQ hair at > 24 MP → cloud BiRefNet (opt-in) | 0–26 MB | |
| Sky mask | **Cloud by default** on mobile, download on desktop | (176 MB) | Size |
| People + parts | **Device** | shared | |
| Batch retouch (500 photos) | **Device** in a background isolate; "Studio" cloud acceleration later | — | Cost |

---

## 7. Build order and license table

### 7.1 Recommended build order (each step ends green on the §6 test layers of PLAN)

| # | Step | Sessions | Ships |
|---|---|---|---|
| 0 | **Spikes:** (a) `flutter_litert` runs `face_landmarker` models on macOS, iOS, Android and Windows CI; (b) `develop` with 7 samplers and 230 floats compiles and runs on Metal, Vulkan, GLES and the tester; (c) 16-bit packed warp round-trip with `FilterQuality.none` (like S4) | 1 | go/no-go on §6.1 and §4.4 |
| 1 | `InferenceBackend` + `ModelStore` (manifest, SHA-256, resume, disk guard) + `FaceAnalyzer` (detect → align → mesh → refine) + debug landmark overlay. Landmark JSON fixtures for tests | 2 | face boxes and landmarks in the editor |
| 2 | **Masks core:** linear/radial (PLAN Phase 2 item 1), mask compose pass, local adjustments in `develop` (generator for unrolled uniforms), mask panel. Fix the `MaskKind` fallback | 2–3 | Lightroom gradients + local sliders |
| 3 | `FaceParser` (multiclass per crop + polygons + colour model + guided refine) + `RetouchMaps` (B1/B2/B3/regions, CPU twin in `lumen_core`) + **`retouch.frag`**: smooth, texture, even tone, under-eye, teeth, eye whites, iris | 3 | **Portrait retouch v1** |
| 4 | Blemish detection + frequency-separated push-pull + manual heal brush + retouch layer schema (`heal` list, patches, aux re-run) | 2 | Auto blemish + heal |
| 5 | AI masks: Subject (Apple Vision / ML Kit / MODNet), People + parts, Background; brush masks | 2 | AI masks |
| 6 | **Remove**: MI-GAN (LiteRT) + crop/feather/detail restoration + Telea/PatchMatch fallback | 2 | Remove tool, offline |
| 7 | Warp field in `develop` + MLS face reshape sliders + eye bulge + liquify brush | 2 | Face reshape |
| 8 | Wrinkles (ridge map), shine, lips/blush, flyaway hair (plain backgrounds), glasses-glare brush | 2–3 | Evoto-parity extras |
| 9 | Cloud sidecar + `/v1/inpaint` HQ (LaMa), Sky mask, HQ subject; Body slim (pose + MLS + line anchors) | 3 | HQ + body |
| 10 | Auto Retouch preset (need-scaled) + vision-provider `retouch.*` deltas + per-face overrides UI | 1–2 | One-click retouch |

**Testing notes:** every recipe gets a `lumen_core` CPU twin with parity tests on synthetic textures (blobs of known size and contrast for blemish detection; sine-ridge "wrinkles"; flat-field skin patches for amplitude selectivity). Region rasterization and MLS are tested from **landmark JSON fixtures**, so CI needs no model. Model-in-the-loop tests use a small **licensed** portrait set (self-shot with model releases, or CC0 sources with releases verified), kept outside the repo and fetched in CI. Never use CelebA, FFHQ or WIDER images in tests or demos.

### 7.2 License table (every model recommended or rejected here)

| Model | Use | License (weights) | Training data | Commercial OK? | Download URL (mirror to own CDN) | Size |
|---|---|---|---|---|---|---|
| **MediaPipe Face Landmarker** (BlazeFace SR + FaceMesh V2 + Blendshapes) | detect + 478 landmarks | Apache-2.0 ✅ | Google-collected, 17 regions ✅ | **Yes** ✅ | `https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task` | 3,758,596 B ✅ |
| **BlazeFace full-range** | group/wide detection | Apache-2.0 🔶 | Google | **Yes** 🔶 | `https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_full_range/float16/latest/blaze_face_full_range.tflite` | 1,083,786 B ✅ |
| BlazeFace short-range | (inside the task) | Apache-2.0 ✅ | Google | Yes | `…/face_detector/blaze_face_short_range/float16/latest/blaze_face_short_range.tflite` | 229,746 B ✅ |
| **Selfie Multiclass 256** | skin/hair/clothes parsing | Apache-2.0 ✅ | Google, fairness-evaluated ✅ | **Yes** ✅ | `https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite` | 16,371,837 B ✅ |
| **Hair Segmenter** | hair edges, flyaways | Apache-2.0 ✅ | Google | **Yes** ✅ | `https://storage.googleapis.com/mediapipe-models/image_segmenter/hair_segmenter/float32/latest/hair_segmenter.tflite` | 781,618 B ✅ |
| **Pose Landmarker lite** | body slim (Phase 3) | Apache-2.0 ✅ | Google (GHUM) | **Yes** ✅ | `https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task` | 5,777,746 B ✅ |
| **MI-GAN 512 Places2 (LiteRT fp16)** | Remove, large spots | MIT ✅ | Places2 ⚠️ | **Yes, legal note** | `https://huggingface.co/litert-community/MI-GAN-512-Places2-LiteRT/resolve/main/migan_fp16.tflite` | 16,312,640 B ✅ |
| MI-GAN pipeline (ONNX) | Remove via ORT/cloud | MIT ✅ | Places2 ⚠️ | Yes, legal note | `https://huggingface.co/andraniksargsyan/migan/resolve/main/migan_pipeline_v2.onnx` | 28.1 MB (03) |
| **LaMa big-lama** | HQ Remove (cloud) | Apache-2.0 ✅ | Places2 ⚠️ | Yes, legal note | `https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx` | 208 MB (03) |
| **MODNet** | Subject (people) | Apache-2.0 ✅ (repo: "code, models, and demos … Apache License 2.0") | per the AAAI paper 🔶 ⚠️ | Yes, check the data | `https://huggingface.co/litert-community/MODNet-LiteRT/resolve/main/modnet.tflite` / ONNX q8 (03) | 26,166,776 B ✅ / 6.6 MB |
| Real-ESRGAN x4v3 (LiteRT) | Upscale (not retouch) | BSD-3 ✅ | DIV2K etc. ⚠️ | Yes, legal note | `https://huggingface.co/litert-community/real-esrgan-x4v3-litert/resolve/main/realesr_general_x4v3.tflite` | 3,549,456 B ✅ |
| EdgeTAM / SAM2.1-tiny | Object click mask | Apache-2.0 (03) | SA-1B 🔶 | Yes ⚠️ | 03 §8.3 | ~20–40 MB |
| YuNet | fallback detector only | MIT ✅ | **WIDER FACE (CC-BY-NC-ND-4.0)** ✅ | ⚠️ data | `https://huggingface.co/opencv/face_detection_yunet/resolve/main/face_detection_yunet_2023mar.onnx` | 232,589 B ✅ |
| ⛔ BiSeNet face parsing (incl. LiteRT port tagged MIT) | — | code MIT | **CelebAMask-HQ (NC, incl. derived data)** ✅ | **No** | — | 52.6 MB ✅ |
| ⛔ SegFormer face-parsing | — | NVIDIA NC | CelebAMask-HQ | **No** | — | — |
| ⛔ LaPa-trained parsers | — | — | LaPa NC ✅ | **No** | — | — |
| ⛔ SCRFD / InsightFace models | — | NC ✅ | — | **No** | — | — |
| ⛔ FFHQR-trained retouch nets | — | — | FFHQR CC-BY-NC-SA ✅ | **No** | — | — |
| ⛔ CodeFormer; ⚠️ GFPGAN | face restore | S-Lab NC / custom (03) | — | No / review | — | — |

**Before shipping any row, add it to `docs/MODEL_LICENSES.md`** (source URL, SHA-256 of the mirrored file, license, training-data note), as that file already requires ✅.

---

## 8. Proposed changes to PLAN.md (for the decision record)

1. **§1.10:** replace `OrtSessionPool` with a runtime-agnostic `InferenceBackend` (LiteRT first). Add the interfaces `FaceAnalyzer` (`Future<List<FaceGeometry>> analyze(ui.Image, {CancelToken?})`), `FaceParser`, `RetouchMapBuilder`, `WarpFieldBuilder`, and `OnDeviceFeature.{faceRetouch, faceReshape, heal}`.
2. **§1.6:** add pass **`R` (`retouch.frag`)** after `N`; add **warp + 2 mask samplers** to `develop` (7 samplers, 230 floats). Update the sampler/float table and `uniform_layout.dart` through a generator.
3. **§2.2:** add `settings.retouch` (§5.5); extend `masks[].shape` with `components`; add `MaskKind.{background, people, object, color, luminance, unsupported}` and a non-lossy unknown-kind fallback.
4. **§2.1:** add `retouch.*` params (`localAllowed: false`, `aiEditable: true`, copy group `retouch`).
5. **§3.2:** reorder Phase 2 to the §7.1 build order: masks core → retouch v1 → heal → AI masks → Remove → reshape.

---

## 9. Still unverified (test next)

1. Exact tensor I/O of `face_landmarks_detector.tflite` inside the `.task` bundle, and the 128 vs 192 detector input conflict (inspect with `flutter_litert` `getInputTensors()` in spike 0).
2. The full-range BlazeFace license card and anchor layout of the 2026-03 file.
3. `flutter_litert` on Windows CI, its CoreML delegate coverage for the multiclass ViT and MI-GAN, and GPU-delegate thread affinity inside `IsolateInterpreter`.
4. Impeller acceptance of 230 floats / 7 samplers on GLES (Android emulator) and the web renderers.
5. The teeth, sclera and shine thresholds in OkLab on a diverse, licensed portrait set (Monk skin tone 1–10). Tone evening must not shift skin hue on deeper skin tones, since the multiclass card shows a 9-point mIoU spread across skin tones ✅.
6. Cost of RetouchMaps on CPU at 2048 for 1–6 faces on a mid-range Android phone.
7. MODNet training-data provenance (AAAI paper), and SA-1B terms for EdgeTAM.
8. LaMa-on-L4 latency, and the cold-start profile of the chosen GPU serverless host.

---

### Sources
- MediaPipe Face Landmarker: https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker · FaceMesh V2 model card (Apache-2.0, inputs, out-of-scope): https://storage.googleapis.com/mediapipe-assets/Model%20Card%20MediaPipe%20Face%20Mesh%20V2.pdf · BlazeFace short-range card: https://storage.googleapis.com/mediapipe-assets/MediaPipe%20BlazeFace%20Model%20Card%20(Short%20Range).pdf · Blendshape card: https://storage.googleapis.com/mediapipe-assets/Model%20Card%20Blendshape%20V2.pdf
- Face detector guide: https://developers.google.com/edge/mediapipe/solutions/vision/face_detector · Image segmenter guide (classes, latency): https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter · Multiclass card: https://storage.googleapis.com/mediapipe-assets/Model%20Card%20Multiclass%20Segmentation.pdf · Hair card: https://storage.googleapis.com/mediapipe-assets/Model%20Card%20-%20Hair%20Segmentation.pdf · Pose guide: https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker · BlazePose GHUM card: https://storage.googleapis.com/mediapipe-assets/Model%20Card%20BlazePose%20GHUM%203D.pdf
- Landmark topology: https://github.com/google-ai-edge/mediapipe/blob/master/mediapipe/python/solutions/face_mesh_connections.py · canonical geometry: https://github.com/google-ai-edge/mediapipe/blob/master/mediapipe/modules/face_geometry/data/canonical_face_model.obj
- File sizes: HTTP `HEAD` on the `storage.googleapis.com/mediapipe-models/...` URLs above (2026-10-03); HF API `?blobs=true` for `litert-community/*`, `opencv/face_detection_yunet`
- InsightFace license: https://github.com/deepinsight/insightface · YuNet: https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet · WIDER FACE license: https://huggingface.co/datasets/CUHK-CSE/wider_face
- CelebAMask-HQ: https://mmlab.ie.cuhk.edu.hk/projects/CelebA/CelebAMask_HQ.html · LaPa: https://openi.pcl.ac.cn/JDOpenISCT/lapa-dataset/src/branch/master · FFHQR: https://github.com/skylab-tech/ffhqr-dataset · ABPN: https://openaccess.thecvf.com/content/CVPR2022/papers/Lei_ABPN_Adaptive_Blend_Pyramid_Network_for_Real-Time_Local_Retouching_of_CVPR_2022_paper.pdf · MODNet: https://github.com/ZHKKKe/MODNet
- LiteRT models: https://huggingface.co/litert-community/MI-GAN-512-Places2-LiteRT · https://huggingface.co/litert-community/MODNet-LiteRT · https://huggingface.co/litert-community/BiSeNet-Face-Parsing-LiteRT · https://huggingface.co/litert-community/real-esrgan-x4v3-litert
- Flutter: https://pub.dev/packages/flutter_litert · https://pub.dev/packages/face_detection_tflite · https://pub.dev/packages/opencv_dart · https://pub.dev/packages/background_downloader · https://docs.flutter.dev/ui/design/graphics/fragment-shaders · Impeller GLES texture-unit validation: https://flutter.googlesource.com/mirrors/flutter/+/e26b384689b8f7ff1c98dd1da9935284516ad631
- Apple: https://developer.apple.com/documentation/avfoundation/avsemanticsegmentationmatte · WWDC19 session 260: https://developer.apple.com/videos/play/wwdc2019/260
- Evoto processing and privacy: https://www.evoto.ai/privacy-center
- GPU pricing: https://jarvislabs.ai/blog/l4-gpu-price · https://cerebrium.ai/blog/2026-gpu-buyers-guide
- Algorithms: Schaefer, McPhail, Warren, *Image Deformation Using Moving Least Squares*, SIGGRAPH 2006 (https://people.engr.tamu.edu/schaefer/research/mls.pdf) · Pérez, Gangnet, Blake, *Poisson Image Editing*, SIGGRAPH 2003 · Gortler et al., *The Lumigraph* (pull-push), SIGGRAPH 1996 · Telea, *An Image Inpainting Technique Based on the Fast Marching Method*, JGT 2004 · Barnes et al., *PatchMatch*, SIGGRAPH 2009 · Frangi et al., *Multiscale Vessel Enhancement Filtering*, MICCAI 1998 · He, Sun, Tang, *Guided Image Filtering*, ECCV 2010 / TPAMI 2013 · Gustafsson, *Interactive Image Warping*, 1993
