# 03 — On-device AI tools for Lumen (models, licenses, runtimes)

> **Status:** research, 2026-10-03. **Stack update:** Lumen is now **Flutter 3.47** (macOS, iOS, Android, Windows). The model and license findings (sections 1–7) apply unchanged, and the ONNX files are the same ones the Flutter runtime will load. Section 8 covers **Flutter on-device inference**. Section 9 (transformers.js / Next.js) only applies if you keep a web build or a web demo.
>
> **License bar:** model weights **and** code must be MIT / Apache-2.0 / BSD. Anything else is flagged ⛔ (non-commercial or copyleft) or ⚠️ (custom terms or unclear provenance, so it needs legal review).
>
> **How each claim is marked:** ✅ **verified** = checked this session against the Hugging Face API, npm/pub.dev registries, GitHub license APIs, or by actually running the model. 🔶 **unverified** = taken from docs or blogs, or my own inference. File sizes come from the HF API (`?blobs=true`).

---

## 0. TL;DR: MVP picks

| Feature | MVP model | License | File to ship (size) | Why |
|---|---|---|---|---|
| **Select Subject** (fast, people) | MODNet | Apache-2.0 ✅ | `Xenova/modnet` `onnx/model.onnx` 25.9 MB (q8 6.6 MB) | Small and fast portrait matte. Ran in 0.69 s on M1 Max CPU ✅ |
| **Select Subject** (general objects, best edges) | BiRefNet_lite | MIT ✅ | `onnx-community/BiRefNet_lite-ONNX` fp16 114.5 MB / fp32 224 MB | Best commercial-safe saliency/DIS model at 1024². Slow on CPU (8 s), so it needs a GPU EP |
| **Click / box to select object** | EdgeTAM (SAM2 for edge devices) | Apache-2.0 ✅ | `onnx-community/EdgeTAM-ONNX`, ~40 MB fp32 (encoder 19.5 + decoder 21) | Encode 325 ms and decode 67 ms on M1 Max CPU ✅. Encode once, then each click is cheap |
| **Select Sky** | `skyseg.onnx` (U²-Net trained for sky) + guided-filter refine | MIT ✅ (training data undisclosed ⚠️) | `JianyuanWang/skyseg` 176 MB fp32 | Only purpose-built sky model I found with a commercial-safe license. SegFormer-ADE is better and smaller but ⛔ NVIDIA non-commercial |
| **Select Background** | invert the subject mask | n/a | n/a | No extra model needed |
| **Background removal** | BiRefNet_lite (general), MODNet (portraits). Alt: ormbg (Apache-2.0) | MIT / Apache-2.0 ✅ | see above; ormbg q8 44 MB | All BRIA RMBG versions ⛔, `@imgly/background-removal` ⛔ AGPL |
| **Remove (object removal)** | **MI-GAN** 512 Places2 ONNX *pipeline* | MIT code **and** weights ✅ | `andraniksargsyan/migan` `migan_pipeline_v2.onnx` 28.1 MB | uint8 in/out with crop, resize and blend built in. **289 ms** for a 2048×1536 image on M1 Max CPU ✅ |
| **Remove (HQ, large holes)** | LaMa (big-lama) | Apache-2.0 ✅ | `Carve/LaMa-ONNX` `lama_fp32.onnx` 208 MB, fixed 512² | Better on big holes. **4.7 s** per 512² on CPU ✅, so use a GPU EP or the server |
| **Upscale (Super Resolution)** | Real-ESRGAN `realesr-general-x4v3` | BSD-3-Clause ✅ | 4.9 MB ONNX | Pure conv (easy for any EP to run). 512→2048 in 2.6 s CPU / **1.06 s CoreML EP** on M1 Max ✅ |
| Denoise (v1.1) | Classical GPU filter first. AI: SCUNet (Apache-2.0) or NAFNet (MIT) | ✅ | 73 MB / needs export | Lightroom-grade Denoise works on raw Bayer data, which is out of MVP scope |
| Portrait retouch | MediaPipe Face Landmarker + Selfie Multiclass (face-skin mask) + shader smoothing | Apache-2.0 | ~4 MB + ~16 MB (`.tflite`/`.task`) | No generative model needed |
| Scene context | SigLIP base-patch16-224 vision tower + precomputed text embeddings, plus EXIF | Apache-2.0 ✅ | vision q8 99.5 MB / q4f16 54.6 MB | CLIP's model card says deployed use is out of scope ⚠️ |

**Total MVP download:** ≈ 40 MB bundled plus ≈ 300–500 MB fetched on demand, lazy-loaded per feature (see §8.3).

---

## 1. AI masking: Subject / Sky / Background / People

### 1a. Promptable "click/box to select" (SAM family)

| Model | HF id (ONNX) | License | Size (enc + dec) | Runtime notes | Verdict |
|---|---|---|---|---|---|
| **EdgeTAM** | `onnx-community/EdgeTAM-ONNX` (base `facebook/EdgeTAM`) | Apache-2.0 ✅ | fp32 19.5 + 21.0 MB; fp16 9.7 + 10.5 MB | `EdgeTamModel` in transformers.js v4 ✅. Ran on M1 Max CPU: encode 325 ms (1800×1200), decode 67 ms ✅. Meta reports "22× faster than SAM 2, 16 FPS on iPhone 15 Pro Max" | **MVP pick** |
| SlimSAM-77 | `Xenova/slimsam-77-uniform` | Apache-2.0 ✅ | fp32 23.3 + 16.6; fp16 12.2 + 8.6; q8 8.9 + 4.9 MB | `SamModel` (SAM-1 decoder) | Fallback / A-B test |
| SAM 2.1 tiny | `onnx-community/sam2.1-hiera-tiny-ONNX` (base Apache-2.0) | Apache-2.0 ✅ (repo card has no tag) | fp32 134 + 21; fp16 67 + 10.5; q4f16 28.5 + 4.6 MB | `Sam2Model` | Higher quality, ~4× heavier |
| SAM-ViT-base | `Xenova/sam-vit-base` | Apache-2.0 ✅ | 359 + 16.6 MB fp32 | slow | ❌ too big |
| MobileSAM / EfficientSAM | only community ONNX (`PulpCut/mobilesam-onnx`, no license tag) | code Apache-2.0 ✅ | 28 + 16.5 MB | not in transformers.js | skip (EdgeTAM supersedes) |
| SAM 3 tracker | `onnx-community/sam3-tracker-ONNX` | ⚠️ custom "SAM License" (commercial allowed with conditions: trade controls, no reverse engineering) | encoder 296 MB q4f16 … 1.87 GB fp32 | `Sam3TrackerModel` | ❌ size and license for MVP |

**Gotchas**
- SAM-family masks come out of the decoder at **256×256**, then get upsampled, so edges are blocky. For photo editing, refine with a **guided filter** (joint-bilateral upsampling against the full-res photo). Or run BiRefNet on the SAM box crop to get hair-level edges.
- The pattern is: encode the image once when the user enters Mask mode, cache the embeddings, then run only the decoder per click.

### 1b. "Select Subject": salient object / matting

| Model | HF id | License | Size | Input | Verdict |
|---|---|---|---|---|---|
| **BiRefNet_lite** | `onnx-community/BiRefNet_lite-ONNX` | MIT ✅ | fp32 224 MB / fp16 114.5 MB | 1024² | **Primary for objects** (8.1 s fp32 on M1 Max CPU ✅, so it needs a GPU EP) |
| BiRefNet (full) | `onnx-community/BiRefNet-ONNX` | MIT ✅ | fp16 490 MB / fp32 973 MB | 1024² | Server / "HQ" toggle only |
| BiRefNet-matting / HR / portrait | `ZhengPeng7/BiRefNet*` (PyTorch only) | MIT ✅ | 178–885 MB | — | Later: export soft-alpha matting variants yourself |
| **MODNet** | `Xenova/modnet` | Apache-2.0 ✅ | fp32 25.9 / fp16 13 / q8 6.6 MB | short side 512 | **Primary for people** (0.69 s CPU ✅) |
| ormbg | `onnx-community/ormbg-ONNX` | Apache-2.0 ✅ | fp32 176 / fp16 88 / q8 44 MB | 1024² | Good people alternative (q8 1.5 s CPU ✅) |
| BEN2 (base) | `onnx-community/BEN2-ONNX` | MIT ✅ | fp16 219 MB | 1024² | Candidate for an A/B quality test |
| U²-Netp | `BritishWerewolf/U-2-Netp` | Apache-2.0 ✅ | 4.6 MB | 320² | Tiny, low quality |
| IS-Net (DIS) | `onnx-community/ISNet-ONNX` tagged **AGPL-3.0** ⛔; `imgly/isnet-general-onnx` tagged MIT | original DIS repo Apache-2.0 ✅ | 176 / 88 / 44 MB | 1024² | ⚠️ The labels conflict. If you want IS-Net, export it yourself from `xuebinqin/DIS` (Apache-2.0) |

### 1c. "Select Sky"

| Option | HF id | License | Size | Notes | Verdict |
|---|---|---|---|---|---|
| **skyseg (U²-Net)** | `JianyuanWang/skyseg` (mirror `bukuroo/SkySeg-ONNX`) | MIT ✅ (GitHub `xiongzhu666/Sky-Segmentation-and-Post-processing` is MIT) | 176 MB fp32 (convert to fp16 ≈ 88 MB 🔶) | Purpose-built for sky. The author warns that building details are sometimes labelled sky. Training data undisclosed ⚠️ | **MVP pick**, plus guided-filter refine |
| Depth Anything V2 **Small** | `onnx-community/depth-anything-v2-small` | Apache-2.0 ✅ (**Base/Large are CC-BY-NC** ⛔) | fp32 99 / fp16 49.6 / q8 27.3 / q4f16 19.1 MB | Sky ≈ zero disparity. Use it as a validator/heuristic (far + top-connected + sky-like hue). It also gives Lens Blur for free. q8 1.09 s CPU ✅ | **Ship it** (dual use) |
| DETR-R50 panoptic | `Xenova/detr-resnet-50-panoptic` | Apache-2.0 ✅ (`facebook/detr-resnet-50-panoptic`) | fp32 172 / fp16 87 / q8 44.5 MB | Has a `sky-other` class. Coarse edges | Backup |
| CLIPSeg | `Xenova/clipseg-rd64-refined` | Apache-2.0 ✅ (CIDAS) | q4f16 115 / q8 139 MB | Text-prompted ("sky", "water", "trees"). Output only 352² | Later: "select by text" |
| UperNet-ConvNeXt-tiny (ADE20K) | `openmmlab/upernet-convnext-tiny` | MIT ✅ | 241 MB fp32 | Not in transformers.js. You export ONNX yourself; post-process is a simple argmax. 🔶 untested | Plan B for full ADE20K semantics (sky, water, vegetation…) |
| SegFormer ADE20K (b0–b5) | `Xenova/segformer-b0-finetuned-ade-512-512` (4.4–15 MB!) | ⛔ **NVIDIA Source Code License: "non-commercially … research or evaluation purposes only"** ✅ | — | Technically ideal | **Prototype only. Never ship** |
| MaskFormer | `onnx-community/maskformer-*` | ⛔ CC-BY-NC-4.0 (repo LICENSE) ✅ | — | — | ❌ |
| Mask2Former / OneFormer | `facebook/mask2former-*`, `shi-labs/oneformer_*` | MIT (GitHub) ✅ / MIT ✅ | 190–270 MB | No ONNX on HF. Export is non-trivial (deformable attention) 🔶 | Later, server-side |

### 1d. People / face part masks (like Lightroom's "Select People": skin, hair, clothes, eyes, lips)

| Option | License | Size | Notes | Verdict |
|---|---|---|---|---|
| **MediaPipe Selfie Multiclass 256×256** | Apache-2.0 (MediaPipe) | ~16 MB `.tflite` | Classes: background, hair, body-skin, face-skin, clothes, accessories. Google lists 71 ms on GPU | **MVP** (upsample with a guided filter) |
| **MediaPipe Face Landmarker** | Apache-2.0 | `face_landmarker.task` (~3–4 MB 🔶) | 478 landmarks + 52 blendshapes. Draw polygons for eyes, iris, lips, teeth, brows | **MVP** |
| MediaPipe Hair Segmenter | Apache-2.0 | 512² | hair only | optional |
| `Xenova/face-parsing` (SegFormer-B5 on CelebAMask-HQ) | ⛔ NVIDIA backbone license + CelebAMask-HQ non-commercial dataset | 89–340 MB | — | ❌ |
| Sapiens seg (Meta) | ⛔ CC-BY-NC-4.0 ✅ | 320 MB+ | — | ❌ |

---

## 2. Background removal (commercial-safe primary only)

| Model | HF id | License | Size | Verdict |
|---|---|---|---|---|
| **BiRefNet_lite** | `onnx-community/BiRefNet_lite-ONNX` | MIT ✅ | 114.5 MB fp16 | **Primary (general)** |
| **MODNet** | `Xenova/modnet` | Apache-2.0 ✅ | 6.6–26 MB | **Primary (portraits, instant)** |
| ormbg | `onnx-community/ormbg-ONNX` | Apache-2.0 ✅ | 44–176 MB | Alternative for people |
| BEN2 base | `onnx-community/BEN2-ONNX` | MIT ✅ | 219 MB fp16 | A/B candidate |
| BiRefNet full | `onnx-community/BiRefNet-ONNX` | MIT ✅ | 490 MB fp16 | Server "HQ" |
| ⛔ BRIA RMBG-1.4 / 2.0 | `briaai/RMBG-1.4`, `briaai/RMBG-2.0` | "bria-rmbg" license: **non-commercial**, paid license needed ✅ | 44 MB–1 GB | Do not use |
| ⛔ `@imgly/background-removal` (npm 1.7.0) | — | **AGPL-3.0** (GitHub) ✅ | — | Do not use (code is copyleft) |
| ⛔ `onnx-community/ISNet-ONNX` | — | tagged AGPL-3.0 ✅ | — | Use self-exported DIS weights instead |

**Edge quality:** none of these give Lightroom-grade hair on their own. Plan for a refinement pass: guided filter or a matting variant (BiRefNet-matting) on a trimap band.

---

## 3. Object removal ("Remove" / healing)

| Model | HF id / source | License | Size | Measured (M1 Max, ORT 1.30 Python, CPU EP) | Verdict |
|---|---|---|---|---|---|
| **MI-GAN 512 Places2 pipeline** | `andraniksargsyan/migan` → `migan_pipeline_v2.onnx` (linked from the official README) | MIT code **and** separate MIT `LICENSE-WEIGHTS` ✅ | 28.1 MB | **289 ms** for 2048×1536 with a 300 px hole ✅ | **MVP** |
| LaMa big-lama | `Carve/LaMa-ONNX` → `lama_fp32.onnx` (use this one, not `lama.onnx`) | Apache-2.0 ✅ (advimman/lama Apache-2.0 ✅) | 208 MB | **4,666 ms** per 512² ✅ | HQ / large-hole mode on a GPU EP or the server |
| LaMa (OpenCV zoo copy) | `opencv/inpainting_lama` | Apache-2.0 | 92.6 MB | same model, re-exported 🔶 | Possibly a smaller drop-in. Test it |
| MI-GAN LiteRT | `litert-community/MI-GAN-512-Places2-LiteRT` | MIT ✅ | 16.3 MB fp16 | 🔶 | For a LiteRT path |
| IOPaint server | `pip install iopaint` → `iopaint start --model=lama --device=mps` | Apache-2.0 ✅ (last push 2025-04, so maintenance is slowing) | — | 🔶 | Local/server option. Its RemoveBG plugin can pull BRIA models ⛔, so pin model choices |
| inpaint-web (reference only) | `lxfater/inpaint-web` | ⛔ GPL-3.0 | — | — | Proves MI-GAN runs in a browser. **Do not copy code** |

**I/O (verified by inspecting the ONNX files ✅)**
- MI-GAN pipeline: inputs `image` uint8 `[N,3,H,W]` RGB and `mask` uint8 `[N,1,H,W]`, where **255 = keep, 0 = fill**. Output `result` uint8 `[N,3,H,W]` at the original size. H and W are dynamic, and the crop around the mask, the resize to 512 and the blend all happen inside the graph. Ops include NonZero, ScatterND and GatherND, which GPU EPs may hand back to the CPU (fine, the model is fast).
- LaMa: `image` float32 `[1,3,512,512]` (0–1) and `mask` float32 `[1,1,512,512]` (1 = hole). Output float32 0–255. The graph has ~17k nodes (Einsum, Sin, Cos DFT emulation), so session creation is slow and GPU-EP coverage is 🔶. You must crop around the mask, resize to 512, inpaint, then paste back and blend yourself.

**Data provenance ⚠️:** both MI-GAN and LaMa were trained on **Places2**, whose terms are research-oriented. The weights are MIT/Apache, and this is common industry practice, but flag it for legal review before launch.

---

## 4. Upscaling / Super Resolution

| Model | HF id | License | Size | Notes | Verdict |
|---|---|---|---|---|---|
| **Real-ESRGAN general x4v3** (SRVGGNetCompact) | `Heliosoph/realesrgan-onnx` → `realesr-general-x4v3.onnx` (3rd-party export of `xinntao/Real-ESRGAN`) | BSD-3-Clause ✅ | **4.9 MB** | Ops are only Conv, PReLU and DepthToSpace ✅, so it is EP-friendly and easy to tile. 256² tile → 1.23 s CPU; 512² → 2.65 s CPU / **1.06 s CoreML EP** ✅. Supports a denoise-strength blend with the `wdn` weights | **MVP**. Re-export from the official release for clean provenance |
| Real-ESRGAN x4plus | `imgdesignart/realesrgan-x4-onnx` (no license tag) | BSD-3 upstream ✅ | 67 MB fp32 / 33.7 MB fp16 | RRDB, ~10× heavier | "Max quality" option |
| Swin2SR (classical x2/x4, realworld x4, compressed x4, lightweight x2) | `Xenova/swin2SR-*` (base `caidas/*` Apache-2.0 ✅) | Apache-2.0 | lightweight x2 7.5 MB fp16; others ~32 MB fp16 / 15.5 MB q4f16 | Transformer. **No resize in the preprocessor, so memory explodes on big images and you must tile.** Lightweight x2 took 1.85 s for a 256×171 input on CPU ✅ | Secondary |
| UpscalerJS ESRGAN slim/medium/thick | npm `@upscalerjs/*` 1.0.0 | MIT ✅ | 4.8–120 MB | **TF.js runtime only** | ❌ for Flutter |

**Practical:** Lightroom "Super Resolution" = 2× linear. Use x4v3, then downscale 0.5×, or tile with a 16–32 px overlap and feathered seams. Cap the input (e.g. ≤ 12 MP) on the device. Larger files go to the server.
**Provenance ⚠️:** most SR models train on DIV2K (academic terms). Same caveat as Places2.

---

## 5. Denoise & portrait retouch

| Option | License | Size | Notes |
|---|---|---|---|
| **Classical GPU denoise** (bilateral / non-local means / guided filter in a fragment shader) | n/a | 0 MB | MVP. Runs in real time with sliders |
| SCUNet color real_psnr | Apache-2.0 ✅ (`Heliosoph/scunet-onnx`, 3rd-party export) | 3.8 MB graph + 73 MB data | Swin-conv. Must tile, heavy 🔶 |
| NAFNet-SIDD width32 | MIT ✅ (megvii LICENSE) | needs own ONNX export (LiteRT fp16 62.5 MB exists) | Trained on real smartphone noise (SIDD) |
| Restormer | MIT ✅ | big | Server only |
| Real-ESRGAN `wdn` blend | BSD-3 ✅ | 4.9 MB | Light denoise as a side effect of SR |
| ⛔ CodeFormer | S-Lab License 1.0 (**non-commercial**) ✅ | — | Do not use |
| ⚠️ GFPGAN | custom (Apache-style + NVIDIA StyleGAN2 parts) | — | Legal review. RestoreFormer++ (Apache-2.0 ✅) is the safer face-restore option, server-side |

**Skin smoothing recipe (no generative model):** MediaPipe face-skin mask (Selfie Multiclass) minus the eyes, brows and lips polygons from Face Landmarker, then feather the mask and run a **frequency-separation** or guided-filter blur in a shader, with a strength slider. Teeth and eye whitening use the landmark polygons.

**True "AI Denoise" like Lightroom's** runs on raw Bayer data. That is a separate project (raw pipeline plus a demosaic-denoise network), not MVP.

---

## 6. Scene / content understanding for auto-edit context

| Option | HF id | License | Size | Verdict |
|---|---|---|---|---|
| **SigLIP base-patch16-224** | `Xenova/siglip-base-patch16-224` (base `google/siglip-base-patch16-224`) | Apache-2.0 ✅ | vision tower q4f16 54.6 MB / q8 99.5 MB / fp16 186 MB | **MVP.** Ship **only the vision tower** and precompute text embeddings for a fixed label set (portrait, landscape, food, night, cityscape, beach, snow, sunset, product, pet, architecture, macro, backlit…) offline as JSON |
| SigLIP2 base | `onnx-community/siglip2-base-patch16-224-ONNX` | Apache-2.0 ✅ | vision q4f16 54.6 MB | Equivalent. Pick one after an A/B |
| ⚠️ CLIP ViT-B/32 | `Xenova/clip-vit-base-patch32` | MIT code, but the model card says *"Any deployed use case of the model – whether commercial or not – is currently out of scope"* ✅ | — | Avoid |
| ⛔ MobileCLIP / MobileCLIP2 | `Xenova/mobileclip_s0`, `apple/MobileCLIP2-*` | `apple-amlr` (restrictive) ✅ | — | Avoid |

**Cheap signals to combine:** EXIF (ISO, shutter, flash, focal length), face count, sky fraction from the sky mask, luminance histogram (low-key/night) and the depth range. A server-side VLM can add richer "why" context later.

---

## 7. Cross-cutting gotchas (any runtime)

1. **Run at model resolution, apply at full resolution.** Downscale (512–1024 px), infer, then upsample masks with a guided filter. Never feed a 24 MP image to a segmentation net.
2. **Self-host model files** on your own CDN/bucket (GCS / Firebase Storage / R2) with versioned paths and SHA-256 checksums. Don't hotlink Hugging Face from a paid product (uptime, rate limits, silent file changes).
3. **Re-export third-party ONNX conversions yourself** (Real-ESRGAN, SCUNet, MobileSAM, skyseg mirrors) from the official weights so the license chain is clean.
4. **Training-data provenance** (Places2, DIV2K, ADE20K, undisclosed sky data) is the remaining legal risk even when weights are MIT/Apache. Get one legal pass before launch.
5. **Quantization vs EP:** q8/QDQ models are small but often fall back to CPU on GPU EPs (CoreML, DirectML). fp16 is the sweet spot on Apple GPUs. Test each model × EP.

---

## 8. Flutter on-device inference

### 8.1 ONNX Runtime in Flutter (pub packages)

| Package | Version / date (pub.dev ✅) | License | Platforms (pub tags ✅) | ORT version | Maintenance | Verdict |
|---|---|---|---|---|---|---|
| **`flutter_onnxruntime`** (masicai) | 1.8.5, 2026-09-08 | MIT | Android, iOS, macOS, Windows, Linux, **Web** | 1.23.0 (README) | Active. 21k downloads/30d, 150/160 points | **Recommended** |
| `onnxruntime` (gtbluesky) | 1.4.1, **2024-03-27** | MIT | Android, iOS, macOS, Windows, Linux | older ORT 🔶 | **Stale**. 14k downloads/30d | Avoid for new work. Its FFI design (`runAsync`, isolate-friendly) is a good reference |
| `onnxruntime_v2` (fork) | 1.23.2+2, 2026-01-21 | MIT | same 5 | 1.22–1.23 | 39 downloads/30d, single maintainer | Fallback only |

**`flutter_onnxruntime` facts (from its README/source ✅)**
- It ships no prebuilt binaries in the package. Native libraries come from official sources at build time: Android `com.microsoft.onnxruntime:onnxruntime-android:1.23.0`, iOS/macOS via CocoaPods or SwiftPM, and **Windows downloads `onnxruntime-win-x64-1.23.0.zip` from the official GitHub release**.
- Minimum versions: **iOS 16** (static linkage: `use_frameworks! :linkage => :static`), **macOS 14**. Android needs `-keep class ai.onnxruntime.** { *; }` in `proguard-rules.pro`. Use ≥ 1.5.1 for Google Play's 16 KB page-size rule.
- FP16 tensors are supported on Android, iOS and macOS. Windows/Linux fp16 is "planned", so **use fp32 ONNX files on Windows**.
- `OrtProvider` enum includes `CORE_ML`, `NNAPI`, `QNN`, `XNNPACK`, `DIRECT_ML`, `CUDA`, `OPEN_VINO`, `WEB_GPU`… but an EP only works if it was compiled into the downloaded binary:

| Platform | EP to use | Status |
|---|---|---|
| macOS / iOS | **CoreML** (`OrtProvider.CORE_ML`), CPU fallback | CoreML EP is in the official Apple builds. Real-ESRGAN ran 2.5× faster with it than with CPU (69/71 nodes on CoreML) ✅ |
| Android | **XNNPACK** (CPU, fast) → NNAPI / QNN | NNAPI is in `onnxruntime-android`, but NNAPI is deprecated from Android 15 🔶. QNN (Snapdragon NPU) needs the separate QNN AAR, so it is a custom build |
| Windows | CPU by default. **DirectML is not in the zip the plugin downloads** ✅ (it is a separate `Microsoft.ML.OnnxRuntime.DirectML` package) | GPU on Windows requires swapping the DLL for the DirectML build (patch the plugin's CMake) 🔶. Windows ML (Win 11) is another route 🔶 |

**Loading a model (Dart):**

```dart
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

final ort = OnnxRuntime();
final providers = await ort.getAvailableProviders(); // e.g. [CORE_ML, CPU]

final session = await ort.createSession(
  modelFile.path,                       // downloaded to app support dir
  options: OrtSessionOptions(
    providers: [
      if (Platform.isMacOS || Platform.isIOS) OrtProvider.CORE_ML,
      if (Platform.isAndroid) OrtProvider.XNNPACK,
      OrtProvider.CPU,
    ],
    intraOpNumThreads: 4,
  ),
);
// Bundled model alternative: ort.createSessionFromAsset('assets/models/migan_pipeline_v2.onnx')

final input = await OrtValue.fromList(float32Pixels, [1, 3, 512, 512]);
try {
  final out = await session.run({'input': input});
  final data = await out['output']!.asList();
  for (final v in out.values) { await v.dispose(); }
} finally {
  await input.dispose();          // native memory: always dispose
}
// session.close() when the feature is unloaded
```

**What you lose vs transformers.js:** there are no processors in Dart. You must port the pre- and post-processing per model: resize, mean/std normalize, NCHW layout, SAM point-coordinate transform plus mask upsampling, and argmax for semantic seg. The `preprocessor_config.json` files give exact values (BiRefNet/BEN2: 1024², ImageNet mean/std; ormbg: 1024², no normalization; MODNet: shortest edge 512, mean/std 0.5, divisible by 32; Depth Anything: 518, multiple of 14). Models with external data (`*.onnx_data`: EdgeTAM, SAM2) must sit in the same folder as their `.onnx` file.

### 8.2 Alternatives

| Option | Platforms | License | Fit |
|---|---|---|---|
| **LiteRT via `flutter_litert`** 3.9.3 (2026-09-28) | Android, iOS, macOS, Windows, Linux, Web | Apache-2.0 ✅ | Active, 160/160 points. Best route for **MediaPipe `.tflite` models** (Selfie Multiclass, face landmarks). `litert-community` has LiteRT ports of MI-GAN, MODNet, DIS-ISNet, Depth Anything V2, Real-ESRGAN x4v3, NAFNet, U²-Net 🔶 (quality/parity untested) |
| `tflite_flutter` 0.12.1 (2025-10-28) | 5 platforms | Apache-2.0 ✅ | Official, but it releases slowly. Prefer `flutter_litert` |
| **Apple Vision subject lifting**: `VNGenerateForegroundInstanceMaskRequest` → `VNInstanceMaskObservation` (`allInstances`, `generateScaledMaskForImage(forInstances:from:)`, `generateMaskedImage(…)`) | iOS 17+ / macOS 14+ 🔶 | OS API (free) | **Excellent zero-download "Select Subject" / BG removal on Apple.** Also `VNGeneratePersonSegmentationRequest` (iOS 15+) and `VNGeneratePersonInstanceMaskRequest` (iOS 17+) for people. Call it via a platform channel or Pigeon |
| **ML Kit Subject Segmentation** (`google_mlkit_subject_segmentation` 0.2.1) | **Android only** (Google docs ✅; the plugin's iOS tag is misleading) | plugin MIT; ML Kit terms | **Beta**, no SLA. Per-subject masks, ~200 ms on Pixel 7 Pro. Zero-download "Select Subject" on Android |
| ML Kit Selfie Segmentation (`google_mlkit_selfie_segmentation` 0.12.1) | Android, iOS | plugin MIT; ML Kit terms | People-only mask |
| Windows App SDK AI imaging (Image Object Extractor / Remover, Image Scaler) | Windows 11 **Copilot+ PCs (NPU) only** 🔶 | OS API | Nice-to-have later, not a baseline |

**Recommended architecture:** behind one Dart interface (`SubjectMasker`, `Inpainter`, `Upscaler`), use the **OS-native fast path** where it exists (Apple Vision on iOS/macOS, ML Kit on Android) for instant "Select Subject". Use **ONNX Runtime with the same model files everywhere** for everything else and for Windows. This also gives consistent output across platforms when you need it (e.g. presets synced between devices).

### 8.3 Per-feature model files: bundle or download?

Rule: **bundle only the small "instant" models (~40 MB total)**. Everything else downloads on first use, with a progress UI, to `getApplicationSupportDirectory()` from your own CDN, with SHA-256 checks and resumable downloads (e.g. `background_downloader`). The URLs below are the HF sources to mirror.

| Feature | ONNX file | Source URL (mirror to your CDN) | Size | Ship |
|---|---|---|---|---|
| Subject (people, instant) | MODNet q8 / fp32 | `https://huggingface.co/Xenova/modnet/resolve/main/onnx/model_quantized.onnx` (or `model.onnx`) | 6.6 MB / 25.9 MB | **Bundle q8** (fp32 on first use for GPU EPs) |
| Subject (objects, HQ) + BG removal | BiRefNet_lite fp16 (Apple/Android) / fp32 (Windows) | `https://huggingface.co/onnx-community/BiRefNet_lite-ONNX/resolve/main/onnx/model_fp16.onnx` · `…/onnx/model.onnx` | 114.5 MB / 224 MB | **Download on first use** |
| Click/box select | EdgeTAM (4 files: `vision_encoder.onnx` + `.onnx_data`, `prompt_encoder_mask_decoder.onnx` + `.onnx_data`) | `https://huggingface.co/onnx-community/EdgeTAM-ONNX/tree/main/onnx` | ~40 MB fp32 / ~20 MB fp16 | **Download** when Masking first opens (prefetch) |
| Sky | skyseg | `https://huggingface.co/JianyuanWang/skyseg/resolve/main/skyseg.onnx` | 176 MB (fp16 ≈ 88 MB after conversion) | **Download on first use** |
| Sky validator + Lens Blur | Depth Anything V2 Small | `https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/main/onnx/model.onnx` (q8: `model_quantized.onnx`) | 99 MB / 27.3 MB | **Download on first use** |
| Background mask | inverted subject mask | — | 0 | — |
| Object removal (default) | MI-GAN pipeline | `https://huggingface.co/andraniksargsyan/migan/resolve/main/migan_pipeline_v2.onnx` | 28.1 MB | **Bundle** (core feature, small, no pre/post code to port) |
| Object removal (HQ) | LaMa | `https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx` | 208 MB | **Download** on the user's first "HQ remove" |
| Upscale | Real-ESRGAN general x4v3 | `https://huggingface.co/Heliosoph/realesrgan-onnx/resolve/main/realesr-general-x4v3.onnx` (re-export from the official `realesr-general-x4v3.pth` before launch) | 4.9 MB | **Bundle** |
| People parts / retouch | MediaPipe Selfie Multiclass + Face Landmarker (LiteRT) | Google `storage.googleapis.com/mediapipe-models/...` 🔶 | ~16 MB + ~4 MB | Download on first use |

The app binary grows by about 40 MB. The full on-device set is about 550–700 MB, which fits comfortably in the 30 GB dev budget.

### 8.4 Running inference off the UI thread (Dart isolates)

- ORT's `session.run` already executes in **native code**, so the bigger jank risks are Dart-side **pre/post-processing** (decode, resize and normalize a 24 MP image; threshold, upsample and feather a mask) and **copying large tensors** across the plugin boundary. `flutter_onnxruntime` appears to use method-channel native wrappers 🔶, so a 1024²×3 float32 input (12 MB) is copied per call.
- Do pixel work in `Isolate.run(...)` (or a long-lived worker isolate per model). Pass buffers as `TransferableTypedData` to avoid copies between isolates.
- Calling a plugin from a background isolate requires `BackgroundIsolateBinaryMessenger.ensureInitialized(RootIsolateToken.instance!)` (pass the token from the root isolate). Otherwise, keep `session.run` on the root isolate and do only the pixel math in the worker.
- Use the engine for cheap resizing: `ui.instantiateImageCodec(bytes, targetWidth: 1024)` decodes straight to model size. Avoid pure-Dart `package:image` resizes on full-res photos.
- Keep one live session per loaded model. Close sessions when the user leaves a tool (memory on iOS). Always `dispose()` `OrtValue`s.

```dart
// sketch: pre-process in a worker isolate, run natively, post-process in a worker isolate
final input = await Isolate.run(() => toNchwFloat32(rgbaBytes, w, h, mean, std));
final out = await session.run({'input': await OrtValue.fromList(input, [1, 3, h, w])});
final alpha = await Isolate.run(() => thresholdAndFeather(out, w, h));
```

---

## 9. Web build only (transformers.js / Next.js), kept for a web demo or Flutter Web

- **transformers.js** latest **4.3.0** (2026-09-16) ✅. v4.0.0 landed 2026-03-30 with a new C++ WebGPU runtime ✅. Its dependency is pinned to `onnxruntime-web 1.31.0-dev…`. If you also import `onnxruntime-web/webgpu` (for MI-GAN, LaMa or Real-ESRGAN), **pin the same version** so npm dedupes it to one runtime.
- Pipelines ✅: `background-removal` (default `Xenova/modnet`), `image-segmentation`, `image-to-image` (Swin2SR only), `depth-estimation`, `zero-shot-image-classification`. **There is no `mask-generation` pipeline in v4.** Use `SamModel` / `Sam2Model` / `EdgeTamModel` + `AutoProcessor` + `model.get_image_embeddings()`.

```js
const seg = await pipeline('background-removal', 'onnx-community/BiRefNet_lite-ONNX', { device: 'webgpu', dtype: 'fp16' });
const rgba = await seg(imageBlobOrUrl);           // RawImage with alpha
const model = await EdgeTamModel.from_pretrained('onnx-community/EdgeTAM-ONNX', { device: 'webgpu', dtype: 'fp16' });
const proc = await AutoProcessor.from_pretrained('onnx-community/EdgeTAM-ONNX');
const inputs = await proc(img, { input_points: [[[[x, y]]]], input_labels: [[[1]]] });
const emb = await model.get_image_embeddings(inputs);            // once per image
const out = await model({ ...inputs, ...emb });                  // per click
const masks = await proc.post_process_masks(out.pred_masks, inputs.original_sizes, inputs.reshaped_input_sizes);
```

- **Caching ✅:** `env.useBrowserCache` (Cache API, key `transformers-cache`), `env.useWasmCache`, `ModelRegistry.is_cached / get_available_dtypes / clear_cache`, `env.remoteHost` to self-host. Call `navigator.storage.persist()`, because Safari can evict script-writable storage 🔶.
- **Next.js 16.3.8 / Turbopack ✅:** the v4 `exports` map sends browsers to `transformers.web.js`, which imports only `onnxruntime-web/webgpu`. Import transformers.js **only inside a Web Worker** (`new Worker(new URL('./ai.worker.ts', import.meta.url), { type: 'module' })`), so SSR never pulls `onnxruntime-node` (301 MB) or `sharp`. Webpack users: alias `sharp$` / `onnxruntime-node$` to `false`. Turbopack: `turbopack.resolveAlias` (only the `browser` condition is supported).
- **COOP/COEP** (`same-origin` + `require-corp`) are only needed for **multithreaded WASM**; WebGPU doesn't need them. Scope them to the editor route. COOP `same-origin` breaks OAuth popups such as Firebase `signInWithPopup`. `credentialless` isn't supported in Safari 🔶. Without `wasmPaths`, transformers.js loads ORT WASM from jsDelivr.
- WebGPU is on by default in Chrome/Edge, Safari 26 and Firefox 141+ (Windows) / 145+ (Apple Silicon macOS) 🔶. img.ly measured ~100 ms (WebGPU fp16) vs ~2,000 ms (16-thread WASM) for an 84–168 MB segmentation net on an M3 Max 🔶.

---

## 10. What is still unverified (test next)

1. GPU-EP coverage per model: CoreML for BiRefNet_lite, EdgeTAM, LaMa; DirectML for any of them; plus Android XNNPACK/NNAPI latency on mid-range phones.
2. `flutter_onnxruntime`'s marshalling overhead for 4–12 MB tensors, and whether it can run from a background isolate.
3. The skyseg quality bar vs SegFormer-ADE (the commercial gap) and whether an fp16 conversion keeps accuracy.
4. EdgeTAM vs SlimSAM vs SAM2.1-tiny mask quality on stills.
5. Apple Vision / ML Kit output resolution and edge quality vs BiRefNet_lite.
6. Legal review of training-data provenance (Places2, DIV2K, skyseg data) and the SAM License.

### Sources
- transformers.js v4 blog: https://huggingface.co/blog/transformersjs-v4 · releases: https://github.com/huggingface/transformers.js/releases · npm: https://www.npmjs.com/package/@huggingface/transformers
- HF model cards and API (sizes/licenses): https://huggingface.co/onnx-community/EdgeTAM-ONNX · https://huggingface.co/Xenova/slimsam-77-uniform · https://huggingface.co/onnx-community/sam2.1-hiera-tiny-ONNX · https://huggingface.co/onnx-community/sam3-tracker-ONNX · https://huggingface.co/onnx-community/BiRefNet_lite-ONNX · https://huggingface.co/Xenova/modnet · https://huggingface.co/onnx-community/ormbg-ONNX · https://huggingface.co/onnx-community/BEN2-ONNX · https://huggingface.co/briaai/RMBG-1.4 · https://huggingface.co/onnx-community/ISNet-ONNX · https://huggingface.co/JianyuanWang/skyseg · https://huggingface.co/onnx-community/depth-anything-v2-small · https://huggingface.co/nvidia/segformer-b0-finetuned-ade-512-512 · https://huggingface.co/Xenova/detr-resnet-50-panoptic · https://huggingface.co/Xenova/clipseg-rd64-refined · https://huggingface.co/Carve/LaMa-ONNX · https://huggingface.co/andraniksargsyan/migan · https://huggingface.co/Heliosoph/realesrgan-onnx · https://huggingface.co/Xenova/swin2SR-classical-sr-x2-64 · https://huggingface.co/Heliosoph/scunet-onnx · https://huggingface.co/Xenova/siglip-base-patch16-224 · https://huggingface.co/openai/clip-vit-base-patch32
- Licenses: https://github.com/NVlabs/SegFormer/blob/master/LICENSE · https://github.com/facebookresearch/MaskFormer · https://github.com/facebookresearch/sam3/blob/main/LICENSE · https://github.com/Picsart-AI-Research/MI-GAN · https://github.com/advimman/lama · https://github.com/xinntao/Real-ESRGAN · https://github.com/imgly/background-removal-js · https://github.com/lxfater/inpaint-web · https://github.com/sczhou/CodeFormer · https://github.com/xiongzhu666/Sky-Segmentation-and-Post-processing · https://github.com/facebookresearch/EdgeTAM
- MediaPipe: https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter · https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker
- ONNX Runtime Web: https://onnxruntime.ai/docs/tutorials/web/env-flags-and-session-options.html · https://opensource.microsoft.com/blog/2024/02/29/onnx-runtime-web-unleashes-generative-ai-in-the-browser-using-webgpu/ · https://img.ly/blog/browser-background-removal-using-onnx-runtime-webgpu/
- Next.js: https://huggingface.co/docs/transformers.js/tutorials/next · https://nextjs.org/docs/app/api-reference/config/next-config-js/turbopack
- Flutter: https://pub.dev/packages/flutter_onnxruntime · https://github.com/masicai/flutter_onnxruntime · https://pub.dev/packages/onnxruntime · https://pub.dev/packages/flutter_litert · https://pub.dev/packages/tflite_flutter · https://pub.dev/packages/google_mlkit_subject_segmentation · https://developers.google.com/ml-kit/vision/subject-segmentation · https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest
- IOPaint: https://github.com/Sanster/IOPaint
