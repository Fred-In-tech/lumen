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

## Workstreams (status)
| # | Workstream | Owner | Status |
|---|---|---|---|
| W1 | Masks engine: model, rasterizer, shader + CPU local adjustments, atlases, overlay | render agent | in progress |
| W2 | Research: Evoto teardown (06) | research agent | in progress |
| W3 | Research: portrait-retouch tech + licenses (07) | research agent | in progress |
| W4 | On-device inference module (ONNX/LiteRT, model store, face detection + landmarks, segmentation) | TBD after W3 | planned |
| W5 | Retouch stage in core (skin, blemish, eye bags, teeth, eyes, reshape) | TBD after W3 | planned |
| W6 | Object removal (MI-GAN/LaMa + classical fallback) + heal brush UI | TBD after W3 | planned |
| W7 | UI: Masks panel, Retouch panel (per-face), Remove tool, AI "Retouch" one-click + sync to set | lead | planned |
