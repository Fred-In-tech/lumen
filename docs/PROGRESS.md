# Lumen: Progress Log

## Current phase: 1. Research → 2. Plan → 3. Build → 4. Verify

### Iteration 1 (2026-10-03)
- [x] Ralph loop initialized (completion promise: "LUMEN APP COMPLETE AND READY FOR TESTING")
- [x] UI reference research via Mobbin → `docs/research/05-ui-references.md`
- [x] Ideation → `docs/IDEAS.md`
- [x] Claude API integration approach confirmed (TS SDK `messages.parse` + `zodOutputFormat`, model `claude-opus-5-5`, explicit effort, `fallbacks: "default"`, local auto-tone fallback when no key)
- [x] 04 market research done (Lumen name has a USPTO conflict, so "Lumen" stays an internal codename; candidates Dialed / Halfstop / Zone Five)
- [x] **User directive (mid-iteration 1): must run on macOS, iOS, Android, Windows. Switched from Next.js to Flutter 3.47 + Dart workspace**: `app/` (Flutter), `packages/lumen_core/` (pure Dart core), `server/` (Dart shelf AI gateway holding the Claude key)
- [ ] Research subagents still running: 01 AI auto-edit, 02 editor engine (asked to add Flutter FragmentShader section), 03 AI tools (asked to add Flutter ONNX section)
- [ ] Planner synthesis → `docs/PLAN.md` (architecture, phases, acceptance criteria)

## Next steps
1. Wait for the 4 research reports in `docs/research/`.
2. Planner/architect subagents synthesize → `docs/PLAN.md` with acceptance criteria.
3. Build lumen_core first (recipe model + color math + auto-tone, TDD with `dart test`), then the Flutter shader pipeline.

## Environment notes
- Flutter 3.47.2 / Dart 3.13.2, Xcode 26.6, Android SDK 36, iPhone 17 Pro simulator booted. Windows can't be built on this Mac, but the code targets it. Apple M1 Max. ~30 GB free disk, so keep model downloads small.
- No ANTHROPIC_API_KEY in env, so the app must work fully with the local auto-tone engine.
- Test photos: system wallpapers are graphics, not photos. Need permission to download a few CC0/Unsplash-license sample photos, or generate synthetic test scenes.
