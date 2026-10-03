# Lumen: Product Ideation

> Working name **Lumen** (the market research checks it for conflicts and suggests alternatives; the name lives in one constant so a rename is cheap).

## The one-liner
**Drop your photos in. AI edits them like a pro retoucher. Every edit stays a slider you can tweak.**

The core concept is **parametric (non-destructive) AI editing**. The AI's output is a *recipe* of develop settings, not a new set of pixels, so the user can always see, tweak or undo it.

## Who it's for (hypothesis, refined by research 04)
1. Creators and small businesses (Etsy/Shopify sellers, realtors, food and lifestyle creators) who want "pro-looking" photos without learning Lightroom.
2. Hobbyist photographers who know some Lightroom but want a fast first pass on 300 vacation shots.
3. Later: working photographers who want to batch-cull and batch-edit in their own style (the Imagen/Aftershoot market).

## Feature brainstorm (ranked by impact × feasibility)

### Must-have (MVP)
| # | Feature | Why it matters |
|---|---------|----------------|
| 1 | **Drag-and-drop import** (JPEG/PNG/WebP/HEIC, RAW via embedded preview), local library with thumbnails and EXIF | Zero-friction entry |
| 2 | **One-click AI Auto-Edit** on import: analyses the photo and sets ~40 develop sliders | The product's promise |
| 3 | **AI Styles**: Natural, Vibrant, Moody, Cinematic, Film, Golden Hour, Clean & Bright, B&W, Portrait Soft. The AI adapts each style *to this photo* instead of applying a fixed filter | Differentiates from static presets |
| 4 | **Describe-an-edit prompt** ("warmer, lift the shadows, make the sky pop") turned into slider deltas and masks | Magic you can steer |
| 5 | **Manual develop panel** in full Lightroom depth: Light, Color (WB, vibrance, HSL 8 bands), Tone Curve, Color Grading, Detail (sharpen/NR), Effects (clarity, texture, dehaze, vignette, grain), Geometry (crop, straighten, flip, rotate) | "Users can go in and make manual edits" |
| 6 | **Histogram**, before/after split wipe, zoom/pan, undo/redo history | Pro trust signals |
| 7 | **AI masks**: Select Subject / Sky / Background, plus brush, linear and radial gradients with local adjustments | Lightroom's most-loved modern feature |
| 8 | **Batch**: multi-select, then auto-edit all, sync settings, apply preset, export all as ZIP | Willingness-to-pay driver |
| 9 | **Presets**: built-in looks plus save your own; copy/paste settings | Retention and consistency |
| 10 | **Export**: JPEG/PNG/WebP at full resolution, quality, resize, EXIF option | The job isn't done until export |

### Next (post-MVP, architected for now)
- **AI Remove** (object eraser via LaMa/MI-GAN) and **Background removal**
- **AI Upscale** (2×/4×) and **AI Denoise**
- **Learn My Style**: build a personal style profile from 10–20 edited photos and apply it to new shoots (Imagen-style)
- **Consistency mode**: match a whole shoot to a hero image's look (white balance and exposure normalization across a set)
- **Smart culling**: flag blurry, closed-eye and duplicate shots
- Accounts, cloud sync, sharing links, team/brand presets, Stripe billing, credits

### Delighters
- "Explain this edit": the AI writes one line per change ("Lifted shadows +35 to open up the face")
- Variations strip: three AI interpretations side by side; pick one
- Keyboard-first power use (Lightroom shortcuts)
- Import of Lightroom `.xmp` presets

## AI architecture concept (refined after research 01/03)
```
                ┌───────────── browser ──────────────┐        ┌──── server (Next.js route) ────┐
 photo ──► decode ─► preview (≤2048px) ─► analyze ─┐ │        │                                │
                │                       stats/hist │ │  JPEG  │  Vision LLM (Claude)           │
                │                                  ├─┼──1024─►│  → strict JSON develop params  │
                │   Local Auto-Tone (offline) ◄────┘ │        │  + rationale per change        │
                │      ↓ params                      │◄───────┤                                │
                │   WebGL2 develop pipeline ──► canvas/export  └────────────────────────────────┘
                │   transformers.js (WebGPU): subject/sky masks, bg removal, upscale
                └────────────────────────────────────┘
```
- **Two auto-edit engines behind one interface**: `local` (statistical auto-tone, free, offline, instant) and `vision` (Claude, style-aware, explains itself). With no API key configured the app degrades to `local` without breaking.
- **The heavy pixel work runs in the browser** (WebGL2 and WebGPU), so serving a user costs almost nothing per photo. That's good unit economics for a SaaS.

## Scale-later architecture principles
- Repository pattern for storage: `LocalPhotoRepository` (IndexedDB) now, `CloudPhotoRepository` (Firebase/Supabase plus object storage) later
- Versioned edit-recipe JSON schema (`schemaVersion`), with migrations
- AI provider behind an interface (`AutoEditProvider`), so models and vendors can be swapped and metered per call for credits
- Feature flags and plan limits in one module, ready for Stripe tiers
- Commercial-safe licenses only (MIT/Apache/BSD), recorded in `docs/LICENSES.md`
