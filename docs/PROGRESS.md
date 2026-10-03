# Lumen: Progress Log

## Status: feature-complete MVP, verified on macOS + iOS simulator; all builds green

### History (condensed)
- **Research** (5 subagents): AI auto-edit, editor engine, on-device AI, market, UI references (Mobbin) → `docs/research/`
- **Plan + design** (2 subagents): `docs/PLAN.md` (architecture, 42-item Definition of Done), `docs/DESIGN.md` ("Darkroom editorial")
- **User directive:** one codebase for macOS, iOS, Android and Windows, so the stack moved from Next.js to **Flutter 3.47 + Dart workspace** (`app/`, `packages/lumen_core/`, `server/`)
- **Build:** parallel workstreams (render engine, auto-edit engine, gateway) plus the app UI, integrated and verified on the iOS simulator and macOS. Bugs found by live testing were fixed with regression tests: typing vs. shortcuts, thumbnail race, isolate capture, reason accuracy, style-preview race, export dialog overflow, folder drops.

## Definition of Done (PLAN.md §9): final verification run (2026-10-03)

Commands are run from the repo root unless noted. `bash tool/verify.sh` ends with **ALL CHECKS PASSED**.

| # | Item | Result | Evidence |
|---|---|---|---|
| 1 | `lumen_core` tests | ✅ 361 passed | `dart test` |
| 2 | core coverage ≥ 80 % | ✅ **96.0 %** (3329/3469) | `tool/coverage_check.dart` |
| 3 | server tests | ✅ 74 passed | `dart test` |
| 4 | app tests | ✅ 101 passed | `flutter test` (UI, repositories, GPU parity, export, architecture, layout) |
| 5 | analyzers: 0 issues | ✅ core, server, app | `dart analyze --fatal-infos` ×2, `flutter analyze` |
| 6 | format clean | ✅ | `dart format --set-exit-if-changed` |
| 7 | macOS build | ✅ | `flutter build macos --debug` |
| 8 | iOS simulator build | ✅ | `flutter build ios --simulator --debug` |
| 9 | Android APK | ✅ | `flutter build apk --debug` |
| 10 | Web build | ✅ | `flutter build web` |
| 11 | Windows safety | ✅ | `flutter analyze` + `test/architecture_test.dart`: no `dart:io`/`dart:isolate` outside `*_io.dart`, `Platform.is` only in `platform_info_io`, every plugin supports Windows, Win32 window 1440×900 |
| 12 | integration on macOS | ✅ | `app_flows_test` (+1), `engine_on_device_test` (+33), `drag_drop_test` (+1) |
| 13 | integration on iOS simulator | ✅ | `app_flows_test` (+1), `engine_on_device_test` (+33) |
| 14 | shader parity: tester + macOS + iOS; +1 EV maps 128 → 176 | ✅ | `test/engine/*` and `integration_test/engine_on_device_test.dart` on Metal (macOS, iOS) |
| 15 | export 6000×4000 JPEG q90; long edge 2048 → 2048×1365; PNG lossless; matches preview (mean ≤ 3/255) | ✅ | `engine_on_device_test` "full-size export" |
| 16 | histogram exact on a 4-colour image | ✅ | `test/analysis/histogram_test.dart` |
| 17 | darkInterior: median 0.098 → **0.467**, clipped 0.23 % | ✅ | `local_auto_tone_test` |
| 18 | overexposedBeach: median 0.854 → **0.539**, clipped 3.99 % → 0 %, highlights −19.7 | ✅ | same |
| 19 | casts: tungsten temp −100 (−92 % cast); cool temp +61; green tint +44.8 | ✅ | same |
| 20 | hazy: blacks −24.5, contrast +40, dehaze +30, σ(L*) ×1.72 | ✅ | same |
| 21 | well-exposed chart: exposure 0.00, temp 0, tint 0 | ✅ | same |
| 22 | idempotence: max Δexposure 0.047 EV, Δtemp 0 | ✅ | same (7 scenes without a deliberate cast) |
| 23 | golden hour: temp −21.5 vs −69.2 (31 %), vibrance 20 | ✅ | same |
| 24 | styles: Moody 0.328 < Natural 0.467 < Clean & Bright 0.593; B&W sets bw; 9 pairwise different | ✅ | `local_provider_test` |
| 25 | lexicon ≥ 40 phrases (73 + 4 named checks) | ✅ | `lexicon_test` |
| 26 | no key / no gateway: `visionAvailable:false`; "Basic auto (offline)"; Auto, styles, prompt, batch work | ✅ | `gateway_contract_test` (health), `app_flows_test` (badge + flows without gateway) |
| 27 | gateway with mocked Claude: request shape, refusal 422, max_tokens 502, malformed 502, clamp, 401, 413, 429, cache | ✅ | `server/test/**` |
| 28 | app ↔ gateway contract: vision → editable sliders + reasons, one history entry, AI amount | ✅ | `app/test/ai/gateway_contract_test.dart` |
| 29 | real-key smoke test | ⏸ **not run: no API key** (conditional item) | `ANTHROPIC_API_KEY=… dart run tool/smoke_vision.dart` |
| 30 | import JPEG/PNG/WebP/HEIC; dedupe; drag-and-drop (macOS) | ✅ | `app_flows_test` (5 formats + dedupe, macOS + iOS); `drag_drop_test` (file + folder via native channel); real iOS photo picker used manually |
| 31 | Auto + each of 9 styles apply; one undo reverts | ✅ | `batch_sync_export_test` (9 styles); manual on iOS (Moody) |
| 32 | prompt "warmer and brighten the shadows a bit" offline → temp↑ shadows↑, one labelled entry | ✅ | `app_flows_test` |
| 33 | every develop control changes the render | ✅ | `test/engine/every_param_test.dart` (80 params + crop/straighten/rotate/flip/bw/4 curves) |
| 34 | split wipe, side by side, hold-to-compare | ✅ | `app_flows_test` (BEFORE/AFTER chips) + screenshots |
| 35 | 50 edits undo/redo exact; survives restart | ✅ | `history_test`; `app_flows_test` reopen |
| 36 | 12 built-ins; saved preset persists; amount 50 % halfway | ✅ | `document_test`, `repositories_test` |
| 37 | copy/paste groups; sync to 5 photos, one entry each | ✅ | `batch_sync_export_test`, `editor_controller_test` |
| 38 | batch auto-edit 20 photos with progress + cancel, UI responsive (isolates) | ✅ | `batch_sync_export_test` |
| 39 | export to folder (desktop) + share sheet (iOS); GPS absent | ✅ | `batch_sync_export_test` (folder, no overwrite, GPS stripped); manual iOS share sheet (2.2 MB JPEG) |
| 40 | README, LICENSES, allow-list check | ✅ | `README.md`, `docs/LICENSES.md`, `tool/check_licenses.dart` (122 packages, 0 problems) |
| 41 | brand only via `kBrand`; no secrets | ✅ | `architecture_test`; secrets scan in `verify.sh` |
| 42 | this table | ✅ | |

Screenshots: `docs/verification/` (desktop library, editor, prompt, compare, crop).

## Known limitations / next steps (Phase 2, per PLAN §3.2)
- AI masks (subject/sky, gradients), object removal, upscale (ONNX on-device): interfaces are designed and the schema reserves `masks`.
- Bundle the Geist/Instrument Serif font files. Platform fonts are used until then.
- Local engine speed is about 0.7 s per photo (runs in an isolate); target 0.3 s.
- Windows: code is analyzer- and architecture-clean but has not been built on Windows hardware (no Windows machine here). An optional CI `windows-latest` build is recommended.
- Vision quality tuning requires a real Anthropic key and the eval set described in research 01 §9.
