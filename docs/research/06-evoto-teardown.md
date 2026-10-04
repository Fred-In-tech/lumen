# 06 · Evoto teardown: what it does, how it works, and what Lumen should copy

**Subject:** Evoto (https://www.evoto.ai), the AI portrait retouching suite from **Truesight Technology Inc.** (Delaware; branches in Singapore, Japan and Korea) [3].
**Research date:** 2026-10-03. Evoto Desktop **8.0** shipped 2026-09-22 [5][71].
**Method:**
- Downloaded all **252 English articles** of the Evoto Help Center (`support.evoto.ai`, via its sitemap) and read the feature, workflow, pricing and privacy articles in full.
- Read the evoto.ai product, pricing, about, business and Trust Center pages, plus the release notes.
- Read press and reviews: PetaPixel, Fstoppers (×2), Digital Camera World, Amateur Photographer, SLR Lounge (×2), Behind the Shutter, Trustpilot, DIY Photography, and Evoto's own statement.
- Ran web searches for the competitors.

**Tags used in this document**
- **[F]** fact, stated by Evoto in its own help center, site, pricing page or release notes during this session.
- **[R]** reported by a third-party reviewer or press outlet.
- **[I]** my inference from the facts. Treat these as hypotheses.
- **[U]** could not verify (blocked, paywalled or not found).

Source numbers in brackets point to the list in §8.

---

## 0. TL;DR

1. **What people buy Evoto for:** **per-face, gender- and age-aware portrait retouching where every effect is a slider**, saved into presets and synced across a whole shoot. The core is skin, blemishes, under-eyes, glasses glare, stray hair, teeth and studio backdrop cleanup. Color looks, culling, galleries, video and generative "AI Lab" tools were added around that core [F][R].
2. **The key product idea is the "character-aware preset".** On import, Evoto detects every face and tags it by **gender and age group**: Male, Female, Child, Senior, plus an Infant / under-3 sub-case. One preset holds **different slider values per group**. Applying it to 1,000 photos retouches each person appropriately, and you can then override one individual and sync that override to the same person across the project [F][14][15][77]. Evoto does **not** call these "Smart Presets"; that term doesn't appear anywhere in its docs [F].
3. **Business model:** editing and previews are free, with a watermark on the preview. **Exporting an AI-edited photo costs 1 credit.** Re-exporting the same photo is free. Annual plans cost **$89 for 800 credits up to $1,339 for 24,000** (about **$0.11 to $0.05 per photo**). Pay-as-you-go runs **$49 for 200 up to $459 for 3,600** (about $0.25 to $0.13). Since v6.1, paid users export **color, crop and manual-tool-only** edits for free, so *AI retouching* is the thing being metered [F][2][48][50].
4. **Architecture is hybrid, and mostly cloud-dependent.** Evoto states that local projects send **only thumbnails** to its cloud (AWS, US). These are deleted after processing, and the results are cached up to 8 days. Rendering runs locally on the GPU, and Evoto publishes a long supported-GPU list. Practically, **you need internet to edit with AI** [F][4][57][R][74][76].
5. **Scale claims:** "1.2M photographers, 200+ countries, 50k studios, 800M+ photos processed." Evoto says it started building the product in 2020 [F][3].
6. **Main weaknesses:**
   - Credit pricing anxiety, plus **rollover forfeiture on downgrade**. One user reported losing about $351 of credits [R].
   - Billing and support complaints. Trustpilot is **3.7/5 from 374 reviews**, with **20% one-star** [R][79].
   - No layers [R].
   - Needs to be online [R].
   - A January 2026 trust incident ("headshot-gate"): Evoto quietly ran a consumer AI headshot generator that undercut its own customers, then withdrew it and apologised [R][80][81].
7. **The opening for Lumen:** Lumen already treats "AI as editable sliders" as its core principle. If we add a **per-face parameter model**, ship the top 8–10 retouch effects **on-device**, and charge a **flat price**, Lumen hits Evoto's core job with a privacy and cost story Evoto structurally cannot match.
8. **MVP replicate list (§5):**
   - Face detection with group tags and per-face/per-group sliders.
   - Blemish/acne removal with freckle preservation.
   - Frequency-separation and dodge & burn skin smoothing.
   - Dark circles and eye bags.
   - Shine reduction.
   - Teeth whitening, plus eye whites and iris brightness.
   - Clean backdrop and Unify Lighting.
   - Manual "tuning pen" brush for every module.
   - Character-aware presets with selective sync.
   - Glasses-glare removal (beta) and stray-hair removal on plain backdrops come right after. They are high-value but hard.

---

## 1. Feature inventory

**How Evoto structures it [F][35]:** the Edit workspace has five **modules**: Color Adjustments, Portrait Retouching, Background Adjustments, Clothing & Accessories, and Crop & Rotate. AI Lab sits on top for generative and cloud tools. Each module holds **feature groups**, which hold **sliders and toggles**.

**Conventions that hold almost everywhere [F]:**
- Effects are 0–100 one-way sliders unless noted. Reshape sliders are bipolar, −100 to +100, default 0.
- A main toggle or slider unlocks **sub-sliders** (for example, Brightness unlocks Iris, Whites, Reflection and Flare).
- Paired features have a **link icon** for left/right ("conjunction/separate"). They are linked by default.
- Most groups have a **Manual Tuning Pen** (brush/erase on the AI's effect mask).
- Most effects can be **saved to presets and synced**. Liquify, healing and mobile Reshape cannot [F][62][65].

### 1.1 Portrait / Skin

| Feature | Exact controls exposed | Scope / detection | How it applies | Quality notes |
|---|---|---|---|---|
| **Freckle & Acne Removal** | Main toggle + slider. Two sub-sliders: **Freckle** and **Acne**, active only once the main toggle is on [F][12][13] | Per group/face. Auto-detects spots. **Beard Protection** always runs when facial hair is detected [F] | AI detect + inpaint. Manual Tuning Pen restores spots. v8 improved separating freckles from acne [F][71] | Reviewers call it the standout: "results from Evoto are better overall" than Retouch4me [R][73]. Early versions over-removed freckles and moles; Evoto's own article covers restoring them [F] |
| **Texture Retention (child)** | Slider in the **Child** tab, only when a child under 3 is detected [F][12] | Age-aware | Limits smoothing on newborn skin. Old presets treat it as 0 | — |
| **Face Mole** | One-click toggle [F] | Per face | Removes moles; restore with the pen | — |
| **Reduce Face Shine** | Slider [F] | Face skin | Detects oily highlights and flattens them, keeping texture | — |
| **Dark Circles** | Slider (right = lighter) [F][12] | Under-eye region | Lightens pigment and shadow | — |
| **Eye Bags** + **Lower Eyelids Protection** | Eye Bags slider. Protection sub-slider, **default 100** [F][12] | Under-eye | Removes puffiness while protecting the natural lower-lid volume | — |
| **Remove Glass Glare** | Single slider. Not for tinted lenses [F][12] | Auto-detects glasses | AI removal. **AI Lab › Strong Glare Removal** (generative) handles large reflections and works per person in groups [F][44] | Fstoppers was "surprised at how well it handled such a bad glare" [R][73]. Marketing says catchlights under the glare are preserved [F][9] |
| **Nostril Cleanup** | Slider + manual brush [F] | Nose | Removes debris around nostrils | — |
| **Lip Wrinkles & Flakes** | Slider [F] | Lips | Smooths dry or cracked lips | — |
| **Double Chin** | Slider [F] | Chin | Subtle liquify plus shadow blending | — |
| **Facial Wrinkles** (8 zones) | **Forehead Wrinkle, Eleven Lines, Eye Wrinkle, Nasal Wrinkle, Smile Line** (separate L/R, linked by default), **Cheek Wrinkle, Marionette Lines, Perioral Wrinkle** [F][12] | Landmark zones | Each zone smoothed independently | Reviewers like the per-zone granularity [R][75] |
| **Body Refinement** | **Body Blemish, Infant Body Blemish** (only when the subject is tagged infant), **Neck Wrinkle, Armpit Touch-up, Stomach Stretch Marks** (+ **Pregnancy Line** sub-slider), **Stretch Marks, Feet Vein**, **Body Hair Removal** (AI Lab, Asia only) [F][12][44] | Body skin | Detection + inpaint | — |
| **Tattoos** | Toggle → manual brush mask → OK [F][13] | Manual mask | Inpaints the masked area | "Erases tattoos in a single click" [R][74] |
| **Even with Dodge & Burn** (face) | Slider, 0–100 [F][11] | Face skin | Automatic micro dodge & burn: evens tone, softens wrinkles and blemishes | Praised as natural, keeping texture [R][76] |
| **Sculpt with Dodge & Burn** | **Facial Features** + **Facial Contours** sliders [F] | Face | Adds 3D shape (eyes, lips, nose; bone structure) | — |
| **Textured Smoothing** | Slider [F] | Face | D&B-based smoothing that keeps highlights, shadows and texture | — |
| **Frequency Separation** | **High Frequency** (texture ±) + **Low Frequency** (tone smoothness ±) [F] | Face; also a body version | Classic two-layer method exposed as sliders | "Frequency separation can be performed with a simple slider" [R][74] |
| **Skin Softening** | Slider [F] | Face; also body | Low-frequency smoothing; warns about a plastic look | — |
| **Body Even (D&B)** | Slider 0–100, default 0 [F] | Body skin | Evens cellulite and compression shading | — |
| **Skin Texture** | Presets **Matte / Satin / Dewy**. Sliders **Glossiness, Texture, Clarity** [F][11] | Skin | Texture overlay / re-synthesis | — |
| **Skin Tone** | **AI Unify Face Complexion; AI Unify Body Complexion; Unify Body Complexion** (face↔body). **Select Skin Tone**: 8 preset swatches + intensity, **Temperature**, **Tint**. **Skin Radiance**; **Rosy Complexion** (±). **Remove Tan Lines**: toggle, **Standard/Enhanced**, brush/erase. **Eyedropper complexion** in v7.1 [F][11][45] | Face vs body masks | Skin Color Change also shifts lips and features; Radiance protects features [F] | v7.1 fixed a gray cast on deeper/brown skin when unifying body tone [F][45] |
| **Hands** | **Even (D&B), Hand Vein, Hand Reshaping** [F][23] | Hands + forearms | — | — |
| **Clothing & Accessories** (its own module) | **De-wrinkle Clothing**: Upper/Lower Garment, Fine/Coarse sub-sliders, gender/age options. **De-blemish Clothing**: Lint Removal; **Sweat Stain Removal** per group (All/Male/Female/Older/Children) + Sweat Stain Masking. **Clothing Edge Smoothing** (+ Edge Refinement pen, Objects Protection). **Clothing Moiré Removal** (AI Lab) [F][24][44] | Clothes mask; per group | Syncable | "Knows which wrinkles to keep to maintain the shape" [R][73] |

### 1.2 Face & body reshaping

| Feature | Exact controls exposed | Scope | How it applies | Notes |
|---|---|---|---|---|
| **Head Pose** | **Up/Down, Left/Right, Tilt**, −100…+100, default 0 [F][20] | Per face | 3D-aware face re-pose | [I] Implies a 3D face model fitted to landmarks |
| **Face Shape** | **Face, Temple, Cheekbone, Jaw, Face Size, V-Shape** (L/R), **Jaw(line) Length, Face Width** (L/R, v5.1), **Hairline, Forehead Height** (L/R), **Forehead Width, Philtrum, Middle Section, Lower Section, Taper Chin, Chin Length, Chin Shape** (L/R, v6.2), plus **Jawline** and **Facial Fullness** (v7.0) [F][20][46][5] | Per face/group | Landmark-driven liquify | AI Lab **Liquify Background Repair** fixes bent backgrounds caused by warping [F][44] |
| **Eyebrows** | **Thickness, Distance, Tilt, Arch Height, Position** (L/R) [F] | Per face | Warp | — |
| **Eyes (shape)** | **Full Eye Size, Eyeball Size, Height, Width, Distance, Inner Corner, Outer Corner, Tilt, Position**, plus **Double Eyelids** (v5.0) [F][20][5] | Per face | Warp | — |
| **Nose** | **Size, Length, Horizontal, Nose Bridge, Width, Nose Tip** [F] | Per face | Warp | — |
| **Mouth** | **Size, Width, Vertical, Horizontal, Tilt, M-shaped Lips, Upper Lip, Lower Lip** [F] | Per face | Warp | — |
| **Symmetrize** | **Facial Symmetry** + **Upper Body Symmetry**, 0–100 [F] | Front-facing subjects | Symmetry warp | — |
| **Facial Expression** | **Gummy Smile** (L/R), **Gentle Smile**, **Smile Generation / Toothy** (5 levels, slight smile → laugh), **Neutral (Smile Reversal)** (levels 0–3, default 3), Manual Tuning Pen [F][22] | Per face | **Generative** mouth synthesis. Auto-disables on pouts, profiles and occlusions [F] | "Swap closed mouth for smile with teeth showing" [R][75]. Digital Camera World asked whether this goes "too far" [R][74] |
| **Eye Symmetry** | **Eye Symmetry** auto-enables **Eye Level** + **Eye Balance** (reference eye = larger by default, or pick L/R) [F][16] | Per face | Warp | — |
| **AI Iris Correction** | Auto + **Direct Gaze**; manual per-eye **horizontal, vertical, size** [F][16][45] | Per face | Gaze/strabismus fix (v7.1) | Fails on strong profiles [F] |
| **AI Open Eyes / Perfect Shot** | AI Lab "AI Open Eyes" (generative). **Perfect Shot**: **Auto Fix / Custom Fix** swaps in better expressions from the ±7 neighbouring frames (14 in total) of the same person [F][43][52] | Same person only | Writes a new `.tsq` file | Amateur Photographer: "Perfect Shot fixes closed eyes in group photos" [R][75] |
| **Full Body Reshape** | **AI Reshape** (3D skeleton + posture; **Smooth Physique** works only when AI Reshape < 0). **Head, Body, Height, Upper Body Length, Neck Width** (L/R), **Neck Length** (±100), **Arms, Breasts, Waist Width** (L/R), **Waist Length, Hips** (L/R), **Leg Width** (thigh/calf, or linked "Amount"), **Leg Length** (thigh:calf default 80:100, golden-ratio based) [F][21]. **Belly Slimming** (AI Lab) [F][44] | Per person | Skeleton-guided liquify | Sliders **grey out** when a body part isn't detected reliably. Several are disabled in group photos [F][63] |
| **Manual Liquify** (toolbar) | **Forward Warp, Reconstruct, Smooth, Twirl Clockwise, Pucker, Bloat, Push Left, Freeze Mask, Thaw Mask**. Settings **Size, Density, Pressure, Rate**. **Pin Edge**, **Show Mask** [F][37] | Manual | Own 10-step history. Not syncable | — |

### 1.3 Eyes / Teeth / Lips / Makeup

| Feature | Exact controls exposed | Scope | How it applies | Notes |
|---|---|---|---|---|
| **Eye Brightness** | **Brightness** unlocks **Iris** (0–100, default 80), **Eyes (Whites)** (default 80), **Eye Reflection** (default 40), **Iris Flare** (default 0). Linked or separate L/R [F][16] | Per face | Masked luminance | Headshot guide suggests 30–50% and warns against >60% [F][9] |
| **Eye White Enhance** | **Red Vein Removal**, **Eye White Cleanse** [F] | Sclera | Color + vein cleanup | — |
| **Red Eye Removal** | Toggle [F] | Auto-detect | — | — |
| **Catchlights** | 12 styles (6 General, 6 Indoor), intensity, drag to reposition [F] | Per eye | Overlay | Pets get 11 styles plus position and rotation [F][46] |
| **Teeth** | **Teeth Flaws Removal** (braces, stains, gaps) + **Fix Teeth Edge** toggle. **Teeth Whitening** unlocks **Brightness** + **Desaturation**. **Teeth Alignment** (5 levels, adults only). **Pretty Teeth** (generates a full set) [F][17] | Per face | Mix of AI correction and **generative** replacement | Flaws Removal doesn't work on generated teeth [F] |
| **Makeup (basic)** | **Highlight, Contour**. **Eyebrow Makeup** (±). **Eye Makeup**: Amount, Saturation, Brightness, Dimensionality. **Lip Makeup**: Amount, Saturation, Luminance/Brightness, Dimensionality [F][18] | Per face | Enhances existing makeup. Backlight detection auto-reduces intensity [F][47] | — |
| **Makeup Looks** | **Makeup Suite**: 22 looks (3 male, 2 child), each with Amount. Components: **Eyebrows** (9), **Eyeshadow** (14), **Eyelashes** (17), **Eyeliner** (9), **Contacts** (11), **Blush** (12; 10–12 for kids), **Lipstick** (15 colors + Texture), **Contour** (6), **Face Decorations** (6 freckle styles) [F][18] | Per face | Replace or enhance existing makeup | — |

### 1.4 Hair

| Feature | Exact controls exposed | Scope | How it applies | Notes |
|---|---|---|---|---|
| **Hair Part Line** | Slider [F][19] | Hair | Fills sparse parting, temples, sideburns | — |
| **Volume** | **Top Hair Volume** ("High Cranial Top") + **Side Hair Volume** [F] | Hair | Warp | — |
| **Hairline** | Slider (shared with Face Shape) [F] | — | — | — |
| **Stray Hairs Removal** | **Within Figure Outlines** + **Beyond Figure Outlines**, separate sliders [F][19] | Hair matte | Removes flyaways over the face and against the background | Repeatedly named as a reason to buy [R][6][73] |
| **Smooth Hair** | **Smooth Hair** (auto-sets **Tame Frizzy Hair** to 100) + **Tame Frizzy Hair** [F] | Hair | — | — |
| **Hair Shine Enhancement** | Slider [F] | Hair | Adds highlights | Also in Video v8 [F][71] |
| **White Hair Blackening** | Slider. Designed for black hair [F] | Hair | Recolors grey/white strands only | — |
| **Hair Color** | Palette + **Hair Color Adjustment** slider. **Golden Blonde Hair** (AI Lab, generative) [F][19][44] | Hair | — | — |

### 1.5 Background

| Feature | Exact controls exposed | Scope / detection | How it applies | Notes |
|---|---|---|---|---|
| **Distractions Removal** | Toggle; auto-detect dropdown (force "Distraction") [F][25] | **Auto-runs only when a solid backdrop *and* distractions are detected.** Complex backgrounds default to "Auto-Detect: No Distractions" | Removes stands, cables and gaps at the backdrop edge, and **expands the canvas** | Forcing it on complex scenes is flagged as risky [F] |
| **Clean Backdrop** | Slider. **Background** (default 100%) and **Ground** (default 100%) sub-sliders. Manual brush → **Apply Enhanced Removal**. Force "Solid Backdrop" mode [F][25] | Solid-backdrop classifier | Removes backdrop dust, wrinkles and scuffs | Sync across non-solid scenes can damage props [F] |
| **Smart Removal** | Guided cleanup when Evoto detects removable areas [F][26] | Auto | — | — |
| **Unify Lighting** | Toggle unlocks **Amount** (0–100) + **Luminance** (±) [F] | Solid backdrops: paper, seamless walls, fabric, white walls, plain floors | Evens backdrop falloff and hotspots | — |
| **Color Banding Removal** | Toggle; auto-on for solid backdrops [F] | Solid backdrops | Removes banding, moiré and ripples | — |
| **Background Enhancement** | Slider [F] | Background | AI saturation and contrast | — |
| **Black & White Edge Removal** | Toggle + brush/eraser + **Update** [F][26] | Subject edge | Cleans halos after a background swap | Manual brushing isn't synced |
| **Backdrop Changer** | Source: **Recommended / My Backdrops** (upload ≤20 MB, grouped) **/ Assets / Solid Color**. **Extraction: Auto / Natural / Precise**. **Preserved Area: Subject / +Related Objects / +Non-Connected**. **Fill Region: Original / Cropped**. **Fill Mode: Center Fill / Center Alignment / Stretch**. **Blend Mode, Edge Adjustments, Opacity, Size, Vertical, Horizontal, Blur, Remove Spill, Floor Reflection** (Opacity, Shadow Blur, Blur Range, Gradient). **AI Retain Shadows**. **Add Shadow: None/Soft/Hard/Drop** with Opacity, Shadow Blur, Gradient, Blend Mode [F][26][45] | Person matte | Matting + compositing; syncable | "AI does a brilliant job of cutting out your subject" [R][74] |
| **Background Color Consistency** | Select several → **Match** [F][28][45] | Background only | Aligns backdrop tone across a set (school, ID, headshots) | Later style looks may clear it |
| **Sky Replacement** | Recommended or own sky. **Rotate & Flip, Angle, Sky Gradient, Edge Transition, Vertical/Horizontal, Temp, Tint, Saturation, Brightness, Sky Blur, Opacity**. **Scenery Color / Human Color (Match Sky)**. **Water Reflection Adjustment + Water Blur**. Brush + **Smart Edge Brush** [F][26][27] | Sky detector ("No skies detected") | Composite + relight match | A generative AI Sky Replacement in AI Lab returns 2 results [F][44] |
| **Lens Blur** | **AI Lens Blur** + **Blur Amount**. Bokeh **Circle, Circle 2, 5-Blade, 8-Blade, Cat's Eye** + **Boost**. **Focus Range**, **Visualize Depth**, Manual Refinement [F][29] | Depth map | Syncable | — |
| **AI Lab (generative)** | **AI Background Fusion** / "AI Set Fusion" (scene packs, ≤50 foreground layers, Character Lighting, batch scenes). **Generative Expand** (3 results per run). **People Removal** (0.3 credits). **Smart Removal: Magic** (0.5 credits) / **Quick** (0.1 credits). **Grass Fill** (2 results), **Face Shadow Removal**, **Shadow Remover** [F][44] | Cloud | Writes new image copies (`.tsq`) | Billed per generation, not per export [F][52] |

### 1.6 Color

| Feature | Exact controls exposed | Scope | How it applies | Notes |
|---|---|---|---|---|
| **Auto Color Corrections** | **Apply** → turns on **AI White Balance** + **AI Exposure** (magic-wand icons) [F][28] | Image | Overwrites WB and exposure | Credit-free for paid users [F][50] |
| **Multi-Image Color Consistency** | Select several → **Match** to the reference [F] | Set | Overwrites WB, HSL and curves; keeps lens and grain | Recommended order: style first, then consistency [F] |
| **AI Color Looks** | ~20 named looks (Neutral, Vivid Light, Pure Love, Clear Nature, Vibrant Warmth, Bright Blossoms, Bright Minimal, Elegant Shades, Olive Green Film, Nile Blue Film, Dawn Voyage, Ember Glow, Sunshade, Golden Ray, Warm & Cozy, Warm Cinnamon, Arctic Blue, Luxury Texture, Visual Impact, Timeless Romance) + **Application Amount** [F][31] | **Auto local masks**: subject and skin protected, background styled separately | Per-image adaptive (adjusts its own exposure and WB per photo) | Costs 1 credit [F] |
| **AI Color Match** | **Upload for Color Matching** or **Create Color Match from Preview**. **Amount, Tone, Color**. Local fine-tune per mask (face/body skin, hair, eyes/lips/teeth, clothes, background) with link. **Quick Mode vs Control Mode**: Control writes the result *into the normal sliders* and auto-creates local masks. Reference Management groups [F][30] | Semantic masks | Clears existing color edits on apply | Six region-aware default references; skin matching tuned for diverse skin [F][47] |
| **Personal AI Look** ("learn my style") | **Lite**: from a single `.xmp` or Evoto color preset. **Personal**: name, type (Wedding/Portrait/Family…), Color or B&W, RAW/JPEG/Both, **≥200 images per format**, sources LrC catalog / Evoto projects / RAW+XMP folder, **AI Smart Selection** (≥50 images). Preview 5 images, then tune Basic in **AI Correction** (offset) vs **Fixed Value** modes, plus Curve, HSL, Grading, Calibration. Up to 100 looks [F][32][8] | Image | Trained server-side; status Unready / Ready / Training / Locked | RAW looks only apply to RAW files [F] |
| **Manual color** | Histogram (RGB/Lab readout). **Real-Time Color Adjustments** (shows color only). **Profile** (Standard, LUT, B&W). Filters. **Basic**: WB presets + picker, Exposure, Contrast, Brightness, Highlight, Shadow, White, Black, Texture, Clarity, Dehaze, Vibrance, Saturation. **Levels**. **Curves** (parametric, RGB, Luma, R/G/B, ≤16 points, on-image tool). **HSL** (8 ranges + picker). **Color Grading** (3 wheels, Blending, Balance). **Selective Color** (9 channels CMYK, Relative/Absolute). **Detail** (AI Denoise for RAW → `.evr` copy; Sharpen; NR; Color NR). **Grain**. **Lens Corrections**. **Transform** (AI Smart/Level/Vertical + Guides). **Color Calibration**. **Creative Effects** (Glow: White Mist/Black Mist/Halation; Post-Crop Vignetting; Lens Blur) [F][28][29] | Image or mask | Lightroom-like | XMP/CUBE import; LrC slider values import from `.lrcat` [F][38][40] |
| **Masking** | **Person** (per person or All Persons; face/body parts, **Ears**, **Apparel**: Tops, Inner Layer, Dress, Bottom, Shoes; Accessories: Headwear, Gloves, Bag, Jewelry). **Pet** (dogs, cats, pigeons, parrots). **Background** (sky, **Reef**, …). **Custom** (Brush: Size/Softness/Flow/Density; Linear; Radial; **Luminance Range**). **Smart Selection**: Segment (pre-segmented hover), Interactive (point/box), Quick (1–300 px brush); Smooth/Expand/Contract (1–500 px), Feather. Add/Subtract (X). Eye toggle excludes a mask from export [F][33][46] | Masks hold Basic, Curves, HSL, Grading, Detail | Masks are syncable (Replace / Add to Existing) | Person masks sync globally, not per individual [F] |

### 1.7 Batch / Workflow

| Feature | What it does / controls | Notes |
|---|---|---|
| **Presets** | Libraries **Recommended / Team / My** (+ **Hot** and official portrait presets Natural, Silk, Flawless, Energized, Sculpted on mobile). **Types: Portrait / Color / AI Color Look / Combination**. On save, choose which effects to include. Groups with drag sort. Right-click **Update Preset with Current Settings**, **Share Preset(s)** (token; custom memorable tokens), Rename, Delete. Import `.xmp`/`.cube`. **Preset Intensity**: separate **Color** and **Portrait** sliders (mobile) [F][38] | **Character-aware**: portrait values are stored per gender/age group. A female-only preset in linked mode leaves males and children untouched [F][14][77] |
| **Sync** | Source is the yellow-highlighted photo, targets white-highlighted. **Sync to all pictures**, Cmd/Ctrl+C/V. Gear dialog picks modules (AI Color, Color, Portrait, Background, Clothing, Crop & Rotate, Others). "Pop-up frequency": once per project (default) or **Always Trigger** [F][39][36] | Individual edits only sync **to the same person** in other photos. Single-person masks don't sync [F] |
| **Per-face editing** | **Face Detection/Recognition** button (top-right of the control panel) shows face boxes and tags. Edit tags; **Locate Face** adds a face (blocked above 50% overlap); delete; Cmd multi-select; **sync tag changes project-wide**. Group tabs (**All** = linked, with group exclusion) + **Individual** tab. Face List shows only edited faces, newest first. **Show Face Frame** toggle [F][14][15] | Individual inherits group values until edited, then detaches; reset re-attaches [F] |
| **Auto Import & Export (hot folders)** | Up to 100 watched folders (+ first-level subfolders); file types JPEG/RAW/TIFF/PNG; preset applied on import; **Smart Import Detection** (resume); export interval 1 s–1 h (default 10 min); import wait time default 2 s; JPEG/PNG integrity check [F][41][56] | Editing is locked while Auto Export runs. Capture, watch and export folders must differ |
| **Tethering** | Canon, Nikon, Sony, Fuji, Leica, Olympus, Panasonic; wired and wireless; desktop, iPad and mobile. "Next Photo Effect": **Sync Previous / Apply Preset / No Effect** [F] | Free to use; credits only on export |
| **Lightroom Classic** | **Edit in Evoto** round-trip ("Return to LR"); `.lrcat` import with collections/filters and **Import Settings from .lrcat** (basic sliders); export **Merge into Original Catalog** / **New Catalog**, Include Color Adjustment parameters, Replace Non-RAW (with backup); LrC plugin [F][42] | Transform, lens, lens blur, local masks don't transfer |
| **Workflow templates** (v8) | Recipe **Import → Cull → Apply Effect → Export → Deliver**. Official templates for wedding, portrait, headshot, school, family, baby, fashion, general [F][61] | "Everything happens in the background" (Mark Wallace demo) [R][72] |
| **AI Lab Batch Edit** | People Removal, Old Photo Restoration, Detail Enhance in batch; batch scene fusion [F][44] | — |
| **Virtual copies, History, Undo** | Virtual copies (Ctrl/Cmd+'), not charged twice. History panel keeps 30 records across restarts. Global undo (v7.1). Liquify/heal have a 10-step local history [F][36][62] | — |
| **Assistant / search** | **Unified Search** (Cmd+F: features, sliders, projects, presets; expands collapsed groups). **Evobot / Ask Me** natural-language help that deep-links and highlights the control [F][61][37] | — |
| **Favorites** | Pin modules or single sliders into one tab; stored locally [F][45] | — |
| **Cloud Space** | Personal and team spaces, upload/download projects, **Smart Preview** (4000 px, under 2 MB, doesn't count against quota), version history, roles [F][58] | Desktop only |

### 1.8 Culling

| Feature | Controls | Notes |
|---|---|---|
| **Smart Culling** (Library › Culling tab) | Subpanels **Basic Info / Filters / Faces / Photo Cluster**. Project-level only. **Start Mode Quick/Custom**. **Event Type**. **Best Picks**: limit total, or per cluster min/max, by Duplicates / Face / Time Interval. **Auto Apply Marks** (incl. **Candidates**, **AI Unselected**). **Auto Save Tags to Local** (XMP for LR/Bridge). Sensitivity for **Closed Eyes, Blur, Exposure**, cluster sensitivity [F][43][46] | Behind the Shutter: "nailed about 95% of selections" [R][78] |
| **Face scores** | Per-face labels: **Eye Status** (Open / Half-Open / Closed / Blurry), **Expression** (Big Smile / Smile / Neutral), **Face Focus** (In Focus / Soft / Blurry). **Face Focus** full-screen face zoom. **Face Gallery** filters by person [F][43][46] | — |
| **Clusters** | **Time Interval** (default 10 s), **Duplicates** (best-of-group by quality score), **Faces** [F] | — |
| **Stories & Segments** (v8) | **Storyline** (wedding chapters), **General** (visual similarity), **Manual**. Segment filter everywhere; export folders by segment; publish each Story as a gallery [F][43][71] | — |
| **Search by Text / Custom Tags** | Natural-language search ("red dress", "kiss"), background incremental analysis; account-wide custom tags [F][43] | [I] CLIP-style embeddings |
| **Instant culling** | Rules **Closed Eyes** (laughing exception; skip groups above N faces), **Blur, Under/Overexposure, Duplicates** (keep top N), Low/Med/High sensitivity, upload only approved photos [F][59] | — |

### 1.9 Export / Delivery

| Feature | Controls | Notes |
|---|---|---|
| **Export dialog** | Menu: **Quick Export / Custom Export / Export with Previous / Export as Catalog**. Left: counts + **Export Presets** (multi-select = multiple versions). Center: preview. Right: **Effect Preset** (apply a look at export), Export To, Auto-Create Subfolder, name collisions (**Add Suffix / Skip / Replace**), 9 naming schemes, scale (%, W×H, long/short edge, PPI/PPC), format (Original / JPG 8-bit / TIFF 8/16-bit / PNG with alpha), JPG quality (Low/Med/High/Best or %, min 20%, or **Limit File Size**), **Output Sharpening** (Screen/Print × Low/Std/High), **Watermark** (image, rotation, size, opacity, position), **Sync to Evoto Instant** [F][40] | Limits: max 1 GB or 12,000 × 12,000 px; 15,000 photos per import; preview up to 4,000 px [F][40] |
| **Credits at export** | 1 credit per *unique* edited photo; re-export free; virtual copies not charged twice; re-imports charged again [F][48][49] | The preview shows a watermark until export [F][36] |
| **Evoto Instant (delivery)** | Phone app + web portal. Pipeline **Imported → Uploaded → AI Edited → Exported → Shared**. Galleries: **Full / FaceKey / Personal**, branding (banners, watermark, domain), QR/SMS/email, **Find Me** face search, **School Mode** (CSV roster → QR cards → auto-sort → Stripe store: per photo / free+paid / full gallery), analytics [F][59][60] | Lets studios sell on site |
| **Slideshow** | Music, backdrop, intro title → video export; re-exports free [F][36] | — |
| **Video** | Evoto Video desktop + DaVinci Resolve 19 / Premiere plugins; Male/Female/Child/Senior groups; **1 vCredit per second** of retouched footage [F][54][71] | Cloud-processed [F][54] |

### 1.10 Platforms and products

| Product | Platform | Notes |
|---|---|---|
| **Evoto Desktop** | Windows 7/10/11 x64, macOS 10.13+ (Intel and Apple Silicon); 8 GB RAM min, 32 GB recommended [F][57] | Main product. Beta and Stable channels |
| **Evoto iPad** | iPadOS | Near-full feature set. Shares credits [F] |
| **Evoto App (mobile)** | iOS, Android | Monthly 60 credits / yearly 800. Hot Edits, tethering in v8, Reshape tool (8 tools, not syncable) [F][53][65] |
| **Evoto Online** | Browser, one tool per page (150 `/features/*` URLs) | Free low-quality export; 1 credit at max quality; AI Lab per generation [F][52][10] |
| **Evoto Instant** | iOS 14.2+ / Android 9+ app + web portal | Event and school delivery; sells photos [F][59] |
| **Evoto Video** | Desktop + NLE plugins | vCredits [F][54] |
| **Asset Hub** | In-app marketplace | Presets $8–30, AI Looks $49–199, backdrops/skies $2–8; creators get 60% [F][R][71] |

---

## 2. Core workflow and UI layout (for a designer to recreate)

### 2.1 Information architecture
**Home** (v8):
- Create Project
- Tethered Shooting
- Workflow
- Asset Hub
- Ask Me

**Library** workspace (`G` grid, `L` loupe, `N` survey) ↔ **Edit** workspace (`D`).

**AI Lab** is entered from an icon at the top-left of Edit. Workspace switching is one keystroke [F][36][35][61].

### 2.2 Library workspace [F][36]
```
┌ Top bar: Undo · Create Project · Import(+) · Search(⌘F) ···· Export · Export History · Profile · Purchase ┐
├ LEFT (resizable)     ┬ CENTER                                   ┬ RIGHT "Quick Access" (resizable)  ┤
│ Cloud Space switch   │ Grid (zoom slider) / Loupe / Survey ≤12   │ Tabs: Culling | Presets & Sync |  │
│ Projects (+ groups)  │ hover: stars, flags, color labels         │       Metadata | Slide Show       │
│ Related Folders      │ preview watermark (not on export)         │ Culling: Basic Info, Filters,     │
│ Collections          │                                           │  Faces, Photo Cluster, Start btn  │
│ Bin                  │                                           │ Sync button at bottom             │
├──────────────────────┴───────────────────────────────────────────┴───────────────────────────────────┤
│ BOTTOM filmstrip: thumbnails · filter bar (\) · sort · Detail/Quick filter modes · quick-mark strip  │
└──────────────────────────────────────────────────────────────────────────────────────────────────────┘
```
Key shortcuts:
- Ratings `1`–`5` (`0` clears)
- Flags `P`, `X`, `U`
- Colors `6`–`9`
- Virtual copy `⌘'`

### 2.3 Edit workspace [F][35][37][15]
```
┌ Top: ← Project(G) · Add Images(+) · Undo/Redo · Manual Tools [Liquify | Healing] · Reset ▾ · Search · AI Lab · Export ┐
├ LEFT floating widget ┬ CENTER preview                          ┬ RIGHT Control Panel                      ┤
│ [Presets]            │ live render of all modules              │ Module tabs: Color · Portrait ·          │
│  Recommended/Team/My │ SPACE = before/after                    │  Background · Clothing · Crop · ★Favs    │
│  groups, +import     │ right-click = canvas color              │ [Face Detection] button (top-right)      │
│ [Masking] list + 👁  │ face boxes + gender/age chips when      │ Group tabs: All(link) · F · M · Child ·  │
│ [History]            │  face mode is on; selected = yellow     │  Senior · Individual                     │
│                      │ manual-pen overlay (red/white)          │ Feature groups (collapsible; Solo mode)  │
│                      │                                         │  each: 👁 hold-to-compare, toggle,       │
│                      │                                         │  sliders + numeric field, 🔗 L/R link,   │
│                      │                                         │  ✎ Manual Tuning Pen, ▾ auto-detect mode │
│                      │                                         │ Bottom: [Save Preset] [Sync ⚙]           │
├──────────────────────┴─────────────────────────────────────────┴──────────────────────────────────────────┤
│ BOTTOM gallery: thumbnails (show edited), filters (rating/label/flag/version/edit/export/format/orientation/ │
│ filename/camera/lens), resizable; source = yellow outline, sync targets = white outline                     │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```
The group-tab labels vary slightly between surfaces in the docs ("Older" vs "Senior", "Children" vs "Child") [F][24][54]. I couldn't see a current desktop screenshot to confirm their exact order and look **[U]**.

### 2.4 The core loop, step by step
1. **Create a project.** Name it, optionally put it in a group, and optionally tick **Enable Smart Photo Analysis**, **Auto Import & Export**, or a **Workflow** [F][43][41][61].
2. **Import.**
   - Sources: files or folders (drag and drop), a `.lrcat` (with slider import), tethering, hot folder, or right-click **Open With › Evoto** in Finder or LrC.
   - In tethered and hot-folder modes a preset is applied **on import** [F][40][41].
   - Importing into an empty project auto-switches to Edit (setting) [F][56].
3. **Analysis in the background.** Faces are detected and tagged by gender and age. If enabled, culling signals are computed: blur, eyes, exposure, clusters [F][14][43].
4. **Cull** (optional, Library). Start Smart Culling. Review Faces, Clusters and Stories. Auto marks are written to XMP [F][43].
5. **Apply a preset.** Click one in the left widget. Portrait values resolve **per detected group**. AI Color Looks and Match adapt per image [F][38][31].
6. **Tune globally by group.** Use the right panel. **All** edits every group (linked). The Female, Male, Child and Senior tabs edit only that group [F][14][15].
7. **Fix individuals.** Turn on Face Detection, click a face box, use the **Individual** tab to adjust, then **Sync** to that same person across the project [F][14][15].
8. **Correct the AI.** Use the **Manual Tuning Pen** in the module, or Healing and Liquify from the top bar [F][12][37].
9. **Compare.**
   - **Space** shows the whole image before/after.
   - **Press and hold a group's eye icon** to disable just that group.
   - **Press and hold a slider** to disable just that slider [F][35].
10. **Sync or save.** Select targets, then **Sync** (gear = which modules). Or **Save Preset**, choosing type and included effects [F][39][38].
11. **Export.** Quick, Custom, or Previous. Export presets can produce several versions at once. Credits are charged once per unique photo. Optionally **Sync to Evoto Instant** to deliver a gallery [F][40][48].

### 2.5 Interaction details worth copying
- **Graceful AI uncertainty:**
  - Sliders **grey out** when a body part isn't detected [F][63].
  - Background tools offer an **auto-detect mode dropdown** you can force: "Distraction", "Solid Backdrop" [F][25].
  - Generative tools **auto-disable** on unsupported poses [F][22].
- **Sub-sliders appear only after the parent is enabled.** This keeps a huge surface manageable [F].
- **Defaults encode expertise.** For example, eye Iris and Whites default to 80, Reflection to 40, Lower Eyelid Protection to 100, and leg ratio to 80:100 [F].
- **Discoverability:** search over every slider plus an AI assistant that deep-links to a control. Reviewers needed this because of the sheer feature count [F][R][74].
- **Free previews with a watermark, payment at export** removes friction to try everything [F][48].

---

## 3. Business model

### 3.1 Credit rules [F][48][49][50]
- **1 credit = 1 exported edited photo.** Editing, AI previews and tethering are free.
- Re-exporting the same photo is free. Re-imports, or the same file imported from another device, are charged again.
- Exporting an unedited original is free.
- **Credit-free features** (paid users, v6.1+) cover color adjustments, masking, manual tools, and crop & rotate. **Not included:** AI Color Looks, AI Color Match, Multi-Image Consistency, and *all* Portrait Retouching. A first export that used a credit stays charged.
- Credits are shared across Desktop, iPad, mobile and Instant. Video uses separate **vCredits**.
- **AI Lab** is billed **per generation**, for example Quick Removal 0.1, People Removal 0.3, Magic Removal 0.5, Open Eyes 3 (2K), Clothes Color Changer 8–10 [F][44][52].

### 3.2 Prices (USD, checked 2026-10-03) [F][2][48][51][53][54]

| Plan | Price | Credits | $/credit | Devices |
|---|---|---|---|---|
| Starter (annual) | $89 | 800 | 0.11 | 2 |
| Basic | $149 | 1,600 | 0.09 | 3 |
| Basic Plus | $269 (shown $242 on promo) | 3,600 | 0.07 | 4 |
| Standard | $579 ($521 promo) | 9,000 | 0.06 | 5 |
| Standard Plus | $1,339 ($1,205 promo) | 24,000 | 0.05 | 6 (+ account manager, 1:1 tutorials) |
| Pay-as-you-go | $49 / $89 / $169 / $459 | 200 / 500 / 1,200 / 3,600 | 0.25 → 0.13 | 2 |
| Add-on packs (subscribers) | at the tier's unit price (e.g. Basic Plus 1,200 = $90) | — | — | — |
| Cloud storage | $119 / $189 / $269 | 500 GB / 1 TB / 2 TB | — | — |
| Mobile | monthly (price not shown) / yearly | 60 per month / 800 per year | — | — |
| Video | 1 vCredit per second of portrait retouching; color free for now; 60 free vCredits | — | — | — |
| Enterprise | custom | — | — | team spaces, team presets |

**Policies:**
- **Rollover** of unused annual credits is capped at 5× the plan's credits, and only if you renew within the 30-day grace period. **Downgrading forfeits the excess.**
- Pay-as-you-go credits expire after 2 years.
- No refunds.
- The **7-day trial** gives 50 credits, needs a $1 card pre-authorization, and **auto-converts to an annual plan**.
- **15 free credits** for completing your profile (valid 30 days) [F][49][51][2].

### 3.3 Cost per photo in practice
- **Wedding:** 800 delivered photos × 25 weddings = 20,000 credits, so Standard Plus at about **$0.05–0.06 per photo**, or about **$40–50 per wedding** [I], in line with [R].
- **Fstoppers:** retouching every frame "could eat through $500 worth of credits in about four weddings." That implies pay-as-you-go-like rates [R][73].
- **Digital Camera World:** about **$0.05–0.25 per image** depending on plan [R][74].
- **Rollover trap:** one Trustpilot user calculated their effective cost tripled (≈$0.055 → $0.17 per photo) after a downgrade forfeited 6,373 credits [R].

### 3.4 Target users and go-to-market
- **Segments marketed** [F][10][6]:
  - Wedding, portrait, **headshot**, **school & sports** (Instant School Mode with Stripe store)
  - Family, newborn, maternity
  - Fashion, makeup and advertising
  - E-commerce and product
  - Pet, underwater
  - Studios and enterprise (team spaces and presets)
- **Acquisition:**
  - **Programmatic SEO**: 150 `/features/*` URLs (135 tool or segment pages plus RAW-converter variants), each doubling as a free single-tool web editor ("Evoto Online") [F][10][52].
  - Educator partnerships: Pratik Naik course, Mark Wallace CreativeLive class [F][83][84].
  - Trade shows (Imaging USA) and its own "Evoto ONE" launch event in NYC [F][70].
  - Referral programme.
  - Asset Hub creator marketplace (60% payout) [F][71].
- **Positioning copy:**
  - "Per-Face AI Retouching — Not a global filter" [F][6]
  - "Faster Edit, Finer Control" [F][3]
  - Testimonials claim editing time drops from "2 to 3 days to one hour after a session" [F][6]

### 3.5 Sentiment
- **Trustpilot: 3.7/5 from 374 reviews.** 70% are 5★ and 20% are 1★ [R][79].
  - Praise: ease of use, retouching quality, time saved.
  - Complaints: unauthorised charges and lost credits, slow or unhelpful support, login and export problems.
- **Press:**
  - Amateur Photographer 4/5 [R][75].
  - Digital Camera World: "fantastic for portrait retouching", but the credit system feels "antiquated" [R][74].
  - Fstoppers: Evoto better than Retouch4me on blemishes, glare, stray hair and clothing, but costlier [R][73].
- **January 2026 "headshot-gate":**
  - Imaging USA attendees found Evoto running a consumer AI-headshot site pitched as cheaper than hiring a photographer. Photographers also pointed at terms granting Evoto a broad licence to uploaded images [R][80][82].
  - Evoto removed it and stated it does not train on customer images [F][81].
  - The About page now promises AI "will never… generate fabricated or synthetic content" [F][3]. That sits awkwardly with Smile Generation, Pretty Teeth, Generative Expand and Background Generator [I].

---

## 4. Technology: what is known vs inferred

### 4.1 Cloud vs on-device
**Facts:**
- **Trust Center [4]:**
  - For local projects, "only thumbnails are sent to the Evoto cloud." They are deleted immediately, and results are returned and **cached in the cloud up to 8 days**.
  - **AI Color and AI Lab** upload thumbnails or originals.
  - All processing and storage is on **AWS in the US**, with encrypted transmission.
  - "Evoto deploys certain algorithms locally. Local projects still rely on algorithms and computing resources in the Evoto cloud."
- **Older help article [55]:**
  - "Most Evoto features require images to be uploaded to our cloud servers."
  - Portrait Retouching, Background Replacement, ID crop and AI horizontal correction are cloud-processed. Server location: Oregon.
- **Desktop publishes a long supported-GPU list** (NVIDIA GTX 10-series and up, AMD RX 500 and up, Intel Arc, Qualcomm Adreno), plus "rendering acceleration" and memory settings [F][57][56].
- **Network timeout setting** defaults to 180 s [F][56].
- **Instant:** AI editing "cannot proceed while the device is offline". Preset **models can be downloaded locally** to run faster [F][59].
- **Video** is cloud-processed [F][54].
- **Reviewers:** "requires internet connection for cloud processing" [R][74]; "lacks offline editing" [R][76].
- **Generated results** become new encrypted **`.tsq`** files. AI Denoise creates proprietary **`.evr`** RAW copies [F][44][46][28].

**Inference [I]:**
- The pipeline is likely **analysis in the cloud, rendering locally**. A ~1–4K thumbnail goes up. The server runs face detection, attribute classification, landmarks, parsing/matting masks, blemish/wrinkle/glare maps and (for AI Looks) predicted parameters, then returns compact result maps. The desktop GPU then renders the slider-driven effects at full resolution.
- This explains several observed behaviours:
  - Sliders feel instant once analysis lands.
  - The app is useless offline.
  - Evoto can meter exports server-side.
  - It can keep its models off the client, which deters piracy and protects IP.
- The 8-day result cache matches the 3–15-day local cache window [F][56].
- Hard generative work (AI Lab, Smile Generation) almost certainly renders fully server-side.

### 4.2 Face detection and per-face parameters
**Facts:**
- Every face gets a "character" with **gender and age attributes**, editable by the user. Groups are Male, Female, Child, Senior, with Infant / child-under-3 sub-behaviour [F][14][15][12].
- You can add a face manually (a box; rejected above 50% overlap), delete faces, and **sync tag edits across the project** [F][15].
- **Per-group defaults** are applied automatically on iPad [F][15].
- Individual values inherit the group's until edited [F][14].
- Individual edits sync to "the same person" in other photos, which implies **cross-photo identity matching**. So do Face Gallery, Face clusters and Perfect Shot's "same person" matching [F][39][43][46].
- Group-photo limits [F][56][21][34]:
  - A speed option for 15+ faces.
  - AI Reshape and some body sliders disabled in groups.
  - Headshot crop disabled with >1 face or a head turned >75°.
- The Trust Center claims Evoto does **not** create "biometric facial templates… for identity recognition" [F][4]. [I] It most likely computes **transient, project-scoped face embeddings** for clustering and doesn't store them as identity templates. Worth knowing if we build the same thing.

**Inferred data model [I]:**
`photo.faces[] = {id, bbox, landmarks, tags{gender, ageGroup}, personId}`, plus `portrait.groupParams{all, female, male, child, senior}` and `portrait.individual{personId → sparse overrides}`. Resolution order: individual → group → all.

### 4.3 Segmentation (skin, hair, clothes, background)
**Facts:**
- Person masks cover face skin, body skin, neck, ears, hair, eyes, lips, teeth and clothes (Tops, Inner Layer, Dress, Bottom, Shoes), plus accessories (Headwear, Gloves, Bag, Jewelry) [F][33][30][11].
- Pets: dogs, cats, pigeons, parrots [F][46].
- Background masks include sky and "Reef" [F][33].
- Interactive "Segment / Interactive / Quick" selection with hover pre-segmentation [F][33].
- Matting modes Auto / Natural / Precise, and "Subject / +Related / +Non-Connected" preserved areas [F][26].
- A depth map for Lens Blur [F][29].
- A **3D skeleton and posture** model for body reshape [F][21].
- A **solid-backdrop classifier** and a distraction detector [F][25].
- Water and sky detectors [F][27].
- Glasses and beard detection [F][12].

**Inference [I]:**
- Expect at least these models: a human-parsing net (about 20 classes), a high-resolution portrait matting net, a SAM-style interactive segmenter, monocular depth, 2D/3D body pose, a 3D face fit (for Head Pose), attribute classifiers, and several task-specific "defect" detectors and inpainting nets (blemish, wrinkle, glare, stray hair, lint, sweat).
- The breadth of slider names maps to **one detector per defect type**. That's a long-tail data-labelling investment, and it's Evoto's real moat.

### 4.4 Presets and "learn my style"
**Facts:**
- **Presets** are parameter bundles. Portrait parameters are stored **per gender/age group**. Preset types restrict which modules are included [F][38][14].
- **AI Color Looks** are per-image adaptive, with automatic local masks [F][31].
- **AI Color Match:**
  - Quick mode is an opaque transfer.
  - **Control mode** writes the result into the standard sliders and auto-creates semantic masks [F][30].
- **Personal AI Look:**
  - Needs ≥200 edited images, from LrC catalogs, Evoto projects, or RAW+XMP.
  - Separate RAW and non-RAW looks.
  - Training runs as a queued server task.
  - Tuning modes are "AI Correction" (offset on top of the AI's values) and "Fixed Value" (replace) [F][32].
  - A Lite variant learns from one XMP or preset [F][32].

**Inference [I]:**
- A Personal AI Look is a **per-user parameter regressor** (image features → Evoto slider values), like Imagen or Aftershoot profiles. "AI Correction" mode = the user's preset offsets added to predicted values.
- The 200-image threshold (vs Imagen's 2,500–5,000) suggests fine-tuning a strong base model rather than training from scratch.

### 4.5 Security claims
**Facts:**
- Certifications:
  - ISO/IEC 27001
  - SOC 2 Type 2
  - PrivacyMark #17004988
  - GDPR, CCPA and CH-DSG compliance
- Data handling:
  - Encrypted transmission (proprietary).
  - Thumbnails deleted after processing.
  - Cloud projects deleted 30 days after the subscription ends.
  - No training on user images "unless you explicitly opt in".
  - Processors are contractually barred from training [F][4][3][1].

**Tensions worth noting:**
- An older help article lists ISO 27001 as "In Progress" and SOC 2 "Under Review" [F][55]. The site now says certified.
- The **Content Analysis** setting says Evoto "may analyze your content using machine learning… to enhance product quality". It is **opt-out**, not opt-in [F][56].
- Evoto's privacy policy also allows limited **manual review** of content "for product improvement". I saw this only as a search-result excerpt of the policy, not the full text [F, excerpt][4b].
- Device counts differ between sources: the help center says Standard Plus covers 5 devices, the pricing page says 6 [F][48][2].
- The January 2026 licence-clause controversy [R][80].

---

## 5. Prioritized "replicate list" for Lumen

**Guiding choices:**
1. **On-device first.** Use MediaPipe and ONNX models we already shortlisted in research 03: Face Landmarker, Selfie Multiclass, MODNet/BiRefNet, EdgeTAM, MI-GAN/LaMa, Depth Anything V2.
   - That makes privacy a wedge, since Evoto structurally needs the cloud.
   - It makes a flat price possible.
2. **Everything is a slider in `ParamRegistry`.** Masks are cached analysis results, never baked pixels. That matches Lumen's core promise.
3. **Run at model resolution, apply at full resolution** with a guided-filter upsample (research 03 §rules).

**Data-model prerequisite** (do this first; everything below depends on it):
- `EditDocument.analysis.faces[]` holds bbox, 478 landmarks, tags and an optional `personId`.
- `portrait.groups{all, female, male, child, senior}` param sets plus `portrait.individual{personId: sparse}`.
- Resolution order is individual → group → all.
- Presets store group param sets.
- Sync has per-module checkboxes plus "same person" semantics.

### P0: MVP-critical (the reasons people pay for Evoto)

| # | Feature | Minimum viable implementation | Effort / risk |
|---|---|---|---|
| 1 | **Face detection + group tags + per-face/per-group sliders** | **MediaPipe Face Landmarker** (Apache-2.0) runs on the preview at import. Faces default to the **All** group. One-click tag chips on each face box (F / M / Child / Senior). Optionally auto-suggest tags with a permissively licensed age/gender model ⚠️ (InsightFace's genderage is non-commercial; verify licences) or a Claude vision call on face crops when online (opt-in). Child/infant can be approximated by face size relative to inter-ocular distance plus landmark ratios **[I, needs eval]**. UI: face boxes, an All/F/M/Child/Senior/Individual tab strip, a face list | M. Ethics: allow manual override and avoid misgendering; treat the tags as "retouch profiles", not identity. Legal review for GDPR biometric angle |
| 2 | **Blemish / acne removal with freckle preservation** (Freckle + Acne sliders, Mole toggle) | Skin mask = Selfie Multiclass face-skin minus landmark polygons (eyes, brows, lips, nostrils), minus the hair class (beard protection). Detect spots with multi-scale difference-of-Gaussians in Lab. **Acne** = blobs with raised a* (red); **freckles** = small, low-contrast, high-b* brown blobs; **moles** = larger, darker isolated blobs. Heal each blob on the GPU with a "low-frequency fill + neighbour texture" patch (or MI-GAN for larger spots). Slider = detection threshold × blend | M–L. Quality bar is high; build an eval set of 100 licensed portraits |
| 3 | **Skin smoothing** (Even D&B, Frequency Separation High/Low, Skin Softening, Texture keep) | Already sketched in research 03 §5. Guided-filter base layer at two radii relative to face width. **Low Freq** blends toward the blurred base; **High Freq** scales detail (σ-limited); **Even D&B** attenuates the mid-frequency band (σ₁–σ₂) so tone evens out while pores stay. All in the develop shader with a skin-mask texture | S–M. Biggest perceived-quality lever; tune against reviewers' "no plastic skin" bar |
| 4 | **Under-eye: Dark Circles + Eye Bags (+ Lower Eyelid Protection)** | A landmark-defined crescent under each eye. Dark circles: lift L* and pull a*/b* toward a cheek-sampled reference. Eye bags: attenuate the mid-frequency shading band. Protection: a falloff mask near the lash line, scaled by the slider (default 100) | S |
| 5 | **Reduce Face Shine** | In the skin mask, find speculars (high L, low chroma, high local contrast). Compress them toward the local low-frequency base | S |
| 6 | **Eyes: Iris / Whites brightness, Red Vein, Red-eye** | Face Landmarker iris points + eyelid polygons give iris and sclera masks. Brightness via masked curves (defaults 80/80 like Evoto). Red vein: suppress a* high-frequency inside the sclera. Red-eye: pupil a* clamp | S |
| 7 | **Teeth whitening** (Brightness + Desaturation/yellow) | Inner-lip polygon ∩ bright, low-saturation pixels → teeth mask. Raise L*, lower b* | S |
| 8 | **Clean backdrop + Unify Lighting + Banding removal** (headshot/school/studio) | Background = inverse of the MODNet/BiRefNet person matte. Classify "solid backdrop" by low chroma variance plus a smooth low-frequency fit. Estimate the backdrop B(x) with a low-order 2D polynomial or a very large guided blur. **Clean** = replace background detail above a frequency threshold with B (Background/Ground split by a horizon line from the subject's feet or a manual line). **Unify** = normalise B toward its mean (Amount) ± Luminance. **Banding** = 16-bit processing + blue-noise dither. Add **Background Color Consistency** across a selection by matching B's mean Lab | M |
| 9 | **Manual Tuning Pen per module** | A brush/erase painter writing to the module's effect-mask channel (stored as a sparse low-res stroke list in `EditDocument`). Essential for correcting AI misses | M (shared component) |
| 10 | **Character-aware presets + selective sync + compare** | Preset types (Portrait / Color / Combination) with "include effects" checkboxes. Separate Portrait and Color intensity sliders. Sync dialog with module checkboxes and a "remember for this project" toggle. Press-and-hold on a group header or slider to disable it temporarily (cheap, high delight). Auto-apply a preset on import | S–M (extends existing presets/sync) |
| 11 | **Glasses-glare removal** (beta) | Glasses region = Selfie Multiclass "accessories" class ∩ the eye neighbourhood from landmarks. Glare = bright, desaturated, low-texture areas inside it. Inpaint with MI-GAN, then LaMa for "HQ" (research 03), constrained by eye landmarks. Ship as **beta** with a strength slider; generative hallucination of the eye is the risk | L, high risk; a top purchase reason [R][73] |
| 12 | **Stray hairs beyond outline** (plain backdrops) | From the hair matte, compute a smoothed silhouette (morphological open/close). Thin, high-frequency matte residue outside it = flyaways. Fill from the estimated backdrop B(x) from #8. Gives "within-face" removal for free later | M (good on studio backdrops, which are Evoto's core use) |

### P1: soon after (expected by Evoto switchers)

| Feature | Minimum viable implementation |
|---|---|
| **Wrinkle zones** (forehead, eleven lines, eye, nasal, smile L/R, marionette, perioral, neck) | Landmark-defined zone masks + directional mid-frequency attenuation (wrinkles are oriented ridges; use a steerable/Gabor band per zone) |
| **Skin tone unify (face↔body), Rosy, Radiance, Skin Tone swatches** | Face-skin vs body-skin masks; match mean Lab of body to face (Amount); Rosy = a* shift; Radiance = L lift excluding feature polygons |
| **Face reshape core** (Face Width, V-Shape/Jaw, Chin, Eye Size, Nose Width, Mouth Size, Smile corners) | Landmark-anchored **moving-least-squares** warp in a vertex shader over a grid mesh; each slider = a displacement field; add "Liquify Background Repair"-style protection by pinning background landmarks |
| **Manual Liquify + Healing (spot / clone)** | Standard GPU tools, stored as stroke lists; not syncable (same as Evoto) |
| **AI Color Match → sliders** | Reference and target stats per semantic mask (skin, hair, clothes, background) in Lab. Solve for Lumen's global sliders plus per-mask offsets with the **existing auto-tone solver**. Directly mirrors Evoto's "Control Mode" and fits Lumen's philosophy. Also gives "Multi-Image Color Consistency" |
| **Backdrop changer** (solid color / image, edge, spill, soft shadow) | BiRefNet_lite matte + Natural/Precise toggle (guided-filter radius); spill = desaturate edge band toward the new BG hue; shadow = blurred offset of the matte |
| **Auto headshot / ID crop** | Face Landmarker → Top Margin, Head Size, Horizontal Face Position sliders; fixed ratios; syncs per face; disabled for multiple faces |
| **Makeup basics** (lip color/saturation, blush, brow darken) | Landmark polygons + blend modes; no generative model |
| **Clothing de-wrinkle + lint** | Selfie Multiclass "clothes" mask + mid-frequency attenuation (wrinkles) + small-blob heal (lint) |
| **Culling** (blur, closed eyes, exposure, duplicates, face clusters) | Laplacian variance on face crops; Face Landmarker **eyeBlink blendshapes**; histogram clipping; SigLIP embeddings (already planned) + capture-time gaps for clusters; write XMP ratings |
| **Export presets, watermark, output sharpening, naming schemes** | Extend the current exporter |

### P2: later or differentiating (cloud, generative, or ecosystem)
- **Body reshape:** MediaPipe Pose (Apache-2.0) + MLS warp; disable for groups, as Evoto does.
- **Hair:** volume, part-line fill, white-hair blackening, hair color.
- **Personal style training:** "learn my look" from ≥N edited photos. Lumen variant: few-shot Claude prompt with the user's slider history, or a small per-user regressor on SigLIP features.
- **Generative expression tools:** Smile generation, open eyes, Perfect Shot face swap. These are ethically sensitive; consider never shipping some of them as a stance.
- **Generative cleanup:** people removal, Generative Expand, background generator. Server GPU, credit-metered.
- **Tethering, hot folders, LrC round-trip.**
- **Delivery:** client galleries, Find Me, school roster/QR store.
- **Other:** pet retouching, video retouching, asset marketplace.

### What Lumen should *not* copy
- **Per-export credits and rollover forfeiture.** These drive Evoto's worst reviews [R][79]. Offer a flat tier with unlimited local retouching. Meter only server-side generative jobs.
- **Opt-out "content analysis" and vague licence terms.** Keep Lumen's README promise: no training on user photos, opt-in only.
- **An overwhelming slider wall at first run.** Lead with presets per group plus 8–10 core sliders. Reveal sub-sliders progressively, as Evoto does.

---

## 6. How Evoto compares (where it is better or different)

| Product | Approach | Per-face / group-aware | Where processing runs | Price model | What Evoto does better / differently |
|---|---|---|---|---|---|
| **Retouch4me** (plugins + **Apex** app) | One AI task per plugin (Heal, Dodge & Burn, Eye Vessels, White Teeth, Skin Tone, Fabric, Clean Backdrop, Mattifier, Portrait Volumes); Apex is a one-click combined app | No gender/age profiles **[I]** | Local | Plugins about $124–149 each (bundle >$500); Apex $20 per 200 or $90 per 1,500 retouches [R][90][91] | Evoto has far more targeted sliders (glare, stray hair, clothing, reshape, makeup) and in-app batch sync. Retouch4me is "dry", natural and cheaper per image, so it's often used for every frame with Evoto for hard images [R][73] |
| **PortraitPro 24** | Slider-based face sculpting, ClearSkin skin smoothing, makeup, relighting; v24 adds generative mouth/teeth, glasses reflection, face recovery | Per face; gender/child-specific presets are likely but weren't re-verified this session **[I]** | Local | Perpetual about $55–130 [R][92] | Evoto is built for **volume** (projects, culling, sync, tethering, export). PortraitPro is single-image, consumer-leaning |
| **Imagen AI** | Learns a personal **color/tone profile** from 2,500–5,000+ LrC edits and returns sliders to Lightroom; add-ons (smooth skin, crop, subject mask) at +$0.01 per photo | No real per-face retouch | Cloud, LrC-centric | About $0.05–0.08 per photo + $7/mo minimum; packages $49–279/mo [R][93] | Evoto does *pixel retouching* per face; Imagen does *style* at scale. Evoto's AI Look needs only 200 images |
| **Aftershoot** (Select / Edits / Retouch) | Culling + style profiles + newer AI Retouch (skin, blemish, glare, object removal) | Limited **[R]** | **Fully local/offline** (their headline vs Evoto) | Flat: Retouch $20–25/mo; Complete about $45–55/mo, unlimited photos [R][94] | Evoto has deeper retouch granularity (competitor concedes "fewer of the deep, granular sliders"). Aftershoot wins on flat pricing and offline [R][94] |
| **Lightroom** (People masks, Adaptive Presets, Generative Remove) | Select People → face skin, body skin, brows, sclera, iris, lips, teeth, hair, clothes masks; adaptive portrait presets (whiten teeth, enhance eyes, smooth hair); Generative/Content-Aware Remove | Masks per person, but no automatic gender/age-specific values | Local masks; generative in cloud | $11.99–19.99/mo + generative credits [R][95] | Lightroom gives *masks* you still have to drive. Evoto gives *finished retouch operations* (blemish heal, glare, stray hair, backdrop clean, reshape) that sync by person group. Lightroom has no frequency separation or D&B, and no liquify |
| **Luminar Neo** (Skin AI, Face AI, Body AI) | Few sliders: skin smoothing, shine, blemish; face light, slim face, eyes, teeth; body/abdomen volume | Basic face detection | Local | Subscription about $49/yr or perpetual | Evoto has much finer control (8 wrinkle zones, per-zone eyes, clothing, backdrop), batch and per-group presets. Neo is a hobbyist one-stop editor [R][96] |
| **Facetune** (Lightricks) | Consumer selfie/video retouch, AI headshots, virtual try-on | Single subject | Mostly cloud plus device | $77.99/yr or $25/mo [R][97] | Different market. Evoto is pro, batch, RAW, tethered. Facetune's "Skin 2.0" shows texture-preserving smoothing is now table stakes |

**In one line:** Evoto wins on **granularity × batch × per-person consistency** for studio and event portrait work. It loses on **pricing model, offline use and trust**. Those three are where Lumen should attack.

---

## 7. What I could not verify
- **YouTube tutorials and transcripts** were not accessed. Workflow details come from Evoto's help center (which embeds the videos), the CreativeLive and Pratik Naik course pages, and SLR Lounge's written tutorial **[U]**.
- **Reddit (r/photography, r/WeddingPhotography)** returned blocked responses to search and API requests. Community sentiment is taken from Trustpilot, Fstoppers, Digital Camera World and DIY Photography instead **[U]**.
- **Evoto Instant tier prices** (`instant.evoto.ai/payment`) render client-side; I only have the rules (monthly 60 credits, no rollover) **[U]**.
- **PPA magazine review** returned 403 and Imagen's comparison page returned 403 **[U]**.
- **Exact numeric ranges and defaults** are documented only for some sliders, listed in §1. Most are presumably 0–100 one-way or ±100 bipolar **[I]**.
- **Exact desktop group-tab labels and order**, and whether the desktop (like iPad) auto-applies non-zero per-group defaults on import without a preset **[U]**.
- **Ownership history.** Truesight's corporate parentage and its relationship, if any, to Chinese retouch apps with similar feature sets were not established **[U]**.

---

## 8. Sources

**Evoto site**
1. Home: https://www.evoto.ai
2. Pricing: https://www.evoto.ai/payment
3. About (company, claims, AI philosophy, addresses): https://www.evoto.ai/about
4. Trust Center: https://www.evoto.ai/privacy-center
4b. Privacy policy (seen only as a search excerpt): https://res.evoto.ai/protocol/en/evoto/privacy
5. Release notes: https://www.evoto.ai/release-notes
6. Business: https://www.evoto.ai/business
7. Portrait retouching page: https://www.evoto.ai/features/portrait-retouching
8. Personal AI preset: https://www.evoto.ai/features/personal-ai-preset
9. Headshot photography: https://www.evoto.ai/features/headshot-photography
10. Feature page inventory (sitemap): https://www.evoto.ai/en-sitemap.xml

**Evoto Help Center** (`support.evoto.ai`, 252 English articles read via https://support.evoto.ai/sitemap.xml)

*Portrait retouching*

11. Skin Retouching: https://support.evoto.ai/portrait-retouching-module-skin-retouching/ · https://support.evoto.ai/skin-retouching/
12. Blemish Removal: https://support.evoto.ai/portrait-retouching-module-blemish-removal/
13. Blemish Removal (older): https://support.evoto.ai/blemish-removal/
14. AI Facial Recognition: https://support.evoto.ai/portrait-retouching-feature-module/ · https://support.evoto.ai/ai-facial-recognition/
15. iPad Portrait Retouching: https://support.evoto.ai/portrait-retouching-ipad/
16. Eyes: https://support.evoto.ai/eyes/ · https://support.evoto.ai/portrait-retouching-eyes/
17. Teeth: https://support.evoto.ai/teeth/
18. Makeup: https://support.evoto.ai/makeup/ · https://support.evoto.ai/portrait-retouching-makeup/
19. Hair: https://support.evoto.ai/hair/
20. Facial Reshape: https://support.evoto.ai/facial-reshape/ · https://support.evoto.ai/portrait-retouching-facial-reshape/
21. Full Body Reshape: https://support.evoto.ai/full-body-reshape/
22. Facial Expression: https://support.evoto.ai/portrait-retouching-facial-expression/
23. Hands: https://support.evoto.ai/hands/
24. Clothing: https://support.evoto.ai/clothing-accessories-adjustments-module/ · https://support.evoto.ai/clothing-adjustment/

*Background and color*

25. Background Adjustments: https://support.evoto.ai/background-adjustments/ · https://support.evoto.ai/how-to-get-a-clean-background-photo-in-evoto/
26. Backdrop Changer / Background panel: https://support.evoto.ai/backdrop-changer/
27. Sky Replacement: https://support.evoto.ai/sky-replacement/
28. Color Adjustments: https://support.evoto.ai/color-adjustment-feature-modules/
29. Creative Effects / Lens Blur: https://support.evoto.ai/color-adjustments-module/
30. AI Color Match: https://support.evoto.ai/feature-introduction-ai-color-match/
31. AI Color Looks: https://support.evoto.ai/feature-introduction-ai-color-looks/
32. Personalized AI Look: https://support.evoto.ai/personalized-ai-look/
33. Masking: https://support.evoto.ai/feature-introduction-masking/
34. Crop: https://support.evoto.ai/crop/

*Workspace and workflow*

35. Edit workspace: https://support.evoto.ai/edit/
36. Library workspace: https://support.evoto.ai/library/
37. Tool Bar: https://support.evoto.ai/tool-bar/
38. Presets: https://support.evoto.ai/how-to-use-preset/ · https://support.evoto.ai/presets/
39. Sync: https://support.evoto.ai/how-to-use-sync-the-feature-effect/ · https://support.evoto.ai/save-time-with-batch-style-matching-sync-presets-in-evoto/
40. Import & Export: https://support.evoto.ai/how-to-use-import-export/
41. Auto Import & Export: https://support.evoto.ai/auto-import-and-export/
42. Lightroom Classic integration: https://support.evoto.ai/lightroom-and-evoto/
43. Culling: https://support.evoto.ai/smart-culling/
44. AI Lab: https://support.evoto.ai/ai-lab/

*Release notes*

45. 7.1 highlights: https://support.evoto.ai/evoto-desktop-7-1-updates/
46. 6.2 updates: https://support.evoto.ai/evoto-ai-version-6-2-updates/
47. 5.1 updates: https://support.evoto.ai/evoto-ai-version-5-1-updates/

*Pricing and credits*

48. Credits & pricing: https://support.evoto.ai/understanding-evoto-credits-and-pricing/
49. Credits: https://support.evoto.ai/credit/
50. Credit-free exports: https://support.evoto.ai/how-can-i-use-credit-free-exports/
51. Plans: https://support.evoto.ai/subscription-plan/ · https://support.evoto.ai/pay-as-you-go-package/ · https://support.evoto.ai/7-day-free-trial-faq/ · https://support.evoto.ai/pricing-faq/
52. Evoto Online / AI Lab costs: https://support.evoto.ai/feature-page-pricing-faqs/
53. Mobile subscription: https://support.evoto.ai/evoto-mobile-subscription-faq/
54. Video: https://support.evoto.ai/evoto-video-pricing-faq/ · https://support.evoto.ai/evoto-video-faq/

*Account, settings and platform*

55. Account settings (cloud processing, server location, certifications): https://support.evoto.ai/account-settings/
56. System settings: https://support.evoto.ai/how-to-use-setting/
57. Getting started (requirements, GPUs): https://support.evoto.ai/getting-started/
58. Cloud Space: https://support.evoto.ai/cloud-space/

*Instant, workflows and other*

59. Instant: https://support.evoto.ai/system-introduction/ · https://support.evoto.ai/creating-a-new-project/ · https://support.evoto.ai/how-photos-are-processed-in-instant/ · https://support.evoto.ai/ai-editing-in-evoto-instant/ · https://support.evoto.ai/ai-culling-in-evoto-instant/ · https://support.evoto.ai/evoto-instant-faq/
60. School workflow: https://support.evoto.ai/school-photography-workflow-from-roster-to-revenue/
61. Workflow / Asset Hub / Assistant: https://support.evoto.ai/workflow-templates/ · https://support.evoto.ai/asset-hub/ · https://support.evoto.ai/evoto-ai-assistant-and-unified-search/
62. History: https://support.evoto.ai/understanding-evotos-history-functions-general-history-liquify-history-and-healing-tool-history/
63. Greyed-out body sliders: https://support.evoto.ai/understanding-the-greyed-out-sliders-in-full-body-reshape-what-it-means-and-how-to-address-it/
64. Mobile export: https://support.evoto.ai/export/
65. Mobile Reshape tool: https://support.evoto.ai/reshape-tool/

**Press, reviews, community**

70. Evoto ONE 2025 / v6.0 / Instant / Video: https://blog.evoto.ai/?p=21336
71. PetaPixel, Evoto 8.0 (2026-09-22): https://petapixel.com/2026/09/22/evoto-adds-portrait-retouching-to-video-intelligent-culling-mobile-tethering-and-more/
72. Fstoppers, Evoto 8.0: https://fstoppers.com/news/evoto-80-brings-new-editing-and-culling-features-904752
73. Fstoppers, Evoto vs Retouch4me: https://fstoppers.com/reviews/evoto-vs-retouch4me-one-better-other-683858
74. Digital Camera World review: https://www.digitalcameraworld.com/tech/software/evoto-ai-review
75. Amateur Photographer review: https://amateurphotographer.com/review/evoto-ai-review-can-ai-make-photo-editing-less-of-a-drag/
76. SLR Lounge, Evoto vs Photoshop: https://www.slrlounge.com/evoto-vs-photoshop/
77. SLR Lounge, batch retouch tutorial: https://www.slrlounge.com/evoto-ai-photo-editor/
78. Behind the Shutter, Evoto 6 review: https://www.behindtheshutter.com/evoto-6-review-all-the-new-ai-editing-features-you-need-to-know/
79. Trustpilot: https://www.trustpilot.com/review/evoto.ai
80. DIY Photography, AI headshot controversy: https://www.diyphotography.net/evoto-angers-photographers-by-a-surprise-ai-headshot-launch-but-is-evoto-the-villain-here/
81. Evoto official statement: https://news.evoto.ai/official-statement-hg0113
82. Glyn Dewis, "Evoto's AI Headshots": https://glyndewis.com/blog/evoto-ai
83. Mark Wallace class: https://www.creativelive.com/classes/evoto-ai-mark-wallace
84. Pratik Naik course: https://blog.evoto.ai/pratik-naik-evoto-ai-course/

**Competitors**

90. Retouch4me Apex: https://petapixel.com/2025/05/22/retouch4me-apex-automatically-retouches-portraits-in-one-click
91. Retouch4me plugins: https://retouch4.me/retouchplugins · https://shotkit.com/retouch4me-review/
92. PortraitPro 24: https://www.ashampoo.com/en-us/anthropics-portraitpro-24
93. Imagen pricing (third-party summary): https://filterpixel.com/imagen-ai-pricing. Imagen's own Evoto comparison (https://imagen-ai.com/valuable-tips/evoto-ai-vs-imagen/) returned 403
94. Aftershoot: https://aftershoot.com/blog/aftershoot-pricing-tiers/ · https://aftershoot.com/blog/evoto-alternatives/ (competitor-authored)
95. Lightroom portrait AI: https://www.rangefinderonline.com/news-features/industry-news/lightrooms-newest-ai-tools-faster-retouches-for-portrait-photographers/ · https://petapixel.com/?p=636478
96. Luminar Neo portrait tools: https://shotkit.com/luminar-neo-portrait-tools/
97. Facetune pricing: https://www.facetuneapp.com/pricing

**Internal cross-references:** `docs/research/03-browser-ai-tools.md` (model and licence choices), `docs/research/04-market.md` (pricing landscape; this doc updates Evoto's Trustpilot from 3.5 to 3.7 and the plan prices).
