# Lumen: Progress Log

## Current phase: 1. Research → 2. Plan → 3. Build → 4. Verify

### Iteration 1 (2026-10-03)
- [x] Ralph loop initialized (completion promise: "LUMEN APP COMPLETE AND READY FOR TESTING")
- [x] UI reference research via Mobbin → `docs/research/05-ui-references.md`
- [x] Ideation → `docs/IDEAS.md`
- [x] Claude API integration approach confirmed (TS SDK `messages.parse` + `zodOutputFormat`, model `claude-opus-5-5`, explicit effort, `fallbacks: "default"`, local auto-tone fallback when no key)
- [x] 04 market research done (Lumen name has a USPTO conflict, so "Lumen" stays an internal codename; candidates Dialed / Halfstop / Zone Five)
- [x] **User directive (mid-iteration 1): must run on macOS, iOS, Android, Windows. Switched from Next.js to Flutter 3.47 + Dart workspace**: `app/` (Flutter), `packages/lumen_core/` (pure Dart core), `server/` (Dart shelf AI gateway holding the Claude key)
- [x] Research 01–05 complete; `docs/PLAN.md` (architecture, phases, 42-item DoD) and `docs/DESIGN.md` (design system) written by planning subagents
- [x] Spike: Flutter FragmentProgram works in headless `flutter test` with exact pixel readback (128→176 at +1 EV)
- [x] Phase 0 hygiene (strict analysis, entitlements, Android debug cleartext)
- [x] lumen_core model layer (TDD): color, ParamRegistry (80 params), DevelopSettings, curves, geometry, history (patch undo/redo), EditDocument + migrations, presets (12 built-in), copy/paste groups, catalog entry
- [x] Gateway workstream (subagent): shared API contract + Dart shelf server, 74 server tests + 32 API tests
- [x] App: tokens/theme, repositories (file+memory, atomic writes), import pipeline, library screen, editor controller, develop panel (all groups), crop, AI panel, prompt bar, styles, presets, copy/paste/sync, batch auto-edit, export, settings
- [ ] Render engine workstream (subagent): reference pipeline done; GPU shaders + RenderScheduler in progress
- [ ] Auto-edit workstream (subagent): analysis/atoms/styles done; LocalAutoEditProvider + lexicon + guards in progress

## Next steps
1. Integrate GPU renderer (RenderScheduler) behind `PhotoRenderer` (CPU renderer is the fallback) and GPU export.
2. Integrate LocalAutoEditProvider; run full test suites; fix analyzer issues across workstreams.
3. Run on macOS + iOS simulator; screenshot verification; integration tests; builds (apk, web).
4. README + LICENSES; walk the §9 Definition of Done.

## Environment notes
- Flutter 3.47.2 / Dart 3.13.2, Xcode 26.6, Android SDK 36, iPhone 17 Pro simulator booted. Windows can't be built on this Mac, but the code targets it. Apple M1 Max. ~30 GB free disk, so keep model downloads small.
- No ANTHROPIC_API_KEY in env, so the app must work fully with the local auto-tone engine.
- Test photos: system wallpapers are graphics, not photos. Need permission to download a few CC0/Unsplash-license sample photos, or generate synthetic test scenes.
