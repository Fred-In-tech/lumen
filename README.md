# Lumen: AI photo editor (codename)

**Drop your photos in. AI edits them like a pro retoucher. Every edit stays a slider you can tweak.**

Lumen is a Lightroom-style photo editor for **macOS, Windows, iOS and Android** (plus a web demo), built with Flutter from one codebase. Import photos and the AI develops them automatically. The edit is never baked into the pixels. Every AI decision is a visible slider value with a one-line reason, so you can adjust, undo or keep editing by hand.

> "Lumen" is an internal codename (trademark conflict, see `docs/research/04-market.md`). The public name lives in one constant: `packages/lumen_core/lib/src/brand.dart`.

## What it does

| Area | Features |
|---|---|
| **AI** | One-click **Auto** · 9 AI **Styles** (Natural, Vibrant, Moody, Cinematic, Film, Golden Hour, Clean & Bright, B&W, Portrait Soft) previewed on your photo · **Describe an edit** ("warmer and lift the shadows a bit") · **AI amount** 0–150 % · "What I changed" explanations · auto-edit on import · batch auto-edit |
| **Develop** | Light (exposure, contrast, highlights, shadows, whites, blacks) · Color (temp, tint, vibrance, saturation, HSL ×8, B&W mix) · Tone curve (RGB/R/G/B points + parametric) · Color grading wheels · Effects (texture, clarity, dehaze, vignette, grain) · Detail (sharpening, noise reduction) · Crop, straighten, rotate, flip |
| **Portrait retouch** (Evoto-style, on-device) | Face detection with clickable face boxes and Female / Male / Child / Senior tags · group tabs **All / Female / Male / Child / Senior / Individual** · **Auto Retouch** scaled to each face's needs · skin softening that keeps pores, even tone, texture, shine · acne / freckle / mole removal with a click-to-keep-or-remove **spot editor** · 5 wrinkle zones · dark circles, eye bags, eye whites, iris, red veins, **red-eye** · teeth whitening · lip colour and blush · **Skin pen** (manual tuning) · press-and-hold compare per section |
| **Face shape & Liquify** | Face width, V-shape, chin, eye size, nose width, mouth size (per group or person) · Liquify brush: push, reconstruct, pucker, bloat |
| **Background** | Clean backdrop (dust, scuffs, seams, banding), unify lighting ± luminance, stray hairs beyond the figure, on plain studio backdrops |
| **Masks** | Up to 8 Lightroom-style masks: linear, radial and brush (paint/erase), plus **AI masks** (Subject, Background, Face skin, Hair, Clothing) · 12 local sliders per mask · red overlay (`O`) |
| **Remove** | Remove / Heal / Clone brushes (`Q`) · zero-download classical fill (spot heal, wire removal, patch fill) · optional on-device **AI fill** (MI-GAN, 16 MB, downloaded only when you switch it on) · every fix is a non-destructive, hideable step |
| **Shoot workflow** | **Auto** edits colour *and* retouches faces in one undoable step, on import or for a whole selection · Sync re-measures retouch per photo · 6 portrait presets (Natural Retouch, Soft Skin, Clean Headshot, Groom, Kids Gentle, Glam) · **Smart Cull** (blurry, eyes closed, clipped, similar shots → picks/rejects you accept) · **Headshot crop** 4:5 / 1:1 / 2:3 · search every control (`/`) |
| **Workflow** | Library grouped by date · multi-select batch bar · undo/redo saved with the photo · before/after (hold `\`, split wipe, side by side) · histogram · 12 built-in presets + your own · copy/paste/sync settings · keyboard shortcuts |
| **Export** | JPEG (quality) / PNG · original or long edge · metadata kept or removed, **location always stripped** · batch to a folder (desktop) or the share sheet (mobile) |

### How the AI works
- **On-device engine (always on, free, offline):** analyses the photo (histograms, white balance, scene key, haze, skin, chroma) and solves for slider values against the app's own renderer. This is the "Basic auto (offline)" engine.
- **Vision engine (optional):** the app sends a 1024-px preview, with no EXIF or GPS, to the **Lumen AI gateway** (`server/`). The gateway asks Claude (`claude-opus-5-5` by default) for structured slider values and a reason per change. Values are clamped and damped on both the server and the app. On refusal, timeout or no key, the app quietly falls back to the on-device engine.

## Repository layout
```
app/                 Flutter app (package `lumen`), all platforms
  lib/design/        design tokens + theme ("Darkroom editorial", docs/DESIGN.md)
  lib/engine/        GPU render engine: fragment shaders, render graph, scheduler, tiled export
  lib/features/      library, editor, develop panel, AI, presets, crop, export, batch, settings
  lib/ai/ondevice/   on-device AI: LiteRT backend, verified model store, face analyzer, AI masks
  lib/features/{portrait,masks,remove}/  Phase 2 modules
  shaders/           develop / finish / denoise / retouch / mask overlay GLSL
  assets/models/     bundled face models (Apache-2.0, see docs/MODEL_LICENSES.md)
packages/lumen_core/ Pure Dart: edit model, color science, CPU reference renderer, image analysis,
                     local auto-tone engine, instruction lexicon, gateway contract, retouch engine
                     (CPU twin of retouch.frag), inpainting, face-pipeline math, model manifest
server/              Dart (shelf) AI gateway: holds the Anthropic key, calls Claude
docs/                research, PLAN (architecture + Definition of Done), DESIGN, PROGRESS, LICENSES
tool/                verify.sh (quality gate), check_licenses.dart
```

## Prerequisites
- Flutter **3.47+** (Dart 3.13+); `flutter doctor` green for your targets
- macOS/iOS: Xcode 26+ · Android: Android SDK 36 · Windows: Visual Studio 2022 with "Desktop development with C++"

Then run `flutter pub get` at the repo root.

## Run the app
| Platform | Command (from `app/`) |
|---|---|
| macOS | `flutter run -d macos` |
| iOS simulator | `flutter run -d "iPhone 17 Pro"` |
| Android emulator | `flutter run -d emulator-5554` |
| Windows | `flutter run -d windows` (on a Windows PC) |
| Web demo | `flutter run -d chrome` (photos kept in memory only) |

The app works fully **without** the gateway, using the on-device engine. To turn on AI vision, run the gateway.

## Run the AI gateway (optional)
From `server/`:
- No key (health works, vision off): `dart run bin/server.dart`
- With vision: `ANTHROPIC_API_KEY=sk-ant-... dart run bin/server.dart`

Notes:
- The app's default URL is `http://localhost:8080`. The Android emulator uses `http://10.0.2.2:8080`. Change it in **Settings** (gear icon in the library).
- Env vars: `LUMEN_MODEL`, `LUMEN_EFFORT` (default `low`), `PORT`, `LUMEN_GATEWAY_TOKEN` (requires a Bearer token), `LUMEN_RPM`/`LUMEN_BURST`. See `server/README.md`.
- Real-key smoke test: `ANTHROPIC_API_KEY=... dart run tool/smoke_vision.dart`.
- The API key is read only from the environment and never ships in the app.

## Tests and quality gate
- Everything: `bash tool/verify.sh`. That runs format, analyze ×3, core tests with ≥80 % coverage, server tests, app tests, licenses and a secrets scan.
- Core (`packages/lumen_core`): `dart test`. Model, color, renderer, analysis, auto engine.
- Gateway (`server`): `dart test`, with Claude mocked.
- App (`app`): `flutter test`. UI, repositories, GPU shader parity (develop, masks, retouch), export.
- On-device model tests need the dev models in `.dev_models/` (see `docs/MODEL_LICENSES.md`) and the LiteRT host libraries; `tool/verify.sh` sets `TFLITE_LIB_PATH` / `LITERT_LIB_PATH`. Without them those tests skip.
- End-to-end (`app`): `flutter test integration_test -d macos`. Screenshots are copied to `docs/verification/`.

## Architecture notes (scale-later)
- **Non-destructive edits:** a versioned JSON `EditDocument` per photo, patch-based history, presets as sparse patches. `ParamRegistry` is the single source of truth for UI, shaders, presets and the AI schema.
- **Rendering:** one float "uber" develop shader plus low-res auxiliary passes. A CPU reference pipeline in `lumen_core` is parity-tested against the GPU. Export is tiled at full resolution. If shaders can't load, the editor falls back to CPU automatically.
- **Storage:** repository interfaces with a JSON-file implementation, ready for SQLite or cloud sync.
- **Gateway:** auth placeholder, rate limiting, usage metering and a result cache, ready for accounts and Stripe credits (`docs/PLAN.md` §8).
- **Privacy:** only a metadata-free downscaled preview leaves the device, exports strip GPS, and no training on user photos.

## Troubleshooting
- **macOS can't open picked files or reach the gateway:** the sandbox entitlements are set in `macos/Runner/*.entitlements`.
- **HEIC on Windows:** install Microsoft's "HEIF Image Extensions".
- **Android emulator → gateway:** use `http://10.0.2.2:8080`. Cleartext is allowed in debug builds only.
