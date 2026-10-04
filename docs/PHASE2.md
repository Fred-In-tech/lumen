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
| W4 | On-device inference: LiteRT backend, ModelStore (SHA-256, resume, disk guard, LRU), FaceAnalyzer, face cache | 🔨 in progress (runtime + models + contracts ✅ `9c36bb8`) |
| W5 | Retouch core: face regions, skin parser, RetouchMaps, blemish heal, CPU kernel, uniforms | 🔨 in progress |
| W6 | Object removal core: push-pull, Telea, PatchMatch, crop/feather/detail pipeline, heal ops | 🔨 in progress |
| W7a | Portrait module UI: group tabs, Individual, sections, Auto Retouch | ✅ scaffold (`b4a9af2`); face boxes and render wiring pending W4/W5 |
| W7b | Masks module UI + canvas tools (linear/radial/brush, overlay) | 🔨 in progress |
| W7c | Remove tool UI + heal brush | planned after W6 |
| W8 | GPU `retouch.frag` pass mirroring the W5 CPU kernel + render-graph integration | planned after W5 |
| W9 | AI masks (Subject/Person/Background/Face skin) from Selfie Multiclass | planned after W4 |
| W10 | Face reshape (MLS warp field in `develop`), backdrop clean, extras | later |
| P1 | **Privacy hardening before launch:** keep face caches and models out of OS backups. Move `cache/` under one excluded root. iOS: `NSURLIsExcludedFromBackupKey`. Android: `dataExtractionRules` + `fullBackupContent`. macOS: the backup-exclude xattr. Legal review of BIPA for on-device face geometry. | planned |
