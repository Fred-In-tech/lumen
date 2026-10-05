# Auto Enhance and Auto Retouch on a real photo: what is wrong (2026-10-04)

Test photo: the user's own Canon R5 RAW (two women, deep skin tones, warm tungsten room light, makeup with strong highlight on forehead and nose, faces about 15% of the frame width, a third face in a mirror). Not stored in the repo. Method: `app/integration_test/zz_retouch_diag_test.dart` (temporary) dumped the editor frame for each state and the frames were compared pixel by pixel and by eye.

## Auto Retouch
1. **Retouch is not drawn when a photo opens already retouched.** With auto-edit on import, the photo opens with retouch values set and the retouch maps built (2 faces, 1366x2048 maps), yet the frame is byte-identical to the frame with no retouch. It appears only after the next settings change. This alone explains "it doesn't work".
2. **Pressing Auto Retouch after Reset all sets nothing.** The portrait settings come back empty (most likely the "values set by hand are locked" rule treats the reset as hand edits). To the user the button does nothing.
3. **The automatic values are too timid to see.** Once drawn, the auto values (softening 22, even 13, shine 33, ...) change 1,812 of 4.4 million pixels, by at most 22/255. The obvious problem in this photo, hot shine on forehead, nose and cheek, is untouched.
4. **At full strength the mask edge shows.** With sliders at 100 a lighter patch with a hard edge appears where the skin mask crosses the hairline and jaw, and shine is still barely reduced.
5. **101 "blemishes" were detected on two made-up faces with clean skin.** The detector is firing on makeup texture, lashes or pores. Healing that many spots on clean skin risks smearing.
6. Tuning so far used drawn faces with light skin only. Deep skin tones, makeup and specular highlights were never tested.

## Auto Enhance
Values chosen: temp −40, tint −12, contrast −20, highlights −29, shadows +18, whites +35, blacks −6, vibrance +20.
1. **White balance is neutralised.** The warm room light is corrected all the way to neutral, so skin loses its warmth and the scene its mood. A professional would correct part of the cast and check the result against skin, not grey.
2. **Contrast −20 flattens the picture** while whites +35 pushes the bright curtain and the lamp further towards clipping.
3. Nothing is face-aware: exposure and colour are solved from whole-image statistics, so the bright background drives the result and the skin is an afterthought.

## What the rebuild must prove
- On this photo: retouch visible on first open; shine reduced on forehead and nose with skin texture kept; no visible mask edge at any strength; nothing done to lashes, brows, lips, hair or the earring; teeth and eyes not glowing.
- Auto Enhance keeps the warm mood (partial WB), keeps skin rich rather than grey or orange, protects the white curtain and lamp, and does not lower contrast on an already soft scene.
- The same checks on light skin, on a face without makeup, on a group, and on a non-portrait scene.

## Status of the Auto Retouch items after the rebuild (2026-10-04, retouch engine v2)

Evidence: `app/integration_test` on the real GPU with the same RAW (temporary diagnostic, not committed), `docs/PHASE2.md` "Retouch engine v2", and the tests named below.

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Retouch not drawn when a photo opens already retouched | **Fixed** | Root cause: `RenderGraph.render` calls interleaved. While the frame waited for the retouch map upload, style-preview thumbnails rendered other tone settings and disposed the graph's single LUT texture; the frame's develop pass threw "Image has been disposed" and the frame was dropped. Renders of one graph now queue. First settled frame = the frame after re-committing the same settings (max difference 0), and differs from the un-retouched frame in 20,157 px. Test: `app/test/engine/render_graph_concurrency_test.dart`. |
| 2 | Auto Retouch after Reset all sets nothing | **Fixed** | With the real `Reset all` the values were set (the reset entry releases the locks); the diagnostic had reset with a slider-kind commit. The same dead button did happen whenever a value was put back to 0 by hand: that locked it at 0. A hand edit back to the default now releases the value, and the button always reports what it did (applied to n faces / nothing to change / hand-set values kept / no faces / failure). Tests: `manualPortraitLocks` in `lumen_core/test/auto/retouch_needs_test.dart`, three widget tests in `app/test/features/portrait_panel_test.dart`. |
| 3 | Automatic values too timid to see | **Fixed** | Auto on this photo: softening 40, even 8, shine 65 (was 22 / 13 / 33). 25,771 px change by more than 2/255 (was 1,812), up to 58/255. Forehead highlight L 0.835 → 0.754. |
| 4 | Mask edge shows at full strength; shine barely reduced | **Fixed** on this photo and on the synthetic set | New pixel-driven masks, masked band blurs, deltas added instead of blurs blended. Every slider at 100: no edge found by eye at 2× and 3× on either face; halo metrics 0.000 L* outside the hairline on all three synthetic tones. Shine 100: forehead L 0.835 → 0.718, nose tip 0.773 → 0.738. |
| 5 | 101 "blemishes" on two clean made-up faces | **Fixed** | 7 candidates (3 kept as freckle-like, 1 mole, 3 dark marks that only heal from slider 30); Auto sets Acne to 0 on this photo. Synthetic precision 1.0, recall 1.0 on every tone. |
| 6 | Only tuned on drawn light-skinned faces | **Partly fixed** | The evaluation set now has light, medium and deep skin with highlights, shimmer, pimples and moles, and the real deep-skin photo was the primary tuning case. Still open: no real light or medium skin photo, no elderly face, beard, glasses or child was available. |

"What the rebuild must prove", retouch part: visible on first open (yes); shine reduced on forehead and nose with texture kept (yes; the small hard highlight on the nose tip is reduced less than the forehead patch); no visible mask edge at any strength (none found); nothing done to lashes, brows, lips, hair or the earring (unchanged in every strip); teeth and eyes not glowing (Auto sets teeth whitening to 4 and brightness to 0 on this photo; eye work is off on the closed eyes). Light skin, a face without make-up and a group were checked on synthetic faces only; the non-portrait RAW (no faces) gets the "No faces found" toast path.
