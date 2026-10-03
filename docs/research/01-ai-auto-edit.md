# 01 · AI Auto-Edit: Approaches, Models, Formulas and Prompting

**Question:** how should Lumen produce a pro-quality automatic edit that stays fully editable as Lightroom-style sliders?
**Stack (updated 2026-10-03):** Flutter (Dart) app on macOS, iOS, Android and Windows, plus a small **Dart backend gateway** that holds the Claude API key. All formulas below are language-neutral maths and pseudo-code that port directly to Dart (`dart:math`: `log`, `pow`, `exp`; note `log2(x) = log(x) / ln2`). "On-device" means ONNX Runtime inside Flutter.
**Research date:** 2026-10-03. **Method:** papers (arXiv HTML), GitHub repos and LICENSE files (read via the GitHub API), Hugging Face model cards, dataset license files, Claude platform docs (vision, structured outputs). No app code is written here.

**Confidence tags** (same convention as `04-market.md`, plus two):
- **[V]** verified from the primary source during this session (paper, repo LICENSE file, vendor doc)
- **[S]** secondary or recalled source; likely right, check before relying on it
- **[C]** sources conflict
- **[U]** could not verify
- **[H]** our own heuristic or proposal; a starting value that must be calibrated on Lumen's eval set

---

## 0. TL;DR

1. **Use a vision LLM as the primary engine (Claude), not a learned enhancement network.** Every serious 2025–2026 system that keeps edits editable (JarvisArt, JarvisEvo, MonetGPT, PhotoArtAgent, RetouchIQ, RetouchLLM) has an MLLM emit **named slider values** (in practice Lightroom's own parameter names) and render them with a deterministic engine. That is exactly Lumen's model.
2. **No open model is commercially usable as-is.** JarvisArt, JarvisEvo and VeraRetouch weights are explicitly non-commercial. MonetGPT is MIT, but it was trained on puzzles built from **PPR10K, whose agreement bans commercial use of "any portion of derived data"**. Its reasoning traces were also generated with Gemini.
3. **The licensing trap sits in the data, not the code.** The small enhancement models (3D-LUT, AdaInt, SepLUT, LUTwithBGrid, IAT, HDRNet, DeepLPF, CURL) have Apache, MIT or BSD code, but all of their shipped weights were trained on **MIT-Adobe FiveK (research-only license)**, PPR10K (non-commercial) or LOL. Treat those weights as **not commercial-safe**. Zero-DCE/Zero-DCE++, Deep White Balance, WB_sRGB and NeuralPreset are non-commercial even at the code level.
4. **The learned models also break the core promise.** They output a LUT, a bilateral grid or per-pixel curves, not sliders. They're useful later only as (a) architectures we retrain on licensed data, or (b) teachers whose output we *project onto sliders*.
5. **Recommended engine stack:** `vision` (Claude: scene understanding, style, explanations) → **deterministic validator/solver** (fixes clipping, white balance drift and overshoot on a 512 px proxy) → render. The `local` engine (statistical auto-tone, section 6) is the offline fallback *and* the anchor value we feed Claude. Phase 2 is an on-device slider regressor (an ONNX file of a few MB, run with ONNX Runtime from Flutter) trained on synthetic inversions of licensed photos.
6. **Prompt pattern that works** (from MonetGPT, PhotoArtAgent and RetouchLLM):
   - image first, then local stats and EXIF as text (Claude doesn't read image metadata)
   - analysis before numbers: issue, adjustment, reason
   - sparse JSON with an intensity legend
   - staged or closed-loop verification with "Image 1: before / Image 2: after"
   - client-side clamping and damping, because LLMs overshoot
7. **Expect to iterate.** PhotoArtAgent (GPT-4o) got a satisfactory result on the first try for only **23.8%** of images [V]. Budget one gated verify round, triggered by the validator or by Pro mode, not on every photo.
8. **Cost per photo** (1024 px preview, about 1k image tokens, cached system prompt):
   - Claude Haiku 4.5: about **$0.005–0.01** per pass
   - Claude Sonnet 5.5: about **$0.01–0.02** per pass
   - Claude Opus 5.5: about **$0.03–0.05** per pass

   A verify round roughly doubles the cost. The Batch API halves it for non-interactive bulk jobs [V pricing table; token estimates H].

---

## 1. Comparison table

Legend: **Wts** = pretrained weights downloadable. **On-device** = realistically runnable inside the Flutter app via ONNX Runtime (plugins `flutter_onnxruntime` MIT, v1.8.5, 2026-09, android/ios/macos/windows/linux/web; or `onnxruntime` MIT, v1.4.1, last release 2024-03 [V pub.dev]) at interactive speed on a 256–512 px proxy. **ONNX exists** = a ready-made `.onnx` file is publicly available; otherwise we export it ourselves from PyTorch (`torch.onnx.export`), which is routine for these small CNNs but custom LUT/grid-sample ops may need rewriting [S]. **Commercial-safe** considers code license *and* weights/training-data license.

### 1a. LLM / MLLM agents that predict editing parameters

| Name (venue) | Repo | License | Wts | Size | On-device | Output | Verdict |
|---|---|---|---|---|---|---|---|
| **JarvisArt** (NeurIPS 2025) | [LYL1015/JarvisArt](https://github.com/LYL1015/JarvisArt) | **JarvisArt Non-Commercial License v1.0** [V]. Dataset (MMArt) Apache-2.0 [S] | Y (HF `JarvisArt/JarvisArt-1208`) | 8B (Qwen2.5-VL-7B base) [V] | N | `<think>` + `<answer>` holding Lightroom params (Lua dict / XMP), 200+ tools including masks [V] | **Don't use the weights.** Its parameter dictionary and CoT structure are the best public reference for our schema |
| **JarvisEvo** (CVPR 2026) | [LYL1015/JarvisEvo](https://github.com/LYL1015/JarvisEvo) | **Non-commercial**: bans use "in direct interactions with … end users" and distillation for commercial use [V] | Y (HF) | 8B [S] | N | Interleaved multimodal CoT: renders, looks at the result, then continues | Don't use. Copy the *idea*: look at intermediate renders |
| **MonetGPT** (SIGGRAPH 2025) | [niladridutt/monetgpt](https://github.com/niladridutt/monetgpt) | Code and weights **MIT** [V]. Base Qwen2-VL-7B (Apache-2.0) [S]. Training puzzles built from **PPR10K** (non-commercial, "derived data" clause) [V]. Reasoning text from Gemini 2.0 Flash [V] | Y (HF `niladridutt/monetGPT`) | 8B [V] | N | Two turns: plan (Adjustment/Issue/Solution), then JSON of LR-named values in [-100, 100]. Staged: tone → WB/saturation → HSL [V] | **Best prompt template to imitate.** Weights are legally grey for SaaS, so don't ship them without counsel |
| **PhotoArtAgent** (CVPR 2026 Findings) | none found | n/a | N | uses GPT-4o (Claude 3.5 Sonnet also tested) [V] | n/a | Analysis → strategy options → histogram analysis → JSON via function calling → reflection loop [V] | Closest to Lumen's design with a hosted VLM. Validates the "Claude + loop" approach |
| **RetouchLLM** (arXiv 2510.08054) | code in paper supplement only [V] | paper CC BY 4.0. Code license [U] | n/a (training-free) | uses GPT-5. Qwen2.5-VL-72B, Gemini 1.5 Pro and InternVL3 also tested [V] | n/a | Visual critic writes descriptions → code generator writes filter code over 7 ops in [-1, 1]. N=3 candidates, up to 10 iterations, selection score [V] | Borrow: candidate sampling + selection + early stop |
| **RetouchIQ** (CVPR 2026, Adobe/UCSB) | none found | n/a | N | Qwen2.5-VL-7B policy + MLLM "generalist reward" [V] | N | Reasoning trace + Lightroom adjustments [V] | Idea only: a reward model that writes *case-specific* metrics |
| **PerTouch** (arXiv 2511.12998) | [Auroral703/PerTouch](https://github.com/Auroral703/PerTouch) | **no LICENSE file** (all rights reserved) [V] | [U] | diffusion + VLM agent | N | 4 attribute maps (colorfulness, contrast, temperature, brightness) in [-1, 1] + SAM regions [V] | Idea only: weak vs strong instructions, user preference memory |
| **PhotoAgent** (ICML 2026) | [mdyao/PhotoAgent](https://github.com/mdyao/PhotoAgent) | MIT announced, **code "coming soon"** [V] | N | VLM + generative editors (Flux Kontext, Step1X-Edit, GPT-4o) [V] | N | MCTS over edit instructions, depth 3, 20 simulations [V] | Not parametric. Its UGC aesthetic reward idea is useful later |
| **VeraRetouch** (arXiv 2604.27375) | [OpenVeraTeam/VeraRetouch](https://github.com/OpenVeraTeam/VeraRetouch) | Code Apache-2.0. **Weights academic-only, commercial use "strictly prohibited"** [V] | Y | 0.5B VLM, about 0.63B total; Core ML export [V] | Maybe (size OK) | Differentiable renderer with lighting/color/HSL latents; auto, style and parameter modes [V] | Proves a sub-1B on-device slider model is feasible. **Can't ship these weights** |

### 1b. Small learned global-enhancement models (on-device candidates)

FiveK PSNR is expert-C, 480p, from the SVDLUT 2025 comparison table unless noted [V]. Differences under about 0.3 dB are visually subtle.

| Name | Repo | Code license | Weights trained on | Wts | Params | ONNX exists | FiveK PSNR | On-device | Output | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| **CSRNet** (ECCV'20) | [hejingwenhejingwen/CSRNet](https://github.com/hejingwenhejingwen/CSRNet) | **none** (all rights reserved) [V] | FiveK | Y | 36.4K | N [U] | 25.19 | Y | pixels (global modulation) | ✗ code unusable. Tiny architecture worth re-implementing from the paper |
| **Image-Adaptive-3DLUT** (TPAMI'20) | [HuiZeng/Image-Adaptive-3DLUT](https://github.com/HuiZeng/Image-Adaptive-3DLUT) | Apache-2.0 [V] | FiveK, PPR10K (research-only) | Y (~2.4 MB) [V] | 593.5K | N [U] | 25.29 | Y (CNN on 256 px + GPU-shader LUT) | 3D LUT | Retrain-only. Best fit for a GPU fragment-shader pipeline |
| **AdaInt** (CVPR'22) | [ImCharlesY/AdaInt](https://github.com/ImCharlesY/AdaInt) | Apache-2.0 [V] | FiveK, PPR10K | Y (2.5 MB FiveK; 47 MB PPR10K) [V] | 619.7K | N [U] | 25.49 | Y | 3D LUT (non-uniform) | Retrain-only |
| **SepLUT** (ECCV'22) | [ImCharlesY/SepLUT](https://github.com/ImCharlesY/SepLUT) | Apache-2.0 [V] | FiveK, PPR10K | Y [V] | 119.8K | N [U] | 25.47 | Y | 1D + 3D LUT | Retrain-only. Its 1D-curve stage maps nicely to a tone curve |
| **LUTwithBGrid** (ECCV'24) | [WontaeaeKim/LUTwithBGrid](https://github.com/WontaeaeKim/LUTwithBGrid) | Apache-2.0 [V] | FiveK, PPR10K | Y [V] | <1M [U] | N [U] | ~25.6 [U] | Y | LUT + bilateral grid | Retrain-only |
| **CLUT-Net** (MM'22) | [Xian-Bei/CLUT-Net](https://github.com/Xian-Bei/CLUT-Net) | **none** [V] | FiveK | Y | small [U] | N | ~25.3 [U] | Y | compressed 3D LUT | ✗ |
| **ICELUT** (CVPR'24) | [Stephen0808/ICELUT](https://github.com/Stephen0808/ICELUT) | **none** [V] | FiveK, PPR10K | Y | tiny (LUT-only inference) [S] | N | [U] | Y (CPU) | LUTs | ✗ license |
| **SVDLUT / LoR-LUT** (2025–26) | arXiv 2508.16121 / 2602.22607 | code status unclear; LoR-LUT "will be released" [V] | FiveK | N | 160.5K / 40–120K [V] | N | 25.76 / 25.35–25.53 [V] | Y | LUT | Watch list |
| **NILUT** (AAAI'24) | [mv-lab/nilut](https://github.com/mv-lab/nilut) | MIT [V]. Shipped LUTs CC-4.0. Demo images FiveK [V] | fitted to given `.cube` LUTs | Y | small MLP [S] | N [U] | n/a | Y (bake to a 33³ LUT) | continuous LUT, blendable styles | **Usable** to encode *our own* creative looks ("Profiles" with an Amount). Not an auto-editor |
| **HDRNet** (SIGGRAPH'17) | [google/hdrnet](https://github.com/google/hdrnet) | Apache-2.0 [V] | FiveK, HDR+ | Y (download script) [V] | 483.1K | N [U] | 24.66 | Y | bilateral grid of affines | Reference only (TF1, old) |
| **DeepLPF** (CVPR'20) | [sjmoran/deeplpf-image-enhancement](https://github.com/sjmoran/deeplpf-image-enhancement) | MIT [V] | FiveK (README notes the photographers' copyright) [V] | Y | 1.7M | **Y** (PINTO #152) [V] | 24.73 | Y | parametric local filters (graduated, elliptical, polynomial) | Retrain-only. Interesting for *local* auto-masks in v2 |
| **CURL** (ICPR'20) | [sjmoran/curl-image-enhancement](https://github.com/sjmoran/curl-image-enhancement) | BSD-3-Clause [V] | FiveK | Y [V] | 1.7M [V] | N [U] | 24.15 (DPE split, per checkpoint name) [V] | Y | global curves in HSV/Lab/RGB | Retrain-only. Curves map to tone curve + HSL |
| **NamedCurves** (ECCV'24) | [davidserra9/namedcurves](https://github.com/davidserra9/namedcurves) | **none** [V] | FiveK, PPR10K | Y [V] | [U] | N | 25.59 (UPE split, per checkpoint name) [V] | Y | tone curve per named color | ✗ license. Concept is very close to HSL |
| **Exposure** (Hu et al., TOG'18) | [yuanming-hu/exposure](https://github.com/yuanming-hu/exposure) | MIT [V] | own data. Weights "might not release" [V] | N | [U] | N | n/a | Y | **sequence of named filters + params** (RL, unpaired) | Best *conceptual* match (white-box, parametric). TF1 is dated, so it's a design reference |
| **IAT** (BMVC'22) | [cuiziteng/Illumination-Adaptive-Transformer](https://github.com/cuiziteng/Illumination-Adaptive-Transformer) | Apache-2.0 [V] | LOL, MIT-5K, Exposure (FiveK-derived) [V] | Y (427 KB each) [V] | 90K [V] | **Y** (PINTO #315) [V] | [U] | Y | local add/mul maps + **global 3×3 color matrix + gamma** [V] | Retrain-only. Its interpretable global branch is a nice design |
| **Zero-DCE / Zero-DCE++** (CVPR'20 / TPAMI'21) | [Li-Chongyi/Zero-DCE](https://github.com/Li-Chongyi/Zero-DCE), [Zero-DCE_extension](https://github.com/Li-Chongyi/Zero-DCE_extension) | **CC BY-NC 4.0, "non-commercial use only"** [V] | SICE (unpaired) | Y | 79K / 10K [S] | **Y** (PINTO #216, #243) [V] | n/a (low-light) | Y | iterative per-pixel quadratic curves | ✗ code and weights. **Zero-reference training idea is valuable** (see 3.3) |
| **SCI** (CVPR'22) | [vis-opt-group/SCI](https://github.com/vis-opt-group/SCI) | **none** [V] | LOL/MIT/LSRW | Y | tiny [S] | Y (PINTO #286) [V] | n/a | Y | illumination map | ✗ |
| **NeuralPreset** (CVPR'23) | [ZHKKKe/NeuralPreset](https://github.com/ZHKKKe/NeuralPreset) | **CC BY-NC-SA 4.0** [V] | n/a | [U] | [U] | N | n/a | Y | color-style transfer | ✗ |

**ONNX availability for Flutter, at a glance:**
- **Ready-made `.onnx` files (PINTO model zoo):** DeepLPF, IAT, Zero-DCE / Zero-DCE++, SCI and Deep White Balance (which also has TF.js) [V]. A ready-made file doesn't change the license. Of these, only DeepLPF (MIT) and IAT (Apache-2.0) have commercial-safe *code*, and both ship FiveK/LOL-trained weights that need retraining.
- **No ONNX file found (export it ourselves):** the 3D-LUT family (3DLUT, AdaInt, SepLUT, LUTwithBGrid), CSRNet, CURL, NamedCurves, NILUT and HDRNet [U]. For the LUT models, export only the small CNN that predicts LUT weights, and do the trilinear LUT lookup in a shader.
- **LLM agents (1a):** none have ONNX files. At 7–8B they're server-GPU models. VeraRetouch ships Core ML, not ONNX [V].

### 1c. Supporting models (white balance, aesthetics)

| Name | Repo | License | Notes | Verdict |
|---|---|---|---|---|
| Deep White Balance (CVPR'20) | [mahmoudnafifi/Deep_White_Balance](https://github.com/mahmoudnafifi/Deep_White_Balance) | **CC BY-NC-SA 4.0** [V] | sRGB WB editing. ONNX/TF.js exist (PINTO #076) [V] | ✗ |
| WB_sRGB (CVPR'19) | [mahmoudnafifi/WB_sRGB](https://github.com/mahmoudnafifi/WB_sRGB) | **CC BY-NC-SA 4.0** [V] | KNN on sRGB histograms | ✗ |
| Exposure_Correction (CVPR'21) | [mahmoudnafifi/Exposure_Correction](https://github.com/mahmoudnafifi/Exposure_Correction) | "research purposes only and CANNOT be used for commercial purposes" [V] | | ✗ |
| C5 / FFCC / FC4 | [mahmoudnafifi/C5](https://github.com/mahmoudnafifi/C5), [google/ffcc](https://github.com/google/ffcc), [yuanming-hu/fc4](https://github.com/yuanming-hu/fc4) | Apache-2.0 / Apache-2.0 / MIT [V] | **raw-domain**, camera-specific color constancy | Only relevant if Lumen decodes real RAW later |
| LAION improved aesthetic predictor | [christophschuhmann/improved-aesthetic-predictor](https://github.com/christophschuhmann/improved-aesthetic-predictor) | Apache-2.0 [V] | needs CLIP ViT-L/14 (server-side) | Optional server-side variant ranking. Check CLIP and LAION data terms first |
| NIMA (idealo) | [idealo/image-quality-assessment](https://github.com/idealo/image-quality-assessment) | Apache-2.0 code [V] | trained on AVA/TID (dataset terms [U]) | Optional. Verify data terms first |

### 1d. Dataset licenses (why weights are the problem)

| Dataset | License | Consequence |
|---|---|---|
| MIT-Adobe FiveK | "RESEARCH LICENSE … solely for your own research purposes … not … directed toward commercial advantage" ([LicenseAdobe.txt](https://data.csail.mit.edu/graphics/fivek/legal/LicenseAdobe.txt)) [V]. Includes a **Lightroom catalog with 5 experts' slider values** [V] | Ideal slider-regression data, but **research-only**. Don't train shipped models on it without a license from Adobe/MIT |
| PPR10K | "available for ***non-commercial research purposes*** only … not … exploit for any commercial purposes, any portion of the images and any portion of derived data" ([README](https://github.com/csjliang/PPR10K)) [V] | Taints MonetGPT, AdaInt/SepLUT PPR10K weights and JarvisArt's MMArt-PPR10K |
| Unsplash **Lite** (25k photos) | license to "internally use the Commercial Licensed Data to train machine learning models or algorithms for your internal business purposes" ([TERMS.md](https://github.com/unsplash/datasets/blob/master/TERMS.md)) [V]. Full dataset: non-commercial only [V] | **Best candidate** for training our own model. "Internal business purposes" plus a shipped model needs a legal read |

---

## 2. What the LLM-agent papers teach (and what to steal)

### 2.1 JarvisArt (NeurIPS 2025) [V]
- Qwen2.5-VL-7B fine-tuned with CoT SFT, then **GRPO-R** reinforcement learning using three rewards:
  - format compliance
  - retouching-operation accuracy: Jaccard similarity on tool names, plus parameter-name and parameter-value similarity
  - perceptual quality: 0.4 × CIELAB color-distribution similarity + 0.6 × pixel distance
- CoT flow: visual scene analysis → user intent → retouching strategy → tool and parameter selection. Output goes in `<think>…</think><answer>…</answer>`.
- The **system prompt is a Lightroom parameter dictionary** with names, ranges and one-line semantics (for example `Exposure2012 [-5, 5]`, `ParametricShadowSplit [10, 50]`, `ToneCurvePV2012` as x,y points 0–255), plus mask schemas (`Mask/Image` subject/sky/person, radial, linear). It also says "only include parameters that need to change". Write our own version; don't copy theirs, since the repo is under a non-commercial license.
- Its data pipeline has the MLLM **pick from a curated preset library** (global + local presets per scene class, with descriptions) and propose *several diverse* recommendations. **Steal:** have Claude choose from Lumen's own style atoms and presets, then fine-tune the numbers. This cuts hallucinated magnitudes and makes the "variations strip" cheap.

### 2.2 MonetGPT (SIGGRAPH 2025) [V from repo code]
- Ops use **Lightroom names** in [-100, 100]: `Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Temperature, Tint, Saturation` + `Hue/Saturation/LuminanceAdjustment{Red,Orange,Yellow,Green,Aqua,Blue,Purple,Magenta}`, plus Dehaze derived internally.
- **Staged closed loop:** stage 1 tone (WB-tone-contrast group) → render → stage 2 (temperature, tint, saturation) → render → stage 3 (HSL, "only pick a few"). Each stage re-sees the *updated* image.
- **Two-turn prompt per stage:**
  1. "Analyze … develop a professional-grade editing plan … For each adjustment: *Adjustment / Issue / Solution*"
  2. "Based on the editing plan … tell the optimal adjustment values … in JSON. All adjustment values are scaled between -100 and +100", plus an **intensity legend**: 1–12 Very Slight, 13–24 Slight, 25–36 Mild, 37–48 Moderate, 49–60 Noticeable, 61–72 Significant, 73–84 Very Significant, 85–100 Extremely Intense.
- **Style instructions** as a parameter: balanced ("avoid overdoing any single parameter … natural, true-to-life"), vibrant, retro.
- **Post-processing damping** of model outputs: Exposure halved, negative Contrast ÷3, cooling Temperature halved, negative Saturation ÷3. Its comments note that the operations aren't symmetric. **Steal:** a per-slider damping/calibration table, tuned on our own renderer.
- Image to the MLLM capped at 1280 px; edits applied at native resolution.
- HSL band hue centers used in its implementation: red 355°, orange 25°, yellow 55°, green 100°, aqua 180°, blue 215°, purple 280°, magenta 320° (`configs/hsl.yaml`). This is a reasonable starting point for Lumen's HSL band centers; Lightroom's exact centers are unpublished [U].

### 2.3 PhotoArtAgent (CVPR 2026 Findings) [V]
- GPT-4o drives Lightroom through an API. Parameters cover Light (exposure, contrast, highlights, shadows, whites, blacks), Color (temperature, tint, saturation, vibrance) and Color Mixer HSL × 8.
- Sequence: image analysis (content, emotion) → **several artistic directions proposed to the user** → **histogram analysis** → structured JSON via function calling → **reflection** on the rendered result, repeated until satisfactory.
- Only **23.8%** of images were satisfactory on the first attempt. GPT-4o beat GPT-4o-mini and Claude 3.5 Sonnet (2024-era models; current Claude models are untested in the paper) [V].

### 2.4 RetouchLLM (training-free) [V]
- Seven ops in [-1, 1]: exposure, contrast, highlight, shadow, saturation, temperature, texture.
- The **visual critic** gets color statistics and CLIP scores in the prompt, then writes 3 candidate descriptions (increase/decrease/maintain per aspect, with ranges). A **code generator** samples parameters inside those ranges.
- Coarse-to-fine rule: global brightness first, then local brightness, then color/texture.
- Selection score picks the best of N+1 candidates (including "no change"). Early stop after 3 consecutive "no change" picks or a critic "stop", with at most 10 iterations.
- **Steal:** (a) feed numeric stats with the image, (b) "no change" is always a candidate, (c) explicit coarse-to-fine order.

### 2.5 RetouchIQ, PerTouch, PhotoAgent, VeraRetouch, JarvisEvo (ideas only)
- **RetouchIQ:** a reward MLLM that *writes case-specific evaluation metrics* before scoring. This maps to our "verify" prompt: ask Claude to state 2–3 checkable criteria for *this* photo, then grade against them.
- **PerTouch:** splits weak instructions ("optimize this") from strong ones ("much brighter eagle"), and keeps a per-user preference memory. This maps to "Learn My Style".
- **PhotoAgent:** tree search over edit actions, scored by an aesthetic reward trained on 7k user-generated photos. Too slow for interactive use; relevant only for an offline "best of N" premium mode.
- **VeraRetouch:** a 0.5B VLM plus a differentiable renderer can run on mobile (Core ML). This shows our Phase-2 on-device model is realistic.
- **JarvisEvo:** interleaving *rendered intermediate images* into the reasoning reduces "instruction hallucination". This supports our render-and-look verify round.

### 2.6 Synthesis: the pattern every successful system shares
1. **Named, bounded parameters** that a deterministic engine renders. Use Lightroom semantics, since VLMs already know them from training data.
2. **Reason first, then numbers:** analysis, issues, plan, then values.
3. **Grounding in measurements:** histograms and color statistics in the prompt.
4. **A closed loop:** render, look again, correct. Staged (MonetGPT) or reflective (PhotoArtAgent, JarvisEvo).
5. **Calibration of magnitudes:** damping, legends, preset anchors. Raw LLM numbers overshoot.

---

## 3. Learned global-enhancement models: how (and whether) to use them

### 3.1 Why not as the primary engine
- **Editability:** a 3D LUT or bilateral grid can't be shown as "Shadows +35". It would be a black-box layer, which contradicts the product promise.
- **Licensing:** see 1d. Every shipped checkpoint was trained on research-only data.
- **Style ceiling:** these models imitate *one* average retoucher (FiveK expert C). Lumen needs styles, instructions and explanations.

### 3.2 Two legitimate uses
1. **Slider projection ("fit-to-target").** Given any target rendering T (from a LUT model, a generative edit or a reference photo), solve for the slider vector θ that minimizes ΔE2000(render(I, θ), T) on a 256–512 px proxy. Use coordinate descent or CMA-ES over about 20 global sliders, or gradient descent if the pipeline has a differentiable CPU/GPU replica (or do the fitting offline in Python). Store any unexplained residual as an optional **"AI Look" profile LUT with an Amount slider**. Lightroom's Creative Profiles work this way [S], so it stays honest and editable. The same machinery powers **"Match look from reference photo"**, the use case of Deep Preset (WACV'21), which predicted 69 Lightroom settings from a reference [S].
2. **Architectures to retrain on licensed data.** The 3D-LUT family fits a GPU pipeline perfectly: a small CNN (ONNX Runtime) on a 256 px thumbnail predicts LUT weights, and a Flutter `FragmentShader` applies the LUT at full resolution.

### 3.3 Phase-2 recommendation: train our *own* slider regressor
- **Model:** MobileNetV3-Small or EfficientNet-Lite0 backbone on a 224–256 px thumbnail, concatenated with a ~64-dim stats vector (histograms, percentiles, chroma stats). An MLP head predicts about 25 global sliders. INT8 ONNX is about 2–6 MB. **We export the `.onnx` file ourselves** and run it with ONNX Runtime from Flutter (`flutter_onnxruntime`, MIT [V]). Execution providers: CoreML on macOS/iOS, NNAPI/XNNPACK on Android, DirectML or CPU on Windows; the CPU fallback is fine at this size [S].
- **Self-supervised inversion data (MonetGPT's puzzle idea, applied to sliders):**
  1. Take well-edited, commercially licensed photos: Unsplash Lite after legal review, commissioned shoots, or licensed stock.
  2. Apply random *degrading* slider vectors with **our own renderer**.
  3. Train the network to predict the inverse vector. Labels are exact and free, with no paired expert data needed.
- **Zero-reference losses** (Zero-DCE's published idea; reimplement, don't reuse its NC code) can add unpaired training:
  - exposure-control loss toward a well-exposedness level (E ≈ 0.6 in the paper [S])
  - gray-world color-constancy loss
  - smoothness of the predicted curve
- **Distill from Claude + user feedback.** Log (thumbnail, Claude's sliders, the user's final sliders) with opt-in consent. The user's final values are the best labels Lumen will ever have. Check Anthropic's usage terms before using Claude outputs as training data [U].
- **Not before:** we have an eval set and at least ~5k licensed images.

---

## 4. Recommended architecture for Lumen auto-edit

```
                          ┌────────────────────────── Flutter app ─────────────────────────┐
 photo ─► decode/EXIF ─► sRGB preview (≤2048) ─► Analyzer (512 px proxy, isolate)         │
                          │   histograms, percentiles, WB estimate, chroma, haze, edges    │
                          │                 │                                              │
                          │                 ├─► LOCAL engine (section 6)  ──► params_L ──► render (instant)
                          │                 │         (also = anchor for vision)           │
                          │                 ▼                                              │
                          │   Request builder: 1024-px JPEG + stats + EXIF + params_L      │
                          └─────────────────┼──────────────────────────────────────────────┘
                                            ▼  Dart gateway (API key stays server-side)
                                Claude (structured output: AutoEditResponse)
                                            ▼
                          ┌────────────── Flutter app ──────────────────────────────────────┐
                          │ Validate (Dart)→ clamp → damp → merge with user-locked sliders  │
                          │ → render proxy → GUARDS (clip %, crush %, WB drift, skin hue)    │
                          │     ├─ OK ───────────────────────────────► apply + explain       │
                          │     ├─ technical violation → local SOLVER fixes the specific     │
                          │     │                         slider (e.g., whites until clip<0.5%)
                          │     └─ big miss / Pro mode → 1 VERIFY round (before/after images)│
                          └──────────────────────────────────────────────────────────────────┘
```

**Engines behind one interface** (matches `IDEAS.md`):

| Engine | When | Latency | Cost | Strength |
|---|---|---|---|---|
| `local` | always (instant first pass); sole engine when no API key | <100 ms on proxy [H] | $0 | Technically correct exposure, levels and WB. No taste |
| `vision` | API key configured | a few seconds per call [U] | ~$0.005–0.05/pass by tier | Scene-aware, styles, instructions, explanations |
| `learned` (Phase 2) | offline premium, batch pre-pass | ~10–50 ms via ONNX Runtime [H] | $0 | Taste learned from users. No API cost |

**Key design decisions**
1. **Progressive UX:** apply `local` immediately, then animate sliders to the `vision` result when it arrives.
2. **Claude decides intent and look; the solver guarantees technical sanity.** LLMs judge "this is a golden-hour portrait, keep it warm, lift the face" well. They are imprecise at "Whites +17 vs +27". Let the response carry both slider values *and* optional semantic targets (key, WB strength, contrast level). The validator only overrides sliders that violate measurable guards. A/B test three modes: (A) raw Claude values, (B) targets + solver, (C) mixed. Start with C.
3. **Store the edit as one history step "AI Auto (style)"** with a global **Amount** (0–150%) that scales deltas from the starting state. It's cheap and very effective for "a bit less".
4. **Variations strip:** request 3 variants (natural / chosen style / bold) in **one** call, so the image tokens are paid once (JarvisArt's multiple recommendations).
5. **Shoot consistency:** for batches, send a contact sheet (grid of 9–16 thumbnails as *one* image) to set shared targets (WB, key, style). Then run the per-photo `local` solver to hit those targets, with per-photo Claude calls only for hero images. This mirrors PPR10K's "group-level consistency" requirement [V].
6. **Determinism:** current Claude models reject `temperature` (400), so outputs vary run to run [V skill docs]. Cache results by `sha256(preview) + style + instruction + model + promptVersion`.
7. **Geometry (straighten/crop) is classical** (section 6.11), not LLM. Claude's docs call spatial and coordinate outputs "approximate" [V].
8. **Failure handling:** on a `refusal` stop reason, timeout or schema failure, fall back silently to `local` and show a subtle "basic auto" badge.

---

## 5. Proposed parameter schema (v1)

### 5.1 `DevelopSettings` (the full edit state; ranges follow Lightroom UI conventions)
XMP names (`crs:`) are listed so Lumen can import and export `.xmp` presets later. Names were checked against ExifTool's XMP crs tag table [V]. Ranges are Lightroom UI ranges as documented in JarvisArt's parameter dictionary and common knowledge [S]. The Kelvin temperature range applies to RAW only.

| Group | Key | Range (default) | XMP `crs:` |
|---|---|---|---|
| Light | `exposure` | −5.00…+5.00 EV, step 0.01 (0) | `Exposure2012` |
| | `contrast`, `highlights`, `shadows`, `whites`, `blacks` | −100…+100 (0) | `Contrast2012`, `Highlights2012`, `Shadows2012`, `Whites2012`, `Blacks2012` |
| Color | `wbMode` | `asShot` \| `auto` \| `custom` | `WhiteBalance` |
| | `temp`, `tint` | −100…+100 relative (0). Shown as Kelvin only for true RAW | `IncrementalTemperature`, `IncrementalTint` (RAW: `Temperature` 2000–50000 K, `Tint` −150…150) |
| | `vibrance`, `saturation` | −100…+100 (0) | `Vibrance`, `Saturation` |
| Presence | `texture`, `clarity`, `dehaze` | −100…+100 (0) | `Texture`, `Clarity2012`, `Dehaze` |
| HSL | `hsl.{red,orange,yellow,green,aqua,blue,purple,magenta}.{hue,sat,lum}` | −100…+100 (0) | `HueAdjustmentRed`, `SaturationAdjustmentRed`, `LuminanceAdjustmentRed`, … |
| Treatment | `treatment` | `color` \| `bw` | `ConvertToGrayscale` |
| | `bwMix.{8 bands}` | −100…+100 (auto) | `GrayMixerRed`, … |
| Tone curve | `curve.parametric.{shadows,darks,lights,highlights}` | −100…+100 (0) | `ParametricShadows`, `ParametricDarks`, `ParametricLights`, `ParametricHighlights` |
| | `curve.splits.{shadow,midtone,highlight}` | 10–50 (25), 25–75 (50), 50–90 (75) | `ParametricShadowSplit`, `ParametricMidtoneSplit`, `ParametricHighlightSplit` |
| | `curve.points.{rgb,red,green,blue}` | 2–16 points `[x,y]`, 0–255, x strictly increasing (identity) | `ToneCurvePV2012`, `…Red/Green/Blue` |
| Color grading | `grade.{shadows,midtones,highlights,global}.{hue,sat,lum}` | hue 0–359, sat 0–100, lum −100…+100 (0) | shadows: `SplitToningShadowHue/Saturation` + `ColorGradeShadowLum`; midtones: `ColorGradeMidtoneHue/Sat/Lum`; highlights: `SplitToningHighlightHue/Saturation` + `ColorGradeHighlightLum`; global: `ColorGradeGlobalHue/Sat/Lum` |
| | `grade.blending`, `grade.balance` | 0–100 (50), −100…+100 (0) | `ColorGradeBlending`, `SplitToningBalance` |
| Detail | `sharpen.{amount,radius,detail,masking}` | 0–150 (0 for JPEG), 0.5–3.0 (1.0), 0–100 (25), 0–100 (0) | `Sharpness`, `SharpenRadius`, `SharpenDetail`, `SharpenEdgeMasking` |
| | `noise.{luminance,color}` | 0–100 (0) | `LuminanceSmoothing`, `ColorNoiseReduction` |
| Effects | `vignette.{amount,midpoint,roundness,feather,highlights}` | −100…+100 (0), 0–100 (50), −100…+100 (0), 0–100 (50), 0–100 (0) | `PostCropVignetteAmount`, `…Midpoint`, `…Roundness`, `…Feather`, `…HighlightContrast` |
| | `grain.{amount,size,roughness}` | 0–100 (0, 25, 50) | `GrainAmount`, `GrainSize`, `GrainFrequency` |
| Geometry | `crop.{top,left,bottom,right}` | 0–1 normalized (0,0,1,1) | `CropTop`, `CropLeft`, `CropBottom`, `CropRight` |
| | `crop.angle` | −45…+45° (0) | `CropAngle` |
| | `orientation.{rotate90,flipH,flipV}` | 0/90/180/270, bool | `Orientation` (EXIF) |
| Meta | `schemaVersion`, `engineVersion` | `1`, `"lumen-1"` | — |

**Color grading luminance** is −100…+100 in the Lightroom UI [S], while JarvisArt's dictionary lists 0–100 [C]. Use −100…+100.

### 5.2 `AutoEditResponse` (what Claude returns)
Design choices:
- A **sparse array of `{param, value, reason}`** with `param` as an **enum** of flattened keys. Keys are always valid, unchanged sliders are omitted, and each change carries a one-line rationale for "Explain this edit".
- **Reasoning fields come first** in the schema, so the model writes analysis before numbers. The output order follows schema order, and MonetGPT's plan-then-values pattern relies on this.
- Claude structured outputs **don't enforce `minimum`/`maximum`** (the SDKs strip them and validate client-side) and require `additionalProperties: false` [V]. **Always clamp after parsing** (in the Dart gateway and again in the app; e.g. `json_serializable` models + an explicit range table).

```jsonc
// Spec, not app code. Ranges in comments are enforced client-side.
{
  "type": "object", "additionalProperties": false,
  "required": ["scene", "issues", "intent", "variants"],
  "properties": {
    "scene": { "type": "object", "additionalProperties": false,
      "required": ["subject", "lighting", "timeOfDay", "keyIntent"],
      "properties": {
        "subject":   { "type": "string" },                       // "portrait, outdoor café"
        "lighting":  { "type": "string" },                       // "backlit, overcast, mixed tungsten"
        "timeOfDay": { "enum": ["day","golden_hour","blue_hour","night","indoor","unknown"] },
        "keyIntent": { "enum": ["low_key","normal","high_key"] } // drives exposure target
      } },
    "issues": { "type": "array", "items": { "type": "object", "additionalProperties": false,
      "required": ["issue", "severity"],
      "properties": { "issue": { "type": "string" },
                      "severity": { "enum": ["low","medium","high"] } } } },
    "intent": { "type": "string" },                              // one sentence: target look
    "variants": { "type": "array",                               // 1 (default) or 3 (variations strip)
      "items": { "type": "object", "additionalProperties": false,
        "required": ["label", "adjustments", "targets", "confidence"],
        "properties": {
          "label": { "type": "string" },                         // "Natural", "Warm film", ...
          "presetAtoms": { "type": "array", "items": { "type": "object", "additionalProperties": false,
              "required": ["atom", "amount"],
              "properties": { "atom": { "enum": ["warm","cool","bright_airy","moody","punchy","soft_matte",
                                                 "cinematic_teal_orange","film_faded","golden_hour",
                                                 "sky_pop","vibrant","muted","bw_classic"] },
                              "amount": { "type": "number" } } } },   // 0..2
          "adjustments": { "type": "array", "items": { "type": "object", "additionalProperties": false,
              "required": ["param", "value", "reason"],
              "properties": {
                "param":  { "enum": ["exposure","contrast","highlights","shadows","whites","blacks",
                                     "temp","tint","vibrance","saturation","texture","clarity","dehaze",
                                     "hsl.red.hue","hsl.red.sat","hsl.red.lum", "...8 bands x 3...",
                                     "curve.parametric.shadows","curve.parametric.darks",
                                     "curve.parametric.lights","curve.parametric.highlights",
                                     "grade.shadows.hue","grade.shadows.sat","grade.midtones.hue", "...",
                                     "grade.blending","grade.balance",
                                     "vignette.amount","vignette.midpoint","grain.amount",
                                     "sharpen.amount","noise.luminance"] },
                "value":  { "type": "number" },                  // absolute (initial) or delta (refine)
                "reason": { "type": "string" } } } },            // <= 12 words, user-facing
          "targets": { "type": "object", "additionalProperties": false,   // semantic targets for the solver
              "required": ["midLStar", "wbStrength", "contrastLevel", "colorLevel"],
              "properties": {
                "midLStar":      { "type": "number" },           // desired median L*, 30..70
                "wbStrength":    { "type": "number" },           // 0 keep cast .. 1 fully neutral
                "contrastLevel": { "enum": ["low","medium","high"] },
                "colorLevel":    { "enum": ["muted","natural","vivid"] } } },
          "confidence": { "type": "number" } } } },              // 0..1
    "done": { "type": "boolean" }                                // verify rounds: true = no change needed
  }
}
```

Request-side fields (not part of the model's output): `mode: "initial" | "refine"`. In refine mode, `value` means a **delta** from the current state.

---

## 6. Classical auto-tone: concrete formulas for the offline `local` engine

### 6.0 How Lightroom and Photoshop "Auto" work (conceptually)
- **Lightroom / ACR Auto (since Dec 2017, LR Classic 7.1):** an Adobe Sensei **neural network trained on tens of thousands of professionally edited photos** predicts **Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Vibrance and Saturation** [S: Adobe blog, PetaPixel]. White balance has a separate "Auto" WB. Internals are unpublished [U]. The pre-2017 Auto Tone was histogram-driven [S]. Lumen's `local` engine reproduces that older statistical approach. `vision` and `learned` play the role of the newer one.
- **Photoshop Auto Color Correction Options** [S] offer three algorithms, each with shadow/highlight **clip %** (commonly 0.1%) and an optional **"Snap Neutral Midtones"** (per-channel gamma that makes near-neutral midtones gray):
  - **Enhance Monochromatic Contrast** (= Auto Contrast): the same clip on all channels, which keeps any cast.
  - **Enhance Per Channel Contrast** (= Auto Tone/Levels): each channel stretched separately, which removes casts.
  - **Find Dark & Light Colors** (= Auto Color).
- **ImageMagick `-auto-gamma`:** γ = ln(mean)/ln(0.5), which maps the mean to 0.5 [V source].
- **darktable color calibration** illuminant detection [V]:
  - gray-world (average color = illuminant)
  - "(AI) detect from edges" (gray-edge: average gradient color)
  - "detect from surfaces" (average weighted toward sharp, color-correlated areas)

### 6.1 Preliminaries
- **Proxy:** downscale to **512 px long edge** with an area filter, in linear light. Run it in a background `Isolate` (CPU) or on the GPU pipeline.
- sRGB decode: `lin(c) = c ≤ 0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4`. Encode `enc(c)` is the inverse.
- **Luminance** (linear): `Y = 0.2126R + 0.7152G + 0.0722B`. **Display luma** `v = enc(Y)` ∈ [0,1]. **L\*** = `116·f(Y) − 16`, where `f(t) = t^(1/3)` if `t > (6/29)³`, else `t/(3·(6/29)²) + 4/29`.
- **Histogram:** 1024 bins of `v`. Percentile `P_q` by linear interpolation in the CDF. All percentiles are on the current *rendered* proxy, re-measured after each stage.
- **Pixel masks:** `clipped = max(enc R,G,B) ≥ 0.995`. `dark = Y < 0.002`. `valid = !clipped && !dark`.
- **Stage order** (same as MonetGPT and RetouchLLM coarse-to-fine): **WB → Exposure → Whites → Blacks → Highlights → Shadows → Contrast → Vibrance/Saturation → Dehaze → (re-check Whites/Blacks)**.

### 6.2 Reference slider model + "solve-on-proxy"
The closed-form formulas below assume this **reference rendering model**. If Lumen's GPU render engine implements a slider differently (for example Lightroom-like adaptive Whites), keep the formula as the *initial guess* and refine with the engine-agnostic solver:

```
solve(slider, measure, target, tol):
  s0 = closedFormGuess; s1 = s0 ± 10
  repeat ≤ 6: render proxy with s, m = measure(proxy)
              secant step on (s, m − target); bisection fallback if non-monotone
  stop when |m − target| < tol
```
This is about 6 proxy renders × about 10 stages, which should be well under a frame budget on the GPU [H, measure]. It makes the auto engine **self-calibrating** whenever slider implementations change.

Reference models [H]:
- **Exposure:** linear RGB × 2^EV.
- **Whites w:** if w > 0, input white point `W_in = 1 − 0.25·w/100` is stretched to 1. If w < 0, output white is compressed to `1 + 0.25·w/100`. Applied on `v` with a smooth shoulder.
- **Blacks b:** if b < 0, input black point `B_in = 0.25·(−b)/100` is crushed to 0. If b > 0, output black is lifted to `0.25·b/100`.
- **Temp t / Tint τ** (relative, per-channel gains in linear light):
  - `R·2^(+κt·t/200)`, `B·2^(−κt·t/200)`
  - `G·2^(−κg·τ/100)`, with κt = 1.0 and κg = 0.5. So ±100 temp equals ±1 stop of R/B ratio, and +τ is magenta.

### 6.3 White balance (temp, tint)
1. **Illuminant estimates** over `valid` pixels in linear RGB. Also exclude highly saturated pixels (HSV S > 0.6), because they bias every method.
   - Gray-world: `e_c = mean(I_c)`
   - White-patch (robust max): `e_c = P99.5(I_c)`
   - **Shades-of-Gray, p = 6:** `e_c = (mean(I_c^p))^(1/p)` (Finlayson & Trezzi 2004; p ≈ 6 reported best [S])
   - **Gray-Edge, n = 1, p = 6, σ = 1:** `e_c = (mean(|∇(G_σ ∗ I_c)|^p))^(1/p)` (van de Weijer et al. 2007 [S])
   - **Combined (recommended):** `e = normalize(sqrt(e_SoG · e_GE))` channel-wise, so `e_G = 1`.
2. **Cast metrics:** `a = log2(e_R / e_B)` (> 0 means warm cast), `m = log2(e_G / sqrt(e_R·e_B))` (> 0 means green cast).
3. **Full neutralization** under the reference model: `t* = −100·a/κt`, `τ* = +100·m/κg`.
4. **Confidence:** `c = clamp(1 − angle(e_SoG, e_GE)/5°, 0, 1)` [H]. The two methods disagreeing means a weird scene.
5. **Strength s:** 0.7 by default [H]. Lower it to 0.35 when the cast is probably intentional: `a > 0.35` and (EXIF time near sunset, *or* low key, *or* Claude's `scene.timeOfDay ∈ {golden_hour, blue_hour, night, indoor tungsten}`). In `vision` mode, use Claude's `targets.wbStrength`.
6. **Final:** `temp = clamp(s·c·t*, −40, 40)`, `tint = clamp(s·c·τ*, −25, 25)` [H].
7. **Kelvin display** (true RAW only, later):
   - convert `e` linear-sRGB → XYZ (D65 matrix) → xy
   - McCamy: `n = (x − 0.3320)/(0.1858 − y)`, `CCT = 449n³ + 3525n² + 6823.3n + 5520.33` (valid ~2000–12500 K) [S]
   - tint ≈ Duv from the Planckian locus [S]

   For JPEGs the camera WB is already baked in, so stay relative.

### 6.4 Exposure (EV)
1. **Log-average luminance** (trimmed to the P1–P99 range of Y): `L_avg = exp(mean(ln(Y + 1e−4)))`.
2. **Scene-adaptive key** (Reinhard 2002 auto-key, as commonly cited [S]; verify the exponent against the paper before shipping):
   `a_key = 0.18 · 4^((2·log2 L_avg − log2 L_min − log2 L_max) / (log2 L_max − log2 L_min))`, with `L_min = P1(Y)` and `L_max = P99(Y)`. Clamp `a_key ∈ [0.09, 0.36]`.
   High-key scenes (snow, white studio) stay bright and low-key scenes stay dark. In `vision` mode, replace it with Claude's `targets.midLStar` (convert L\* → Y).
3. `EV* = log2(a_key / L_avg)`. **Damped:** `EV = clamp(0.75·EV*, −1.5, +2.0)` [H]. There's more headroom for brightening, since under-exposure is the common failure.
4. **Highlight guard:** let `f(EV)` be the fraction of pixels with `max(R,G,B)·2^EV ≥ 1`. If `f(EV) > 0.005` and `f(EV) > 2·f(0)`, bisect EV down until satisfied, but not below `EV*/2`. Highlights recovery (6.6) handles the rest.
5. **Night guard:** if EXIF `ExposureTime ≥ 1/15 s` and `ISO ≥ 1600`, or `L_avg < 0.02`, cap at `EV ≤ +1.0` [H].
6. Lightroom habit worth copying: when `EV > +0.7`, pre-add `highlights −= 15·EV` [H].

### 6.5 Whites and Blacks (levels with clip targets)
Measure after exposure. `P_hi = P99.5(enc(max(R,G,B)))` (uses max channel so no channel clips). `P_lo = P0.5(v)`. Targets: `T_hi = 0.96`, `T_lo = 0.025` [H].
- **Whites:** `w* = P_hi < T_hi ? 400·(1 − P_hi/T_hi) : 400·(T_hi/P_hi − 1)`, then `w = clamp(w*, −40, +50)`.
  Example: `P_hi = 0.85` → w ≈ +46. Already clipped (`P_hi = 1`) → w ≈ −17.
- **Blacks:**
  - `P_lo > T_lo` (washed out): `b* = −400·(P_lo − T_lo)/(1 − T_lo)`
  - otherwise, lift only if crushed: `crush = frac(v < 0.01)`, `b* = crush > 0.02 ? +min(20, 400·(crush − 0.02)) : 0`
  - then `b = clamp(b*, −40, +20)`
  - Example: `P_lo = 0.10` → b ≈ −31.
- A Photoshop-style per-channel alternative ("Auto Levels"): compute per-channel P0.1/P99.9 and write the per-channel stretch into `curve.points.red/green/blue`. Use it only as an optional "Auto Color" mode, because it fights the WB stage.

### 6.6 Highlights and Shadows
Zone stats on `v` after levels:
- `hiMean = mean(v | v ≥ P90)`, `hiClip = frac(enc(max RGB) ≥ 0.99)`
- `loMean = mean(v | v ≤ P10)`, `loCrush = frac(v ≤ 0.02)`

Formulas [H]:
- `highlights = −clamp(300·max(0, hiMean − 0.82) + 1500·hiClip, 0, 70)`
  e.g. hiMean 0.92 with 2% clipped → −60
- `shadows = +clamp(250·max(0, 0.14 − loMean) + 500·max(0, loCrush − 0.02), 0, 60)`
  e.g. loMean 0.05 with 6% crushed → +42
- **Low-key guard:** if `a_key < 0.10` or `scene.keyIntent = low_key` → `shadows ×= 0.5`.

### 6.7 Contrast
Measure after all of the above: `σ = std(L*)` over `valid` pixels. Target `σ_t = 20` L\* units [H, calibrate on the eval set; style-dependent]. Then `contrast = clamp(150·(σ_t − σ)/σ_t, −20, +40)` [H]. The negative side is capped tighter, because high contrast is often deliberate. Style offsets: Punchy σ_t +4, Soft/Matte σ_t −4.

### 6.8 Vibrance and Saturation
Work in CIELAB (D65) on pixels with `15 < L* < 90`. `C* = sqrt(a*² + b*²)`.
- **Skin candidates** (crude [H]): `h_ab ∈ [20°, 75°]`, `C* ∈ [10, 45]`, `L* ∈ [30, 85]` → `skinShare`.
- `C̄` = mean C\* over non-skin pixels. `HS` = frac(C\* > 60).
- `vibrance = clamp(120·(C_t − C̄)/C_t, −25, +35)` with `C_t = 28` [H]. If `HS > 0.15`, `vibrance = min(vibrance, 5)`.
- `saturation = clamp(0.25·vibrance, −10, +8)`. Pros lean on vibrance, not saturation.
- If `skinShare > 0.12`, `vibrance = min(vibrance, 20)` and `saturation = min(saturation, 3)`.

### 6.9 Dehaze
Dark channel (He, Sun & Tang, 2009 [S]): `D(x) = min over a 15×15 patch of min_c enc(I_c)` on the 512 px proxy. `meanD` = mean of D over pixels with `v < 0.9` (excludes sky and specular highlights, a known failure case). If `σ < σ_t`: `dehaze = clamp(250·(meanD − 0.12), 0, 30)`, else 0 [H]. MonetGPT's dehazer is adapted from a BSD-2 implementation (Single-Image-Dehazing-Python) [V], so that's a license-clean reference.

### 6.10 HSL nudges (off by default in `local`; `vision` usually does better)
Use HSV hue bands with MonetGPT's centers (6.2 / 2.2). All values below are [H]:
- **Pale sky:** blue-band share > 8%, mean v > 0.55 and mean S < 0.35 → `hsl.blue.sat +10`, `hsl.blue.lum −8`
- **Neon foliage:** green-band mean S > 0.55 → `hsl.green.sat −10`
- **Hot skin:** orange-band share > 10% and mean S > 0.5 → `hsl.orange.sat −8`

### 6.11 Auto-straighten (Upright "Level" equivalent)
1. Canny edges on a 1024 px proxy, then probabilistic Hough (`opencv_dart`, Apache-2.0 [V pub.dev], via FFI; or a small custom Dart implementation).
2. Keep segments longer than 5% of the diagonal that lie within ±12° of horizontal or vertical. Deviation `d_i` = angle − 0° (or − 90°). Weight by length, and halve the weight of verticals, which suffer from keystone.
3. `d` = weighted median. **Confidence** = weight share within ±0.75° of `d`.
4. Apply `crop.angle = −d` only if confidence > 0.35 and `0.3° ≤ |d| ≤ 10°`. Auto-crop to the largest inscribed rectangle [H].

### 6.12 Constants summary (all [H]; tune with the eval harness)

| Constant | Value | Constant | Value |
|---|---|---|---|
| proxy size | 512 px | WB strength default / intentional cast | 0.7 / 0.35 |
| EV damping, clamp | 0.75, [−1.5, +2.0] | temp / tint clamp | ±40 / ±25 |
| white / black targets | 0.96 / 0.025 | whites / blacks clamp | [−40, 50] / [−40, 20] |
| clip guard | 0.5% pixels | highlights / shadows max | −70 / +60 |
| σ(L\*) target | 20 | contrast clamp | [−20, +40] |
| C\* target | 28 | vibrance / saturation clamp | [−25, 35] / [−10, 8] |
| dark-channel threshold | 0.12 | dehaze max | 30 |

**Styles in `local` mode** shift targets instead of adding filters. For example:
- **Bright & Airy:** key ×1.3, T_lo +0.03, σ_t −3, C_t −2
- **Moody:** key ×0.7, σ_t +3, C_t −6, WB strength 0.4
- **Vibrant:** C_t +8, σ_t +3

---

## 7. Instruction-based editing ("make it moodier", "warmer sunset")

### 7.1 Pipeline
1. **Parse** (Claude, or the offline lexicon). Classify the instruction as:
   - global vs local ("brighten the face" means masks, which is v2)
   - absolute ("shadows to 40", "+0.5 exposure") vs relative ("a bit warmer")
   - style intent vs technical fix
2. **Map to deltas** relative to the *current* state: `Δ = Σ_k amount_k · atom_k` (style atoms, 7.3) + explicit per-slider deltas. Claude may do both; the atoms keep magnitudes calibrated.
3. **Respect user locks:** never touch sliders the user set manually in this session unless the instruction names them.
4. **Apply, validate and guard** as in section 4. Optionally run **one verify round**: "Image 1 (before), Image 2 (after): does Image 2 satisfy '<instruction>' without new problems? If not, return delta corrections." RetouchIQ-style: state 2–3 checkable criteria first.
5. **Undoable as one history step**, labeled with the instruction text.

### 7.2 Intensity lexicon (multiplier on the atom or delta) [H]

| Phrasing | × | MonetGPT legend equivalent |
|---|---|---|
| "a touch", "a hint", "tiny bit" | 0.25 | Very Slight (1–12) |
| "slightly", "a bit", "a little" | 0.5 | Slight–Mild (13–36) |
| (no modifier), "more", "noticeably" | 1.0 | Moderate–Noticeable (37–60) |
| "much", "a lot", "really", "very" | 1.75 | Significant (61–72) |
| "way", "extremely", "dramatically", "super" | 2.5 (clamped) | Very Significant+ (73–100) |
| "less X" / "not so X" | −0.5…−1.0 of X, **never past the pre-instruction baseline** | — |

**Per-instruction caps** (unless the user gives explicit numbers): exposure ±1.0 EV, temp ±30, any other slider ±40.

### 7.3 Style atoms (Δ at amount 1.0; our proposals [H], to be tuned by a photographer)

| Atom | Typical phrasing | Δ vector |
|---|---|---|
| `warm` | warmer, cozier | temp +15, tint +3, hsl.orange.sat +5 |
| `cool` | cooler, colder, icy | temp −15, tint −2, hsl.blue.sat +5 |
| `bright_airy` | brighter, airy, light & bright | exposure +0.4, contrast −10, highlights −20, shadows +25, whites +10, blacks +10, vibrance +5, hsl.orange.lum +5 |
| `moody` | moodier, darker, dramatic | exposure −0.3, highlights −25, shadows −5, blacks −10, vibrance −15, saturation −5, temp −5, vignette.amount −15, grade.shadows {hue 215, sat 10} |
| `punchy` | more contrast, pop, crisp | contrast +20, whites +8, blacks −8, clarity +8, vibrance +10 |
| `soft_matte` | softer, flatter, matte | contrast −15, highlights −15, shadows +15, clarity −10, curve.points.rgb lift black to (0, 18) |
| `cinematic_teal_orange` | cinematic, movie look | contrast +10, blacks +6, grade.shadows {hue 200, sat 15}, grade.highlights {hue 40, sat 12}, hsl.blue.hue −10, hsl.orange.sat +5, vibrance −5, vignette.amount −10 |
| `film_faded` | film, vintage, retro, faded | curve.points.rgb [(0,20),(64,60),(192,200),(255,245)], contrast −10, saturation −10, grade.highlights {hue 45, sat 10}, grain.amount 20, vignette.amount −8 |
| `golden_hour` | golden, sunset warmth | temp +20, tint +5, grade.highlights {hue 40, sat 15}, hsl.orange.sat +10, hsl.yellow.sat +5, highlights −10 |
| `sky_pop` | make the sky pop, bluer sky | hsl.blue.sat +15, hsl.blue.lum −15, hsl.aqua.sat +8, highlights −15, dehaze +8 (global proxy for a sky mask) |
| `vibrant` | more colorful, vivid | vibrance +25, saturation +5, clarity +5 |
| `muted` | muted, desaturated, subtle color | vibrance −25, saturation −10 |
| `bw_classic` | black and white, monochrome | treatment bw, contrast +15, bwMix.blue −20, bwMix.orange +10 |

**Composition rules:**
- Sum atoms, then explicit deltas, then clamp.
- Resolve conflicts ("brighter but moodier") in favor of the *later* clause in offline mode. Claude resolves them semantically in `vision` mode.
- **Offline instruction fallback:** a regex/keyword lexicon maps phrases to atoms and multipliers. This is deterministic, free, and fine for the most common 80% of short commands [H].

### 7.4 Local instructions (v2)
Follow JarvisArt's representation: `{maskType: subject|sky|person|background|radial|linear, invert, feather, adjustments: {exposure, contrast, …}}`.
- Masks come from on-device segmentation (ONNX/TFLite). Check each model's license; MediaPipe and SAM-family models are Apache-2.0 [S].
- Claude chooses mask *type* and parameters only. Never ask it for pixel coordinates beyond a coarse box.

---

## 8. Prompt-engineering guidance for Claude (vision → JSON sliders)

### 8.1 Request construction

| Practice | Why / source |
|---|---|
| **Image first, then text** | Claude docs: works best when images come before text [V] |
| **Send a 1024 px long-edge sRGB JPEG (q≈90)**. Cost is `⌈w/28⌉·⌈h/28⌉` visual tokens: 1024×683 ≈ 925 tokens, 1024² ≈ 1369. Claude 4.7+ models accept up to 2576 px (4784 tokens); others downscale above 1568 px [V] | Tone and color judgments don't need more. MonetGPT used ≤1280 px [V]. Avoid heavy compression, since artifacts read as noise [V] |
| **Optional 2nd image: a 512×512 crop at 100%** of the subject or center, labeled "Image 2: 100% crop" | Lets Claude judge noise and sharpness and set texture/sharpen/NR. Label multiple images "Image 1:", "Image 2:" [V] |
| **Convert Display P3 / HEIC to sRGB before encoding** | Avoid misjudged saturation [H] |
| **Send EXIF as text** (camera, lens, ISO, shutter, aperture, focal length, local time, flash) | **Claude does not read image metadata** [V]. ISO and time of day steer noise and WB decisions |
| **Send a compact stats block** (about 300 tokens): luma percentiles P0.5/P5/P50/P95/P99.5, clip % and crush %, L_avg, WB estimate (a, m and confidence), mean C\*, skin share, haze score, the 8-band HSL share and mean S | Grounding is how PhotoArtAgent (histograms) and RetouchLLM (color stats) work [V]. VLMs misjudge exact exposure from pixels alone |
| **Send `params_L`, the local engine's result, as "baseline (technically neutral, no style)"** | Anchors magnitudes and cuts overshoot. Tell Claude it may deviate for style and scene reasons |
| **Put the style and user instruction last** | Stable prefix first means better caching |

### 8.2 System prompt skeleton (about 3–5k tokens: stable, versioned, cached)
1. **Role:** "You are a senior photo retoucher. You edit with Lumen's develop sliders only; you never describe pixel edits you cannot express as sliders."
2. **Slider dictionary:** every `param` enum key with range, unit and *Lumen-calibrated* semantics, written by us. For example: "exposure +1.0 = one stop brighter (doubles linear light)"; "whites moves the white point; prefer it over exposure to fix a dull top end"; "vibrance boosts low-saturation colors and protects skin; prefer it over saturation".
3. **Workflow and order:** WB → exposure → whites/blacks → highlights/shadows → contrast → presence → color (vibrance, HSL) → grading → detail → effects. Fix technical problems before applying style (MonetGPT stages, RetouchLLM coarse-to-fine).
4. **Magnitude calibration:**
   - the intensity legend (2.2)
   - "Most professional edits stay within exposure ±1 EV and ±40 on other sliders"
   - "Prefer a few decisive changes over many tiny ones"
   - "Omit sliders you would leave at 0"
5. **Taste rules:**
   - protect skin tones (orange/red hue shifts within ±5)
   - don't neutralize intentional ambient color (sunset, candlelight, stage)
   - keep highlights from clipping on faces and skies
   - avoid "HDR look" combos (shadows > +60 together with highlights < −60 and clarity > +30) unless asked
6. **Style definitions:** one paragraph per Lumen style (Natural, Vibrant, Moody, Cinematic, Film, Golden Hour, Clean & Bright, B&W, Portrait Soft), in MonetGPT's style-instruction format, plus which atoms each style typically uses.
7. **Output contract:** fill `scene`, `issues` and `intent` *before* `variants`. Each `reason` is ≤12 words and user-facing. Use "Adjustment / Issue / Solution" thinking internally.
8. **Refine mode contract:** in refine mode, values are **deltas** from the current state. Return `done: true` with an empty adjustment list when no change is needed ("no change" is always an allowed answer, as in RetouchLLM).

### 8.3 API settings [V skill docs, cached 2026-09-25]

| Setting | Recommendation |
|---|---|
| **Model tier** | Make it configurable. Opus 5.5 (`claude-opus-5-5`, $4/$20 per MTok) for best taste. Sonnet 5.5 (`claude-sonnet-5-5`, $2/$10) as the likely price/quality default for auto-edit. Haiku 4.5 (`claude-haiku-4-5`, $1/$5, standard-res tier) for bulk. **Decide with the eval set (section 9), not by assumption** |
| **JSON** | Use structured outputs, `output_config: {format: {type: "json_schema", …}}` (there is no official Anthropic Dart SDK, so the Dart gateway calls `POST /v1/messages` over raw HTTP and validates the JSON itself). Forced `tool_choice` returns **400** on Opus 5.5 and Sonnet 5.5, so don't use a forced tool for JSON. No numeric `minimum`/`maximum` support: **clamp client-side**. A new schema has a one-time compile latency and is then cached for 24 h |
| **Thinking / effort** | Opus 5.5 thinking can't be disabled. Its default effort is `medium`; try `low` for auto-edit. Sonnet 5.5 defaults to `high`; try `low`/`medium`. Measure quality vs cost per route |
| **Sampling** | `temperature` is rejected on current models. Get diversity via the 3-variant request, and reproducibility via result caching |
| **Prompt caching** | `cache_control` on the system prompt (dictionary, rules, styles). Keep it byte-stable (no timestamps). Model-specific minimum cacheable length is 512–4096 tokens, so make sure the prefix exceeds it |
| **Batch API** | 50% cheaper for "auto-edit 300 imported photos" when the user doesn't need results instantly |
| **Refusals** | Check `stop_reason` before parsing. On `refusal`, `max_tokens` or a parse failure, fall back to `local` |
| **Key handling** | Calls go through the Dart backend gateway, and the API key never ships in the app binary |

### 8.4 The verify (reflection) round
Send:
- "Image 1: original"
- "Image 2: current edit"
- the current slider JSON
- a **stats diff** (before/after clip %, median L\*, WB cast, C\*)
- for instructions, the instruction text

Ask Claude to:
1. state 2–3 criteria this photo must meet (RetouchIQ)
2. grade Image 2 against them
3. return **delta** corrections or `done: true`

**Trigger only when:**
- the validator found a violation the solver can't fix (for example skin hue drift), or
- the photo is a "hero" or Pro-mode image, or
- `confidence < 0.6`

Cap at **2 rounds** (RetouchLLM uses up to 10, which is too expensive for SaaS).

### 8.5 Failure modes and mitigations

| Failure | Mitigation |
|---|---|
| Overshoot (huge contrast, saturation, clarity) | Intensity legend + baseline anchor + per-slider damping table (start from MonetGPT's factors, then fit ours) + clamps + guards |
| Neutralizes intentional color (sunsets turned gray) | `scene.timeOfDay` + `targets.wbStrength`, plus an explicit taste rule |
| "Looks right in words, wrong in pixels" | Stats in the prompt + verify round with the rendered image (JarvisEvo's interleaved-image insight) |
| Invalid keys or out-of-range values | Enum `param` + structured outputs + Dart-side clamp |
| Inconsistent results across a shoot | Contact-sheet targets + local solver per photo (section 4) |
| Numeric imprecision on technical sliders | Solver overrides whites/blacks/exposure only when guards fail (mode C) |
| Geometry hallucination | Straighten and crop are classical only |

---

## 9. How to evaluate (needed before choosing the model tier or tuning constants)
- **Golden set:** 150–300 *licensed* photos across portraits, landscape, food, product, night and indoor mixed light, each with 1–2 **commissioned pro edits stored as slider values**. That gives us our own legal FiveK-style data.
- **Metrics:**
  - ΔE2000 and PSNR vs the pro edit
  - slider-space error vs the pro edit (JarvisArt's operation-accuracy idea)
  - technical guards: clip %, crush %, neutral-patch ΔE
  - **pairwise human preference** (blind A/B)
  - in-product: **acceptance rate** (share of AI sliders the user keeps) and **revert rate**
- **Arms to compare:** `local` alone; Claude Haiku/Sonnet/Opus × effort {low, medium} × mode {A raw, B targets+solver, C mixed} × {no verify, gated verify}.
- **Tune with this harness:** the damping table, section 6 constants, and atom vectors.

---

## 10. Open questions and things not verified
- Exact Lightroom slider math and HSL band centers are proprietary. Our renderer defines its own semantics, and calibration happens through the solver and eval [U].
- The Reinhard auto-key exponent form is from memory of the 2002 JGT paper; confirm it before shipping [S].
- Several repos' param counts, ONNX availability and PSNR (LUTwithBGrid, CLUT-Net, ICELUT, IAT on FiveK) are marked [U].
- Whether Unsplash Lite's "internal business purposes" covers a model shipped inside a SaaS product, and whether Claude outputs may be used to train Lumen's Phase-2 model, both need legal review [U].
- Patent freedom-to-operate for auto-tone and auto-WB methods was **not** checked [U].
- Claude per-call latency for this payload wasn't measured. Benchmark it in the spike [U].

---

## Sources
1. JarvisArt paper: https://arxiv.org/html/2506.17612v1 · NeurIPS: https://proceedings.neurips.cc/paper_files/paper/2025/hash/4ac4365b98bc242acd5ab974a05c68a8-Abstract-Conference.html
2. JarvisArt repo, LICENSE and system prompt: https://github.com/LYL1015/JarvisArt (`LICENSE`, `data_scripts/format_conversion/system_prompt.py`, `data_scripts/image_pairs_xmp_generation/prompt_en.py`) · weights: https://huggingface.co/JarvisArt/JarvisArt-1208
3. JarvisEvo: https://arxiv.org/html/2511.23002v1 · license: https://github.com/LYL1015/JarvisEvo
4. MonetGPT paper: https://arxiv.org/html/2505.06176 · repo and configs: https://github.com/niladridutt/monetgpt (`configs/inference_config.yaml`, `configs/hsl.yaml`, `dataset/constants.py`, `inference/core.py`, `config.py`) · weights: https://huggingface.co/niladridutt/monetGPT
5. PhotoArtAgent: https://arxiv.org/html/2505.23130v1
6. RetouchLLM: https://arxiv.org/html/2510.08054v2
7. RetouchIQ: https://arxiv.org/html/2602.17558 · https://research.adobe.com/news/teaching-an-ai-agent-to-retouch-photos-retouchiq-at-cvpr-2026/
8. PerTouch: https://arxiv.org/html/2511.12998 · https://github.com/Auroral703/PerTouch
9. PhotoAgent: https://arxiv.org/html/2602.22809v1 · https://github.com/mdyao/PhotoAgent
10. VeraRetouch: https://www.emergentmind.com/papers/2604.27375 · https://github.com/OpenVeraTeam/VeraRetouch
11. SVDLUT comparison table (FiveK params/PSNR): https://arxiv.org/html/2508.16121 · LoR-LUT: https://arxiv.org/html/2602.22607
12. Image-Adaptive-3DLUT: https://github.com/HuiZeng/Image-Adaptive-3DLUT · AdaInt: https://github.com/ImCharlesY/AdaInt · SepLUT: https://github.com/ImCharlesY/SepLUT · LUTwithBGrid: https://github.com/WontaeaeKim/LUTwithBGrid · CLUT-Net: https://github.com/Xian-Bei/CLUT-Net · ICELUT: https://github.com/Stephen0808/ICELUT
13. CSRNet: https://github.com/hejingwenhejingwen/CSRNet · NILUT: https://github.com/mv-lab/nilut · HDRNet: https://github.com/google/hdrnet
14. DeepLPF: https://github.com/sjmoran/deeplpf-image-enhancement · CURL: https://github.com/sjmoran/curl-image-enhancement · NamedCurves: https://github.com/davidserra9/namedcurves · Exposure: https://github.com/yuanming-hu/exposure
15. IAT: https://github.com/cuiziteng/Illumination-Adaptive-Transformer · Zero-DCE: https://github.com/Li-Chongyi/Zero-DCE · Zero-DCE++: https://github.com/Li-Chongyi/Zero-DCE_extension · SCI: https://github.com/vis-opt-group/SCI · NeuralPreset: https://github.com/ZHKKKe/NeuralPreset
16. PINTO model zoo (ONNX conversions: 076 Deep WB, 152 DeepLPF, 216/243 Zero-DCE, 286 SCI, 315 IAT): https://github.com/PINTO0309/PINTO_model_zoo
17. Afifi repos (licenses): https://github.com/mahmoudnafifi/Deep_White_Balance · https://github.com/mahmoudnafifi/WB_sRGB · https://github.com/mahmoudnafifi/Exposure_Correction · https://github.com/mahmoudnafifi/C5 · FFCC: https://github.com/google/ffcc · FC4: https://github.com/yuanming-hu/fc4
18. MIT-Adobe FiveK and license: https://data.csail.mit.edu/graphics/fivek/ · https://data.csail.mit.edu/graphics/fivek/legal/LicenseAdobe.txt · https://data.csail.mit.edu/graphics/fivek/legal/LicenseAdobeMIT.txt
19. PPR10K agreement: https://github.com/csjliang/PPR10K
20. Unsplash datasets terms: https://github.com/unsplash/datasets · https://github.com/unsplash/datasets/blob/master/TERMS.md
21. Lightroom Auto (Sensei, Dec 2017): https://blog.adobe.com/en/publish/2017/12/12/announcing-december-update-lightroom · https://petapixel.com/2017/12/12/lightroom-cc-ecosystem-gets-better-ai-auto-dec-2017-update/
22. Photoshop auto-correction algorithms: https://astropix.com/books/PFA/BOOK/F_PS/F02/F020507/F020507.HTM · https://photofocus.com/software/removing-color-cast-with-auto-curves-in-photoshop/
23. ImageMagick auto-gamma source: https://imagemagick.org/api/MagickCore/enhance_8c_source.html
24. darktable color calibration (gray-world / edges / surfaces): https://docs.darktable.org/usermanual/4.6/en/module-reference/processing-modules/color-calibration/
25. Reinhard 2002 parameter estimation (JGT 7(1):45–52): https://ftp.math.utah.edu/pub/tex/bib/idx/jgraphtools/7/1/45-52.html
26. ExifTool XMP crs tag names: https://exiftool.org/TagNames/XMP.html
27. Claude vision docs (formats, limits, token formula, metadata not read, image ordering): https://platform.claude.com/docs/en/build-with-claude/vision
28. ONNX Runtime docs: https://onnxruntime.ai/docs/ · Flutter plugins: https://pub.dev/packages/flutter_onnxruntime · https://pub.dev/packages/onnxruntime · OpenCV for Dart: https://pub.dev/packages/opencv_dart
29. Deep Preset (reference-photo → 69 Lightroom settings): https://ar5iv.arxiv.org/html/2007.10701
30. Lightroom & Claude pricing, structured outputs and effort semantics: Anthropic `claude-api` skill reference (cached 2026-09-25); live pricing at https://claude.com/pricing
