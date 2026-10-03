# 05 — UI References (Mobbin) & Design Synthesis

Mobbin has no web Lightroom screens. It does have Canva's photo editor plus several dark pro editors, and those are what this uses. Lightroom conventions come from domain knowledge (Develop module: histogram → Basic → Tone Curve → HSL → Color Grading → Detail → Effects → Optics).

## References pulled

| # | App | What we take from it | Link |
|---|-----|----------------------|------|
| 1 | Canva: Image edit panel | Left flyout with "Select area: All / Click / Brush" mask chips, then **Magic Studio** tiles (BG Remover, Magic Eraser), **Filters** strip with thumbnails, **Effects** | https://mobbin.com/screens/b0142fb1-2e36-4eaf-91d4-f446e665a5ae |
| 2 | Canva: Adjust panel | Big gradient **Auto-adjust** button at top. Grouped sliders (White balance → Temperature/Tint, Light → Brightness/Contrast/Highlights/Shadows) with a numeric box beside each. **Reset adjustments** pinned at bottom | https://mobbin.com/screens/49e77586-4ecb-4b2e-9496-7ae7ddcfab72 |
| 3 | Canva: Duotone presets | Grid of preset thumbnails rendered *on the user's own photo* | https://mobbin.com/screens/1265af1b-2b5e-42ed-93d2-0d27e227471b |
| 4 | Canva: shell | Icon rail (Design, Elements, Uploads, Tools, Apps, Magic Media) + flyout + canvas, floating contextual toolbar pill above the canvas, zoom slider + page count bottom-right | https://mobbin.com/screens/b0142fb1-2e36-4eaf-91d4-f446e665a5ae |
| 5 | Canva: Uploads | Uploads panel: primary "Upload files" button and grid of uploads | https://mobbin.com/screens/3cfc4c71-7380-4557-b850-fde27d0a90c6 |
| 6 | VSCO (iOS): HSL | Row of 6–8 **color dots** that select the band, with Hue/Sat/Lightness sliders tinted per color | https://mobbin.com/screens/9b5f4b29-caa9-4443-a8dd-2900a717dd19 |
| 7 | Telegram (web): photo edit | Dark right-hand slider column (Enhance, Brightness, Contrast, Saturation, Warmth, Fade, Highlights, Shadows, Vignette, Grain). Value shown top-right of each row, slider centered at 0 | https://mobbin.com/screens/d21a9252-e0f8-439c-a8df-dcd5a6abb83f |
| 8 | Shopify: image editor | Dark canvas with collapsible accordion tool cards on the right (Crop and transform, Resize, Draw, Generate). Discard/Save top-right | https://mobbin.com/screens/4fe0e77a-a75a-4842-8a99-9d1fad49c360 |
| 9 | Magnific: editor | Dark shell, **bottom filmstrip** of pages, zoom % slider, Export primary button top-right | https://mobbin.com/screens/785a97bc-8cad-4e40-80d0-20dce043bd40 |
| 10 | Krea AI: edit | **Prompt bar docked under the image** ("change the water with mud") + Generate button, with variant thumbnails at the side | https://mobbin.com/screens/b55a031a-39e5-4150-b48d-16b86a67625e |
| 11 | Magnific: image editor | Prompt composer floating under the photo, with an Auto mode dropdown and send button | https://mobbin.com/screens/4a86b072-64cb-4f18-a63d-dd16759b2ff6 |
| 12 | Visual Electric | Right rail of AI tool rows (Retouch, Upscale, Remove Background), each a single click | https://mobbin.com/screens/1cf6ee4c-a1d5-4eca-aa46-47bff3f74029 |
| 13 | Higgsfield: gallery | Dark masonry library, selection checkboxes, **floating batch-action bar** at the bottom ("1 selected · Download · Add to · Delete") | https://mobbin.com/screens/f6ecfe4d-bc8e-4946-b561-281becc37ef0 |
| 14 | Later: media library | Grouping by date ("Today", "Last 7 days") with a filter sidebar | https://mobbin.com/screens/272cbc05-555c-43ba-bdff-bbea6e5af7b6 |
| 15 | Cosmos: select | Floating pill: "4 Selected · Subcollection · Organize · Remove · Done" | https://mobbin.com/screens/ca5fc71d-56ce-4486-934a-586bbbefa500 |

## Design synthesis for Lumen

**Direction:** "Darkroom editorial". The editor is a neutral graphite workspace, because a neutral surround keeps color judgement honest (Lightroom does the same). The accent is a warm *safelight amber*. AI actions carry a signature gradient (amber → rose) so users learn that "gradient = AI did this". The library and marketing surfaces use an editorial serif for display moments.

### Editor layout (desktop ≥1024px)
```
┌──────────────────────────────────────────────────────────────────────────┐
│ ◧ Lumen  /  IMG_2041.jpg      ↶ ↷    [◐ Before/After]   [Export ▾]       │  top bar (48px)
├──┬──────────────┬──────────────────────────────────────────┬─────────────┤
│▣ │ Flyout panel │      floating context pill: Crop·Flip·…  │ Histogram   │
│✦ │ (Canva-style │                                          │ ─────────── │
│◑ │  contextual: │              PHOTO CANVAS                │ ✦ Auto (AI) │
│◎ │  AI styles / │        (WebGL, zoom/pan, split           │ Light  ▾    │
│⌫ │  Masks /     │         before/after slider)             │ Color  ▾    │
│▤ │  Presets /   │                                          │ Effects ▾   │
│⇪ │  Remove …)   │  ┌────────────────────────────────────┐  │ Detail ▾    │
│  │              │  │ ✦ Describe an edit… "golden hour"  │  │ Optics/Geo ▾│
│  │              │  └────────────────────────────────────┘  │ [Reset]     │
├──┴──────────────┴──────────────────────────────────────────┴─────────────┤
│ filmstrip ▢▢▢▢▢▢▢▢                                      zoom ─●── 86%    │
└──────────────────────────────────────────────────────────────────────────┘
```
- **Left icon rail** (Canva): Library, AI Studio (styles + prompt history), Masks, Presets, Crop/Geometry, Remove (object/background), Export.
- **Left flyout** opens per rail item; collapsible.
- **Right develop panel** (Lightroom): histogram, AI Auto button, accordion groups (Light, Color incl. HSL color dots, Effects, Detail, Curve, Color grading). Each slider has a numeric field and resets on double-click. Panel switches to edit the active mask's local adjustments when a mask is selected.
- **Prompt bar** (Krea/Magnific) floats under the photo for natural-language edits. Each edit becomes slider deltas and is shown as an undoable history step.
- **Bottom bar**: filmstrip of the current library selection, zoom control, and the compare mode toggle.

### Library layout
- Large drop zone hero when empty: "Drop your photos. We'll edit them. You stay in control."
- Masonry/justified grid grouped by import date; hover shows an "Edited by AI" badge and a before/after scrub.
- **Floating batch bar** on selection (Higgsfield/Cosmos): `n selected · ✦ Auto-edit all · Apply preset · Sync settings · Export · Delete`.

### Tokens (draft)
- Surfaces: `--bg 0.16 L graphite`, `--panel`, `--panel-2`, `--line`. Light theme for library is optional; dark is the default for color-accurate editing.
- Accent: safelight amber `oklch(80% 0.16 70)`. AI gradient: `linear-gradient(135deg, oklch(82% 0.15 75), oklch(68% 0.2 15))`.
- Type: **Geist** (UI, tabular numerals for slider values) and **Instrument Serif** (display: library hero, empty states, marketing).
- Motion: 150ms ease-out for controls, 300ms expo for panels. Before/after uses a clip-path wipe (compositor-only).

### Interaction principles
1. **AI first, control always.** Every AI result is a set of visible slider values plus masks, never a baked pixel blob (except generative remove/upscale, which are separate layers and can be undone).
2. One click to a great edit: upload → auto-edit starts immediately (opt-out toggle).
3. Prefer direct manipulation: drag on the canvas for before/after, scroll to zoom, double-click a slider to reset.
4. Keyboard: `\` before/after, `Cmd+Z` undo, `R` crop, `A` auto, `M` masks, `E` export, `Cmd+Shift+C/V` copy/paste settings.
