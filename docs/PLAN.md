# Lumen: Implementation Plan (v1.0)

> **Status:** approved plan, 2026-10-03. **Owner:** one engineer, executed iteration by iteration (Ralph loop).
> **Inputs:** `docs/IDEAS.md`, `docs/research/01…05`. Where this plan and the research disagree, **this plan wins** (it is the decision record).
> **Brand:** "Lumen" is an internal codename (USPTO conflict, see 04 §4.2). The public name lives in **one constant**: `packages/lumen_core/lib/src/brand.dart` → `kBrand.name`. Package names (`lumen`, `lumen_core`, `lumen_server`) are internal and never shown to users.
> **Completion promise:** "LUMEN APP COMPLETE AND READY FOR TESTING" may only be output when **every item in §9 (Definition of Done)** is checked and its verification command has been run in the same iteration.

---

## 0. Decisions at a glance

| Topic | Decision | One-line why |
|---|---|---|
| Stack | Flutter 3.47.2 / Dart 3.13.2 pub workspace: `app/`, `packages/lumen_core/`, `server/` | Decided. One codebase, five targets |
| State management | **Riverpod 3** (`flutter_riverpod ^3.4.3`), no code generation | DI + test overrides for repositories/providers/gateway in one tool; `Notifier`/`AsyncNotifier` cover editor and async jobs; no `build_runner` to babysit |
| Render hot path | **Not** driven by widget rebuilds: a `RenderScheduler` (plain Dart object owned by the editor notifier) coalesces settings → GPU passes → `ValueNotifier<ui.Image>` | Slider drags at 60 Hz must not rebuild the widget tree |
| Models / JSON | Hand-written immutable classes + `toJson/fromJson` in `lumen_core` (no freezed/json_serializable) | Pure Dart, zero codegen, shared by app and server |
| Settings shape | Sparse **flat scalar map keyed by `ParamId`** + typed curves/geometry/treatment | Same keys for UI, history patches, presets, copy/paste, AI responses, uniform packing |
| Working color space | **Linear sRGB primaries, unclamped float inside the shader** (engine `lumen-1`) | MVP inputs are 8-bit display-referred sRGB; ProPhoto adds matrix surface with no visible gain until RAW (then `lumen-2`) |
| Engine shape | **One "develop" uber shader does every per-pixel op in float in a single pass.** Low-res auxiliary passes (computed once per photo, from the source) feed it. 8-bit textures everywhere; precision-critical aux data packed as 16-bit in two 8-bit channels | Float render targets are **unverified** in Flutter; this design never needs them |
| Storage | **JSON files** under the app-support dir, behind repository interfaces (`CatalogRepository`, `PresetRepository`, `SettingsRepository`). Originals **copied** into the managed library, deduped by SHA-256 | Zero native deps, identical on all 4 platforms, sandbox-safe (no security-scoped bookmarks). Migrate to `sqlite3`/drift behind the same interface past ~5k photos |
| Web | Secondary target: must build; uses `MemoryCatalogRepository` (no persistence) | Keeps the code honest about `dart:io` |
| AI engines | `AutoEditProvider` interface in `lumen_core`: `local` (offline, always), `vision` (gateway → Claude, when available), `learned` (Phase 3 stub) | App fully works offline; vision lights up when the gateway reports a key |
| On-device ML | Interface + model registry designed now; **implementation is Phase 2** (no `flutter_onnxruntime` in the MVP build) | Keeps MVP builds free of min-OS bumps (iOS 16 / macOS 14) and Windows DLL downloads |
| Masks / Remove / Upscale | **Phase 2** (masks first, then Remove, then Upscale). Schema v1 already reserves `masks: []` | See §3.3 effort/risk table |
| Export encoding | `package:image` (pure Dart) in an isolate, tiled GPU render | Only encoder that is identical on all 5 targets; swap behind `ImageEncoder` later |
| Gateway | Dart `shelf` + `shelf_router`, raw HTTP to `POST /v1/messages`, structured outputs, `fallbacks: "default"`, explicit effort | Key never ships in the app |

### 0.1 Verified spike results (Flutter 3.47.2 on this Mac)
1. `ui.FragmentProgram.fromAsset` **works inside plain `flutter test`** (headless `flutter_tester`). An exposure shader (`#include <flutter/runtime_effect.glsl>`, `FlutterFragCoord()`, `uniform sampler2D`, `uniform vec2 uSize`, floats via `setFloat`, `setImageSampler`) drawn via `PictureRecorder` → `toImage` gave **pixel 176 for input 128 at +1 EV**, exactly as computed. ⇒ The shader engine is **TDD'd with numeric pixel-readback tests** (`toByteData(format: rawRgba)`), not only goldens.
2. Shaders are declared under `flutter: shaders:` in `app/pubspec.yaml`.
3. Float intermediates (`toImageSync(targetFormat: TargetPixelFormat.rgbaFloat32)`) exist in the API but are **unverified per backend: do not depend on them.** All design below assumes 8-bit (`rgba8888`) storage.

### 0.2 Spikes still to run (first tasks of their phase; each has a fallback)
| Spike | Pass condition | Fallback if it fails |
|---|---|---|
| S1 local `#include "lib/common.glsl"` in shaders | compiles in `flutter test` and `flutter build macos` | Inline shared functions per shader (generated by `tool/gen_shader_common.dart`) |
| S2 EXIF orientation applied by `instantiateImageCodec` for JPEG | synthetic JPEG with Orientation=6 decodes as portrait | Read orientation via `exif`, set `geometry.baseOrientation`, rotate in shader |
| S3 HEIC decode via engine codec on macOS/iOS/Android | `.heic` fixture decodes | `platform_image_converter` (MIT) → JPEG/PNG bytes; Windows needs Microsoft HEIF extension (clear error message otherwise) |
| S4 `setImageSampler(..., filterQuality: FilterQuality.none)` gives exact texel values for packed textures | packed 16-bit round-trip error 0 at texel centers | Store 8-bit only and accept quantization in aux data (documented quality loss) |
| S5 develop shader compiles and runs on Android emulator (Vulkan + GLES) | `flutter run -d emulator` renders, uv not flipped | Apply `#ifdef IMPELLER_TARGET_OPENGLES` uv flip |

---

## 1. Architecture

### 1.1 System overview
```
┌───────────────────────────── app (Flutter, package lumen) ─────────────────────────────┐
│  UI (Riverpod)  ─►  EditorNotifier ─► RenderScheduler ─► RenderGraph (FragmentPrograms)  │
│     │                 │   ▲                                   │ ui.Image (view)          │
│     │                 │   └── HistoryStack (lumen_core)       └► HistogramService        │
│     │                 ▼                                                                  │
│     │           AutoEditService ──► LocalAutoEditProvider (lumen_core, isolate)          │
│     │                 └───────────► VisionAutoEditProvider ──HTTP──┐                     │
│     ▼                                                              │                     │
│  Repositories (JSON files via path_provider; memory on web)        │                     │
└────────────────────────────────────────────────────────────────────┼─────────────────────┘
                                                                     ▼
┌──────────── server (lumen_server, shelf) ───────────┐   POST /v1/messages (raw HTTP)
│ auth → rate limit → body limit → route → ClaudeClient├──────────► Claude (claude-opus-5-5)
│ shares DTOs + JSON schema + clamp from lumen_core    │
└──────────────────────────────────────────────────────┘
lumen_core (pure Dart): params, settings, history, presets, color math, LUT baking,
uniform packing, CPU reference pipeline, stats, local auto-tone, lexicon, gateway contract.
```

### 1.2 `packages/lumen_core/` (pure Dart, no Flutter, no `dart:io`)
```
packages/lumen_core/
  pubspec.yaml                       # deps: meta, collection; dev: test, lints, coverage
  lib/lumen_core.dart                # public exports
  lib/testing.dart                   # exports synthetic scenes + matchers for app/server tests
  lib/src/brand.dart                 # kBrand {name, tagline, supportUrl}: THE only brand constant
  lib/src/model/
    param_id.dart                    # ParamId registry: id, group, min, max, default, step, unit, xmp, aiEditable, localAllowed
    develop_settings.dart            # immutable; sparse Map<ParamId,double> + curves + geometry + treatment
    tone_curve.dart                  # point curves (master/r/g/b), parametric zones+splits, monotone cubic (Fritsch–Carlson)
    geometry.dart                    # crop rect, angle, rotate90, flipH, flipV, aspect, baseOrientation
    treatment.dart                   # color | bw
    mask.dart                        # LocalMask (Phase 2 use; serialized in v1)
    edit_document.dart               # EditDocument {schemaVersion, engineVersion, assetId, settings, history, snapshots, ai}
    history.dart                     # HistoryEntry, HistoryStack (cursor, coalescing, cap 200)
    preset.dart                      # Preset (sparse), apply(amount)
    builtin_presets.dart             # 12 built-in looks as data
    settings_subset.dart             # SettingsGroup enum for copy/paste/sync; extract/merge
    catalog_entry.dart               # CatalogEntry, CatalogIndex
    exif_summary.dart                # camera, lens, iso, shutter, aperture, focal, capturedAt (no GPS by type)
    migrations.dart                  # schemaVersion migrations (v1 baseline + test harness)
  lib/src/color/
    srgb.dart  luminance.dart  oklab.dart  cielab.dart  white_balance.dart (temp/tint → RGB gains)
  lib/src/render/
    engine_constants.dart            # every [H] constant the shader also hard-codes (mirrored, parity-tested)
    tone_lut.dart                    # bake composite tone LUT + RGB point curves → 1024 entries x 4 rows
    lut_packing.dart                 # 16-bit value ⇄ 2×8-bit (R=hi, G=lo) packing
    uniform_layout.dart              # DevelopUniforms.pack(settings, ctx) → Float32List; index table
    finish_uniforms.dart             # FinishUniforms.pack
    reference_pipeline.dart          # CPU implementation of all point ops (parity + solver)
    rgba_buffer.dart                 # RgbaBuffer (Uint8List w,h) + FloatRgbBuffer
  lib/src/analysis/
    proxy.dart                       # area downscale to N px long edge
    histogram.dart                   # 256-bin R,G,B,luma + clip counts + percentiles
    image_stats.dart                 # §6.1–6.9 stats: percentiles, L_avg, WB estimates, C*, skin share, dark channel, HSL shares
  lib/src/auto/
    auto_edit_provider.dart          # interface + DTOs (AutoEditInput/Outcome, ParamChange, ProviderStatus)
    local_auto_tone.dart             # staged solver WB→EV→W/B→H/S→contrast→vib/sat→dehaze
    ai_style.dart                    # 9 styles → target shifts + atoms
    atoms.dart                       # §7.3 style atoms as sparse deltas
    lexicon.dart                     # offline instruction parser (intensity + atoms + explicit numbers)
    guards.dart                      # clip/crush/key/WB-drift checks + whites/exposure fixer
    amount.dart                      # AI Amount 0–150 % interpolation from pre-AI state
    reasons.dart                     # templated "why" strings for local changes
    local_provider.dart              # LocalAutoEditProvider implements AutoEditProvider
  lib/src/api/
    gateway_contract.dart            # request/response DTOs, ErrorCode enum, contractVersion=1
    auto_edit_response.dart          # Claude output model, tolerant parse + clamp + damping
    response_schema.dart             # JSON schema built from ParamRegistry (enum of param ids)
  lib/src/testing/
    synthetic_scenes.dart            # deterministic scene generators (see §6.4)
    scene_metrics.dart               # medianLuma, clipFraction, castA/castM, sigmaLStar…
  test/                              # mirrors lib/src; one *_test.dart per file
```

### 1.3 `app/` (Flutter, package `lumen`)
**Platform rule (enforced by `test/architecture_test.dart`):** `dart:io` may only be imported in files named `*_io.dart`; each has a `*_web.dart` twin selected by conditional export (`export 'x_web.dart' if (dart.library.io) 'x_io.dart';`). `Platform.isX` is only read in `lib/platform/platform_info_io.dart`.
```
app/
  pubspec.yaml                       # flutter: shaders: [shaders/*.frag]
  shaders/
    lib/common.glsl                  # sRGB, OkLab, packing, manual bilinear for packed textures (S1)
    aux_luma.frag                    # source → analysis: RG=packed norm log2Y, B=min(r,g,b), A=1
    guided_prep.frag                 # (I, I²) packed into RG/BA
    blur_packed.frag                 # separable 13-tap Gaussian on packed RG and BA (dir, radius uniforms)
    guided_ab.frag                   # a = var/(var+eps), b = meanI − a·meanI → packed RG/BA
    min_filter.frag                  # separable min (dark channel), radius 7 @ analysis res
    blur8.frag                       # separable Gaussian on plain 8-bit channel (transmission)
    denoise.frag                     # NR-lite: 5×5 bilateral, luma/chroma strengths (pre-pass, optional)
    develop.frag                     # uber pass: every per-pixel op in float
    finish.frag                      # sharpen (luma USM) → grain → dither
  lib/
    main.dart                        # ProviderScope(overrides by platform) → LumenApp
    app/lumen_app.dart  app/theme/{tokens.dart,theme.dart}  app/providers.dart  app/shortcuts.dart
    platform/
      platform_info.dart (+_io/_web)        # isDesktop, isMobile, isApple, isWindows, isWeb
      file_io.dart (+_io/_web)               # read/write/atomicWrite/list/delete; web = unsupported/no-op
      app_dirs.dart (+_io/_web)              # path_provider wrappers
    data/
      catalog_repository.dart                # interface: watchAll, get, add, update, delete, saveEdit, loadEdit, thumbPath
      file_catalog_repository_io.dart        # JSON impl (catalog.json + assets/<id>/edit.json)
      memory_catalog_repository.dart         # web + tests
      preset_repository.dart / file_preset_repository_io.dart / memory_preset_repository.dart
      settings_repository.dart (+_io/memory) # gateway URL, token, autoEditOnImport, defaultStyle, export defaults
    import/
      import_service.dart                    # hash → dedupe → copy → decode probe → exif → thumbnail → catalog
      import_sources.dart                    # file_picker adapter; drop adapter (desktop/web only)
      photo_decoder.dart                     # engine codec (targetWidth) → HEIC fallback → DecodeError
      heic_converter.dart (+_io/_web)        # platform_image_converter wrapper (S3)
      exif_reader.dart                       # exif pkg → ExifSummary (GPS never read into the model)
    engine/
      shader_library.dart                    # loads all FragmentPrograms once; fails loudly
      gpu_pass.dart                          # runPass(shader, w, h) via PictureRecorder → toImageSync (rgba8888)
      aux_cache.dart                         # aux textures per (assetId, sourceSize); dispose discipline
      render_graph.dart                      # denoise? → develop → finish? ; cache keys = hash of read params
      render_scheduler.dart                  # latest-wins coalescing, generation ids, drag scale 0.5
      lut_texture.dart                       # packed LUT bytes → ui.Image via decodeImageFromPixels
      histogram_service.dart                 # 256-px readback → lumen_core Histogram (10 Hz throttle)
      export_renderer.dart                   # tiled full-res render → RGBA bytes
      image_encoder.dart (+_io/_web)         # isolate: package:image JPEG/PNG; EXIF copy minus GPS
    ai/
      auto_edit_service.dart                 # orchestrates local → vision, guards, amount, history entry
      gateway_client.dart                    # http client for /v1/health, /v1/auto-edit, /v1/instruct
      vision_provider.dart                   # VisionAutoEditProvider implements AutoEditProvider
      preview_encoder.dart                   # 1024-px JPEG (q88), no metadata
    ai_ondevice/                             # Phase 2 (interfaces land in MVP, impls later)
      on_device_ai.dart                      # SubjectMasker, SkyMasker, Inpainter, Upscaler, OnDeviceCapabilities
      unavailable_ai.dart                    # MVP implementation: everything reports unavailable
    features/
      library/ library_screen.dart, library_grid.dart, drop_zone.dart, batch_bar.dart, library_notifier.dart
      editor/  editor_screen.dart, editor_notifier.dart, photo_canvas.dart, compare_view.dart,
               crop_overlay.dart, filmstrip.dart, top_bar.dart, responsive_layout.dart
      develop/ develop_panel.dart, param_slider.dart, histogram_view.dart, tone_curve_editor.dart,
               color_wheel.dart, hsl_band_picker.dart,
               sections/{light,color,hsl,curve,grading,effects,detail,geometry}_section.dart
      ai/      ai_styles_panel.dart, auto_button.dart, prompt_bar.dart, explain_list.dart, amount_slider.dart
      presets/ presets_panel.dart, save_preset_dialog.dart
      sync/    copy_settings_dialog.dart, sync_service.dart
      batch/   batch_auto_edit_service.dart, batch_progress.dart
      export/  export_dialog.dart, export_service.dart, export_targets.dart (+_io/_web: folder vs share sheet)
      settings/settings_dialog.dart
  test/                                      # unit + widget + shader numeric tests (flutter test)
    architecture_test.dart  engine/*_test.dart  features/**  data/**  support/test_images.dart
  integration_test/
    app_flows_test.dart  engine_on_device_test.dart  export_test.dart
```

### 1.4 `server/` (Dart shelf, package `lumen_server`)
```
server/
  pubspec.yaml               # deps: lumen_core, shelf, shelf_router, http, crypto, logging; dev: test, lints
  bin/server.dart            # GatewayConfig.fromEnv → buildHandler → serve(PORT)
  lib/lumen_server.dart
  lib/src/config.dart        # env: ANTHROPIC_API_KEY, LUMEN_MODEL (default claude-opus-5-5), LUMEN_EFFORT (default low),
                             #      PORT (8080), LUMEN_GATEWAY_TOKEN (optional), LUMEN_RPM (20), LUMEN_BURST (5),
                             #      LUMEN_MAX_BODY_BYTES (4194304), LUMEN_UPSTREAM_CONCURRENCY (4), ANTHROPIC_BASE_URL
  lib/src/app.dart           # buildHandler(config, ClaudeClient, Clock) → Pipeline
  lib/src/middleware/{request_id,error_envelope,cors,auth,rate_limit,body_limit}.dart
  lib/src/routes/{health,auto_edit,instruct}.dart
  lib/src/claude/claude_client.dart        # injectable http.Client; timeout 90 s; 1 retry on 429/529/5xx honoring retry-after
  lib/src/claude/messages_request.dart     # builds the /v1/messages body (see §1.9)
  lib/src/claude/messages_response.dart    # stop_reason handling, text-block extraction, usage/iterations
  lib/src/prompt/system_prompt.dart        # kPromptVersion; built from ParamRegistry + style table (byte-stable)
  lib/src/metering/usage_meter.dart        # interface + LogUsageMeter (Stripe meter later)
  lib/src/cache/result_cache.dart          # LRU(256) keyed sha256(image)+style+instruction+model+promptVersion
  test/                                    # mocked http.Client (package:http/testing.dart MockClient)
  tool/smoke_vision.dart                   # real-key smoke test against a synthetic dark scene
```

### 1.5 State management (Riverpod 3)
| Provider | Type | Notes |
|---|---|---|
| `platformInfoProvider`, `appDirsProvider` | `Provider` | overridden in tests |
| `catalogRepositoryProvider`, `presetRepositoryProvider`, `settingsRepositoryProvider` | `Provider` | file impl on io, memory on web/tests |
| `libraryProvider` | `AsyncNotifier<List<CatalogEntry>>` | selection lives in `librarySelectionProvider` (`Notifier<Set<String>>`) |
| `editorProvider(assetId)` | `AsyncNotifier.family` → `EditorState {doc, compareMode, activeSection, pendingAi}` | owns `RenderScheduler`, `HistoryStack` |
| `renderedImageProvider(assetId)` | exposes the scheduler's `ValueListenable<ui.Image?>` | canvas listens with `ValueListenableBuilder`, not a rebuild of the panel |
| `histogramProvider(assetId)` | `StreamProvider<Histogram>` | throttled 10 Hz |
| `autoEditServiceProvider`, `gatewayStatusProvider` | `Provider` / `FutureProvider` (refresh every 60 s and on settings change) | vision availability drives UI badges |
| `batchJobsProvider`, `exportJobsProvider` | `Notifier<List<Job>>` | progress + cancel |

### 1.6 Rendering engine (Flutter `FragmentProgram`)

**Image sizes**
| Image | Size | Produced by | Lifetime |
|---|---|---|---|
| Source preview | long edge = clamp(viewportLongEdge × DPR, 1600, **2560 desktop / 2048 mobile**), never upscaled | `instantiateImageCodec(bytes, targetWidth/Height)` (engine decoders use scaled JPEG decode) | while photo open; JPEG q95 cache at `assets/<id>/preview.jpg` |
| Analysis | **512 px** long edge | `aux_luma.frag` from source | while photo open; reused by export |
| View output | = source preview size (× 0.5 while dragging) | develop/finish | per frame |
| Histogram readback | 256 px wide | `drawImageRect` of output into a 256-px picture | per settled frame |
| Thumbnail | 384 px long edge, edited | develop on a 384-px source | on import and on edit commit (debounced 1 s) |
| Export | full res (≤ 16384 Apple, ≤ 8192 Android/Windows/web; larger sources downscaled with a warning) | tiled develop/finish | export only |

**Passes** (all targets `rgba8888`; packed = 16-bit value in two 8-bit channels, R=hi G=lo, **always sampled with `FilterQuality.none` at texel centers and unpacked before any math**; plain 8-bit textures use `FilterQuality.low`)
| # | Shader | Input → output | Size | Recomputed when |
|---|---|---|---|---|
| A1 | `aux_luma` | source → RG=packed `(log2(Y)+14)/16`, B=min(r,g,b) (sRGB-encoded), A=1 | 512 | new source |
| A2–A3 | `blur_packed` H,V (σ = 1.2 % long edge) | A1 → **baseMid** (clarity base) | 512 | new source |
| A4 | `guided_prep` | A1 → (I, I²) packed RG/BA | 512 | new source |
| A5–A6 | `blur_packed` H,V (r = 3.2 % long edge) | A4 → (meanI, meanII) | 512 | new source |
| A7 | `guided_ab` (ε = 0.01 in normalized log units) | A6 → (a, b) packed RG/BA | 512 | new source |
| A8–A9 | `blur_packed` H,V | A7 → **guidedAB** (meanA, meanB) | 512 | new source |
| A10–A11 | `min_filter` H,V (radius 7) | A1.B → dark channel | 512 | new source |
| A12–A13 | `blur8` H,V | dark → **darkSmooth** (8-bit) | 512 | new source |
| N | `denoise` (skipped when NR = 0) | source → denoised source | preview | NR params change |
| D | `develop` (uber) | source/N + baseMid + guidedAB + darkSmooth + curveLut → output | view | any develop param change |
| F | `finish` (skipped when sharpen = grain = 0) | D → output | view | sharpen/grain change or D change |
| H | (no shader) | F → 256-px picture → `toByteData(rawRgba)` → `Histogram` | 256 | after F, throttled |

Key properties:
- **All auxiliary data is computed once per photo from the unedited source** in source-uv space (≈13 passes at 512 px, < 10 ms). Slider moves re-run only D (+F). Geometry changes never invalidate aux, because `develop` maps each output pixel through the inverse geometry to a **source uv** and samples source and aux textures with that same uv.
- **Guided upsampling:** shadows/highlights base at preview res = `meanA(uv)·I(pixel) + meanB(uv)`, i.e. edge-aware at full preview resolution from 512-px statistics.
- **Texture** (fine local contrast) is computed inline in `develop` from a 9-tap neighborhood of the source; no extra pass.
- **Airlight** for dehaze comes from CPU stats (`ImageStats.airlight`: mean color of the top 0.1 % dark-channel pixels), passed as a uniform.
- **Resolution independence:** export tiles sample the same 512-px aux textures in source uv, so preview and export match and tiles have no seams.
- **Coalescing:** `RenderScheduler` keeps one pending settings value, one in-flight frame, a generation counter; stale frames are disposed. While a slider is dragged it renders at 0.5× and re-renders at 1× 120 ms after the last change.
- **Disposal:** every `ui.Image` has exactly one owner (`AuxCache`, `RenderScheduler`, or a test). A debug-only counter asserts zero leaked images when an editor closes.

**`develop.frag` per-pixel order** (engine `lumen-1`; formulas mirrored in `reference_pipeline.dart`):
1. Output pixel → output-normalized uv (+ `uTile` for export) → inverse geometry (crop rect, straighten angle, rotate90, flips) → source uv. Outside source → transparent black (only possible mid-crop-edit).
2. Sample source (or N) bilinear → sRGB decode → linear RGB.
3. White balance: per-channel gains from temp/tint (§6.2 reference model of research 01, κt = 1, κg = 0.5) → × 2^exposure.
4. Dehaze: `t = max(1 − ω·dark/A, 0.1)` with ω = 0.95·dehaze; positive → `J = (I − A)/t + A`; negative → `mix(I, A, −0.4·dehaze·(1−t))`.
5. Shadows/highlights: `L = log2 Y`, base from guidedAB; `Bn` = normalized base; `ΔEV = 1.5·(shadows·smoothstep(0.55, 0.0, Bn) + highlights·smoothstep(0.45, 1.0, Bn))`; RGB × 2^ΔEV.
6. Clarity: `ΔL = 0.8·clarity·(L − baseMid)·midtoneMask(Y)`; Texture: `ΔL = 0.6·texture·(L − blur3x3(L))`; RGB × 2^ΔL.
7. Composite tone LUT (row 0 of `curveLut`: parametric zones + contrast S-curve + whites/blacks + master point curve), applied hue-preserving (DNG RGBTone: curve on max and min, interpolate middle).
8. RGB point curves (rows 1–3), in sRGB-encoded domain.
9. HSL mixer in OkLCh: 8 bands, centers (deg) red 25, orange 55, yellow 100, green 140, aqua 195, blue 255, purple 295, magenta 335; raised-cosine weights, normalized.
10. Vibrance (chroma-weighted, skin-protected 20–75° hue) then saturation.
11. Color grading: shadows/midtones/highlights/global wheels as OkLab a/b offsets + lum, weights from luma with `balance` shift and `blending` overlap.
12. B&W (if treatment = bw): 8-band gray mixer on OkLCh hue → L only.
13. Post-crop vignette (paint style in encoded domain, `highlights` protection), output in sRGB-encoded 0–1, `fragColor = vec4(rgb, 1)` (premultiplied trivially).

All [H] constants above live in `engine_constants.dart` and in the shader; parity tests (§6.3) catch drift. Changing any of them after release requires a new `engineVersion`.

**`develop.frag` uniform layout** (floats are set in declaration order; `uniform_layout.dart` holds the same index table and a unit test asserts `pack(...).length == kDevelopFloatCount`):
| Float idx | Uniform | Components |
|---|---|---|
| 0–1 | `vec2 uOutSize` | output w, h (px) |
| 2–5 | `vec4 uTile` | tile offset x, y; full output w, h (preview: 0, 0, w, h) |
| 6–9 | `vec4 uCrop` | left, top, right, bottom (normalized, oriented-source space) |
| 10–13 | `vec4 uGeom` | angle (rad), rotate90 (0–3), flipH (0/1), flipV (0/1) |
| 14–17 | `vec4 uSrc` | source w, h, analysis w, h |
| 18–21 | `vec4 uWbExp` | gainR, gainG, gainB, 2^exposure |
| 22–25 | `vec4 uLocal` | highlights, shadows, clarity, texture (−1…1) |
| 26–29 | `vec4 uHaze` | dehaze (−1…1), airlight R, G, B |
| 30–33 | `vec4 uColor` | vibrance, saturation (−1…1), treatmentBw (0/1), curvesActive (0/1) |
| 34–41 | `vec4 uHslHue0, uHslHue1` | 8 bands, −1…1 (→ ±30° hue) |
| 42–49 | `vec4 uHslSat0, uHslSat1` | 8 bands |
| 50–57 | `vec4 uHslLum0, uHslLum1` | 8 bands |
| 58–73 | `vec4 uGradeShadows/Midtones/Highlights/Global` | OkLab a, b offset, lum, unused |
| 74–77 | `vec4 uGradeParams` | blending, balance, 0, 0 |
| 78–85 | `vec4 uBwMix0, uBwMix1` | 8 bands |
| 86–89 | `vec4 uVignette` | amount, midpoint, roundness, feather |
| 90–93 | `vec4 uVignette2` | highlights, crop aspect, showClipping (0/1), 0 |
| samplers | 0 `uSource`, 1 `uBaseMid`, 2 `uGuidedAB`, 3 `uDarkSmooth`, 4 `uCurveLut` (1024×4, packed) | 5 samplers |

`finish.frag`: `vec2 uSize`, `vec4 uSharpen` (amount, radius, detail, masking), `vec4 uGrain` (amount, size, roughness, seed), `vec4 uDither` (enabled, 0, 0, 0); sampler 0 = develop output. Grain seed = hash of `assetId`, so grain is stable across renders and export.

**Tone LUT:** `tone_lut.dart` bakes 1024 entries per row (row 0 composite tone, rows 1–3 R/G/B point curves) into 16-bit values, packed into a 1024×4 `rgba8888` image via `decodeImageFromPixels`. The shader interpolates two texel-center taps manually. Re-baked only when tone/curve params change (cache key = hash of those params).

**Histogram:** after each settled frame, draw the output into a 256-px-wide `PictureRecorder` with `FilterQuality.medium`, `toByteData(rawRgba)`, bin in `lumen_core.Histogram` (65k px, < 2 ms, main isolate is fine). Shows R, G, B, luma; clipping triangles light up at ≥ 0.1 % pixels at 255/0; `J` toggles the clipping overlay (`showClipping` uniform).

**Full-res export** (`export_renderer.dart`):
1. Decode the original at full resolution (capped per platform, see table) with `instantiateImageCodec`.
2. Reuse the photo's aux textures (rebuild them from the preview if the editor is closed; they are resolution independent).
3. Compute output size from crop and resize option (long edge / megapixels / original).
4. For each 2048² tile (+16 px apron for denoise/sharpen): run N (if enabled) on the tile region, D with `uTile`, F; `toByteData(rawRgba)`; copy the apron-free region into a full-frame `Uint8List` in an isolate (`TransferableTypedData`).
5. Encode in an isolate with `package:image`: JPEG (quality 1–100) or PNG (8-bit); optionally copy EXIF **minus GPS and serial numbers**; set sRGB.
6. Write via `export_targets` (desktop: chosen folder; iOS/Android: app documents then share sheet via `share_plus`; web: browser download). Progress per tile, cancellable between tiles.
Peak memory for 24 MP ≈ 96 MB source texture + 96 MB output buffer + encoder copy. Mobile export default cap: 24 MP (user can override on desktop).

### 1.7 Storage (repository pattern)
Root: `getApplicationSupportDirectory()/<kBrand.storageId>/` where `storageId = 'lumen_catalog_v1'` (stable across public renames).
```
catalog.json                     # CatalogIndex {schemaVersion: 1, entries: [CatalogEntry]}
originals/<assetId>.<ext>        # managed copy of the imported file (assetId = first 32 hex of SHA-256)
assets/<assetId>/edit.json       # EditDocument (settings + history + snapshots + last AI result)
assets/<assetId>/thumb.jpg       # 384-px edited thumbnail
assets/<assetId>/preview.jpg     # unedited preview cache (q95)
presets/<uuid>.json              # user presets
settings.json                    # app settings
```
- **Atomic writes:** write `<file>.tmp`, flush, rename over the target; on Windows, if rename fails because the target exists, delete then rename (covered by a unit test with an injected filesystem).
- **Debounced saves:** `edit.json` 500 ms after the last change and on app pause/close (`AppLifecycleListener`).
- **Dedupe:** import of identical bytes returns the existing entry.
- **Web:** `MemoryCatalogRepository` (session only), banner "Web demo: photos are not saved".
- **Scale path:** `SqliteCatalogRepository` (drift, MIT) behind the same interface when catalogs pass ~5k entries; cloud sync adds `SyncingCatalogRepository` (local first, recipes + previews only).

### 1.8 AI: `AutoEditProvider`
```dart
// lumen_core/lib/src/auto/auto_edit_provider.dart (signatures only)
enum AutoEditEngine { local, vision, learned }
abstract interface class AutoEditProvider {
  AutoEditEngine get engine;
  Future<ProviderStatus> status();                       // available / unavailable(reason)
  Future<AutoEditOutcome> autoEdit(AutoEditInput input); // style-driven full edit
  Future<AutoEditOutcome> instruct(InstructInput input); // "warmer, lift shadows" → deltas
}
class AutoEditInput { ImageStats stats; ExifSummary? exif; AiStyle style; DevelopSettings current;
  Set<ParamId> locked; Uint8List? previewJpeg; DevelopSettings? baseline; int variants; }
class InstructInput { /* AutoEditInput fields + */ String instruction; }
class AutoEditOutcome { DevelopSettings settings; List<ParamChange> changes /* param, from, to, reason */;
  String? intent; SceneInfo? scene; AutoEditEngine engineUsed; bool degraded; String? degradedReason;
  double confidence; }
```
**`AutoEditService` flow (app):**
1. Compute `ImageStats` from the 512-px analysis readback in `Isolate.run`.
2. Run `LocalAutoEditProvider` (< 300 ms) → show as a **pending preview** (not committed); sliders animate.
3. If `gatewayStatus.visionAvailable`: send `VisionAutoEditProvider` request with the 1024-px JPEG, stats, EXIF summary, `baseline = local result`, `locked` params. Timeout 30 s.
4. Validate: clamp to `ParamRegistry` ranges → damping (per-param factors, start at 0.85 for local-contrast/color params) → merge respecting `locked` → `guards.dart` on the CPU reference render at 256 px (clip ≤ 1 %, crush ≤ 2 %, median L* within key band); the guard fixer only adjusts exposure/whites/blacks.
5. Commit **one** history entry: `AI Auto · <Style>` (vision) or `AI Auto · <Style> (basic)` (local or degraded). Store `ai: {engine, style, model, promptVersion, changes, intent}` in the document for the Explain list and the AI Amount slider.
6. Failure, refusal, timeout or gateway down → keep the local result, badge "Basic auto (offline)". Never block editing.

**AI Amount** (0–150 %): interpolates every AI-changed param between the pre-AI value and the AI value (extrapolates above 100 %, clamped). Moving it creates one coalesced history entry.

**AI Styles** (`ai_style.dart`): applied in `local` as target shifts + atoms (research 01 §6.12, §7.3); in `vision` as the style paragraph in the prompt.
| Style | Local target shifts | Atoms (amount) |
|---|---|---|
| Natural | none | none |
| Vibrant | C*t +8, σt +3 | vibrant 0.6 |
| Moody | key ×0.7, σt +3, C*t −6, WB strength 0.4 | moody 0.8 |
| Cinematic | σt +2 | cinematic_teal_orange 1.0 |
| Film | σt −2 | film_faded 1.0 |
| Golden Hour | WB strength 0.2 | golden_hour 1.0 |
| Clean & Bright | key ×1.3, T_lo +0.03, σt −3, C*t −2 | bright_airy 0.6 |
| B&W | σt +3 | bw_classic 1.0 |
| Portrait Soft | vibrance cap 10, skin protect | soft_matte 0.4, clarity −10, texture −15 |

**Offline describe-an-edit** (`lexicon.dart`): tokenizes the instruction, splits clauses on "and/,/but/then", matches intensity words (§7.2 of 01: 0.25/0.5/1.0/1.75/2.5), atoms by synonym table (§7.3), direct slider phrases ("lift the shadows" → shadows +, "less contrast" → contrast −, "exposure +0.5" → explicit), later clause wins on conflict, per-instruction caps (exposure ±1 EV, temp ±30, others ±40), never past the pre-instruction baseline for "less X". Unrecognized → `InstructionResult.unrecognized(suggestions)` shown as chips. Vision mode sends the raw instruction to `/v1/instruct`; the lexicon result is the fallback.

**Learned provider** (Phase 3): ONNX slider regressor trained on licensed data; same interface.

### 1.9 Gateway API contract (v1)
All bodies JSON, UTF-8. `contractVersion: 1`. Every response carries `x-request-id`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/health` | liveness + capability |
| POST | `/v1/auto-edit` | style-driven edit from image + stats |
| POST | `/v1/instruct` | natural-language edit → deltas |
| — Post-MVP — | `/v1/auto-edit/shoot` (contact sheet), `/v1/usage`, `/v1/auth/*` | |

`GET /v1/health` → `200 {"status":"ok","version":"1.0.0","contractVersion":1,"visionAvailable":false,"model":null,"promptVersion":"2026-10-03.1"}` (`visionAvailable` = API key present; `model` set when available).

`POST /v1/auto-edit` request:
```json
{
  "contractVersion": 1,
  "requestId": "6f1c…",
  "client": {"app": "lumen", "version": "1.0.0", "platform": "macos"},
  "style": "moody",
  "variants": 1,
  "image": {"mime": "image/jpeg", "width": 1024, "height": 683, "base64": "…"},
  "stats": {"lumaP": {"p0_5": 0.02, "p5": 0.05, "p50": 0.18, "p95": 0.71, "p99_5": 0.93},
            "clipPct": 0.1, "crushPct": 3.2, "lAvg": 0.07, "wb": {"a": 0.41, "m": -0.03, "confidence": 0.8},
            "meanChroma": 19.5, "skinShare": 0.14, "haze": 0.09, "hslShare": {"orange": 0.22, "blue": 0.31}},
  "exif": {"camera": "…", "lens": "…", "iso": 1600, "shutter": "1/60", "aperture": 2.0, "focalMm": 35,
           "localTime": "18:42", "flash": false},
  "baseline": {"exposure": 0.62, "shadows": 31, "whites": 18, "temp": -12},
  "current": {},
  "locked": []
}
```
`POST /v1/instruct` = same + `"instruction": "warmer and lift the shadows a bit"`; `variants` ignored; adjustment values in the result are **deltas** from `current`.

Success `200`:
```json
{
  "requestId": "6f1c…", "engine": "vision", "model": "claude-opus-5-5", "servedBy": "claude-opus-5-5",
  "promptVersion": "2026-10-03.1", "cached": false, "latencyMs": 5400,
  "result": {
    "scene": {"subject": "portrait, outdoor café", "lighting": "backlit", "timeOfDay": "golden_hour", "keyIntent": "normal"},
    "issues": [{"issue": "face underexposed", "severity": "medium"}],
    "intent": "Warm, soft backlit portrait with an open face",
    "variants": [{"label": "Moody", "confidence": 0.78,
      "targets": {"midLStar": 48, "wbStrength": 0.3, "contrastLevel": "medium", "colorLevel": "natural"},
      "presetAtoms": [{"atom": "moody", "amount": 0.7}],
      "adjustments": [{"param": "shadows", "value": 28, "reason": "Open the face without flattening the sky"}]}],
    "done": false
  },
  "usage": {"inputTokens": 4210, "outputTokens": 612, "cacheReadTokens": 3020, "cacheWriteTokens": 0, "fallbackUsed": false}
}
```
The server clamps every `value` to `ParamRegistry` ranges before responding; the app clamps again (never trust the network).

**Errors** — envelope `{"error": {"code": "...", "message": "...", "retryable": bool, "retryAfterMs": int?, "details": {}}, "requestId": "..."}`:
| HTTP | code | When |
|---|---|---|
| 400 | `invalid_request` / `unsupported_contract` | schema validation failed / unknown `contractVersion` |
| 401 | `unauthorized` | `LUMEN_GATEWAY_TOKEN` set and bearer missing/wrong |
| 413 | `payload_too_large` | body > `LUMEN_MAX_BODY_BYTES` (4 MB) or image long edge > 1568 px |
| 422 | `upstream_refusal` | Claude `stop_reason: "refusal"` (after server-side fallback); `details.category` from `stop_details` (may be null) |
| 429 | `rate_limited` | token bucket empty or upstream queue full; `Retry-After` header + `retryAfterMs` |
| 502 | `upstream_error` / `upstream_incomplete` / `upstream_invalid_output` | Anthropic 5xx after retry / `stop_reason: "max_tokens"` / JSON missing or invalid |
| 503 | `vision_unavailable` | no `ANTHROPIC_API_KEY` |
| 504 | `upstream_timeout` | > 90 s |
App mapping: every non-2xx → local result + "Basic auto" badge; 401 → settings prompt; 429 → toast with retry time.

**Auth (placeholder):** if `LUMEN_GATEWAY_TOKEN` is set, require `Authorization: Bearer <token>` (constant-time compare). Later: verify Firebase/Auth.js ID tokens, user id becomes the rate-limit and metering key.

**Rate limiting:** token bucket per client key (bearer token or remote IP): 20 req/min, burst 5. Global upstream semaphore: 4 concurrent Claude calls, queue ≤ 16, else 429. In-memory now; Redis/Firestore counters when horizontally scaled.

**Upstream call** (`messages_request.dart`), raw HTTP:
```
POST {ANTHROPIC_BASE_URL:-https://api.anthropic.com}/v1/messages
x-api-key: $ANTHROPIC_API_KEY
anthropic-version: 2023-06-01
anthropic-beta: server-side-fallback-2026-07-01
content-type: application/json
{
  "model": "claude-opus-5-5",                     // LUMEN_MODEL
  "max_tokens": 16000,
  "system": [{"type": "text", "text": "<SYSTEM PROMPT kPromptVersion>", "cache_control": {"type": "ephemeral"}}],
  "messages": [{"role": "user", "content": [
     {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": "<b64>"}},
     {"type": "text", "text": "Image 1: photo to edit.\n<stats>…</stats>\n<exif>…</exif>\n<baseline>…</baseline>\nStyle: Moody\n"}]}],
  "output_config": {"format": {"type": "json_schema", "schema": { /* AutoEditResponse schema, additionalProperties:false */ }},
                    "effort": "low"},               // LUMEN_EFFORT, always sent explicitly
  "fallbacks": "default"
}
```
Rules (from the claude-api skill, cached 2026-09-25):
- No `temperature`, no `thinking` field (Opus 5.5 thinking is always on; effort is the only knob; its default would be `medium`, so effort is always sent), no `tool_choice` (forced tool use 400s), no assistant prefill (400s).
- `fallbacks: "default"` + header `server-side-fallback-2026-07-01` only when the model is in `{claude-opus-5-5, claude-opus-5, claude-sonnet-5-5, claude-fable-5-1}`; omit both for other models (e.g. `claude-haiku-4-5`). Never on the Batches API (rejected there).
- Response: check HTTP status first; then **check `stop_reason` before reading `content`**: `refusal` → 422 (branch on `stop_reason`, treat `stop_details` as informational, possibly null); `max_tokens` → 502 `upstream_incomplete`; otherwise take the first `type == "text"` block (skip `thinking` and `fallback` blocks), `jsonDecode`, parse with `AutoEditResponse.fromJson` (tolerant), clamp. `servedBy` = top-level `model`; `fallbackUsed` = any `usage.iterations[].type == "fallback_message"`.
- Structured outputs don't enforce numeric min/max → clamp client-side (server and app).
- Prompt caching: system prompt is byte-stable (no timestamps), generated from `ParamRegistry` + style table, ≥ 4096 tokens; verify `usage.cache_read_input_tokens > 0` on the second call in the smoke test.
- Image: 1024-px long edge JPEG q88, re-encoded from pixels (so **no EXIF/GPS leaves the device**); EXIF facts travel as text, GPS and serial numbers are excluded by the `ExifSummary` type.

### 1.10 On-device AI module (designed now, built in Phase 2)
```dart
// app/lib/ai_ondevice/on_device_ai.dart (signatures only)
abstract interface class OnDeviceCapabilities { Future<Set<OnDeviceFeature>> available(); } // subjectMask, skyMask, inpaint, upscale
abstract interface class SubjectMasker { Future<MaskImage> subject(ui.Image preview, {CancelToken? cancel}); }
abstract interface class SkyMasker     { Future<MaskImage> sky(ui.Image preview, {CancelToken? cancel}); }
abstract interface class Inpainter     { Future<ui.Image> inpaint(ui.Image src, MaskImage holes, {CancelToken? cancel}); }
abstract interface class Upscaler      { Future<ui.Image> upscale(ui.Image src, int factor, {void Function(double)? onProgress}); }
```
Implementations (Phase 2): `OrtSessionPool` over `flutter_onnxruntime` (providers: CoreML→CPU on Apple, XNNPACK→CPU on Android, CPU on Windows with fp32 models), `ModnetSubjectMasker` (q8 bundled, 6.6 MB), `MiganInpainter` (28 MB bundled), `RealEsrganUpscaler` (4.9 MB bundled), `SkysegMasker` (download on demand), optional fast paths `AppleVisionSubjectMasker` (Pigeon) and `MlKitSubjectMasker` (Android). `ModelStore` downloads to app support with SHA-256 verification and resume. Pre/post-processing in `Isolate.run`; `OrtValue.dispose()` in `finally`.
**Graceful degradation:** each feature asks `OnDeviceCapabilities`; unavailable → the UI control is visible but disabled with a reason tooltip; runtime failure → toast and the edit stays unchanged; nothing in the develop pipeline depends on ML. MVP ships `UnavailableOnDeviceAi`.

---

## 2. Data model (schema v1)

### 2.1 `ParamId` registry (single source of truth)
Each entry: `id` (string, dotted), `group`, `min`, `max`, `default`, `step`, `unit`, `xmp` (crs: name), `aiEditable`, `localAllowed` (for masks), `copyGroup`.
| Group | Params (range, default 0 unless noted) |
|---|---|
| light | `exposure` (−5…5 EV, 0.01), `contrast`, `highlights`, `shadows`, `whites`, `blacks` (−100…100) |
| color | `temp`, `tint` (−100…100 relative), `vibrance`, `saturation` (−100…100) |
| presence | `texture`, `clarity`, `dehaze` (−100…100) |
| hsl | `hsl.<band>.hue/sat/lum` for red, orange, yellow, green, aqua, blue, purple, magenta (−100…100) — 24 params |
| bw | `bw.<band>` (−100…100) — 8 params |
| curve | `curve.p.shadows/darks/lights/highlights` (−100…100), `curve.split.shadow` (10…50, 25), `curve.split.midtone` (25…75, 50), `curve.split.highlight` (50…90, 75) |
| grading | `grade.<shadows/midtones/highlights/global>.hue` (0…359), `.sat` (0…100), `.lum` (−100…100); `grade.blending` (0…100, 50), `grade.balance` (−100…100) |
| detail | `sharpen.amount` (0…150), `sharpen.radius` (0.5…3.0, 1.0), `sharpen.detail` (0…100, 25), `sharpen.masking` (0…100), `noise.luminance`, `noise.color` (0…100) |
| effects | `vignette.amount` (−100…100), `vignette.midpoint` (0…100, 50), `vignette.roundness` (−100…100), `vignette.feather` (0…100, 50), `vignette.highlights` (0…100), `grain.amount` (0…100), `grain.size` (0…100, 25), `grain.roughness` (0…100, 50) |
`aiEditable` = everything except geometry and sharpen.radius. The `AutoEditResponse` schema `param` enum is generated from this registry, so the app, the server and the prompt can never disagree.

### 2.2 `DevelopSettings` / `EditDocument` JSON
```json
{
  "schema": "lumen.edit",
  "schemaVersion": 1,
  "engineVersion": "lumen-1",
  "assetId": "9f2c…",
  "settings": {
    "values": {"exposure": 0.62, "shadows": 31, "hsl.orange.sat": -8},      // sparse: defaults omitted
    "curves": {"master": [[0,0],[255,255]], "red": null, "green": null, "blue": null},  // null = identity
    "treatment": "color",
    "geometry": {"crop": [0,0,1,1], "angle": 0.0, "rotate90": 0, "flipH": false, "flipV": false,
                 "aspect": "original", "baseOrientation": 1},
    "masks": []                                                                  // reserved; Phase 2
  },
  "history": {"cursor": 3, "entries": [
    {"id": "h3", "label": "Exposure +0.62", "at": "2026-10-03T10:00:00Z", "kind": "slider",
     "ops": [{"path": "values.exposure", "from": 0.0, "to": 0.62}]}
  ]},
  "snapshots": [],
  "ai": {"engine": "local", "style": "natural", "model": null, "promptVersion": null, "intent": null,
         "preAi": {"values": {}}, "changes": [{"param": "exposure", "from": 0, "to": 0.62, "reason": "Underexposed: median 9 %"}]},
  "createdAt": "…", "updatedAt": "…"
}
```
- **Curves:** 2–16 points, x strictly increasing, 0–255; stored as whole arrays (a curve edit is one op).
- **Masks (Phase 2):** `{"id","name","kind": "linear|radial|subject|sky|brush","invert","opacity","shape": {linear: {x0,y0,x1,y1}, radial: {cx,cy,rx,ry,angle,feather}, ai: {model, modelVersion, maskRef: "assets/<id>/masks/m1.png"}}, "adjustments": {sparse, localAllowed params only}}`. Max 8 masks.
- **Migrations:** `migrations.dart` maps `schemaVersion n → n+1`; unknown future versions open read-only. `engineVersion` is never upgraded silently.

### 2.3 History (patch-based undo/redo)
- `HistoryEntry {id, label, at, kind (slider|ai|preset|paste|curve|geometry|reset|instruction), ops: [ {path, from, to} ]}`; `path` is `values.<ParamId>`, `curves.<channel>`, `treatment`, `geometry.<field>`, or `masks` (whole list).
- Undo applies `from`, redo applies `to`; a new edit after undo truncates the redo tail. Cap 200 entries (oldest dropped; settings unaffected).
- **Coalescing:** a slider gesture opens a transaction on pointer-down and commits one entry on pointer-up; keyboard nudges within 600 ms on the same param merge.
- Persisted inside `edit.json`, so undo survives restarts.

### 2.4 Presets
```json
{"schema": "lumen.preset", "schemaVersion": 1, "id": "uuid", "name": "Warm Film", "group": "Film",
 "builtIn": false, "amountSupported": true, "values": {"temp": 12, "grain.amount": 20},
 "curves": {"master": [[0,20],[64,60],[192,200],[255,245]]}, "treatment": null, "createdAt": "…"}
```
Sparse merge; omitted keys keep current values; explicit 0 resets. **Amount** (0–100 %) interpolates numeric values between current and preset. Geometry is never part of a preset. Built-in (12): Natural Lift, Bright & Airy, Moody, Punchy, Soft Matte, Cinematic Teal-Orange, Faded Film, Golden Hour, Crisp Landscape, Clean Product, Classic B&W, High-Contrast B&W (defined from the atoms table).

### 2.5 Copy / paste / sync
`SettingsGroup` = light, color, presence, hsl, bw/treatment, curve, grading, detail, effects, geometry(crop), masks. Copy dialog defaults to all groups **except geometry and masks**. Paste/sync = one history entry per target photo (`Paste settings`). Sync applies to every selected photo in the library.

### 2.6 Catalog entry
```json
{"assetId": "9f2c…", "fileName": "IMG_2041.HEIC", "original": "originals/9f2c….heic", "format": "heic",
 "width": 4032, "height": 3024, "bytes": 2481930, "importedAt": "…", "capturedAt": "…",
 "exif": {"camera": "iPhone 16 Pro", "lens": "…", "iso": 80, "shutter": "1/120", "aperture": 1.8, "focalMm": 6.8},
 "hasEdits": true, "editedAt": "…", "ai": {"engine": "local", "style": "natural"}, "thumbVersion": 4,
 "rating": 0, "flag": "none"}
```

---

## 3. Scope

### 3.1 MVP (must ship; "Lightroom with AI")
| Area | In MVP |
|---|---|
| Import | File picker (all platforms), drag-and-drop (macOS/Windows/web), JPEG/PNG/WebP/HEIC, SHA-256 dedupe, EXIF summary, auto-edit-on-import toggle |
| Library | Grid with edited thumbnails grouped by import date, multi-select (click, shift, cmd/ctrl, long-press on mobile), floating batch bar, delete (moves catalog entry + files to an in-app trash folder; empty trash asks for confirmation) |
| AI | One-click Auto (local, + vision when available), 9 AI Styles, AI Amount slider, Explain list (reason per change), describe-an-edit prompt bar (offline lexicon + vision), "Basic auto (offline)" badge |
| Develop | Light, Color/WB, HSL 8 bands, Tone curve (parametric + point curves master/R/G/B), Color grading (3 wheels + global, blending, balance), Effects (clarity, texture, dehaze, vignette, grain), Detail (sharpen, NR-lite), Geometry (crop with aspect presets, straighten, rotate 90°, flip H/V), B&W treatment |
| View | Histogram with clipping indicators, before/after (split wipe, side-by-side on desktop, hold `\` / press-and-hold), zoom (fit, 100 %, pinch/scroll), pan |
| Workflow | Undo/redo (persisted), reset (all / per section), double-click a slider to reset, keyboard shortcuts, presets (12 built-in + save/rename/delete user presets, amount), copy/paste and sync settings, batch auto-edit with progress/cancel |
| Export | JPEG (quality) / PNG, resize (long edge, original), metadata on/off (GPS always stripped), filename template `{name}_edit`, single and batch (folder on desktop, share sheet on mobile, download on web) |
| Gateway | `/v1/health`, `/v1/auto-edit`, `/v1/instruct`, token auth placeholder, rate limit, metering log, result cache |

### 3.2 Post-MVP (ordered)
| Phase | Item |
|---|---|
| **2 (v1.1)** | Masks: linear + radial gradients (analytic in shader), then AI Subject (MODNet ONNX + Apple Vision/ML Kit fast paths) and Sky; per-mask local adjustments; "brighten the face"-style local instructions |
| 2 | Shoot consistency ("Match shoot": shared WB/key targets across a selection) and vision contact-sheet calls (`/v1/auto-edit/shoot`) |
| 2 | Object removal (MI-GAN bundled, LaMa HQ download) as a pixel layer with C2PA/AI label; Upscale 2×/4× on export (Real-ESRGAN) |
| 2 | Variations strip (3 variants in one call), verify (reflection) round for Pro mode |
| 3 | RAW (Apple CIRAWFilter, LibRaw CDDL via FFI) → engine `lumen-2` in linear ProPhoto; Lightroom `.xmp` preset import; auto-straighten (Hough) |
| 3 | Learned provider (on-device slider regressor), Learn My Style (per-user, opt-in) |
| 3 | Accounts, Stripe billing + credits, cloud sync of recipes, WebP/HEIC/16-bit TIFF export, platform encoders |

### 3.3 Why masks, Remove and Upscale are Phase 2
| Feature | Effort (focused sessions) | Main risks | MVP value without it | Decision |
|---|---|---|---|---|
| Linear/radial gradients | 2 | canvas handle UX on 3 form factors, uniforms per mask, local-adjustment panel mode | Auto + global sliders already deliver the promise | Phase 2, first item. Schema reserves `masks` now so no migration |
| AI Subject/Sky masks (ONNX) | 3–4 | adds `flutter_onnxruntime` (iOS 16 / macOS 14 minimums, Windows DLL download at build, no fp16 on Windows), model download/storage, isolate marshalling of 12 MB tensors, mask edge refinement | Same | Phase 2 after gradients |
| Object removal (MI-GAN) | 3 | brush UI, pixel layer breaks the pure-recipe model, EU AI Act Art. 50 labeling, inpainting at full-res export | Commoditized, low willingness to pay (04 §5.1) | Phase 2 |
| Upscale (Real-ESRGAN) | 2 | 2–8 s per image, tiling for memory, export-only feature | Low for ICP | Phase 2 (export option) |
None of these change the develop shader contract for global ops, so deferring them costs nothing architecturally.

---

## 4. Phased build order
Conventions: **one checkbox = one commit**. Verification commands run from the repo root unless noted. `CORE` = `cd packages/lumen_core`, `APP` = `cd app`, `SRV` = `cd server`. TDD: write the test file first, see it fail, implement, see it pass.

### Phase 0 — Repo hygiene (½ session)
- [ ] P0.1 Strict analysis: `analysis_options.yaml` in all three packages (`strict-casts`, `strict-raw-types`, `strict-inference`; lints incl. `prefer_const_constructors`, `always_declare_return_types`, `avoid_print` (server uses `logging`)). Verify: `CORE dart analyze && SRV dart analyze && APP flutter analyze`.
- [ ] P0.2 Replace `Awesome` stub; add `lib/src/brand.dart` (`kBrand`) and export it. Verify: `CORE dart test`.
- [ ] P0.3 `tool/verify.sh`: format check, analyze ×3, `dart test` ×2, `flutter test`, coverage gate (§6.1). Verify: `bash tool/verify.sh`.
- [ ] P0.4 macOS entitlements (Debug + Release): add `com.apple.security.network.client`, `com.apple.security.files.user-selected.read-write`. Android debug manifest `usesCleartextTraffic="true"` (debug only). Verify: `APP flutter build macos --debug`.
- [ ] P0.5 Move `http` to `dependencies` in `server/pubspec.yaml`; add packages from §7 needed for Phase 1 only. Verify: `dart pub get` at root.

### Phase 1 — `lumen_core` with TDD (3 sessions)
- [ ] P1.1 `color/srgb.dart`, `luminance.dart`, `cielab.dart`, `oklab.dart` (+ tests: round-trips ≤ 1e-6, known reference values). `CORE dart test test/color`.
- [ ] P1.2 `model/param_id.dart` registry (+ tests: ids unique, defaults within range, every param has a group/xmp, count = 80 scalar params per §2.1). `CORE dart test test/model/param_id_test.dart`.
- [ ] P1.3 `model/tone_curve.dart` (monotone cubic, validation, identity detection), `geometry.dart`, `treatment.dart`, `mask.dart` (serialize only). Tests: monotonicity, endpoints, JSON round-trip.
- [ ] P1.4 `model/develop_settings.dart` (sparse map, get/set with clamp, `withValues`, equality, JSON). Tests: defaults omitted from JSON, clamp on set, round-trip.
- [ ] P1.5 `model/history.dart` (cursor, truncate, coalesce, cap). Tests: 50 random edits → undo all → equals initial; redo all → equals final.
- [ ] P1.6 `model/edit_document.dart`, `migrations.dart` (v1 baseline; test harness with a fake v0 fixture), `catalog_entry.dart`, `exif_summary.dart`.
- [ ] P1.7 `model/preset.dart`, `builtin_presets.dart` (12), `settings_subset.dart`. Tests: sparse merge, amount 0/50/100 %, geometry never applied, every built-in only uses valid ids.
- [ ] P1.8 `color/white_balance.dart` (temp/tint → gains). Tests: 0/0 → (1,1,1); +100 temp → R/B ratio ×2 (κt = 1).
- [ ] P1.9 `render/lut_packing.dart`, `render/tone_lut.dart`. Tests: identity settings → identity LUT (±1/65535); contrast +50 is an S-curve through mid-gray; whites/blacks reference model; curve rows independent.
- [ ] P1.10 `render/engine_constants.dart`, `render/uniform_layout.dart`, `finish_uniforms.dart`. Tests: length = 94 floats, index table matches doc table, defaults pack to neutral values.
- [ ] P1.11 `render/rgba_buffer.dart`, `render/reference_pipeline.dart` (point ops 2–13 of §1.6; spatial terms take precomputed base values). Tests: identity → input ±1/255; exposure +1 on 128 → 176; bw treatment → R=G=B.
- [ ] P1.12 `testing/synthetic_scenes.dart`, `scene_metrics.dart` (§6.4). Tests: generators deterministic (hash of bytes stable), metrics on known images.
- [ ] P1.13 `analysis/proxy.dart`, `histogram.dart`, `image_stats.dart`. Tests: histogram counts exact on a 4-color image; percentiles; WB cast estimate sign on warm/cool scenes; dark channel on hazy scene.
- [ ] P1.14 `auto/local_auto_tone.dart` + `reasons.dart` (stages, constants §6.12 of 01, solver on 256-px CPU reference render). Tests = acceptance checks AC-15…AC-22 (§9) as unit tests.
- [ ] P1.15 `auto/atoms.dart`, `ai_style.dart`, `amount.dart`. Tests: each style differs from Natural on the same scene; Moody median < Natural < Clean & Bright; B&W sets treatment; amount 0 % = pre-AI, 150 % clamped.
- [ ] P1.16 `auto/lexicon.dart`. Tests: ≥ 40 table-driven phrases (intensity, atoms, explicit numbers, "less X", conflicts, caps, unrecognized).
- [ ] P1.17 `auto/guards.dart`, `auto/auto_edit_provider.dart`, `auto/local_provider.dart`. Tests: guard fixes an over-bright vision proposal (clip 6 % → ≤ 1 %); locked params untouched.
- [ ] P1.18 `api/response_schema.dart`, `api/auto_edit_response.dart`, `api/gateway_contract.dart`. Tests: schema has `additionalProperties: false` everywhere and an enum equal to `aiEditable` ids; tolerant parse drops unknown params; clamp; contract DTO round-trips.
- [ ] P1.19 Coverage gate. Verify: `CORE dart run coverage:test_with_coverage && dart run tool/coverage_check.dart coverage/lcov.info 80`.

### Phase 2 — Shader engine with numeric tests (2–3 sessions)
- [ ] P2.1 Spikes S1 (include) and S4 (packed exactness) as tests in `app/test/engine/spike_test.dart`. Verify: `APP flutter test test/engine/spike_test.dart`.
- [ ] P2.2 `shaders/lib/common.glsl`, `engine/shader_library.dart`, `engine/gpu_pass.dart`; `test/support/test_images.dart` (synthetic scene → `ui.Image`, readback helpers). Verify: `flutter test test/engine/gpu_pass_test.dart`.
- [ ] P2.3 `aux_luma.frag`, `blur_packed.frag`, `guided_prep.frag`, `guided_ab.frag`, `min_filter.frag`, `blur8.frag`, `engine/aux_cache.dart`. Tests: packed log-luma decodes to CPU value ±1e-3; blur of a constant is constant; min filter of a single dark dot spreads to 15×15; guided base preserves a hard edge (≤ 5 % overshoot).
- [ ] P2.4 `engine/lut_texture.dart`. Test: upload + shader readback of LUT entries exact.
- [ ] P2.5 `develop.frag` stage by stage, each with a CPU-parity test vs `reference_pipeline` (WB/exposure → tone LUT → curves → HSL → vib/sat → grading → bw → vignette). Verify: `flutter test test/engine/develop_parity_test.dart`.
- [ ] P2.6 Spatial ops in `develop.frag` (dehaze, shadows/highlights, clarity, texture) with behavior tests (hazy scene: contrast of far region rises; shadows +100 lifts P10 luma; clarity raises local σ; no NaN/Inf: output never 0/255 floods on extreme slider combos).
- [ ] P2.7 Geometry in `develop.frag`: rotate90/flip/crop/straighten tests on an asymmetric marker image (corner colors land where expected).
- [ ] P2.8 `denoise.frag`, `finish.frag`. Tests: NR lowers noise σ on a noisy flat patch ≥ 40 % at 100; sharpen raises edge acutance; grain deterministic for the same seed; identity when amounts are 0.
- [ ] P2.9 `engine/render_graph.dart`, `render_scheduler.dart` (coalescing, generations, drag scale, disposal counter). Tests with a fake clock: 100 rapid updates → ≤ 3 renders, last settings win, 0 leaked images.
- [ ] P2.10 `engine/histogram_service.dart`. Test: known image → expected bins; throttling.
- [ ] P2.11 `engine/export_renderer.dart` + `image_encoder` (isolate). Tests: 3000×2000 tiled render equals single-pass render (max diff ≤ 1/255); JPEG/PNG decode back with expected size.
- [ ] P2.12 Spikes S2 (EXIF orientation) and S3 (HEIC) in `integration_test/engine_on_device_test.dart`; same parity tests run on device. Verify: `APP flutter test integration_test/engine_on_device_test.dart -d macos` and `-d "iPhone 17 Pro"`.
- [ ] P2.13 Spike S5 on Android emulator. Verify: `APP flutter test integration_test/engine_on_device_test.dart -d emulator-5554`.

### Phase 3 — UI shell (2–3 sessions)
- [ ] P3.1 Theme tokens (graphite surfaces, safelight amber accent, AI gradient, Geist + Instrument Serif via bundled fonts with OFL notices), `lumen_app.dart`, `responsive_layout.dart` (mobile < 700 px, tablet, desktop ≥ 1024). Widget test: layouts at 375, 768, 1440 widths without overflow.
- [ ] P3.2 `platform/*` with `_io/_web` twins; `test/architecture_test.dart` (no `dart:io` outside `*_io.dart`; brand literal only in `brand.dart`; no `desktop_drop` import outside the drop adapter). Verify: `flutter test test/architecture_test.dart`.
- [ ] P3.3 `data/` repositories (file + memory) with tests on a temp dir (atomic write, debounced save, dedupe, corrupt-file recovery: unreadable `edit.json` → backup + default doc).
- [ ] P3.4 `import/` (picker adapter, drop adapter, decoder, HEIC fallback, EXIF, thumbnail) + `library_screen` with empty-state drop zone. Widget test with a fake import source.
- [ ] P3.5 Library grid, selection model, floating batch bar (counts, actions disabled states). Widget tests: shift/cmd selection, long-press on mobile.
- [ ] P3.6 Editor shell: top bar, canvas (`ValueListenableBuilder<ui.Image?>`, fit/100 %/pinch/scroll zoom, pan), filmstrip, right develop panel (desktop) / bottom tool tabs (mobile). Widget test: opens a photo from the memory repo and shows a rendered frame.
- [ ] P3.7 `param_slider.dart` (centered zero, numeric field, double-click reset, keyboard nudge, accessible label/value, gesture transaction) + Light and Color sections wired to the editor notifier + history. Widget test: drag → one history entry; undo restores.
- [ ] P3.8 Histogram view + clipping toggle; before/after (split wipe, side-by-side, hold `\`). Widget tests.
- [ ] P3.9 Shortcuts (`app/shortcuts.dart`, ⌘ on Apple / Ctrl elsewhere): undo/redo, `\`, `A`, `R`, `E`, `J`, copy/paste settings, zoom. Widget test per shortcut.
- [ ] P3.10 Run on macOS and iOS simulator. Verify: `APP flutter run -d macos`, `flutter run -d "iPhone 17 Pro"` (manual smoke: import, open, slide, undo).

### Phase 4 — Features (3–4 sessions)
- [ ] P4.1 Remaining develop sections: HSL (band dots), tone curve editor (parametric sliders + draggable points per channel), color grading wheels, effects, detail, B&W mixer. Test `test/features/develop/every_param_test.dart`: for every `ParamId`, moving it to a non-default value changes the rendered pixels of the "all-features" synthetic scene (allow-list for documented no-ops: splits at default curve, grain size/roughness at amount 0, sharpen sub-params at amount 0, vignette sub-params at amount 0).
- [ ] P4.2 Geometry: crop overlay with aspect presets, straighten slider + drag-to-level, rotate/flip buttons; crop mode renders uncropped with overlay. Widget + engine tests.
- [ ] P4.3 `ai/auto_edit_service.dart`, Auto button, AI Styles panel (style tiles rendered on the user's photo), AI Amount, Explain list, badges. Tests with fake providers (local only; vision success; vision 422 → local + badge).
- [ ] P4.4 Prompt bar (offline lexicon now; vision hook in P5.6), suggestion chips, one history entry labeled with the instruction.
- [ ] P4.5 Presets panel (built-in + user, hover/tap preview on the canvas, amount, save dialog with group selection, rename/delete). Repository + widget tests.
- [ ] P4.6 Copy/paste settings dialog + sync to selection. Tests: groups respected, one entry per target.
- [ ] P4.7 Batch auto-edit service (concurrency 2 for local, 2 for vision, progress, cancel, per-photo failure isolation) + auto-edit-on-import. Test: 20 synthetic photos, cancel at 10 → 10 edited, 10 untouched.
- [ ] P4.8 Export dialog + export service + queue (single + batch, folder / share sheet / download, metadata option with GPS always stripped). Tests: file written, dims, quality, EXIF without GPS (`exif` re-read).
- [ ] P4.9 Thumbnail re-render on commit; library shows edited thumbs and "AI" badge.
- [ ] P4.10 Settings dialog (gateway URL with platform default `http://localhost:8080` / Android emulator `http://10.0.2.2:8080`, token, auto-edit on import, default style, export defaults).

### Phase 5 — Gateway (2 sessions)
- [ ] P5.1 `config.dart`, `app.dart`, middleware (request id, error envelope, CORS, auth, rate limit, body limit) with tests (`shelf` handlers called directly, fake clock).
- [ ] P5.2 `/v1/health`. Tests: no key → `visionAvailable:false`; key → true + model.
- [ ] P5.3 `prompt/system_prompt.dart` (role, slider dictionary from registry, workflow order, magnitude legend, taste rules, 9 style paragraphs, output contract, refine contract; `kPromptVersion`). Tests: byte-stable across runs; mentions every `aiEditable` id; ≥ 4096 tokens estimate (chars/3.5).
- [ ] P5.4 `claude/*` (request builder, client, response parser). Tests with `MockClient`: exact headers; body has `model`, `max_tokens`, cached system block, image-then-text order, `output_config.format.type == "json_schema"`, `output_config.effort`, `fallbacks:"default"`; **no** `temperature`/`tool_choice`/`thinking`; haiku model → no fallbacks/beta header; `stop_reason:"refusal"` → 422 with category; `max_tokens` → 502; non-JSON text → 502; `fallback` + `thinking` blocks skipped; 429 retried once honoring `retry-after`; 500 twice → 502; timeout → 504.
- [ ] P5.5 `/v1/auto-edit`, `/v1/instruct`, result cache, usage meter. Tests: out-of-range values clamped; same request twice → second `cached:true` and one upstream call; 413; 401 with token; 429 after burst.
- [ ] P5.6 App: `gateway_client.dart`, `vision_provider.dart`, `preview_encoder.dart`, `gatewayStatusProvider`, prompt bar vision path. Tests with a fake HTTP server (`shelf` in-process via `lumen_server.buildHandler` + mocked Claude) end-to-end from app code.
- [ ] P5.7 `server/README.md`, `Dockerfile` update (`dart compile exe`), `tool/smoke_vision.dart`. Verify (conditional on a key): `SRV ANTHROPIC_API_KEY=… dart run bin/server.dart & dart run tool/smoke_vision.dart`.

### Phase 6 — Polish and verification (2 sessions)
- [ ] P6.1 Integration tests `integration_test/app_flows_test.dart` (flows AC-27…AC-37 using an injected `ImportSource` with synthetic JPEG/PNG/WebP/HEIC fixtures generated at test start). Verify: `APP flutter test integration_test -d macos` and `-d "iPhone 17 Pro"`.
- [ ] P6.2 Performance pass: frame timing during slider drag on macOS (debug overlay logs p90 render ≤ 16 ms at 2560 px preview), memory check after opening 30 photos (image disposal counter = 0 leaks).
- [ ] P6.3 Accessibility: semantics labels on all sliders/buttons, focus traversal in the develop panel, contrast ≥ 4.5:1 for text tokens, reduced-motion respects `MediaQuery.disableAnimations`.
- [ ] P6.4 Builds: `flutter build macos --debug`, `flutter build ios --simulator --debug`, `flutter build apk --debug`, `flutter build web`. Optional: `.github/workflows/windows.yml` running `flutter build windows` on `windows-latest` (real Windows proof once the repo is on GitHub).
- [ ] P6.5 `README.md` (root): what it is, architecture diagram, prerequisites, run app per platform, run gateway with/without key, run all tests, troubleshooting (sandbox entitlements, Android emulator URL, HEIC on Windows). `docs/LICENSES.md` (every direct dependency, version, license; fonts OFL; research attributions: DNG SDK notice if any port lands, RAWmakase MIT attribution). `docs/MODEL_LICENSES.md` stub for Phase 2.
- [ ] P6.6 Run the full §9 checklist; record results with command output excerpts in `docs/PROGRESS.md`.

---

## 5. Acceptance criteria → see §9 (Definition of Done)

---

## 6. Testing strategy

### 6.1 Layers
| Layer | Where | Tool | Gate |
|---|---|---|---|
| Unit (core) | `packages/lumen_core/test` | `dart test` | **≥ 80 % line coverage** (`coverage` package → `coverage/lcov.info` → `tool/coverage_check.dart`) |
| Unit (server) | `server/test` | `dart test` + `MockClient` | every route and every error code has a test |
| Unit/widget (app) | `app/test` | `flutter test` | every feature folder has widget tests; providers overridden with memory repos and fake AI providers |
| Shader numeric | `app/test/engine` | `flutter test` (headless `flutter_tester` renders `FragmentProgram`s, verified) | parity vs CPU reference; behavior tests for spatial ops |
| Shader on device | `app/integration_test/engine_on_device_test.dart` | `flutter test integration_test -d macos / iPhone 17 Pro / emulator` | same parity thresholds on Metal and Vulkan/GLES |
| Goldens (UI only) | `app/test/goldens` | `matchesGoldenFile` with bundled fonts | library empty state, develop panel, editor desktop/mobile layouts; updated only deliberately (`--update-goldens` in a dedicated commit) |
| Integration flows | `app/integration_test/app_flows_test.dart` | `integration_test` | AC-27…AC-37 on macOS and iOS simulator |
| Architecture | `app/test/architecture_test.dart` | `flutter test` | platform-import rules, brand constant, no secrets |

### 6.2 Test doubles
- `FakeAutoEditProvider` (scripted outcomes, delays, errors), `MemoryCatalogRepository`, `FakeClock`, `FakeImportSource` (in-memory files), in-process gateway (`buildHandler` + `MockClient` Claude) for app↔server contract tests. No network in any automated test.

### 6.3 Shader parity thresholds
- Point ops: GPU vs `reference_pipeline` on the 6 synthetic scenes × 12 seeded random settings: **max |Δ| ≤ 3/255 per channel, mean ≤ 1/255**.
- Identity: all defaults → output equals sRGB input ±1/255.
- Spatial ops: behavior assertions (monotone response, no NaN/Inf, edge overshoot ≤ 5 %), not parity.

### 6.4 Synthetic scenes (`lumen_core/lib/src/testing/synthetic_scenes.dart`, deterministic, no downloads)
| Scene | Construction | Used by |
|---|---|---|
| `darkInterior` | low-key gradient room, median luma ≈ 0.10, 3 % crushed | exposure/shadows checks |
| `overexposedBeach` | median 0.85, 4 % clipped highlights | highlights/exposure down |
| `tungstenCast` | neutral scene × gains (1.35, 1.0, 0.65) | WB (temp < 0) |
| `daylightCoolCast` | gains (0.8, 1.0, 1.25) | WB (temp > 0) |
| `greenCast` | G × 1.2 | tint (magenta) |
| `hazyLandscape` | contrast-compressed, P0.5 = 0.2, airlight veil | blacks/contrast/dehaze |
| `wellExposedChart` | 24-patch chart incl. gray ramp and skin patches, median 0.46 | "don't wreck good photos", skin |
| `goldenHourPortrait` | warm cast + skin oval + bright sky | intentional cast kept |
| `noisyFlat` | mid-gray + seeded Gaussian noise σ = 6/255 | NR |
| `markerCorners` | asymmetric 4-corner colors + arrow | geometry |
| `allFeatures` | quadrants: ramps, saturated hues ring, skin, sky, texture, edges | every-param test |
Sizes: 512 px (core), 1024–3000 px (app), 6000×4000 (export). App tests encode them to JPEG/PNG/WebP with `package:image`; HEIC fixtures are produced on Apple platforms in the integration test via `platform_image_converter` or skipped with a logged reason elsewhere.

---

## 7. Packages
All licenses verified on pub.dev on 2026-10-03 (score tags). ✅ = commercial-safe permissive.

| Package | Version | License | Windows | Use | When |
|---|---|---|---|---|---|
| flutter_riverpod | ^3.4.3 | MIT ✅ | ✅ | state + DI | MVP |
| file_picker | ^13.1.0 | MIT ✅ | ✅ | import, save-folder picker | MVP |
| desktop_drop | ^0.8.4 | Apache-2.0 ✅ | ✅ (no iOS: guarded) | drag-and-drop | MVP |
| path_provider | ^2.1.6 | BSD-3 ✅ | ✅ (no web: memory repo) | app dirs | MVP |
| path | ^1.9.1 | BSD-3 ✅ | ✅ | paths | MVP |
| image | ^4.10.1 | MIT ✅ | ✅ pure Dart | export encode, test fixtures | MVP |
| exif | ^3.3.0 | MIT ✅ | ✅ pure Dart | EXIF read. ⚠️ last release 2023-10; small, stable; fork if it breaks | MVP |
| platform_image_converter | ^2.2.0 | MIT ✅ | ✅ (WIC; HEIF extension needed) | HEIC fallback (S3). FFI/JNI based, verify builds | MVP |
| share_plus | ^13.3.1 | BSD-3 ✅ | ✅ | mobile export share sheet | MVP |
| crypto | ^3.0.7 | BSD-3 ✅ | ✅ | SHA-256 asset ids, cache keys | MVP |
| uuid | ^4.6.0 | MIT ✅ | ✅ | preset/request ids | MVP |
| collection, meta | ^1.19.1 / ^1.19.0 | BSD-3 ✅ | ✅ | equality, annotations | MVP |
| http | ^1.6.0 | BSD-3 ✅ | ✅ | app→gateway, gateway→Claude, `MockClient` | MVP |
| shelf | ^1.4.2 | BSD-3 ✅ | ✅ | gateway | MVP |
| shelf_router | ^1.1.4 | Apache-2.0 ✅ | ✅ | routing | MVP |
| logging | ^1.3.0 | BSD-3 ✅ | ✅ | server logs | MVP |
| test, lints, flutter_lints, coverage | latest | BSD-3 ✅ | ✅ | dev only | MVP |
| integration_test, flutter_test | SDK | BSD-3 ✅ | ✅ | dev only | MVP |
| mocktail | ^1.0.5 | MIT ✅ | ✅ | dev only (sparingly; prefer fakes) | MVP |
| archive | ^4.3.0 | MIT ✅ | ✅ | ZIP for batch export on web | MVP (web only path) |
| flutter_onnxruntime | ^1.8.5 | MIT ✅ | ✅ CPU EP, fp32 models only; downloads ORT 1.23 zip at build | masks, inpaint, upscale | Phase 2 |
| gal | ^2.3.3 | BSD-3 ✅ | ✅ | save to Photos gallery | Phase 2 (share sheet suffices for MVP) |
| drift / sqlite3 | ^2.35.1 / ^3.7.0 | MIT ✅ | ✅ | catalog > 5k photos | Phase 3 |
| flutter_image_compress | ^2.5.1 | MIT ✅ | ❌ no Windows | faster platform JPEG | **Not used** (Windows gap); revisit behind `ImageEncoder` |
| heic2png | 0.1.1 | MIT | — | — | **Do not use: discontinued** |
| super_drag_and_drop | 0.9.1 | MIT | ✅ | richer DnD | Not needed |
Fonts: Geist (OFL-1.1), Instrument Serif (OFL-1.1), bundled as assets with license files. Anything GPL/AGPL/LGPL/non-commercial is banned from the app binary (see research 02 §10, 03 TL;DR); add a check to `tool/verify.sh` that greps `dart pub deps --json` licenses against an allow-list.

---

## 8. Scale-later notes (architected now, built later)
| Concern | Hook in the MVP | Later |
|---|---|---|
| Auth | gateway `auth.dart` middleware (bearer token), app `settings.json` token | Firebase Auth (email link + Google + Apple); ID-token verification in the gateway; user id keys rate limits/metering |
| Billing / credits | `UsageMeter` interface records `{user, route, model, tokens, cached, fallbackUsed}` per call; `PlanLimits` constants module in `lumen_core` (free: 25 AI edits/mo) | Stripe Checkout + Billing + Customer Portal, idempotent webhooks, Billing Meters for AI edits, $5/1,000 top-ups (04 §6.1); quota meter always visible |
| Cost control | result cache, effort `low`, 1024-px previews, local engine first | contact-sheet "anchor + propagate" calls, Batch API (−50 %, no `fallbacks` there), Haiku for bulk, per-user cost alerts |
| Cloud sync | repositories are interfaces; documents are small JSON; assets content-addressed | `SyncingCatalogRepository`: recipes + previews to Firestore/R2, originals optional with lifecycle rules |
| Privacy | only re-encoded 1024-px pixels + text facts leave the device; `ExifSummary` has no GPS/serial fields; export strips GPS always | DPA + subprocessor list, account deletion cascade, DSAR export; **never train on user photos/edits without explicit opt-in**; Learn-My-Style profiles are per-user data, deletable; no face recognition/grouping (BIPA) |
| EU AI Act Art. 50 | `HistoryEntry.kind` distinguishes parametric AI edits from (future) generative ones | generative Remove/expand writes C2PA Content Credentials + "AI-generated content" in export metadata; parametric slider edits are labeled "AI-assisted edit" in the Explain list |
| Licenses | `docs/LICENSES.md` + license allow-list check | `MODEL_LICENSES.md` per model (license, source, SHA-256, commercial OK), in-app "Acknowledgements" via `LicenseRegistry` |
| Observability | request ids, structured logs, latency + token usage per call | OpenTelemetry, error tracking (Sentry, opt-in), AI acceptance-rate metric (exported photos with ≤ small slider changes after AI) |
| Brand rename | `kBrand` constant; storage id independent of brand | change one constant + bundle ids/app names in platform folders |

---

## 9. Definition of Done (gates the completion promise)
Every item must be **verified in the same iteration** that outputs the promise, with the command output recorded in `docs/PROGRESS.md`.

**Build and quality**
1. [ ] `cd packages/lumen_core && dart test` passes.
2. [ ] `lumen_core` line coverage ≥ 80 %: `dart run coverage:test_with_coverage && dart run tool/coverage_check.dart coverage/lcov.info 80` exits 0.
3. [ ] `cd server && dart test` passes.
4. [ ] `cd app && flutter test` passes (unit, widget, shader numeric, goldens, architecture).
5. [ ] `dart analyze` (core, server) and `flutter analyze` (app) report **0 issues** (errors, warnings and infos).
6. [ ] `dart format --output=none --set-exit-if-changed .` exits 0.
7. [ ] `flutter build macos --debug` succeeds.
8. [ ] `flutter build ios --simulator --debug` succeeds.
9. [ ] `flutter build apk --debug` succeeds.
10. [ ] `flutter build web` succeeds.
11. [ ] Windows safety: `flutter analyze` clean (it analyzes Windows-only code too) **and** `test/architecture_test.dart` passes (no `dart:io` outside `*_io.dart`; every plugin used is listed with Windows support in §7 or guarded by `platformInfo`).
12. [ ] `flutter test integration_test -d macos` passes.
13. [ ] `flutter test integration_test -d "iPhone 17 Pro"` passes.

**Engine correctness**
14. [ ] Shader parity (§6.3) passes in `flutter test` **and** on macOS + iOS simulator; exposure +1 EV maps 128 → 176 (±1).
15. [ ] Export: a 6000×4000 synthetic exports to JPEG q90 at 6000×4000 and decodes; "long edge 2048" gives 2048×1365; center crop of the export matches the preview render (scaled) with mean |Δ| ≤ 3/255; PNG export decodes losslessly equal to the tiled render.
16. [ ] Histogram of a known 4-color image matches expected bin counts exactly.

**Local engine (unit tests on 512-px synthetic scenes, CPU reference render; all deterministic)**
17. [ ] `darkInterior` (median luma 0.10): after Auto Natural, median luma ∈ **[0.38, 0.55]** and clipped pixels ≤ 0.5 %.
18. [ ] `overexposedBeach` (median 0.85, 4 % clipped): median ∈ [0.50, 0.72], `highlights < 0`, clipped ≤ 1 %.
19. [ ] `tungstenCast`: `temp < 0` and |log2(R/B) cast| reduced by ≥ 50 % on neutral patches; `daylightCoolCast`: `temp > 0`; `greenCast`: `tint > 0`.
20. [ ] `hazyLandscape`: `blacks < 0`, `contrast > 0`, `dehaze > 0`, σ(L*) after ≥ 1.4 × before.
21. [ ] `wellExposedChart`: |exposure| ≤ 0.15 EV, |temp| ≤ 5, |tint| ≤ 5 ("doesn't wreck good photos").
22. [ ] Idempotence: running Auto on an already-auto-edited render yields |Δexposure| ≤ 0.10 EV and |Δtemp| ≤ 3.
23. [ ] `goldenHourPortrait`: WB strength reduced (warm cast kept: temp correction ≤ 50 % of full neutralization); vibrance ≤ 20 (skin protection).
24. [ ] Styles: on `darkInterior`, median luma ordering Moody < Natural < Clean & Bright; B&W sets `treatment = bw`; all 9 styles produce pairwise-different settings.
25. [ ] Lexicon: ≥ 40 phrase tests pass, including "a bit warmer" → temp +7.5 ±0.5, "make it moodier and lift the shadows" → moody atom + shadows > 0, "less contrast" never below the pre-instruction baseline, "exposure +0.5" → +0.5 exactly.

**AI and gateway**
26. [ ] No key: `GET /v1/health` → `visionAvailable:false`; the app shows "Basic auto (offline)" and Auto, Styles, prompt bar, batch all work (integration test with the gateway stopped).
27. [ ] Gateway tests with mocked Claude cover: request shape (model default `claude-opus-5-5`, `output_config.format` json_schema, explicit `effort`, `fallbacks:"default"` + beta header, no temperature/tool_choice/thinking), refusal → 422 → app falls back to local, `max_tokens` → 502, malformed JSON → 502, clamping, 401, 413, 429, cache hit.
28. [ ] App↔gateway contract test (in-process server + mocked Claude): vision result becomes editable sliders with a reason per change in the Explain list, one history entry, AI Amount works.
29. [ ] **Conditional (only when a real key is provided):** `tool/smoke_vision.dart` returns 200 with ≥ 3 adjustments on `darkInterior`, median luma after applying ∈ [0.30, 0.60], second identical call reports cache hit or `cacheReadTokens > 0`. Otherwise recorded as "not run: no key".

**User flows (integration tests on macOS and iOS simulator + a manual pass on the running macOS app, screenshots saved under `docs/verification/`)**
30. [ ] Import JPEG, PNG, WebP and HEIC via picker (macOS + iOS) and drag-and-drop (macOS) → entries appear with thumbnails; re-importing the same file does not duplicate.
31. [ ] One-click Auto and each of the 9 styles apply; one undo reverts each.
32. [ ] Prompt "warmer and brighten the shadows a bit" (offline) → temp > 0 and shadows > 0, one history entry labeled with the text.
33. [ ] Every develop control changes the render (`every_param_test`), including crop/straighten/rotate/flip, HSL, curves, grading, effects, detail.
34. [ ] Before/after split wipe, side-by-side (desktop) and hold-to-compare show the unedited image.
35. [ ] 50 edits → undo all → settings equal the initial state; redo all → equal the final state; state survives an app restart.
36. [ ] Presets: 12 built-ins apply; a saved user preset persists across restart; amount 50 % gives values halfway.
37. [ ] Copy/paste (group-filtered) and sync to 5 selected photos work, one history entry per photo.
38. [ ] Batch auto-edit of 20 photos completes with progress; cancel stops further work; the UI stays interactive (analysis runs in isolates).
39. [ ] Export single and batch (10 photos) to a folder on macOS and via share sheet on iOS; GPS absent in exported EXIF.

**Docs and hygiene**
40. [ ] Root `README.md` has working run instructions for app (macOS, iOS sim, Android, Windows, web), gateway (with and without key) and all tests; `docs/LICENSES.md` lists every direct dependency with license; license allow-list check passes.
41. [ ] The brand string appears only in `brand.dart` (architecture test); no secrets in the repo (`git grep -nE "sk-ant-[A-Za-z0-9]"` returns nothing).
42. [ ] `docs/PROGRESS.md` lists every item above with its verification result.

---

## 10. Risks and mitigations
| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | Float render targets unsupported on some backend | Med / High | Design never needs them: one float uber pass; aux in 8-bit with 16-bit RG packing (S4) |
| R2 | Packed textures sampled with filtering → garbage | High if ignored / High | Rule: packed = `FilterQuality.none` + manual bilinear in `common.glsl`; unit test per packed texture |
| R3 | Shader compile limits / GLES differences on Android (uniform count, samplers, uv flip, constant loops) | Med / Med | ≤ 5 samplers, 94 floats, constant-bound loops, no derivatives/bools/uints; S5 spike on emulator early (P2.13) |
| R4 | `flutter_tester` (Skia path) vs device (Impeller Metal/Vulkan) render differences | Med / Med | Same parity suite runs on device in `integration_test` (AC-14) |
| R5 | Large images on mobile (OOM) | Med / High | Preview ≤ 2048, aux at 512, tiled export, 24 MP default export cap on mobile, 8192 source cap on Android/Windows, single-owner `ui.Image` disposal with leak counter |
| R6 | Pure-Dart JPEG encode is slow (24 MP: seconds) | High / Low | Isolate + progress; `ImageEncoder` interface allows platform encoders later (not `flutter_image_compress`: no Windows) |
| R7 | HEIC: engine codec gaps; Windows needs HEIF extension | Med / Med | S3 spike; `platform_image_converter` fallback; clear error with a store link on Windows |
| R8 | EXIF orientation not applied by the codec | Med / Med | S2 spike; `geometry.baseOrientation` fallback |
| R9 | ONNX on Windows (no DirectML in the downloaded zip, fp32 only) and min-OS bumps | High / Med | Deferred to Phase 2; CPU EP + fp32 files; capability gating; features degrade, editing never depends on ML |
| R10 | Local engine taste is heuristic | High / Med | Measurable gates (AC-17…25), constants in one file, vision overrides, Phase 2 eval harness with licensed real photos + AI acceptance-rate metric |
| R11 | Claude: latency, refusals, schema compile latency on first call, overshoot | Med / Med | Local result shown first; `fallbacks:"default"`; refusal → local; clamp + damping + guards; cache; effort `low` |
| R12 | macOS sandbox blocks network/files | High if missed / High | P0.4 entitlements; README troubleshooting |
| R13 | Android emulator can't reach `localhost` gateway; cleartext blocked | High / Low | Platform default `10.0.2.2`, debug-only cleartext |
| R14 | Windows untestable on this Mac | Certain / Med | Architecture test, analyzer, conditional imports, optional GitHub Actions Windows build (P6.4) |
| R15 | Atomic rename semantics differ on Windows | Med / Med | `atomicWrite` with delete-then-rename fallback + test |
| R16 | JSON catalog slows past thousands of photos | Low (MVP) / Med | Index loaded once, per-asset docs lazy; drift migration behind the repository |
| R17 | `exif` package unmaintained since 2023 | Low / Low | Wrapped by `exif_reader.dart`; fork or swap without touching callers |
| R18 | Riverpod major-version churn | Low / Low | Pin `^3.4.3`, no codegen, providers centralized in `app/providers.dart` |
| R19 | Brand/trademark conflict | Certain / Med | `kBrand` constant, storage id decoupled from brand |
| R20 | License contamination (GPL/AGPL/NC models or code) | Low / High | Allow-list check in `tool/verify.sh`; clean-room rule for RapidRAW/darktable; MODEL_LICENSES.md before any model ships |

---

## 11. Iteration protocol (for the Ralph loop)
1. Read `docs/PROGRESS.md` and this plan; pick the first unchecked task in phase order.
2. Write the test first; run it red; implement; run it green; run `bash tool/verify.sh`.
3. Commit (`feat|fix|test|chore: …`), tick the box here, append a line to `PROGRESS.md` with the verification command and result.
4. If a spike fails, take its fallback, note the decision in `PROGRESS.md`, and continue. Do not change §9 thresholds without writing down why.
