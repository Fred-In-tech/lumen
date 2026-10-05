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
