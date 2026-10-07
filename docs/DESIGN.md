# Lumen: Design Spec ("Darkroom editorial")

> **Status:** v1 spec, 2026-10-03. Implement directly. When a value here disagrees with older drafts (`research/05-ui-references.md` § Tokens), this file wins.
> **Brand name:** "Lumen" is an internal codename (trademark conflict, see `research/04-market.md` §4.2). Every user-visible occurrence reads from one constant, `Brand.name` in `app/lib/core/brand.dart`. Never hard-code the word in widgets, copy or assets.
> **Platforms:** macOS, Windows, iOS, Android from one Flutter 3.47 codebase. Phone and desktop layouts are both first-class. Neither is a scaled copy of the other.
> **ICP:** semi-pro "side-hustle" shooters (portraits, families, small events, product work; 100–800 photos per shoot). They know what good looks like, they don't want to learn Lightroom, and batch consistency matters more to them than single-photo magic.

---

## 0. Studio redesign (2026-10-04): read this first

The user asked for a lighter, simpler look after using the app. Where this section disagrees with the rest of the file, this section wins. Everything it does not mention (components, microcopy, accessibility, motion) still applies.

**References (Mobbin):** Krea AI's enhance editor and Magnific's skin enhancer for the look (soft grey workspace, white floating panel, pill toolbar, one blue action colour); Apple Photos for the "Auto first" order of tools.

**Look: "Studio" (light).** `LumenTokens.light` is the default theme; `LumenTokens.dark` keeps the darkroom palette for a later appearance setting.

| Token | Value | Use |
|---|---|---|
| surface0 | `#F3F3F1` | workspace behind the photo, card wells |
| surface1 | `#FFFFFF` | panels, raised pills |
| surface2 / surface3 | `#EFEFEC` / `#E4E4E0` | tracks, wells, hover |
| line / lineStrong | `#E6E6E3` / `#D0D0CB` | hairlines |
| text | `#161616` / `#55554F` / `#74746D` | primary / secondary / tertiary |
| accent | `#2563EB` | the one action colour: primary button, slider fill, active tool |
| AI gradient | `#7C3AED` → `#5B4FE9` → `#2563EB` | only on things a model decides (same rule as §7) |

- The histogram keeps a dark well so the additive RGB curves stay readable.
- Tooltips and toasts are dark on the light theme.
- Shadows are soft (`Elevation.e1`–`e3`); panels are white cards with a 16px radius floating on the workspace.

**Flow: two modes.** One `Auto | Manual` pill at the top centre of the editor (`editorModeProvider`), on phone just above the sheet.

- **Auto** (default): the panel holds three numbered cards and nothing else: 1 Enhance (one button, an amount slider, "why" collapsed), 2 Retouch (Auto Retouch, with a link to fine-tune faces), 3 Looks (style tiles). The prompt bar floats under the photo. No histogram, no sliders.
- **Manual**: histogram, then six tool tabs (Adjust, Portrait, Masks, Remove, Crop, Presets), then only that tool's controls. The left rail and the AI Studio / Presets flyouts are gone; Crop and Presets are tabs. No AI block sits on top of the sliders.
- Shortcuts that start a Manual tool (M, Q, R) and controls found through search move the editor to Manual; "Auto edit" in search moves it to Auto. Going back to Auto puts crop, masks, portrait and remove tools away.

**Portrait panel.** Auto Retouch is the first thing in the panel. Under it: face status, "Apply to" (All / Female / Male / Child / Senior / Individual), then four parts shown one at a time (Skin, Face, Shape, Scene) in place of one list of eleven groups:

| Part | Groups |
|---|---|
| Skin | Skin, Blemishes, Wrinkles |
| Face | Eyes, Teeth, Makeup |
| Shape | Face shape, Liquify |
| Scene | Background swap, Background, Clothing |

### Home and projects (2026-10-07)

The app opens on **Home**, not on the photo grid. Same Studio look: grey workspace, white floating cards (`Rad.lg`, `Elevation.e1`), one blue action colour, serif for page titles and section heads only, Lucide icons. Imagen's home page was the reference for the structure, not the look (no dark theme).

- **Shell:** a left rail (84 px, white, hairline right edge) with icon + label tiles: Home, Projects, All photos, Looks, and Settings at the bottom; the selected tile is `accentTint` with `accent` icon and label. On macOS the rail starts below the window buttons. Under 600 px: a bottom tab bar (Home, Projects, Import, Settings) and no rail. A 2 px progress line runs along the top while an import or a batch edit works.
- **Home (desktop, content ≥ 1080 px):** main column + a 320 px side column. Main: the date (micro caps) and the **Import** button; a hero card (one slide at a time, dots and arrows, never auto-advancing) with a serif headline, one sentence and one primary button that does the thing (Import RAW photos, Retouch a portrait, Cull a shoot) beside a painted illustration (no fake screenshots, no numbers); **Active projects** (dashed "New project" card first, then project cards, unfinished first, Unsorted last, a fade at the right edge); **Looks & presets** (dashed "Create a preset", then the user's presets and the AI styles, each with "Use on a project…"). Side column: "Welcome back" (with the Settings name: "Welcome back, Sam") and a status line, **This week** (imported, edited, exported in the last 7 days), Auto-edit on import with its switch, and quick links (Import a shoot, Quick start guide, Check for updates, Send feedback). Narrower: the greeting moves to the top and the side column goes under the main one. A new library shows one welcoming import card instead of empty rows.
- **Project card:** a cover mosaic (cover large, two more photos), name, shoot date · count, the five-step stepper (ticked when done, a partial arc while under way, dashed ring when there is nothing to do, the connector lit as far as the steps are done in a row, the current step's label in `accent`), and the next step as a full-width secondary button. Hover lifts 2 px with `e2`. Right-click or "…": Open, Rename, Set cover, Delete. Files dragged over it turn the edge `accent` and drop into that project.
- **Projects page:** breadcrumb, serif title, count, New project; pill search field and Sort (Recent, Name, Date); a grid of cards with the dashed New project card first and Unsorted last.
- **Project page:** breadcrumb (Home › Projects › Name), title with "…" menu, date · count, Add photos and Export picks (Export all when nothing is picked); a white progress panel with each step's count line ("38 of 120 edited") and the next step as the primary button; then the familiar grid with a flat cull strip aligned to the page margin. Phones: the compact stepper and the current step's count line.
- **Import destination dialog:** three option cards with a radio dot: New project (name field prefilled "12 Oct 2026 · IMG_4021", focused), Add to a project (dropdown, only when projects exist), Unsorted; the primary button names the count ("Import 120 photos").
- **Delete project dialog:** two choices that name the count ("Keep the 120 photos": they move to Unsorted; "Delete the 120 photos too": red edge), and the danger button says what will happen ("Delete project and 120 photos").
- **Screenshots:** `docs/verification/projects/`.

---

## 1. Principles and visual direction

### 1.1 Five principles
1. **The photo is the loudest thing on screen.** Chrome is neutral graphite (R=G=B, zero chroma) so color judgement stays honest. Saturated color in the chrome means *state* (active, AI, error), never decoration.
2. **AI shows its work.** Every AI decision lands as a visible slider value with a one-line reason. Nothing is a black box, and nothing is baked into pixels you can't get back.
3. **Gradient = a model looked at your photo.** The amber→rose gradient is reserved for decisions made by a model (LLM or on-device neural net). It's a learned signal, so it has to stay scarce (§7).
4. **Direct manipulation first, numbers always.** Drag on the canvas, drag the histogram, scrub a slider. A typed numeric field is always one click away. Double-click resets anything.
5. **Pro density, not pro intimidation.** Lightroom's depth and Lightroom's group order, but with progressive disclosure: Light and Color are open by default, everything else stays one click away.

### 1.2 Visual direction: "Darkroom editorial"
- **Workspace:** a graphite darkroom. Panels are stacked tonal planes (surface 0→3), separated by hairlines and light, not by heavy borders or Material elevation tint.
- **Accent:** *safelight amber* `#FEA92F`, the only "UI color". It marks the active tool, slider fill, selection and the primary button.
- **AI signature:** a 3-stop gradient, amber `#FCB442` → coral `#FF894B` → rose `#F45693`. Think of it as a darkroom safelight bleeding into a print.
- **Type pairing:** **Geist** for all UI (precise, neutral, tabular numbers). **Instrument Serif** for editorial moments only: library date headers, empty states, onboarding, export-complete. Serif never appears inside the editor's working chrome.
- **Atmosphere:** a 2% film-grain noise texture on empty states and onboarding backgrounds only. Never in the editor, where it would contaminate color judgement.
- **Photos:** square corners and no shadow on the editor canvas, because the photo's real edge matters. Library tiles get a 4px radius.

### 1.3 Anti-template rules (enforced in review)
| Banned | Use instead |
|---|---|
| Material ripples and ink splashes | `splashFactory: NoSplash.splashFactory`, plus custom hover/pressed overlays (§2.4) |
| Elevation surface tint (M3 `surfaceTintColor`) | Explicit surface levels 0–3, with `surfaceTintColor: Colors.transparent` everywhere |
| Default `Slider`, `Switch`, `Checkbox`, `NavigationBar`, `FloatingActionButton`, `AppBar` visuals | Custom `LumenSlider`, `LumenToggle`, `LumenCheck`, `ToolTabs`, `TopBar` (§4) |
| Uniform 8px radius on everything | The radius ladder in §2.8, chosen per component |
| `Icons.*` (Material icons) and `cupertino_icons` | `lucide_icons_flutter` only (§2.11). CI greps for `Icons.` and `CupertinoIcons.` |
| Gray-on-white defaults, purple "AI" gradients | Graphite plus amber, with the amber→rose gradient used only per §7 |
| Centered-hero + gradient-blob empty states | An editorial serif headline, left-aligned on desktop, with a real drop zone |

---

## 2. Tokens

Implement as one `ThemeExtension<LumenTokens>` (colors, gradient, radii, spacing, motion, shadows) in `app/lib/design/tokens.dart`, with typography in `app/lib/design/type.dart`. Widgets read tokens and never use literal values.

### 2.1 Color: Editor dark theme (default and only editor theme)

**Surfaces (strictly neutral, R=G=B)**
| Token | Hex | Use |
|---|---|---|
| `surface0` | `#111111` | App background, canvas surround (default), behind everything |
| `surface1` | `#181818` | Docked panels: rail, flyout, develop panel, top bar, filmstrip, phone tool tabs |
| `surface2` | `#212121` | Raised inside panels: inputs, value fields, hovered rows, dialogs, phone sheets |
| `surface3` | `#2A2A2A` | Floating: prompt bar, batch bar, toasts, popovers, menus, tooltips |
| `line` | `#2E2E2E` | Hairlines: panel edges, dividers, accordion separators |
| `lineStrong` | `#3D3D3D` | Input borders, slider track, unselected chip borders, grid lines |
| `scrim` | `#000000` @ 55% (desktop) / 45% (phone) | Behind dialogs and sheets |

**Canvas surround** (user setting, View menu / `Shift+B` cycles it):
| Option | Hex | Note |
|---|---|---|
| Graphite (default) | `#111111` | = `surface0` |
| Black | `#000000` | Night work, high-key photos |
| Mid grey 18% | `#777777` | Print-proofing reference |

**Text**
| Token | Hex | On `surface1` | Use |
|---|---|---|---|
| `textPrimary` | `#EDEDED` | 15.2:1 | Titles, values, active labels, slider thumb |
| `textSecondary` | `#A3A3A3` | 7.0:1 | Slider labels at default, body copy, inactive tabs |
| `textTertiary` | `#8A8A8A` | 5.1:1 | Meta (EXIF, counts, hints). **Not on `surface3`** (4.2:1); use secondary there |
| `textDisabled` | `#595959` | 2.5:1 | Disabled only (exempt from contrast). Always paired with a reason in a tooltip |
| `textOnAccent` | `#1A1206` | 9.6:1 on accent | Text and icons on amber fills and on the AI gradient (≥5.8:1 at the rose end) |

**Semantic**
| Token | Hex | Contrast on `surface1` | Use |
|---|---|---|---|
| `accent` | `#FEA92F` | 9.2:1 | Active tool, slider fill, selection ring, primary button fill, links |
| `accentHover` | `#FFBE5C` | – | Primary button hover |
| `accentPressed` | `#E78C08` | – | Primary button pressed |
| `accentTint` | `#FEA92F` @ 14% | – | Selected row, chip and rail-item backgrounds |
| `focusRing` | `#81B4F6` | 8.3:1 | **Keyboard focus only.** It's cool blue on purpose, so *focused* (blue) never reads as *selected* (amber) |
| `danger` | `#F75E51` | 5.6:1 | Errors and destructive actions. Always with an icon (`triangleAlert`) plus text, never as a gradient |
| `success` | `#52CD86` | 8.8:1 | Export complete, saved. Icon plus text |
| `warning` | `#E7B643` | – | Clipping warnings, low-credit notices |
| `offline` | `textSecondary` on `surface2` | – | "Basic auto (offline)" badge. Neutral on purpose: offline is a mode, not an error |

**AI gradient** (`aiGradient`)
| Stop | Position | Hex | OKLCH source |
|---|---|---|---|
| Amber | 0.0 | `#FCB442` | `oklch(82% 0.15 75)` |
| Coral | 0.5 | `#FF894B` | `oklch(76% 0.17 45)` |
| Rose | 1.0 | `#F45693` | `oklch(68% 0.20 0)` |

- Direction: `begin: Alignment(-1, -1)`, `end: Alignment(1, 1)` (135°).
- `aiGlow`: `#FF894B` @ 35%, blur 24, used only behind the AI Auto button while it is working.
- The rose end sits at hue 0 (pink-rose), well away from `danger` (vermilion, hue ~28). A gradient is AI; a flat red with ⚠ is an error.

### 2.2 Color: Light "Paper" theme (Library only, opt-in)
**Decision:** dark ships everywhere by default. Settings → Appearance → *Library: Dark / Light / Match system* (default **Dark**). The editor, crop and export preview **always stay dark**.
**Why:** the library is for browsing, culling and sharing, often on a phone outdoors or while showing clients, where a light surface reads better. Color *judgement* happens in the editor, which needs the neutral dark surround. Making light opt-in avoids a jarring dark↔light flash when the default user moves from library to editor.

| Token | Hex | Notes |
|---|---|---|
| `surface0` | `#F4F4F3` | Page |
| `surface1` | `#FFFFFF` | Top bar, section backgrounds |
| `surface2` | `#ECECEA` | Inputs, hovered tiles |
| `surface3` | `#FFFFFF` + e2 shadow | Batch bar, menus, toasts |
| `line` | `#DEDEDB` | |
| `textPrimary` | `#141414` | 16.7:1 |
| `textSecondary` | `#55554F` | 6.8:1 |
| `textTertiary` | `#6B6B65` | 4.9:1 |
| `accent` (fills) | `#FEA92F` + `textOnAccent` | Same amber fill |
| `accentInk` (text and icons) | `#A75C00` | 4.6:1. Amber text on light needs the darker ink |
| `focusRing` | `#2769B7` | 5.0:1 |
| `danger` | `#C93029` | 4.9:1 |
| AI gradient | unchanged; text on it stays `textOnAccent` | |

### 2.3 Data colors (sliders, HSL, histogram)
**Colored slider tracks** (painted at 70% opacity across the full track; no accent fill; a zero tick marks neutral):
| Slider | Left → right |
|---|---|
| Temperature | `#3D7BD9` → `#E8E8E8` (center) → `#E8C547` |
| Tint | `#3FAE5A` → `#E8E8E8` → `#C24FC0` |
| HSL Hue (per band) | band's −30° neighbor → band color → band's +30° neighbor |
| HSL Saturation | `#808080` → band color |
| HSL Luminance | band color @ 25% L → band color @ 85% L |
| Color-grade Luminance | `#000000` → `#FFFFFF` |

**HSL bands (8 dots)**
| Band | Hex | | Band | Hex |
|---|---|---|---|---|
| Red | `#E5484D` | | Aqua | `#3CC7C2` |
| Orange | `#F2994A` | | Blue | `#3D7BD9` |
| Yellow | `#F2D74A` | | Purple | `#8E5BD9` |
| Green | `#5BBF5B` | | Magenta | `#D94FAE` |

**Histogram:** R `#FF5A5A`, G `#5AD17A`, B `#5A8CFF`, each @ 55% with additive blending (overlaps read as cyan/magenta/yellow/white). Luminance fill `#8A8A8A` @ 35%. Shadow clipping overlay on canvas `#3D7BD9`, highlight clipping `#FF3B30` (Lightroom convention).

**Mask overlay:** default `#FF2E63` @ 45%; user-selectable (rose, green `#3BD16F`, blue `#3D8BFF`, white).

### 2.4 State layers (dark theme; light theme uses `#000000` at the same %)
| State | Treatment | Duration |
|---|---|---|
| Hover | `#FFFFFF` @ 5% overlay | 90ms linear in, 150ms out |
| Pressed | `#FFFFFF` @ 9% overlay; buttons also `scale 0.97` | 90ms |
| Selected | `accentTint` background + `accent` icon/text (+ icon switches to the `…500` stroke weight) | 150ms |
| Focused (keyboard only, `FocusHighlightMode.traditional`) | 2px `focusRing`, 2px offset, radius = component radius + 2 | 0ms (instant) |
| Dragging | Slider thumb grows 12→16px; the value text turns `textPrimary` | 90ms |
| Disabled | Content @ 38% opacity, no hover, `SystemMouseCursors.forbidden` | – |

Cursors (desktop): `click` on buttons, `resizeLeftRight` on slider tracks, `grab`/`grabbing` on a zoomed canvas, `precise` in crop and brush, `text` in value fields.

### 2.5 Typography

**Families (verified 2026-10-03)**
| Family | Source / license | Availability |
|---|---|---|
| **Geist** (UI) | Vercel, SIL OFL 1.1 | Google Fonts ✓ (`fonts.googleapis.com/css2?family=Geist` resolves). `google_fonts` 9.0.0 exposes `GoogleFonts.geist()` (requires Flutter ≥3.47 ✓) |
| **Geist Mono** (EXIF, keycaps, file names) | Vercel, SIL OFL 1.1 | Google Fonts ✓, `GoogleFonts.geistMono()` ✓ |
| **Instrument Serif** (display) | Instrument, SIL OFL 1.1 | Google Fonts ✓ (regular + italic), `GoogleFonts.instrumentSerif()` ✓ |

**Decision: bundle as assets, don't fetch at runtime.** It's an offline-first desktop/mobile app, so no first-paint font swap and no network call at launch.
- Bundle `Geist-{Regular,Medium,SemiBold}.ttf`, `GeistMono-{Regular,Medium}.ttf` and `InstrumentSerif-{Regular,Italic}.ttf` under `app/assets/fonts/`, declared in `pubspec.yaml` `fonts:`. Total ≈ 650 KB.
- Ship `app/assets/fonts/OFL.txt` and register it with `LicenseRegistry.addLicense` so it shows in Settings → About → Licenses. Record it in `docs/LICENSES.md`.
- Optional: keep `google_fonts` as a dependency with `GoogleFonts.config.allowRuntimeFetching = false`. It then resolves the bundled files by name.
- Only weights 400/500/600 are used. Never 700+; heavy weights look cheap at UI sizes on dark backgrounds.

**Numbers:** every numeric readout (slider values, zoom %, counts, EXIF, export size) uses `fontFeatures: [FontFeature.tabularFigures()]`, so values don't jitter while dragging. Add a golden test asserting equal advance widths for `0–9` in Geist `tnum`. If that test fails on any platform, switch value styles to Geist Mono 500. Signed values use a true minus `−` (U+2212) and an explicit `+`.

**Scale** (desktop ≥1024 / touch <1024; tracking in % of size)
| Token | Family | Desktop size/line | Touch size/line | Weight | Tracking | Use |
|---|---|---|---|---|---|---|
| `displayXL` | Instrument Serif | 56/60 | 40/44 | 400 | −1% | Onboarding hero, empty library headline |
| `display` | Instrument Serif | 36/40 | 30/34 | 400 | −0.5% | Export complete, secondary empty states |
| `titleSerif` | Instrument Serif | 24/28 | 22/26 | 400 | 0 | Library date headers ("Today", "Sep 28") |
| `title` | Geist | 16/22 | 17/22 | 600 | −0.5% | Dialog and sheet titles, flyout titles |
| `heading` | Geist | 13/18 | 15/20 | 600 | 0 | Accordion headers, section titles |
| `body` | Geist | 13/18 | 15/21 | 400 | 0 | Default text, AI explanations |
| `bodyStrong` | Geist | 13/18 | 15/21 | 500 | 0 | Emphasis, menu items |
| `label` | Geist | 12/16 | 13/18 | 500 | +0.5% | Slider labels, chip labels, small buttons |
| `button` | Geist | 13/16 | 15/20 | 600 | 0 | Buttons |
| `value` | Geist `tnum` | 12/16 | 14/18 | 500 | 0 | Slider values, zoom %, counts |
| `caption` | Geist | 11/14 | 11/13 | 500 | +2% | Badges, tab labels, filmstrip meta, timestamps |
| `micro` | Geist | 10/12 | 10/12 | 600 | +8%, UPPERCASE | Canvas "BEFORE"/"AFTER" chips only |
| `mono` | Geist Mono | 11/14 | 12/16 | 400 | 0 | EXIF line, file names, keycaps |

Editorial rule: one italic word per serif headline at most ("Your photos, *developed*."). Serif text is never under 22px.

### 2.6 Spacing (4-pt base with 2/6 half-steps)
`sp0_5 = 2`, `sp1 = 4`, `sp1_5 = 6`, `sp2 = 8`, `sp3 = 12`, `sp4 = 16`, `sp5 = 20`, `sp6 = 24`, `sp8 = 32`, `sp10 = 40`, `sp14 = 56`, `sp20 = 80`

Rhythm rules (deliberately not uniform):
- Panel inner padding is 16 horizontal and 12 vertical. Slider rows inside a group are separated by 4. **Sub-groups** (e.g. White balance | Tone | Presence) are separated by 16 plus a hairline.
- Accordion headers sit flush, separated only by `line`. Open groups add 4 top and 16 bottom.
- The canvas gets 24 padding on desktop and 8 on phone.
- In the library grid, the gap between tiles is 4 (desktop) / 2 (phone). Date sections are separated by 40 (desktop) / 24 (phone), so tiles group tightly and sections breathe.

### 2.7 Layout constants
| Constant | Value |
|---|---|
| Top bar height | 48 desktop / 44 + safe area phone |
| Left rail width | 56 |
| Flyout width | 280 |
| Develop panel width | 320 (1024–1439) / 352 (≥1440) |
| Filmstrip height | 88 (thumb 64) |
| Phone tool tabs height | 64 + bottom safe area |
| Phone slider sheet | 40% of screen height, min 248, max 420 |
| Prompt bar | height 48, width clamp(360, 60% canvas, 600) |
| Min canvas width (desktop) | 480. Below that, the flyout overlays instead of pushing |
| macOS title bar | Traffic lights live inside the top bar: reserve 78px leading inset when `TitleBarStyle.hidden` |
| Windows title bar | Native caption buttons: reserve 138px trailing inset if a custom title bar is used |

### 2.8 Radii (non-uniform by intent)
| Token | Value | Applies to |
|---|---|---|
| `rNone` | 0 | Photo on the canvas (always), crop frame, histogram plot area |
| `rXs` | 3 | Filmstrip thumbs, value fields, keycaps, mini badges |
| `rTile` | 4 | Library tiles, style thumbnails |
| `rSm` | 6 | Buttons, inputs, tooltips, rail item highlight, menu items |
| `rMd` | 10 | Popovers, menus, toasts, cards inside flyouts, AI explanation card |
| `rLg` | 14 | Prompt bar, desktop dialogs |
| `rXl` | 16 | Batch bar |
| `rSheet` | 20 (top corners only) | Phone bottom sheets |
| `rPill` | 999 | Status pills (AI status, offline badge), suggestion chips, HSL dots, AI badge circle |

### 2.9 Elevation (dark: light plus shadow; no Material tint)
| Level | Surface | Border / highlight | Shadow (`BoxShadow` list) | Used by |
|---|---|---|---|---|
| e0 | `surface0` | none | none | App background, canvas |
| e1 | `surface1` | 1px `line` on the edge facing the canvas | none | Docked panels, top bar, filmstrip |
| e2 | `surface3` | 1px top highlight `#FFFFFF` @ 6% (`Border(top: …)`) + 1px `#000000` @ 40% outline | `(0,1) blur 2 #000@40%`, `(0,12) blur 32 #000@45%` | Prompt bar, batch bar, toasts, popovers, overlay flyout |
| e3 | `surface2` | 1px top highlight `#FFFFFF` @ 6% | `(0,24) blur 64 #000@60%` + `scrim` | Dialogs, phone sheets |

Light theme: e2 = `(0,1) blur 2 #000@6%`, `(0,8) blur 24 #000@10%`; e3 = `(0,24) blur 64 #000@16%`.

### 2.10 Motion
| Token | Duration | Curve | Use |
|---|---|---|---|
| `instant` | 0ms | – | Focus ring, slider value text while dragging |
| `micro` | 90ms | `Curves.linear` | Hover and pressed overlays |
| `fast` | 150ms | `Cubic(0.2, 0, 0, 1)` (standard) | Toggles, chips, selection, chevrons, toast out |
| `base` | 220ms | `Cubic(0.16, 1, 0.3, 1)` (expo-out) | Accordion expand, tooltip in, toast in (+8px rise) |
| `panel` | 300ms | expo-out | Flyout slide (16px + fade), panel show/hide, crop mode enter |
| `slow` | 450ms | expo-out | Onboarding steps, export-complete |
| `develop` | 600ms per slider, 35ms stagger, total cap 1200ms | expo-out | AI values arriving (§3.8) |
| `shimmer` | 1400ms loop | linear | Thumbnails and panels waiting on AI |
| `sheet` | spring (mass 1, stiffness 420, damping 38) | `SpringSimulation` | Phone sheets: open, drag and fling |

- Animate only opacity, transform and clip (`FadeTransition`, `SlideTransition`, `ScaleTransition`, `ClipRect` with an animated rect). The before/after wipe is a clip, never a re-layout.
- The before/after wipe follows the pointer 1:1 with no easing. Toggling the split mode animates the divider 220ms expo-out.
- **Reduced motion** (`MediaQuery.disableAnimations` OR Settings → *Reduce motion: System / On / Off*, needed because desktop OS flags aren't reliably surfaced): every duration becomes 0, except opacity crossfades, which become 120ms. The develop-in becomes one 150ms crossfade, shimmer becomes a static "Editing…" label, and the sheet spring becomes a 150ms fade.

### 2.11 Icons
**Package: `lucide_icons_flutter` 3.1.21.** The Flutter wrapper is MIT and upstream Lucide is ISC. Both are commercial-safe; record them in `docs/LICENSES.md`.
- Why Lucide over `phosphor_flutter` (MIT, 2.1.0, last major in 2023): Lucide's package is actively released, its stroke style matches Geist's geometry, and it ships **stroke-weight variants** (`LucideIcons.crop`, `.crop300`, `.crop500`…), which we use for selected states.
- Sizes: 16 (inline, in rows), 18 (desktop rail, top bar), 22 (phone tool tabs, phone top bar). Default stroke is the base variant (400). The selected/active state uses the `…500` variant. Never mix weights in one row except for active versus inactive.
- Remove `cupertino_icons` from `app/pubspec.yaml`. Set `uses-material-design: false` once no Material icon widgets remain.
- **AI glyph:** `LucideIcons.sparkles` filled with `aiGradient` through `ShaderMask`. This is the only place the sparkles icon appears.

| Concept | Icon | | Concept | Icon |
|---|---|---|---|---|
| Library | `layoutGrid` | | Undo / Redo | `undo2` / `redo2` |
| AI Studio / AI | `sparkles` (gradient) | | Compare | `squareSplitHorizontal` |
| Presets | `swatchBook` | | History | `history` |
| Masks | `scanFace` | | Reset | `rotateCcw` |
| Crop / Geometry | `crop` | | Group visibility | `eye` / `eyeOff` |
| Remove (later) | `eraser` | | Import | `imagePlus` |
| Export | `share` | | Offline | `cloudOff` |
| Brush / Linear / Radial | `paintbrush` / `rectangleHorizontal` / `circleDashed` | | Error | `triangleAlert` |
| Pick from photo | `pipette` | | Success | `circleCheck` |
| Rotate / Flip | `rotateCw` / `flipHorizontal2` | | Settings / Help | `settings` / `circleHelp` |
| Aspect | `ratio` | | More | `ellipsis` |

---

## 3. Screens and layouts

### 3.0 Breakpoints
| Class | Width | Composition |
|---|---|---|
| **Phone** | < 600 | Canvas on top, tool tabs at the bottom, slider sheet, prompt as a sheet. Library is a 3-column square grid |
| **Tablet** | 600–1023 | Portrait: phone composition with a larger canvas and a 4–5 column grid. **Landscape ≥ 840**: canvas plus a docked right develop panel (300), tool tabs become a 56px left rail, no flyout (rail items open as popovers) |
| **Desktop** | ≥ 1024 | Full shell: top bar, rail, flyout, canvas, develop panel, filmstrip. 1024–1279: the flyout **overlays** the canvas (e2). ≥ 1280: the flyout **docks** and pushes the canvas |
| **Wide** | ≥ 1440 | Develop panel 352; library rows target 220px tall |

Input mode is decided separately from width. Use `PointerDeviceKind` to choose touch sizing (44+ targets) on an iPad with no trackpad, and compact sizing with a mouse.

### 3.1 Library: empty state (first run, desktop)
```
┌────────────────────────────────────────────────────────────────────────────────┐
│ Lumen                                                       ⚙   [ + Import ]   │ 48 top bar, serif wordmark 20
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│   Your photos,                                                                 │ displayXL, left-aligned,
│   developed.                                                                   │ 80px from left edge
│                                                                                │
│   AI makes the first edit. Every change stays a slider.                        │ body 15, textSecondary
│                                                                                │
│   ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐   │ drop zone: 1.5px dashed
│        ⊕  Drop photos or a folder here                                         │ lineStrong, rMd, h=280,
│   │       JPEG · PNG · WebP · HEIC · RAW previews                         │   │ surface1 + grain 2%
│           [ Choose photos ]   or  Try a sample photo →                         │
│   └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘   │
│   ☑ Auto-edit photos when I import them                                        │ LumenCheck, default ON
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```
- **Drag-over state:** the whole window is a drop target. The dashed border becomes solid 2px `accent`, the zone fills `accentTint`, and the label changes to "Drop to import 24 photos" (count from the drag payload when the platform exposes it).
- **Phone:** headline `displayXL` 40/44 top-left at 24 inset, the drop zone becomes a full-width tappable card (h 200) with "Choose from Photos" (primary) and "Try a sample photo" (text button). Photo-library permission is asked only on tap (just-in-time), never at launch.
- "Try a sample photo" loads a bundled CC0 portrait so the first AI edit can happen in under 10 seconds.

### 3.2 Library: grid, selection and batch bar
**Desktop**
```
┌────────────────────────────────────────────────────────────────────────────────┐
│ Lumen   All · AI edited · Not edited      ⌕ Search      ▭─●─▭ size  [ + Import ]│
├────────────────────────────────────────────────────────────────────────────────┤
│  Today  ·  48 photos                                            Select all     │ titleSerif + caption tertiary
│  ┌──────────┐┌─────────────┐┌──────┐┌──────────────┐┌──────────┐               │ justified rows, target h 200
│  │☐         ││             ││      ││ ✦ Editing…   ││          │               │ gap 4, rTile
│  │        ✦ ││           ✦ ││    ✦ ││ ░░shimmer░░  ││     ⧉    │               │ ✦ = AI badge (bottom-right)
│  └──────────┘└─────────────┘└──────┘└──────────────┘└──────────┘               │ ⧉ = manual-edit badge
│  Sep 28  ·  212 photos                                                         │
│  ┌────────┐┌──────────┐┌──────────────┐┌─────────┐┌──────────┐                 │
│  │■ ✓     ││■ ✓       ││☐             ││■ ✓      ││☐         │                 │ ■ selected: 2px accent ring
│  └────────┘└──────────┘└──────────────┘└─────────┘└──────────┘                 │ inset, tile scales 0.96
│                                                                                │
│        ╭────────────────────────────────────────────────────────────────╮      │ batch bar e2, rXl, h 52
│        │ 3 selected │ ✦ Auto-edit all │ Apply preset │ Sync │ Export │ ⋯ │ ✕ │      │ bottom 24, centered
│        ╰────────────────────────────────────────────────────────────────╯      │
└────────────────────────────────────────────────────────────────────────────────┘
```
- **Grouping:** by capture date (EXIF `DateTimeOriginal`), falling back to import date. Headers are "Today", "Yesterday", then "Sep 28" (current year) or "Sep 28, 2025". Headers stick to the top while scrolling (`SliverPersistentHeader`, `surface0` @ 92% + 12px backdrop blur).
- **Tile hover (desktop):** after a 400ms dwell, horizontal pointer position scrubs a before/after wipe (left of pointer = before) with a 1px white divider. The badge expands into a pill reading "Edited by AI" or "Edited". A checkbox fades in top-left (20px, `rSm`).
- **Badges** (bottom-right, 20px circle, `#000` @ 55% backdrop):
  - AI-edited, untouched by the user: gradient sparkles 12px.
  - AI-edited and then adjusted by the user: gradient sparkles + 1px white ring ("yours now").
  - Manual only: `slidersHorizontal` 12px in `textPrimary`.
  - Not edited: no badge.
- **Selection:** click the checkbox, `Cmd/Ctrl`-click, `Shift`-click for a range, drag-marquee on empty space, `Cmd/Ctrl+A`. Selected tiles scale 0.96 and get a 2px `accent` inset ring plus a check on an amber 20px circle. `Esc` clears.
- **Batch bar:** appears when ≥1 selected, sliding up 16px + fading in 220ms. Order: count · **✦ Auto-edit all** (AI button, small) · Apply preset ▾ · Sync settings · Export · ⋯ (Copy settings, Paste settings, Remove from library [danger]) · ✕.
- **Phone:** 3-column square grid, 2px gap. Pinch changes columns 2↔3↔5. Long-press enters selection mode; then tap toggles and drag-paints a selection. The top bar swaps to "3 selected · Select all · Done". The batch bar docks above the home indicator (full width − 16, `rXl`) with 4 actions, each an icon over a caption (48×48): ✦ Auto-edit · Preset · Export · More.

### 3.3 Editor: desktop (≥1024)
```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│ ‹ Library   IMG_2041.jpg · 3 of 48     ↶ ↷   [◧ Compare ▾]          🕘   [ Export ]      │ top bar 48, surface1
├────┬──────────────────┬───────────────────────────────────────────────┬──────────────────┤
│ ▦  │ AI Studio      ✕ │                                               │ ▁▂▅█▇▅▃▂▁ histo  │ panel 320
│ ✦  │ ──────────────── │   ✦ Developing…  (status pill, top-left)      │ f/2.8 1/250 ISO200│ mono, tertiary
│ ◑  │ Styles           │                                               │ ──────────────── │
│ ◎  │ ┌────┐┌────┐     │                                               │ [ ✦ Auto       ▾]│ AI button 40h
│ ⌗  │ │Natu││Vivi│     │                 PHOTO CANVAS                  │ AI amount ──●─ 100%│
│    │ └────┘└────┘     │          (fit, 24px padding, rNone)           │ ● Light       ↺ ▾│ accordion
│    │ ┌────┐┌────┐     │                                               │   Exposure  +0.35│
│    │ │Mood││Cine│     │                                               │   ━━━━━━●────────│
│    │ └────┘└────┘     │                                               │   Contrast    +12│
│    │ ──────────────── │     ╭──────────────────────────────────────╮  │   ━━━━━━━━●──────│
│    │ Recent prompts   │     │ ✦  Describe an edit…              ➤ │  │ ● Color         ▾│
│ ⚙  │ "warmer, lift…"  │     ╰──────────────────────────────────────╯  │ ○ Curve         ▸│
│ ?  │                  │                                    − 86% +  ⤢ │ ○ Effects       ▸│
├────┴──────────────────┴───────────────────────────────────────────────┴──────────────────┤
│ ▢▢▣▢▢▢▢▢▢▢▢▢ filmstrip (88)                               ★ sort ▾   3 of 48            │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```
**Top bar (48, `surface1`, e1):** `‹ Library` (text button, `G`) · file name (`bodyStrong`) + "· 3 of 48" (`caption`, tertiary) · undo/redo (icon buttons 28) · Compare split-button (`squareSplitHorizontal` + ▾ menu: *Off · Split wipe · Side by side*) · History (`history`, popover listing steps; AI steps carry a gradient dot) · **Export** (primary, amber fill, 32h, `rSm`).

**Left rail (56, `surface1`):** 40×40 items with 18px icons, 4px vertical gap, top-aligned. Order: Library `layoutGrid` · **AI Studio** `sparkles` (gradient glyph, always) · Presets `swatchBook` · Masks `scanFace` · Crop & geometry `crop` · *(Remove `eraser`, hidden until shipped)*; bottom-aligned: Settings `settings`, Shortcuts `circleHelp`. Active: `accentTint` bg (`rSm`), `…500` icon in `accent`, plus a 2×16 amber bar on the rail's leading edge. Tooltips show the name plus the shortcut keycap ("Masks  M") after a 500ms delay.

**Flyout (280, `surface1`, docked ≥1280 / overlay e2 below):** title row (`title`, close ✕) + scrollable content. Toggling the same rail item closes it. `Esc` closes.
- *AI Studio:* Styles grid (2 columns, 120×120 thumbs rendered on the current photo), "Variations" (3 AI interpretations, later), Recent prompts (tap to re-run).
- *Presets:* "Yours" / "Built-in" segmented; list rows 48h with a 40×40 thumb on the user's photo; hover previews live on the canvas (debounced 120ms) without committing; click applies; `+ Save current as preset`.
- *Masks:* AI tiles (Subject, Sky, Background; gradient glyph, 2-column 64h cards), then manual tools (Brush, Linear, Radial), then the mask list. With a mask selected, the develop panel header turns into a 32h amber-tinted banner "Editing: Subject mask · Done", and the sliders edit that mask's local adjustments. `O` toggles the overlay.
- *Crop & geometry:* enters crop mode (§3.6).

**Canvas (`surround` color):** fit-to-view by default.
- Zoom: scroll wheel (pointer-anchored), pinch on trackpad, `Cmd/Ctrl +/−`, `Z` toggles Fit↔100%. Zoomed-in: `Space`-drag or plain drag to pan; a 120×80 navigator mini-map appears bottom-left for 1.5s after each zoom.
- Zoom control bottom-right (`− 86% +` in `value`, `⤢` fit): an e2 pill, 32h, 40% opacity until hovered.
- **Before/after:**
  - **Hold `\`** (or hold the Compare button) shows the *before* while held, with a "BEFORE" `micro` chip top-center (`#000`@60%, `rPill`).
  - **Split wipe** (Compare ▾ or `Y`): a vertical 1px white divider with 32px round handle (`surface3`, `↔` glyph) and "BEFORE"/"AFTER" chips at the top of each side. Drag anywhere near it (±12px hit) to move. Rendered as a `ClipRect` of the before layer.
  - **Side by side** (`Shift+Y`): two fitted panes with a 2px `surface0` gutter.
- **Status pill** (top-left, 12 inset, e2, `rPill`, 28h) appears only during AI work or offline (§3.8, §3.9).

**Prompt bar:** floats bottom-center, 24 above the canvas bottom edge (§4.10).

**Develop panel (320/352, `surface1`, e1, independently scrollable, 6px overlay scrollbar):**
1. Histogram block (288×96) + EXIF line (`mono`, tertiary). Pinned at top and never scrolls away.
2. **✦ Auto** AI button (full width, 40h) with ▾ for the engine/style menu. Under it, **AI amount** slider (0–150%, default 100%) appears once an AI edit exists, plus the offline badge when applicable.
3. Accordion groups in Lightroom order: **Light** (open) · **Color** (open; WB, Vibrance/Saturation, HSL dots) · **Curve** · **Color grading** · **Effects** · **Detail** · **Optics** (Lens corrections, later). Geometry lives in crop mode, not in the panel.
4. Footer pinned at bottom (48h, `surface1`, top hairline): `Copy` · `Paste` · `Reset all` (secondary buttons; Reset all asks for confirmation through a 4s inline undo toast, not a modal).

**Filmstrip (88, `surface1`):** horizontal list of the current library filter (§4.9). The right side shows the position "3 of 48". `Shift+F` collapses it to 0; `Tab` hides the side panels; `Shift+Tab` hides all chrome; `F` gives full-screen preview.

**Group slider inventory (ranges, steps, polarity)**
| Group | Slider | Range | Step (fine) | Polarity | Track |
|---|---|---|---|---|---|
| Light | Exposure | −5.00…+5.00 EV | 0.05 (0.01) | bipolar | accent |
| | Contrast, Highlights, Shadows, Whites, Blacks | −100…+100 | 1 | bipolar | accent |
| Color | Temperature | −100…+100 (JPEG) / 2000…50000 K (RAW) | 1 / 50 K | bipolar | colored |
| | Tint | −150…+150 | 1 | bipolar | colored |
| | Vibrance, Saturation | −100…+100 | 1 | bipolar | accent |
| | HSL Hue / Sat / Lum ×8 | −100…+100 | 1 | bipolar | colored |
| Effects | Texture, Clarity, Dehaze, Vignette | −100…+100 | 1 | bipolar | accent |
| | Grain amount / size / roughness | 0…100 | 1 | unipolar | accent |
| Detail | Sharpening amount | 0…150 | 1 | unipolar | accent |
| | Radius | 0.5…3.0 | 0.1 | unipolar | accent |
| | Noise reduction, Color NR | 0…100 | 1 | unipolar | accent |

Sub-group dividers inside **Light**: none. Inside **Color**: "White balance" (Temp, Tint, `pipette` WB picker), "Presence" (Vibrance, Saturation), then "Mix" (HSL dots).

### 3.4 Editor: phone (<600)
```
┌───────────────────────────────┐
│ ✕   ↶ ↷        ◧      Export  │ 44 + safe area; Export = amber text button
├───────────────────────────────┤
│ ✦ Developing…                 │ status pill (only when active)
│                               │
│          PHOTO CANVAS         │ resizes to the space above the sheet;
│   (press-and-hold = before)   │ pinch zoom, 2-finger pan, double-tap 100%↔fit
│                               │
├───────────────────────────────┤ ── slider sheet (rSheet top, surface1) ──
│            ───                │ grab handle 36×4
│ Light                     ↺   │ heading + group reset
│ Exposure               +0.35  │ slider rows 56h
│ ━━━━━━━━━━●───────────────    │
│ Contrast                 +12  │
│ ━━━━━━━━━━━━●─────────────    │
│ Highlights               −40  │
├───────────────────────────────┤
│  ✦    ☀     ◑    ✧    ▲   ⌗  ›│ tool tabs 64: icon 22 + caption
│  AI  Light Color Effects Detail│ horizontal scroll; active = accent + 2px top bar
└───────────────────────────────┘
```
- **Tool tabs** (order): **AI** · Light · Color · Curve · Effects · Detail · Crop · Masks · Presets. The tab strip scrolls horizontally with a 24px right-edge fade. Tapping the active tab collapses the sheet (canvas maximized).
- **Slider sheet** (40% height, min 248, max 420): spring drag between *collapsed* (0, tabs only), *half* (default) and *full* (88%, canvas shrinks to a 30% strip). The canvas **resizes** to stay fully visible above the sheet and is never covered.
- **Single-slider focus (VSCO pattern):** tapping a slider *label* collapses the sheet to one 96h row holding that slider at full width with a large 28px thumb, plus ✕ (cancel, restores the value) and ✓ (commit). The canvas becomes maximal. Ideal for one-handed fine tuning.
- **AI tab content:** ✦ **Auto** (full-width AI button, 48h) · AI amount slider · Styles carousel (88×88 thumbs on the user's photo, horizontal) · a "Describe an edit…" pill (48h, `surface2`, `rPill`) that opens the **prompt sheet**.
- **Prompt sheet:** keyboard-attached bottom sheet, e3. A multiline field (1–4 lines, `body` 15) with gradient sparkles leading; suggestion chips row above the field ("Brighter face", "Make the sky pop", "Moodier", "Golden hour", "Clean & bright"); send button 40×40 AI gradient circle with `arrowUp`. On send the sheet dismisses and the status pill shows progress on the canvas.
- **Compare:** press-and-hold the canvas for 250ms shows *before* with the "BEFORE" chip (haptic `selectionClick`). The ◧ top-bar button toggles split wipe; the divider is draggable with a 44px hit.
- **Filmstrip on phone:** none in the editor. Swipe left/right on the canvas at fit zoom moves to the previous/next photo, with a 150ms crossfade plus a 24px slide.

### 3.5 Editor: tablet
- **Portrait (600–839):** phone composition with the slider sheet at max 360 and tabs showing icon + label without scrolling where possible.
- **Landscape (≥840):** top bar (48) · left rail (56, tool icons; Presets/Masks/AI Studio open as e2 popovers 320 wide anchored to the rail) · canvas · docked develop panel 300 · prompt bar floating on the canvas · no filmstrip (swipe on canvas).

### 3.6 Crop and straighten mode
**Desktop:** the flyout closes and the develop panel is replaced (panel 300ms crossfade) by the crop panel. The canvas shows the full uncropped image with the crop frame.
```
┌───────────────────────────────────────────────────────┬──────────────────┐
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │ Crop & geometry  │
│  ░░┏━━              ┃               ━━┓░░░░░░░░░░░░░  │ Aspect           │
│  ░░┃      ┊         ┊         ┊       ┃░░  outside =   │ [Original ▾] ⇄   │
│  ░░        ┊ thirds grid while dragging   #000 @ 60%  │ ◻Free 1:1 4:5 3:2│
│  ░░━━━━━━━━┼━━━━━━━━━┼━━━━━━━━━━━━━━━━░░              │ 16:9 9:16 Custom │
│  ░░┃      ┊         ┊         ┊       ┃░░              │ Straighten       │
│  ░░┗━━              ┃               ━━┛░░              │ ━━━━━━●━━━  −1.4°│
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │ [Auto] [Level ⌖]  │
│                                                       │ ↻ 90°   ⇋ Flip   │
│                                                       │ ──────────────── │
│                                                       │ Reset   [ Done ] │
└───────────────────────────────────────────────────────┴──────────────────┘
```
- **Frame:** 1px white @ 80% edge. L-shaped corner handles 20×20 with a 3px white stroke and a 1px black @ 40% outline. Edge handles 24×3. Hit areas are 24 desktop / 44 touch. The rule-of-thirds grid (1px white @ 35%) shows only while dragging; it switches to a fine 9×9 grid while straightening.
- **Interactions:** drag inside to move the image under the frame. Drag outside the frame to rotate (cursor `rotateCw`). `Shift` constrains aspect while free. `X` swaps orientation. The `⌖ Level` tool lets you draw a line along the horizon to straighten. **Auto** is an *algorithmic* horizon detector, so it is a neutral button with no gradient (§7).
- **Enter/exit:** `R` enters; `Enter`/Done commits; `Esc` cancels and restores the previous crop. The frame animates in with a 300ms expo-out inset from the image bounds.
- **Phone:** top bar `Cancel · Crop · Done`; canvas with the frame; below it, an aspect chip row (horizontal scroll, `rPill`, 36h) and a **straighten ruler**: a horizontal tick dial (−45°…+45°, major tick every 5°, center needle `accent`, value `value` above the needle, haptic tick at each whole degree and at 0). Under that: `Rotate 90°` · `Flip` · `Auto` · `Reset` icon buttons (48×48).

### 3.7 Export: dialog (desktop) / sheet (phone)
```
╭──────────────────────────── Export 12 photos ──────────────────────────╮  520w, rLg, e3
│ Format        [ JPEG | PNG | WebP ]                                     │  segmented, 32h
│ Quality       ━━━━━━━━━━━━━━━━━●━━━  90         (JPEG/WebP only)        │
│ Size          (•) Original 6000 × 4000                                  │
│               ( ) Long edge  [ 2048 ] px    ( ) Scale [ 50 ] %          │
│ Color         sRGB  (Display P3 later)                                  │
│ Metadata      [ All  ▾ ]    ☑ Remove location                           │
│ File names    [ Original name ▾ ]   IMG_2041_edit.jpg                   │  mono preview
│ Save to       ~/Pictures/Lumen Exports          [ Change… ]             │
│ ─────────────────────────────────────────────────────────────────────── │
│ ≈ 4.1 MB each · 49 MB total                    [ Cancel ]  [ Export 12 ]│  primary = amber
╰─────────────────────────────────────────────────────────────────────────╯
```
- **Defaults:** last-used settings. First run: JPEG, quality 90, Original, Metadata *All*, *Remove location* **on** (privacy by default), name "Original name" + `_edit` suffix.
- **Progress:** the dialog body is replaced by a progress row: "Exporting 7 of 12" + a 4px `accent` bar (not gradient, because export isn't AI) + Cancel. On completion the dialog closes and a success toast reads "12 photos exported · Show in Finder" ("Show in Explorer" on Windows).
- **Phone:** bottom sheet (e3, `rSheet`, 90% height, scrollable) with the same fields stacked as 56h rows. Primary buttons: **Save to Photos** (amber, full width 52h) and **Share…** (secondary, opens the OS share sheet). Destination is implicit.
- **Batch export from the library** uses the same dialog with the count in the title.
- The `E` shortcut opens the dialog; `Cmd/Ctrl+Shift+E` exports immediately with the last settings and shows a toast.

### 3.8 AI processing states
| Stage | Where | Visual | Copy |
|---|---|---|---|
| Queued on import | Library tile | Gradient shimmer sweep @ 15% opacity, 1400ms loop, diagonal. Top-left pill `✦ Editing…` (`caption`, e2, `rPill`) | "Editing…" |
| Waiting for the model (editor) | Canvas top edge + status pill | 2px indeterminate **gradient line** across the canvas top (1200ms loop). Status pill: gradient sparkles + text | "Reading the light…" (0–3s) → "Developing…" (values streaming) |
| Long wait | Status pill | Text swaps, no new motion | after 8s: "Still working. Big photo." · after 30s: fallback (see §3.9) |
| **Develop-in** (values arrive) | Develop panel + canvas | Each changed slider animates from current → target (600ms expo-out, 35ms stagger top→bottom, total ≤1200ms). The canvas re-renders every frame, so the photo *develops* in place. Changed groups auto-expand. Each changed slider gets the **AI marker** (§4.1) fading in at the end of its animation | – |
| Explanation | Card under the AI button | `rMd` card, `surface2`, 1px gradient left edge (3px). Header "What I changed" + 3–5 lines (`body`), each line clickable (scrolls to and pulses the slider). Collapses after 8s into a chip `✦ 9 changes · Why?` | "Lifted shadows +35 to open up the face." |
| Done | History + toast (batch only) | History step "✦ Auto edit" (gradient dot). Batch toast with AI icon | "48 photos auto-edited. Every change is a slider." |
| Prompt applied | Under the prompt bar | Result row (e2, 36h): "✦ 6 sliders changed · Show · Undo" for 6s | – |
| Batch running | Batch bar | The bar becomes progress: "✦ Auto-editing 12 of 48" + a gradient fill bar inside the bar (2px, bottom edge) + `Stop` | – |

**Never block the UI during AI work.** Every slider stays draggable. If the user drags a slider while values are arriving, that slider is skipped (the user wins) and the explanation line is marked "(you changed this)".

### 3.9 Error and offline states
| Situation | Treatment | Copy |
|---|---|---|
| No connection / no API key → local engine | Neutral pill next to the Auto button: `cloudOff` 14 + "Basic auto (offline)" (`caption`, `surface2`, `rPill`). Auto button stays enabled but renders **neutral** (`surface2` fill, `textPrimary`, no gradient), because a statistical auto-tone is not a model (§7) | Tooltip: "You're offline, so this auto-tone runs on your device. AI styles and prompts come back when you reconnect." |
| Prompt bar while offline | Field disabled; placeholder changes; `Retry` text button appears when the network returns | "Prompts need a connection." |
| AI request fails | Inline row under the prompt bar or under the Auto button: `triangleAlert` `danger` + text + `Try again` | "Couldn't read that edit. Try again, or say it another way." |
| AI timeout (>30s) | Automatically apply Basic auto; toast (neutral) with `Retry AI` | "AI took too long, so I used Basic auto. Retry AI?" |
| Daily AI limit / out of credits | Neutral inline notice. Never the AI gradient, never a modal on the editing path | "You've used today's AI edits. Basic auto and every slider still work." |
| Unsupported or corrupt file | Library tile shows `surface2` with `triangleAlert` + file name (`mono`) + `Remove` | "Can't open this file." |
| RAW without embedded preview | Tile + editor banner | "This RAW has no preview we can read yet. JPEG export from your camera works." |
| Export failure | The dialog stays open; inline danger row above the buttons, with `Choose another folder` | "Couldn't save to that folder. Check permissions or pick another." |
| Partial batch failure | Toast with `View` → filter to failed items | "45 of 48 exported. 3 failed." |

### 3.10 First-run onboarding (3 steps max, skippable, never blocking)
1. **Welcome = empty library** (§3.1). No separate splash and no carousel. The headline does the onboarding.
2. **After the first auto-edit completes:** a coach mark anchored to the develop panel (e2 popover, `rMd`, 280w, arrow 8px): "**These sliders are the AI's edit.** Drag any of them. It's yours now." · `Next`.
3. **Coach mark on the prompt bar:** "**Or just say it.** Try *warmer, lift the shadows*." · `Got it`.

Each step shows "1/3" (`caption`, tertiary) and `Skip` (text button). Completion is stored per device (`onboarding.v1.done`). Phone: steps 2–3 anchor to the AI tab and the Describe pill. With reduced motion, coach marks appear without the 220ms rise.

---

## 4. Components

### 4.1 Develop slider (`LumenSlider`)
**Anatomy (stacked layout, default on all platforms)**
```
 ✦• Shadows                         +35     ← label row 16h: [AI marker] label · value field
 ━━━━━━━━━━━━━━━━━━┃━━━━━━━━━●━━━━━━━━━     ← track row 20h hit (desktop) / 32h (touch)
                   ↑ zero tick         ↑ thumb
```
| Part | Desktop | Touch |
|---|---|---|
| Row height | 44 (16 label + 4 + 20 track + 4) | 56 (18 + 6 + 32) |
| Track | 2px, `lineStrong`, `rPill` caps | 3px |
| Fill | `accent`, from **zero** (bipolar) or **min** (unipolar) to the thumb | same |
| Zero tick (bipolar) | 1×8px `textTertiary` at center | 1×10 |
| Thumb | 12px circle `textPrimary`, 1px `#000` @ 40% border; hover 14; drag 16 | 20; drag 24 |
| Hit area | full row width × 24 tall | full width × 44 |
| Label | `label`, `textSecondary`; becomes `textPrimary` when value ≠ default | `label` 13 |
| Value field | `value`, right-aligned, 52w × 20h, `rXs`; hover shows a `surface2` bg | 64w × 28h |

**Behavior**
- **Click track:** jumps the thumb (desktop). Touch: the track only responds to horizontal drags (8px slop) so vertical sheet scrolling still works. **Never** jump on touch tap.
- **Drag:** relative drag (Lightroom feel). 1px of pointer = (range / track width). **Fine drag:** hold `Alt/Option` (×0.1). Touch fine drag: drag vertically away from the track while sliding (≥60px up = ×0.25, iOS scrubbing pattern), with the hint "Fine" (`caption`) showing above the thumb.
- **Reset:** double-click (desktop) / double-tap (touch) on thumb, label or track resets to default. The reset animates 150ms; the history step reads "Reset Shadows".
- **Keyboard (focused):** `←/→` ±1 step, `Shift+←/→` ±10 steps, `Alt+←/→` fine step, `Home/End` min/max, `Backspace/Delete` = reset. Typing a digit starts editing the value field.
- **Value field:** click to edit (select all). Accepts `35`, `+35`, `-35`, `−35`. Exposure accepts `0.35` or `1/3`. `Enter`/blur commits (clamped), `Esc` cancels. `↑/↓` nudge ±1 (Shift ±10). The scroll wheel changes the value **only while the field is focused**, so panel scrolling is never hijacked.
- **Colored tracks** (Temp, Tint, HSL, grade luminance): gradient per §2.3, with no accent fill.
- **AI marker:** a 6px gradient dot left of the label when the current value was set by AI and not yet touched. Hover/long-press shows a tooltip (`rMd`, max 260w) with that slider's reason: "Lifted +35 to open up the face." Once the user moves the slider, the dot disappears (the value is user-owned). The tooltip remains reachable from History.
- **Live render:** dragging sends values at display refresh rate (throttle to one per frame). One history step is committed on drag end.
- **Semantics:** `Semantics(slider: true, label: 'Shadows', value: '+35', increasedValue, decreasedValue, hint: 'Set by AI: lifted shadows to open up the face. Double tap and hold to adjust.')`.
- **Compact density** (desktop opt-in, Settings → *Panel density*): one row, 28h: label 96w · track flex · value 44w.

### 4.2 Accordion group header (`DevelopGroup`)
```
 ●  Light                          ◉ ↺  ▾        36h, full width, surface1
```
- Height 36. Padding 16 horizontal. Label `heading` (`textPrimary`). The chevron (`chevronDown`, 16) rotates −90° when closed (150ms).
- **Modified dot:** 5px `accent` circle before the label when any slider in the group ≠ default. It turns into a gradient dot when every change in the group came from AI and is untouched.
- **Right controls** (shown on hover/focus, or always on touch): visibility toggle (`eye`/`eyeOff`, 16) that disables the group's effect for comparison (label turns `textTertiary` and an "Off" caption appears); reset `rotateCcw` 16 (only when modified). The reset can be undone via a toast.
- Click anywhere on the header toggles it. `Alt`-click collapses all others (solo mode, Lightroom). `Enter`/`Space` toggles when focused.
- Expand: `base` 220ms expo-out via `SizeTransition` + 120ms fade of content. Open/closed state persists per user.

### 4.3 Histogram
- 288×96 (desktop) / full width × 64 (phone, in the Light tab header; tap to hide). `surface0` background, `rNone`. Faint quarter gridlines (`line`).
- RGB + luminance per §2.3, computed from the rendered preview at ≤256px on a background isolate and updated ≤10×/s while dragging.
- **Clipping indicators:** two 12px triangles in the top corners (shadows left, highlights right), `textTertiary` when clean, filled white/channel color when clipped. Click toggles the canvas clipping overlay; `J` toggles both.
- **Region drag (desktop):** hovering shows five zones (Blacks · Shadows · Exposure · Highlights · Whites) with a `surface3` @ 40% band and the zone name + value in the EXIF line. Horizontal drag adjusts that slider (Lightroom behavior).
- **EXIF line** below: `f/2.8 · 1/250 s · ISO 200 · 85 mm` (`mono`, tertiary). Replaced by the region readout while hovering.

### 4.4 Style chip (AI Style / Preset thumbnail)
- Thumb: 120×120 desktop flyout (2-column), 88×88 phone carousel, `rTile`. Rendered **on the user's current photo** (center-weighted square crop at 2× density, via the same shader pipeline at a 256px proxy, cached by recipe hash).
- Label below: `label`, `textSecondary` → `textPrimary` when selected; 6 gap.
- AI styles carry a 16px gradient sparkles badge top-right on a `#000`@55% circle. Static presets carry no badge.
- **States:** loading = `surface2` + gradient shimmer (AI styles) / neutral shimmer `#FFFFFF`@6% (presets). Hover = scale 1.03 (150ms) + live preview on the canvas after 120ms. Selected = 2px `accent` ring with a 2px `surface1` gap (outer radius 6) + label primary. Pressed = scale 0.97.
- **When selected,** an "Amount" slider (0–150%, default 100) appears directly under the grid row (desktop) / under the carousel (phone).

### 4.5 HSL color dots
- A row of 8 dots, 20px (desktop) with 8 gap / 28px (touch) within 44px hit cells, in the colors of §2.3. Selected: 2px `textPrimary` ring + 2px `surface1` gap. The band name shows under the row (`caption`, "Orange"), so the selection never relies on color alone.
- A dot with a non-default adjustment gets a 4px `accent` pip at its bottom.
- Below the row, three colored sliders for the selected band: Hue, Saturation, Luminance. A mode toggle `Per color | All` shows all 8×3 in compact rows (desktop only).
- `pipette` "Pick from photo" (targeted adjustment): click a color on the canvas to select the nearest band; drag vertically on the canvas to adjust that band's saturation (with `Alt`: luminance). Esc exits.

### 4.6 Tone-curve editor
- 288×288 (desktop) / full width square (phone, max 360). `surface0`, `rNone`. 4×4 grid in `line`, diagonal baseline `lineStrong` dashed 4/4. Behind the curve, the histogram @ 25%.
- Channel chips above: `RGB` · `R` · `G` · `B` (8px colored dots + letter, `rPill` 28h). Mode toggle: `Point | Parametric`.
- Curve stroke 1.5px `textPrimary` (RGB) or the channel color. Points are 10px circles, `surface1` fill with 1.5px stroke; selected is filled `accent`.
- Click on the curve adds a point, drag moves it, double-click a point deletes it (or drag it out of bounds; it fades at 50% before removal). `Alt`-drag = fine. Arrow keys nudge the selected point by 1 (Shift 10). Max 16 points. Endpoints are fixed in x.
- Readout bottom-left: `In 128 · Out 142` (`value`).
- **Parametric mode:** 4 region sliders (Highlights, Lights, Darks, Shadows) + 3 draggable split handles under the graph.

### 4.7 Color-grading wheels
- **Default "3-way" view:** three wheels (Shadows, Midtones, Highlights) side by side at 88px (desktop) / 104px (phone, horizontally scrollable), each with a luminance slider underneath and its name (`caption`). Segmented control above: `3-way · Shadows · Midtones · Highlights · Global`. A single-wheel view renders at 200px.
- Wheel: a conic hue ring desaturated to 70% chroma, fading radially to neutral `#808080` at the center, 1px `lineStrong` rim. The puck is a 12px (touch 20) white circle with 1px black @ 40%; the hue/sat line runs from the center to the puck at 1px white @ 50%.
- Drag the puck to set hue and saturation. `Alt` = fine. `Shift` locks hue (changes saturation only). Double-click resets. Hue and Sat values show under the wheel while dragging (`value`).
- Below: Blending (0–100, default 50) and Balance (−100…+100).

### 4.8 AI gradient button (`AIButton`)
| Size | Height | Radius | Text | Use |
|---|---|---|---|---|
| Large | 48 | `rSm` | `button` 15 | Phone AI tab ✦ Auto |
| Medium | 40 | `rSm` | `button` 13 | Desktop panel ✦ Auto |
| Small | 32 | `rSm` | `label` 600 | Batch bar "✦ Auto-edit all", masks AI tiles |
| Icon | 32/40 circle | `rPill` | – | Prompt send |

- Fill `aiGradient`; content `textOnAccent` (sparkles glyph *solid* `textOnAccent`, not gradient-on-gradient).
- Hover: the gradient shifts (animate `GradientRotation` 0→0.15 rad, 220ms) + brightness via a `#FFFFFF`@8% overlay. Pressed: scale 0.97 + `#000`@8%. Focus: `focusRing`. Disabled: `surface2` fill + `textDisabled`, no gradient (the gradient never appears inert).
- **Working state:** the label is replaced by a 14px spinner (`loaderCircle` rotating, 900ms) + "Developing…"; `aiGlow` pulses behind (opacity 0.2↔0.45, 1400ms). Reduced motion: no pulse and no spin; static label only.
- A split ▾ (desktop) opens a menu: *Natural (default) · Use style… · Basic auto (on-device)*.

### 4.9 Filmstrip item
- Height 64, width by aspect (min 48, max 96), `rXs`, 4 gap; the strip has 12 vertical padding.
- **Current:** 2px `accent` outline (outset 2) + full opacity. Others are at 72% opacity, 100% on hover.
- **Selected (multi):** 2px `textPrimary` inner ring + a check badge 14px.
- **Badges** bottom-left at 12px: AI (gradient), manual, failed (`triangleAlert` danger). Processing: gradient shimmer @ 15%.
- Click opens; `Cmd/Ctrl`/`Shift`-click multi-selects (enables "Sync settings" in the top bar as a secondary button: `Sync to 4`). Drag to reorder: never (sort is by date/name).
- `←/→` moves between photos when the canvas or filmstrip has focus.

### 4.10 Prompt bar
```
╭──────────────────────────────────────────────────────────────╮
│ ✦  Describe an edit… "warmer, lift the shadows"           ➤ │   48h, rLg, surface3, e2
╰──────────────────────────────────────────────────────────────╯
```
- Width clamp(360, 60% canvas, 600). Leading gradient sparkles 18. Field `body` 14 (desktop override), placeholder `textTertiary`. Trailing send (32 AI icon button), enabled only with text.
- **Idle:** 85% opacity, 1px `line` border. **Focused** (`/` or click): 100% opacity, a 1px gradient border (`aiGradient` through a stroked `ShapeDecoration`) + a suggestion chip row above (`rPill` 28h, `surface3`, e2): "Brighter face" · "Make the sky pop" · "Moodier" · "Golden hour" · "Clean & bright" (chips are contextual from the image analysis when available).
- `Enter` submits, `Shift+Enter` adds a newline (max 4 lines, the bar grows upward), `Esc` blurs, `↑` in an empty field recalls the last prompt.
- **While a slider/canvas drag is in progress** the bar fades to 0% (150ms) and ignores pointer input, so it never covers the area being judged. It returns 400ms after the drag ends.
- **After submit:** the field locks and shows the status text in place ("Reading the light…"), with a 2px gradient progress line along the bar's bottom edge. The result row (§3.8) appears above the bar.
- Each prompt is one history step: "✦ 'warmer, lift the shadows'".

### 4.11 Batch bar
- Spec in §3.2. Desktop 52h, `rXl`, e2, internal padding 8, items 36h `rSm`, separators 1×20 `line`. The count uses `value` + "selected" `label`.
- Enter: 16px rise + fade 220ms. Exit: 150ms fade. Stays above toasts (z-order: batch bar > toast).
- Keyboard: when ≥1 selected, `A` = Auto-edit all, `E` = Export, `Cmd/Ctrl+Shift+S` = Sync settings, `Esc` = clear selection.

### 4.12 Toast
- Desktop: bottom-left of the canvas region, 16 inset, above the filmstrip. Phone: above the tool tabs / batch bar, full width − 16. Max width 400, min 240. `surface3`, e2, `rMd`, padding 12/16, `body`.
- Leading icon 16: neutral (none), success `circleCheck` green, danger `triangleAlert`, AI = gradient sparkles (only for completed AI work).
- One action max (text button, `accent`). Durations: 4s; 8s with an action; persistent for errors needing a decision. Hover pauses the timer. Max 3 stacked (newest at the bottom, older ones scale 0.96 and fade to 80%).
- Undo toasts ("Reset all · Undo") always last 8s.
- Screen readers: announced through `SemanticsService.sendAnnouncement` (polite).

### 4.13 Other primitives (summary)
| Component | Spec |
|---|---|
| Primary button | Amber fill, `textOnAccent`, 32h desktop / 48h touch, `rSm`, padding 14/16. One per surface |
| Secondary button | `surface2` fill, 1px `lineStrong`, `textPrimary` |
| Text button | No fill, `accent` text (dark) / `accentInk` (light); hover underline offset 3 |
| Icon button | 28 (desktop) / 44 (touch) square, `rSm`, 18/22 icon, `textSecondary` → `textPrimary` on hover |
| Segmented | `surface2` track, `rSm`, selected segment `surface3` + `textPrimary` + 1px top highlight, 150ms slide |
| Toggle (`LumenToggle`) | 28×16 track (`lineStrong` → `accent`), 12px thumb `textPrimary`. Touch: 44×26 |
| Checkbox (`LumenCheck`) | 16px (touch 22) `rXs` box, 1.5px `lineStrong`; checked = `accent` fill + `textOnAccent` check |
| Tooltip | `surface3`, `rSm`, `caption` + optional keycap (`mono` in a 1px `lineStrong` `rXs` box), 500ms delay, 0ms when moving between tooltipped items |
| Menu / popover | `surface3`, e2, `rMd`, items 32h (desktop) / 48h (touch), shortcut right-aligned in `mono` tertiary |
| Scrollbar | Overlay, 6px, `#FFFFFF`@18% → 32% on hover, `rPill`, auto-hide after 800ms |

---

## 5. Microcopy

**Voice:** short, confident, human. A photographer talking to a photographer. Sentence case everywhere. No exclamation marks. No "magic", no "AI-powered" in UI chrome (the gradient already says it). Use photography verbs: *lift, pull, warm, cool, open up, tame, recover*.

### 5.1 Key labels and buttons
| Context | Text |
|---|---|
| Import button | `Import` |
| Auto button | `✦ Auto` (menu: `Natural`, `Use style…`, `Basic auto (on-device)`) |
| AI amount | `AI amount` |
| Prompt placeholder | `Describe an edit…` |
| Prompt example (empty, focused) | `"warmer, lift the shadows"` |
| Batch: AI | `✦ Auto-edit all` |
| Batch: others | `Apply preset` · `Sync settings` · `Export` |
| Copy / paste settings | `Copy settings` · `Paste settings` |
| Reset | `Reset` (slider/group) · `Reset all` (photo) |
| Compare menu | `Off` · `Split wipe` · `Side by side` |
| Export primary | `Export 12` (desktop) · `Save to Photos` (phone) |
| Save preset | `Save as preset` |
| Masks AI tiles | `Subject` · `Sky` · `Background` |
| Offline badge | `Basic auto (offline)` |
| Library filters | `All` · `AI edited` · `Not edited` |

### 5.2 Empty states
| Where | Headline (serif) | Body | Action |
|---|---|---|---|
| Library | Your photos, *developed*. | AI makes the first edit. Every change stays a slider. | `Choose photos` · `Try a sample photo` |
| Filter "AI edited", none | Nothing developed yet. | Select photos and press ✦ Auto-edit. | – |
| Presets "Yours" | Your looks live here. | Edit a photo you love, then save it as a preset. | `Save current as preset` |
| Masks | Edit just part of the photo. | Start with Subject or Sky. AI finds the edges. | – |
| History | No edits yet. | Every change you or the AI make shows up here. | – |
| Recent prompts | Say what you want. | "Make the sky pop." "Warmer skin." "Moodier." | – |

### 5.3 AI explanations
**Pattern:** `{Verb} {slider} {signed value} to {visible purpose}.` Keep it under 60 characters, one per changed slider, and show the 3–5 biggest changes first.
- Lifted shadows +35 to open up the face.
- Pulled highlights −40 to bring back the sky.
- Warmed temperature +12 for late-afternoon light.
- Added clarity +10 for crisper fabric detail.
- Cooled blues −8 so the sea reads true.
- Eased saturation −6 to keep skin natural.
- Set blacks −14 for deeper contrast without crushing.
- Straightened 1.4° to level the horizon.

Prompt result summary: `✦ 6 sliders changed` · `Show` · `Undo`.

### 5.4 Status and errors
- `Reading the light…` → `Developing…` → (after 8s) `Still working. Big photo.`
- `Couldn't read that edit. Try again, or say it another way.`
- `AI took too long, so I used Basic auto. Retry AI?`
- `You're offline. Basic auto and every slider still work.`
- `You've used today's AI edits. Basic auto and every slider still work.`
- `Can't open this file.`
- `12 photos exported.` · `Show in Finder`
- `48 photos auto-edited. Every change is a slider.`
- `Reset all edits on this photo.` · `Undo`

### 5.5 Onboarding
1. *(Library hero)* "Your photos, *developed*." / "AI makes the first edit. Every change stays a slider."
2. "**These sliders are the AI's edit.** Drag any of them. It's yours now."
3. "**Or just say it.** Try *warmer, lift the shadows*."

---

## 6. Accessibility

### 6.1 Contrast targets (WCAG 2.2 AA minimum; we hit AAA for primary text)
| Pair | Ratio | Target |
|---|---|---|
| `textPrimary` on `surface1` | 15.2:1 | ≥7 ✓ |
| `textSecondary` on `surface1` / `surface3` | 7.0 / 5.7:1 | ≥4.5 ✓ |
| `textTertiary` on `surface1` | 5.1:1 | ≥4.5 ✓ (not allowed on `surface3`: 4.2) |
| `accent` text on `surface1` | 9.2:1 | ✓ |
| `textOnAccent` on amber / AI gradient (worst stop: rose) | 9.6 / 5.8:1 | ✓ |
| `danger` on `surface3` | 4.6:1 | ✓ |
| `focusRing` vs `surface1` | 8.3:1 | ≥3 (non-text) ✓ |
| Slider thumb `textPrimary` vs track area | 15:1 | ≥3 ✓ (the thumb is the identifying part; the 2px track is supplementary) |
| Light theme `textTertiary` / `accentInk` on `surface0` | 4.9 / 4.6:1 | ✓ |

Rules: never convey state by color alone. The AI marker has a tooltip and a semantics hint, HSL bands are named, clipping triangles change shape (outline→filled), and errors always carry an icon plus text.

### 6.2 Focus order and regions (desktop)
Regions in order: **Top bar → Left rail → Flyout → Canvas (zoom, compare) → Prompt bar → Develop panel → Filmstrip.**
- `F6` / `Shift+F6` jumps between regions (Windows convention, also on macOS). `Tab` moves within a region via `FocusTraversalGroup` + `OrderedTraversalPolicy`. *Tab cycles inside the region once the user is in it; F6 leaves.*
- Inside the develop panel: group header → its sliders (when open) → next header. Arrow keys adjust a focused slider and never move focus.
- Opening a dialog traps focus and returns it to the invoker on close. Coach marks are announced but never steal focus.
- The focus ring shows only in keyboard mode (`FocusManager.highlightMode == traditional`).

### 6.3 Keyboard shortcuts (desktop; `⌘` on macOS = `Ctrl` on Windows; keycaps render per platform)
| Action | Shortcut | | Action | Shortcut |
|---|---|---|---|---|
| Library grid / Develop | `G` / `D` | | Undo / Redo | `⌘Z` / `⌘⇧Z` (`Ctrl+Y` also on Windows) |
| Open selected | `Enter` | | Copy / Paste settings | `⌘⇧C` / `⌘⇧V` |
| Prev / next photo | `←` / `→` | | Sync settings to selection | `⌘⇧S` |
| ✦ Auto (AI) | `A` | | Reset all | `⌘⇧R` |
| Focus prompt bar | `/` | | Export dialog / quick export | `E` / `⌘⇧E` |
| Show before (hold) | `\` | | Import | `⌘I` |
| Split wipe / Side by side | `Y` / `⇧Y` | | Select all / clear | `⌘A` / `Esc` |
| Zoom fit↔100% / in / out | `Z` / `⌘=` / `⌘−` | | Hide side panels / all chrome | `Tab` / `⇧Tab` |
| Fit / 100% | `⌘0` / `⌘1` | | Full-screen preview | `F` |
| Pan (zoomed) | hold `Space` + drag | | Toggle filmstrip | `⇧F` |
| Crop mode / swap aspect | `R` / `X` | | Cycle canvas surround | `⇧B` |
| Masks / overlay | `M` / `O` | | Clipping overlay | `J` |
| Brush size | `[` / `]` | | AI Studio / Presets | `S` / `P` |
| Next region | `F6` | | Shortcut sheet | `?` |
| Slider fine drag | hold `⌥/Alt` | | Slider ±1 / ±10 / fine | `←→` / `⇧←→` / `⌥←→` |
| Reset slider | double-click, or `Delete` when focused | | Solo group | `⌥`-click header |

Single-letter shortcuts are disabled while any text field has focus. Implement them with `Shortcuts` + `Actions` + `Intent`s so menu items (macOS `PlatformMenuBar`) and keycaps read from one registry.

### 6.4 Hit targets
- Touch (phone, tablet, touch-mode): **≥ 44×44 pt** everywhere (we use 48 logical px for primary actions and tool tabs). Slider hit rows are 44 tall; HSL dots and wheel pucks get 44 hit cells around smaller visuals.
- Desktop pointer: ≥ 24×24 (WCAG 2.5.8). Typical icon buttons are 28, rail items 40.
- Spacing: adjacent touch targets keep ≥ 8 between hit areas, or merge them into one control.

### 6.5 Reduced motion, text scaling, screen readers
- Reduced motion per §2.10. AI develop-in becomes a single 150ms crossfade, and its *information* (which sliders changed) still appears via the AI markers and the explanation card.
- Text scaling: honor `MediaQuery.textScaler` up to 1.3× in the editor chrome (panels reflow and slider rows grow), and up to 2.0× in library, onboarding, dialogs and sheets. Clamp above that only in the editor top bar and tool tabs, where labels move into tooltips.
- Screen readers: the canvas announces "Photo, IMG_2041, edited by AI. Hold backslash to compare." Every icon-only button has a `Semantics` label. Live AI status changes are announced politely ("Developing… Done, 9 changes").
- Color-blind safety: clipping overlay colors are user-changeable, and histogram channels can be toggled individually.

---

## 7. The AI moments: where the gradient lives (and where it never does)

**Rule:** the amber→rose gradient means *a model (LLM or on-device neural net) made a decision about this photo.* Deterministic algorithms, user actions and commerce never get it.

### 7.1 Gradient appears (exhaustive list)
1. ✦ **Auto** button (develop panel, phone AI tab) when an AI engine is available.
2. ✦ **Auto-edit all** in the batch bar and its progress fill.
3. **Prompt bar:** leading sparkles, focused border, send button, progress line.
4. **AI Style** thumbnails' sparkles badge and their loading shimmer.
5. **AI mask tiles** (Subject, Sky, Background) and the masks' "AI" list badge.
6. **AI marker dots** on sliders set by AI and untouched; the gradient modified-dot on a group when all its changes are AI's.
7. **AI badges** on library tiles and filmstrip items; the import shimmer while AI edits.
8. **Status pill** sparkles ("Reading the light…", "Developing…") and the 2px indeterminate canvas line.
9. **Explanation card** left edge, the `✦ 9 changes · Why?` chip, and prompt result rows.
10. **History steps** created by AI (gradient dot).
11. **AI Studio** rail icon (sparkles glyph only, not the item background).
12. AI completion toasts (icon only).

### 7.2 Gradient never appears
- **Primary non-AI actions:** Export, Import, Done, Save to Photos, Save preset. These use amber.
- **The user's own adjustments:** slider fills, curve, wheels and manual masks (brush/linear/radial) stay amber or neutral, even after AI touched the photo earlier.
- **Algorithmic "auto"s:** Basic auto (offline/on-device statistical), auto-straighten, WB eyedropper, auto-clipping. Neutral buttons.
- **Selection, focus and navigation:** selected tiles, active rail items, tabs, focus rings.
- **Errors, warnings and limits:** never gradient, and never gradient-styled upsells.
- **Paywall, pricing, "Pro" badges and upgrade prompts.** The gradient is a trust signal ("a model acted here"), not a premium signal. Using it to sell would wear that trust down.
- **Large surfaces:** never as a panel, header or screen background, and never behind photos. Max gradient area on screen at once: one AI button + small glyphs.
- **Inert states:** a disabled AI control loses its gradient (§4.8).

---

## 8. Implementation notes (Flutter, no code here)
- **Theme plumbing:** build `ThemeData(useMaterial3: true)` only as plumbing: `splashFactory: NoSplash.splashFactory`, `highlightColor`/`hoverColor`/`splashColor` transparent, `surfaceTintColor` transparent on every component theme, `visualDensity: VisualDensity.compact` on desktop. All visible styling comes from `LumenTokens` and custom widgets.
- **Suggested file layout:** `app/lib/design/{tokens.dart, type.dart, motion.dart, icons.dart}`, `app/lib/design/components/{lumen_slider.dart, develop_group.dart, histogram.dart, ai_button.dart, prompt_bar.dart, batch_bar.dart, toast.dart, …}`, `app/lib/core/brand.dart` (`Brand.name`).
- **Responsive:** one `LayoutBuilder` breakpoint resolver (`WindowClass.phone/tablet/desktop/wide`) + an `InputMode` (touch/pointer) provider. Never branch on `Platform.isX` for layout; only for title-bar insets, keycap glyphs and share/save destinations.
- **Custom painting:** slider tracks, histogram, curve, wheels and crop overlay are `CustomPainter`s with `RepaintBoundary`, repainting from `ValueListenable`s, never from a whole-panel `setState`.
- **Verification:** golden tests at 375, 768, 1024 and 1440 widths for Library (empty, grid, selection), Editor (idle, AI working, offline) and Export; dark and light Library variants; a contrast unit test asserting the §6.1 table from the token values; a `tnum` advance-width golden.
