# 04 · Market & Competitive Research

**Product:** AI-first, web-based photo editor ("Lumen" is the working name; see the trademark warning in section 4). AI makes the first edit as editable sliders, works on one photo or a batch, and adds AI masks, object and background removal, presets, before/after and export.
**Research date:** 2026-10-03. **Method:** web search plus vendor pages, release notes and review sites; Claude pricing and vision docs fetched from platform.claude.com.

**Confidence tags used in tables**
- **[V]** verified on the vendor's own page during this session
- **[S]** secondary source (review site, pricing aggregator, press); likely right, but check before quoting publicly
- **[C]** sources conflict or the vendor hides the figure; treat it as a range

Prices are USD per month unless noted. "Annual" means the per-month equivalent of yearly billing. Source numbers like [12] point to the list at the end.

---

## 0. TL;DR

1. **"AI edit delivered as sliders" already exists, but only for pros, only on the desktop, and mostly tied to Lightroom.** Imagen and Aftershoot both return Lightroom-style slider values, not baked pixels [35]. Both gate personal style behind **2,500–5,000 previously edited photos** [13][16], and they cost $30–170/mo or about $0.05/photo.
2. **Consumer and web tools do the opposite.** Canva, Picsart, Fotor, Pixlr, Remini and Photoroom apply AI as one-shot filters, generative regeneration or credit-metered effects. There is no editable recipe and little real photographic tone control.
3. **The open slot is a web-first "parametric AI" editor for the middle market:** enthusiasts and side-hustle photographers who want pro-looking, *consistent* sets without learning or paying for Lightroom.
4. **Object removal and background removal are table stakes now.** They're free or bundled in Lightroom, Canva, Photoroom, Google Photos and Apple Photos. Ship them cheaply with in-browser models; don't build the pitch on them.
5. **Willingness to pay comes from time saved on batches, consistency across a shoot, and "looks like *my* style".** It doesn't come from single-photo magic.
6. **Unit economics work if the architecture is disciplined.** A Claude call per photo on a downscaled 1024 px preview costs about **$0.003 (Haiku 4.5)** to **$0.008–0.011 (Sonnet 5.5)**. A shoot-level contact-sheet call gets this to **about $0.0005–0.0014 per photo**. Competitors charge about $0.05/photo. In-browser masks, background removal and inpainting cost **$0** in server compute.
7. **Don't use "Lumen" as the public brand.** There's a live US registration **LUMEN, Reg. No. 5560647, for "computer software for processing digital images"** [40]. Lumen Technologies also holds class 9/42 marks [41], several "Lumen" photo and camera apps exist [42], and the name sits close to Skylum's **Luminar**. Candidate names: **Dialed**, **Halfstop**, **Zone Five**. All three need professional clearance.
8. **Recommended ICP:** semi-pro "side-hustle" shooters (portraits, families, small events, small-business product work; 100–800 photos per shoot). Pricing hypothesis: **Free → Pro $12/mo ($8 annual) → Studio $35/mo ($29 annual)**, plus credit top-ups for seasonal spikes.

---

## 1. Competitive landscape

### 1.1 Master comparison

| # | Product | Target user | AI features (2025–26) | Price (USD/mo) | Platform | Key weakness / complaints | Src |
|---|---|---|---|---|---|---|---|
| 1 | **Adobe Lightroom** (Lightroom, Classic, web, mobile) | Enthusiasts → pros | Auto (Sensei) sets slider values; AI masks (subject/sky/people/objects); **Adaptive presets** (new seasonal landscape set Oct 2025); **Denoise**; **Generative Remove** and distraction/people removal (improved Dec 2025); Lens Blur; **Assisted Culling** (Feb/Apr 2026); **Generative Expand** (Aug 2026); AI metadata filters | **Lightroom 1TB $11.99** (250 gen credits) [V]; **Photography 1TB $19.99** (Lr + LrC + Ps, 1,000 credits) [V]; 20GB $9.99 plan closed to new subs Jan 15 2025 [S]; existing Lightroom-1TB subs reportedly moving to $14.99 from Mar 2026 [C] (the Adobe FAQ returned 403) | Win, Mac, iOS, Android, **Web** | Subscription fatigue and repeated price changes; generative-credit metering; performance complaints in AI-era releases; steep learning curve; **Auto is generic and erratic ("the over-exposure button")** [9]; no personal-style learning | [1][2][3][4][5][6][7][8][9] |
| 2 | **Luminar Neo** (Skylum) | Hobbyists who want one-click AI looks | Enhance AI, Sky AI, Relight, Portrait/Skin AI, GenErase/GenExpand/GenSwap, Noiseless, Upscale | Subscription from **about $49/yr** [S]; perpetual **$79–$109** one-time (Jul 2026) [S]; **generative tools expire 1 yr after a perpetual purchase** [S] | Mac, Win (+ plugin) | Called "slow, buggy", with a pattern of paid upgrades instead of fixes; plugin breakage with PS 2025; gen-feature expiry feels like a bait-and-switch | [10][11] |
| 3 | **Imagen AI** | High-volume wedding, event and portrait pros | **Personal AI Profile** trained on **≥3,000 edited LrC photos (5,000 recommended)** [S]; returns **sliders into Lightroom**; culling; crop/straighten/subject mask/smooth skin add-ons | PAYG **$0.05/photo + $7/mo minimum** (some sources say $0.08) [C]; add-ons **+$0.01/photo each**; **Limitless about $129/mo annual or $165 monthly** [S]; culling add-on $12–18 [S] | Desktop app + Lightroom Classic; cloud processing | Needs Lightroom habits plus a large catalog; add-ons push the effective rate to **about $0.09/photo** [S]; reports of inconsistent edits in tricky light and of fee transparency issues | [12][13][14][35] |
| 4 | **Aftershoot** | Same pro segment | Culling; AI editing with **Pro AI Profiles (2,500 min / 5,000 recommended)** and **Instant AI Profile built from a Lightroom preset in about 60 s**; retouching; **built-in RAW editor + Galleries (May 2026)** | **Select $10 annual / $15 monthly; Edit $30/$35; Retouch $20/$25; Complete $45/$55**; unlimited photos [S] | Desktop (Mac/Win, offline); web galleries | History of white-balance and consistency complaints (needed a full WB model rebuild and profile retraining in Edits 2.0) [17]; desktop-only; profile-training friction | [15][16][17] |
| 5 | **Evoto** | Portrait, headshot and studio retouchers | Skin and blemish retouch, background change, color, batch sync, AI presets | Credits at about **1 credit per photo**; annual plans **$80/yr (800 credits) to $1,205/yr (24k)**, i.e. **about $0.05–0.10/photo** [S] | Win, Mac, iOS | Trustpilot about **3.5/5**: disappearing credits, export problems, slow support, "prices more than doubled" | [18][19] |
| 6 | **Picsart** | Consumers, creators, SMB social content | Generative fill, object and background removal, enhance, templates | **Plus about $5** (200 credits), **Pro about $7** (500 credits), Ultra about $22 (annual-equivalent) [S] | iOS, Android, Web | Many complaints about **unexpected renewals and charges** and hard refunds; credits reset monthly; destructive, filter-style edits | [20][21] |
| 7 | **Canva** (photo editor) | Marketers, SMBs, teams | Magic Edit/Eraser/Expand, Background Remover, Magic Studio; Affinity AI tools | **Pro about $15–18** [C] (sources disagree); Business about $25/user [S] | Web, desktop, mobile | Not a photographic editor (no real RAW or tone pipeline); 2024 Teams price hike of up to about +300% caused backlash; billing and refund complaints | [22][23] |
| 8 | **Photoroom** | E-commerce sellers and resellers | Background removal, AI backgrounds, batch, Shopify sync, API/MCP | **Pro about $7.99, Max about $26.99** [S]. **Since 2026-07-22 the site hides prices until checkout, and the free plan card was removed** [S]. API about $0.02/img bg-removal and about $0.10/AI edit [S] | iOS, Android, Web, API | Removed the free tier; opaque pricing; export caps (1k/3k/10k per month); product-photo focus only | [24] |
| 9 | **Pixlr** | Budget, casual web users | Gen fill, background removal, image generation | **Plus €1.99, Premium €7.99, Ultra €19.99, Ultra MAX €39.99** (annual) [S] | Web, mobile | Ads on free tier; credit system; basic tone and color controls | [25] |
| 10 | **Fotor** | Casual users, SMB | 1-tap enhance, background removal, AI generation, headshots | **Pro $8.99, Pro+ $19.99 monthly** (Pro+ about $7.49 annual); 100/300 credits [S] | Web, desktop, mobile | Credit gating; generic one-click looks | [26] |
| 11 | **Remini** (Bending Spoons) | Consumers (selfies, old photos) | Face enhance and restore, AI headshots/avatars | Billed **weekly, about $6.99–9.99/wk**; also about $4.99 monthly and about $99.99/yr [C] | iOS, Android, Web | **Dark-pattern weekly billing**: many reports of unauthorized charges and billing after cancellation; heavy ads; generative face changes | [27] |
| 12 | **Snapseed** (Google) | Casual mobile editors | Light AI; v3.0 iOS redesign (Jun 2025); **v4.0 on iOS and Android (May 2026)**; generative AI promised | **Free** [S] | iOS, Android | No batch, no web or desktop, minimal AI. It sets a free baseline for basic sliders | [28] |
| 13 | **Darkroom** | iPhone and Mac enthusiasts | AI-backed masks, color grading, curves, batch | **$4.99/mo, $32.99/yr, $74.99 lifetime** [V-ish: vendor help page] | iOS, iPadOS, macOS, visionOS | Apple-only; little "auto-edit" intelligence | [29] |
| 14 | **VSCO** | Creators who want film looks; some pros (galleries) | Presets, **AI Lab (unlimited on Pro)**, Capture | **Plus $29.99/yr or $7.99/mo; Pro $59.99/yr or $12.99/mo** [S] | iOS, Android, web | Filter-first; limited tonal and batch depth for paid work (inference) | [30] |
| 15 | **Polarr** / **Polarr Next** | Creators; Next targets pros | AI styles and copilots; Next does AI culling and edits | Polarr **$7.99/mo or $47.99/yr**; **Next: $0.05/export PAYG, or $29.99 monthly / $19.99 annual unlimited** [S] | iOS, Android, Web, desktop | Fragmented product line and pivots (inference); small ecosystem | [31] |
| 16 | **Topaz Photo AI** | Enthusiasts and pros needing denoise, sharpening, upscaling | Denoise, sharpen, upscale, face recovery | **$39/mo, $199/yr, Pro $599/yr**; **perpetual licenses ended Oct 2025** [S] | Mac, Win, plugins | Backlash over the move to subscription-only; GPU-heavy; a fixer, not a look/style editor | [32] |

**Adjacent "free baselines" that set user expectations**
- **Google Photos "Help me edit"** does conversational, Gemini-powered editing ("make it better", "remove the glare"). It's free and rolling out to eligible US Android users [33]. This *regenerates* pixels, which is the opposite of a slider recipe.
- **Lightroom on the web** is a real browser editor. It gained improved blemish removal and subject selection in 2026 and needs a modern 64-bit machine with 8 GB RAM [7]. "Web-first" alone is not a moat.
- **Real-estate niche:** Autoenhance.ai charges about **$0.08–0.20/photo** (sky replacement, perspective, brightness) [34].

### 1.2 Where competitors sit

| | **Baked pixels / filters / generative** | **Editable parametric sliders** |
|---|---|---|
| **Pro, desktop, Lightroom-adjacent** | Topaz, Luminar Neo, Evoto | **Imagen, Aftershoot**, Lightroom Auto/Adaptive, Polarr Next |
| **Consumer, web/mobile** | Canva, Picsart, Fotor, Pixlr, Remini, Photoroom, Google Photos "Help me edit" | *Mostly empty.* Darkroom/VSCO/Snapseed have sliders but weak AI. Lightroom web has sliders plus a generic Auto. **This is the target quadrant.** |

### 1.3 Market size: low confidence
Analyst estimates for "photo editing software" don't agree. Figures range from **about $0.9B to $2.5B** with **about 8% CAGR** [56]. Don't put these in a pitch deck without a bottom-up model (number of ICP users × ARPU).

---

## 2. Gaps and opportunity (a)

| # | Gap | Evidence | What to build into the product |
|---|---|---|---|
| G1 | **Parametric AI for the middle market.** AI-as-sliders only exists in pro desktop tools at $30–170/mo | [12][15][35] | A browser editor where the AI writes slider values, with an "AI Amount" master slider (0–150%) |
| G2 | **The black-box problem.** Lightroom Auto is distrusted; generative editors silently change faces and details | [9][27][33] | **"Shows its work"**: a one-line reason per changed slider ("Temp +350 K: scene is shade-lit") that only an LLM can produce. Position against regeneration: *developed, not generated* |
| G3 | **The style-learning threshold.** Imagen needs ≥3,000 edits and Aftershoot ≥2,500 for a personal profile | [13][16] | **Few-shot style**: learn from 10–50 example edits, an imported `.xmp` preset, or a reference image. Then keep learning from each slider correction |
| G4 | **Consistency across a shoot.** This is the hardest and most-valued problem (Aftershoot's WB rebuild shows it) | [17] | A first-class **"Match shoot"** feature: cluster by scene and light, edit one anchor photo, propagate, then normalize exposure and WB |
| G5 | **Pricing distrust.** Weekly billing, credits that vanish, hidden prices, metered AI | [21][24][27][19][8] | Transparent quotas, no weekly plans, one-click cancel, credits that roll over for 12 months |
| G6 | **Adobe fatigue.** Price changes, gen-credit metering, performance complaints | [2][4][8] | "No Adobe account needed"; import Lightroom presets on day 1 |
| G7 | **Privacy.** Uploading every photo to the cloud makes people uneasy | [53][54] | **Local-first** editing: originals stay on the device; only a downscaled preview goes to the LLM; edit recipes (a few KB of JSON) sync |

**Honest risks**
- Adobe can ship a better Auto plus style features at any time; Adaptive presets show the direction.
- Aftershoot is now a complete pro suite [15].
- Google Photos is free.
- RAW performance in the browser (LibRaw WASM, memory limits) caps realistic batch size per session.

**How to defend:** move fast in the middle market, put explanations and few-shot style at the center, keep the per-photo cost structure about 10× cheaper than per-photo competitors, and build up proprietary "accepted edit" data (with consent).

---

## 3. ICP options (b)

| | **A. Lightroom-fatigued enthusiast / creator** | **B. Volume event and portrait pro** | **C. Semi-pro "side-hustle" shooter** (recommended) |
|---|---|---|---|
| Who | Hobbyists and creators on mirrorless or phone; 50–300 photos per outing; posts to Instagram | Wedding and event photographers; 500–3,000 photos per shoot; 20–60 shoots/yr | Paid portrait, family, small-event and small-business product shoots; 100–800 photos per shoot; often a second income |
| Current tools | Lightroom mobile/web, VSCO, Snapseed, Darkroom | Lightroom Classic + Imagen or Aftershoot | Lightroom used reluctantly, Canva, or nothing |
| Pain | Lightroom is complex and costly; "my photos look flat" | Editing hours in peak season; consistency; delivery deadlines | Evenings lost to editing; inconsistent galleries; can't justify $45–165/mo pro tools |
| WTP (inference) | $5–12/mo | $30–150/mo or $0.03–0.09/photo | **$10–35/mo** |
| Web-first fit | Good | **Weak**: RAW at 50 GB per shoot, entrenched desktop workflows | **Good**: hundreds of files is manageable in a browser |
| Reach | SEO, TikTok/IG, YouTube tutorials | Trade shows, FB groups, education creators | YouTube "edit faster" content, r/photography, r/AskPhotography, local photographer communities, presets marketplaces |
| Main risk | Low ARPU, high churn | Hard switching (catalogs, plugins) | Segment definition is fuzzy; needs crisp messaging |

**Recommendation: lead with C and design for an upgrade path to B.** C feels batch and consistency pain (the WTP drivers) at volumes a browser can handle, and it is under-served on price between the $8 consumer apps and $45+ pro suites. A's acquisition loop (free tier, shareable before/afters) still feeds C. Move to B later with Lightroom XMP export, style learning from catalogs, and a desktop-class performance path.

---

## 4. Positioning, names and taglines (c)

### 4.1 Positioning statement (Moore format)
> **For** enthusiast and side-hustle photographers who want polished, consistent photos without learning or paying for Lightroom,
> **[Name]** is a browser-based photo editor
> **that** makes the first edit for you, one photo or a whole shoot, as real sliders you can see, tweak and save as your own style.
> **Unlike** Canva, Picsart or "describe-your-edit" AI that bakes changes into the pixels, and unlike Imagen or Aftershoot, which need Lightroom-era workflows and thousands of past edits,
> **[Name]** shows its work: every AI decision is a slider with a reason, and it learns your look from a handful of examples.

**Short form:** *The AI photo editor that shows its work.*

### 4.2 The "Lumen" trademark problem
| Risk | Detail | Severity |
|---|---|---|
| Same goods, same word | US **LUMEN, Reg. No. 5560647** (registered 2018-09-11) for **"computer software for processing digital images"**. The owner wasn't visible without login [40] | **High** (direct class and goods overlap) |
| Famous mark | **Lumen Technologies** (formerly CenturyLink) holds LUMEN marks in classes 9/42 across the US, CA, AU and UK [41] | Medium-high (dilution, domain and SEO collisions) |
| Crowded field | "Lumen Camera" (iOS), "Rollei Lumen", "LUMINS – Light Photo Editor" [42]; Epic's Unreal Engine "Lumen" lighting system is a well-known tech term | Medium (SEO and app-store confusion) |
| Close to a direct competitor | **Luminar** (Skylum) is in the same product category, with the same Latin root (*lumen* = light) | Medium |

**Verdict:** keep "Lumen" as an internal codename only.

### 4.3 Three candidate names (web-level screening only, not legal clearance)

| Name | Why it fits | Quick screen | Domain idea (availability not checked) |
|---|---|---|---|
| **Dialed** | Photographer slang for settings that are "dialed in", and literally dials and sliders. Short, verb-friendly ("Dialed it") | No photo-editing app found under the name. It's a common English word, so expect weaker distinctiveness and possible unrelated class-9 marks | dialed.photo, getdialed.app |
| **Halfstop** | A half stop of exposure: precise, pro-credible, slightly nerdy. Implies subtle, not over-processed | No app or software found | halfstop.app, halfstop.photo |
| **Zone Five** | Zone V is middle grey in Ansel Adams' Zone System, the calibrated anchor. Fits "AI gets you to a perfect middle; you take it anywhere" | Zone-System meter apps exist, but none found with this exact name | zonefive.app, zone5.photo |

**Screened out:** *Kelvin* (an existing local-AI photo editor and Creative Force's "Kelvin" app) [43]; *Fixer* (many "AI Photo Fixer" apps); *Halation* ("Halationify" and a common effect name); *Tonecraft* (several audio apps) [44]; *Glassbox* (an analytics company).

**Before committing:**
1. Run a USPTO Trademark Search in classes 9 and 42, an EUIPO/TMview search, and app-store and domain checks.
2. Get a trademark attorney knockout opinion (about $300–800, typical US range, unverified).
3. File an intent-to-use application.

### 4.4 Taglines
`Awareness: L3 Solution Aware · In-market: partly (already trying AI editors) · Message: AI that edits like a pro and shows its work as sliders · CTA rung: "Try it free on one shoot" / compare`

| Name | Tagline options (L3, mechanism-led) |
|---|---|
| Dialed | "AI dials it in. You fine-tune." · "Your photos, dialed in. Every slider stays yours." |
| Halfstop | "AI edits. You keep every slider." · "Pro edits, half the effort, full control." |
| Zone Five | "The AI finds the middle. You find the mood." · "Developed, not generated." |

**What L3 leaves out:**
- **Level 2 (problem-aware):** a pain-first hook, e.g. "Still spending Sunday editing last Saturday's shoot?"
- **Level 4 (product-aware):** proof assets such as a slider-reveal before/after video or a timed batch demo. Mark these `[REAL RESULT NEEDED]` until there's real data; don't invent time-saved stats.

**Market sophistication is high** ("one-click AI" is everywhere), so claims must lead with the mechanism (sliders plus reasons, few-shot style), not "better results".

---

## 5. MVP feature priority from a market view (d)

### 5.1 What drives willingness to pay (ranked; inferred from competitor packaging and complaints)
1. **Batch time saved.** Imagen markets "4 hr → 15 min" style outcomes; Aftershoot sells unlimited volume [14][15].
2. **Consistency across a shoot.** Same skin tones and WB through changing light [17].
3. **"Looks like my style."** Personal profiles are the premium gate at Imagen and Aftershoot [13][16].
4. **RAW support.** Separates paid photographers from casual users.
5. **Trust and control.** Editable sliders, explanations, predictable pricing.
6. AI masks (subject/sky) are expected in any paid editor.
7. Object and background removal are expected but commoditized, so they add little WTP.

### 5.2 Feature tiers

| Priority | Feature | Why (market view) |
|---|---|---|
| **Must (MVP)** | Upload JPEG/HEIC/PNG; non-destructive edit stack; undo/history | Baseline |
| **Must** | **One-click AI Auto-Edit → sliders** (exposure, contrast, highlights/shadows/whites/blacks, temp/tint, vibrance/saturation, HSL, tone curve, clarity/texture/dehaze, vignette, crop/straighten) | The core promise |
| **Must** | **"AI Amount" master slider + "why" notes per slider** | Differentiator (G2); cheap to build with an LLM |
| **Must** | **Batch auto-edit + "Match shoot"** (anchor photo → propagate → normalize) | Top WTP driver (G4) |
| **Must** | Before/after (split view and hold-to-compare) | Demo and conversion asset |
| **Must** | Built-in looks (10–20) + save your own preset | Retention and identity |
| **Must** | AI masks: subject and sky (in-browser) | Parity with Lightroom and Darkroom |
| **Must** | Export: full-res JPEG/WebP, social sizes, ZIP for batches | Finishing the job |
| **Should (v1.1, for Pro launch)** | **RAW** (DNG + CR3/NEF/ARW via LibRaw-WASM) | Paid-photographer gate |
| **Should** | **Import Lightroom `.xmp` presets** | Removes switching cost for Adobe refugees |
| **Should** | Object removal (in-browser LaMa/MI-GAN); background removal (BiRefNet/MODNet) | Expected; keep cheap |
| **Should** | **Few-shot "Learn my style"** (10–50 examples, or a preset/reference image, plus learning from corrections) | Premium gate (G3) |
| **Later** | Lightroom XMP **export** (round-trip), culling, cloud sync and sharing links, client proofing galleries, team seats, PWA/mobile, public API | Path to ICP B; expansion revenue |
| **Later** | Generative expand/fill (server GPU), people-aware retouch | Costly; legal and labeling duties (section 7) |

**North-star quality metric:** the **AI acceptance rate**, meaning the share of AI-edited photos exported with no slider changes or only small ones. Track it per style and per scene type.

---

## 6. Pricing, packaging and unit economics (e)

### 6.1 Packaging hypothesis

| Tier | Price | Includes | Anchor logic |
|---|---|---|---|
| **Free** | $0 | Unlimited manual editing; in-browser AI tools (masks, background removal, object removal up to about 4 MP); **25 AI Auto-Edits/mo**; batches up to 10; full-res JPEG export, **no watermark**; local-only storage | Beats Snapseed/Pixlr on AI; gets people to the first "wow" |
| **Pro** | **$12/mo monthly, $96/yr ($8/mo)** | **1,500 AI edits/mo** (fair use); Match shoot (≤500 photos per batch); RAW; preset import; **few-shot style (3 styles)**; 50 GB optional cloud | Same as Lightroom 1TB ($11.99) [1], but with AI that does the work. Matches VSCO Pro and Picsart/Fotor tiers |
| **Studio** | **$35/mo monthly, $29/mo annual** | **10,000 AI edits/mo**; unlimited batch size; style learning from history or catalog; unlimited styles; Lightroom XMP export; priority queue and server-GPU tools; +$15 per extra seat | Below Aftershoot Complete ($45–55) [15] and Imagen Limitless ($129–165) [12], with no Adobe subscription needed on top |
| **Top-up** | **$5 per 1,000 AI edits**, valid 12 months | For seasonal peaks | Half of Imagen's $0.05/photo PAYG |

**Pricing rules to follow** (these turn the complaints in G5 into selling points):
- No weekly plans.
- Prices shown on the site.
- One-click cancel.
- Quota meter always visible.
- Unused top-ups roll over.

### 6.2 AI cost per photo (Claude API, verified prices as of 2026-10-03)

**Inputs used** [36][37]:
- **Image tokens = ⌈width/28⌉ × ⌈height/28⌉.**
  - Standard tier (e.g. Haiku 4.5): max 1568 px long edge and 1,568 tokens.
  - High-res tier (Claude 4.7+ models, including Sonnet 5.5): max 2576 px and 4,784 tokens.
- **Prices per MTok (input / output / cache read):** Haiku 4.5 $1 / $5 / $0.10; Sonnet 5.5 $2 / $10 / $0.20; Opus 5.5 $4 / $20 / $0.20. **Batch API = −50%.** The Claude 4.7+ tokenizer produces about 30% more text tokens.
- **Example:** a 1024×683 preview costs **925 visual tokens**; a 384×256 thumbnail costs **140**.

**Per-photo assumptions:**
- A 1024 px preview plus about 250 tokens of EXIF and histogram stats.
- A 3,000-token cached system prompt (slider schema and style guide).
- About 350 output tokens of slider JSON.
- About 300 tokens of thinking on Sonnet and Opus.
- The cache only applies once the prompt prefix exceeds the model's minimum cacheable length.

| Strategy | Model | Cost per photo | Per 1,000 photos | With Batch API |
|---|---|---|---|---|
| Per-photo call, 1024 px preview | **Haiku 4.5** | **≈ $0.0032** | ≈ $3.2 | ≈ $1.6 |
| Per-photo call, 1024 px preview | **Sonnet 5.5** | **≈ $0.008–0.011** | ≈ $8–11 | ≈ $4–5.5 |
| Per-photo call, 1024 px preview | Opus 5.5 | ≈ $0.021 | ≈ $21 | ≈ $10.5 |
| Per-photo call, full-res (4,784-token cap) | Sonnet 5.5 | ≈ $0.019 | ≈ $19 | ≈ $9 |
| **Shoot-level contact sheet** (24 × 384 px thumbnails per call, compact per-photo deltas) | **Sonnet 5.5** | **≈ $0.0014** | ≈ $1.4 | ≈ $0.7 |
| Shoot-level contact sheet | Haiku 4.5 | ≈ $0.0005 | ≈ $0.5 | ≈ $0.25 |
| In-browser models (masks, background removal, inpainting, deterministic auto-tone) | Client WebGPU/WASM | **$0 server compute** | $0 | n/a |

**Architecture takeaways:**
- **Recommended "anchor + propagate" design:** the LLM reasons over a contact sheet and one hero image per scene cluster. Deterministic code (histogram, WB and exposure matching) applies the result to every photo. This is the cheapest option **and** the most consistent one, so the cost problem and the G4 problem have one fix.
- **Don't send full-res.** Global tone decisions don't need 4,784 tokens, and downscaling is also the privacy-friendly choice.
- **The cost of in-browser inference moves to the client.** Users download model weights (tens to hundreds of MB; serve them from a zero-egress CDN) and need a WebGPU-capable device. Keep a server-GPU fallback for weak devices, only on paid tiers.

### 6.3 Gross margin sanity check

Assumptions:
- Stripe is about $0.73 on a $12 charge (2.9% + $0.30 + 0.7% Billing) [38].
- R2 storage is $0.015/GB-mo with no egress fees [39]; about $0.09/mo for 1,000 cloud-synced 6 MB JPEGs. Local-first storage costs about $0.

| User | Price | AI edits/mo | COGS (per-photo Sonnet) | COGS (anchor + propagate) | Margin (anchor + propagate) |
|---|---|---|---|---|---|
| Pro (heavy) | $12 | 1,000 | ≈ $8–11 → **5–30%** margin | ≈ $1.4 + $0.1 | **about 80%** |
| Pro (typical, assumed 250) | $12 | 250 | ≈ $2–3 | ≈ $0.4 | about 90% |
| Studio (peak wedding month) | $35 | 10,000 | ≈ $80–110 (**loss**) | ≈ $14 (Batch ≈ $7) | **about 50–75%** |
| Free | $0 | 25 | ≈ $0.08–0.27 | ≈ $0.04 | n/a (acquisition cost) |

**Conclusion:** sending each photo to Sonnet one by one breaks the Studio tier. Design for shoot-level reasoning with deterministic propagation from day 1. Use Haiku or Batch for overnight jobs and Sonnet for anchors and "learn my style".

Competitor per-photo benchmarks:
- Imagen $0.05 (+$0.01 add-ons) [12]
- Polarr Next $0.05 [31]
- Evoto about $0.05–0.10 [18]
- Autoenhance $0.08–0.20 [34]
- Photoroom API about $0.02–0.10 [24]

---

## 7. Scale-later checklist (f)

**Auth and accounts**
- [ ] Auth provider (Firebase Auth or Auth.js): email magic link + Google; Apple later. Session hardening and rate limits on auth endpoints.
- [ ] Self-serve **account deletion** that cascades to stored photos, recipes, style profiles and backups (GDPR Art. 17; also required by app stores later).

**Billing (Stripe)**
- [ ] Checkout + Billing + Customer Portal. Entitlements driven by **idempotent webhooks**. **Billing Meters** for AI-edit usage and top-ups.
- [ ] Fees to budget: 2.9% + $0.30, Billing 0.7%, Tax 0.5%, $15 per dispute, +1.5% international cards [38].
- [ ] VAT/sales tax: **Stripe Tax** vs a **Merchant of Record** (e.g. Paddle) if selling globally early.
- [ ] Easy cancel and clear renewal notices. State auto-renewal laws (e.g. California) and EU consumer rules apply; the federal FTC "click-to-cancel" rule was vacated in 2025 (verify current status). Avoid Remini/Picsart-style patterns [21][27].
- [ ] Dunning, proration, annual-plan refund policy, student/education discount (optional).

**Storage and data architecture**
- [ ] **Local-first:** originals stay in OPFS/IndexedDB or the File System Access API. Sync only edit recipes (JSON) and small previews.
- [ ] Optional cloud: R2/S3/Firebase Storage with **per-user prefixes, signed URLs, encryption at rest, lifecycle rules** (e.g. delete originals 30 days after export unless pinned).
- [ ] Before any frame leaves the device: **strip EXIF GPS and serial numbers**, then downscale (data minimization).

**Privacy (GDPR, US state law, AI-specific)**
- [ ] Privacy policy; lawful basis (contract); **DPA + public subprocessor list** (Anthropic, Stripe, Cloudflare/Google); EU→US transfers via DPF/SCCs; DSAR export; documented retention schedule.
- [ ] **Never train on user photos or edits without explicit opt-in consent.** The FTC's Everalbum order forced deletion of *models* trained on photos without consent [53]. Build the "learn my style" profile per user, stored as the user's data and deletable.
- [ ] **Faces:** detecting a face or person for masks is not the same as recognizing who they are. Avoid face recognition and grouping, or get explicit written consent. **Illinois BIPA** suits have hit Apple Photos, CapCut and Lensa [54]. Similar laws exist in TX and WA, and GDPR Art. 9 covers biometric data used for identification.
- [ ] **Anthropic API:** images aren't used to train models and are processed ephemerally per the vision docs [36]. Review commercial terms and retention; consider ZDR or `inference_geo` for EU customers (US-only inference is a 1.1× price multiplier [37]).
- [ ] **EU AI Act Art. 50** (in force since **2 Aug 2026**): disclose AI-manipulated or deepfake content. The watermarking duty for providers of synthetic content is postponed to **2 Dec 2026** [55]. For generative remove/expand, add **C2PA Content Credentials** and a visible "AI-generated content" note in export metadata.
- [ ] Cookie consent and consent-gated analytics (PostHog/GA4).

**Model license compliance** (keep a `MODEL_LICENSES.md` inventory: model, version, license, attribution, commercial OK?)

| Model (candidate use) | License | Commercial SaaS OK? |
|---|---|---|
| **SAM 2** (masks) [46] | Apache-2.0 | Yes |
| **BiRefNet** (background removal) [47] | MIT | Yes |
| **MODNet** (portrait matting) [52] | Apache-2.0 | Yes |
| **LaMa** (object removal) [48] | Apache-2.0 | Yes |
| **MI-GAN** (mobile inpainting) [49] | Reported MIT (check the repo LICENSE) | Probably; **verify** |
| **MediaPipe** segmenters (selfie/hair/multiclass) [50] | Apache-2.0 framework; check each model card | Probably; **verify per model** |
| **BRIA RMBG-2.0 / RMBG-1.4** [45] | **CC BY-NC 4.0 / BRIA non-commercial** | **No, not without a paid BRIA license.** These power many Transformers.js "remove background" demos [51], which is an easy trap |
| FLUX.1-dev / SD-family (generative fill, later) | Mixed (FLUX.1-dev non-commercial; Stability Community License has revenue thresholds) | **Verify before use** |

**Ops, security and quality**
- [ ] Job queue for batches; **Batch API (−50%) for non-urgent overnight jobs**; model fallback; per-user cost metering and alerts; abuse rate limits.
- [ ] Golden eval set (photos plus pro reference edits) to score every prompt or model change on **AI acceptance rate** and a color-difference metric before shipping.
- [ ] CSP and signed URLs. If public share links ever host user images, add a CSAM detection and reporting process.

**Business and legal**
- [ ] Trademark clearance and filing (section 4.3).
- [ ] Terms of service: a license to process user content only, no ownership claims, and an AI-output disclaimer.
- [ ] Company and payments setup.
- [ ] SOC 2 only if Studio or teams sell into agencies.

---

## 8. Validation plan (before heavy build)
1. **Positioning smoke test:** one landing page with 3 headline variants (L2 pain, L3 mechanism, L4 proof) and a waitlist. Compare at a *single* awareness level per ad set.
2. **Concierge test:** 15–20 ICP-C photographers each send one 100–300 photo shoot. Deliver AI slider edits and measure the **acceptance rate** and how long they spend tweaking. **[REAL RESULT NEEDED]** before claiming any time-saved figure.
3. **Price test:** use a Van Westendorp survey on the waitlist, then A/B test $10 vs $12 vs $15 for Pro at launch.
4. **Kill or pivot signal:** if acceptance stays low after style tuning, or ICP C won't pay at least $10/mo, move to the real-estate niche (per-image pricing, HDR and sky features) [34] or to ICP B through Lightroom XMP export.

---

## 9. Vocabulary (named concepts used above)
- **Parametric / non-destructive editing:** the edit is stored as a recipe of adjustments (sliders), not baked into the pixels.
- **Human-in-the-loop AI / glass-box (explainable) AI:** the AI proposes, the human reviews and adjusts, and the reasoning is visible.
- **Few-shot style learning:** personalizing from a handful of examples instead of thousands (contrast with "personal AI profiles").
- **Look matching / batch sync:** making a set of photos share one consistent look across changing light.
- **Hybrid (freemium + usage-based) pricing:** subscription tiers with included quotas, plus metered top-ups.
- **Edge / on-device inference:** running models in the user's browser or device, so there's no server GPU cost.
- **Data minimization:** sending only the data a task needs (e.g. a downscaled, EXIF-stripped preview).

---

## 10. Sources
1. Adobe Lightroom plans: https://www.adobe.com/products/photoshop-lightroom/plans.html
2. Adobe Photography 20GB plan FAQ: https://helpx.adobe.com/creative-cloud/faq/ccpp-20gb.html
3. DIYPhotography, 20GB plan ending: https://www.diyphotography.net/adobe-is-killing-off-its-20gb-photoshop-lightroom-plan-in-two-days/
4. Adobe Lightroom 1TB pricing-change FAQ (403 on fetch; figure via search snippet): https://helpx.adobe.com/lightroom-cc/kb/lightroom-1tb-plan-faq.html
5. Lightroom Classic release notes: https://helpx.adobe.com/at/lightroom-classic/desktop/introduction-to-lightroom-classic/release-notes.html
6. Lightroom desktop release notes: https://helpx.adobe.com/uk/lightroom/desktop/introduction/release-notes.html
7. Lightroom on the web, requirements and notes: https://helpx.adobe.com/lightroom/web/get-set-up/learn-the-basics/technical-requirements.html · https://helpx.adobe.com/at/lightroom/web/whats-new/release-notes.html
8. Adobe pricing and gen-credit backlash: https://www.pcworld.com/article/2788602/adobe-will-charge-you-more-for-creative-cloud-in-june-because-ai.html · https://community.adobe.com/questions-6/continue-with-full-subscription-or-drop-to-photoshop-plan-generative-fill-credits-a-concern-1614521 · https://kompozy.io/news/adobe-photoshop-ai-backlash-exodus
9. Lightroom Auto complaints: https://lightroomkillertips.com/hit-lightrooms-auto-tone-button/ · https://community.adobe.com/t5/lightroom-ecosystem-cloud-based-discussions/auto-tone-results-in-overexposed-photos/m-p/11595586
10. Luminar Neo pricing: https://photutorial.com/luminar-pricing · https://www.temperstack.com/plans/luminar-neo/ · https://www.culturedkiwi.com/?p=10013
11. Luminar Neo issues: https://www.fotowissen.eu/luminar-neo-test-1243-update-2025/ · https://community.adobe.com/t5/photoshop-ecosystem-discussions/luminar-neo-plugin-for-ps2025/m-p/14947164
12. Imagen pricing: https://filterpixel.com/imagen-ai-pricing · https://imagen-ai.com/valuable-tips/imagen-ai-review/ · https://www.photoworkout.com/?p=221310
13. Imagen profile requirement: https://imagen-ai.com/post/create-ai-editing-profile/
14. Imagen reviews: https://www.saasworthy.com/product/imagen-ai/reviews
15. Aftershoot 2026 suite and pricing: https://photorumors.com/2026/06/06/aftershoot-the-workflow-is-now-complete-and-ai-that-works-for-you-not-against-you/ · https://aftershoot.com/blog/aftershoot-pricing/ · https://pricingsaas.com/companies/aftershoot
16. Aftershoot profile training: https://support.aftershoot.com/en/articles/6673009-how-many-images-should-i-use-to-train-a-profile
17. Aftershoot WB / Edits 2.0: https://support.aftershoot.com/en/articles/9542253-retraining-your-personal-ai-editing-profiles-to-edits-2-0 · https://aftershoot.com/blog/ai-photo-editing-models/
18. Evoto pricing: https://www.evoto.ai/payment · https://www.xpay.sh/saas-pricing/evoto-ai/
19. Evoto reviews: https://www.trustpilot.com/review/evoto.ai?page=3
20. Picsart pricing: https://toolradar.com/tools/picsart/pricing · https://costbench.com/software/ai-design-tools/picsart-ai/
21. Picsart complaints: https://uk.trustpilot.com/review/picsart.com · https://support.picsart.com/hc/en-us/articles/35274842696733-Why-are-my-credits-not-renewed-correctly
22. Canva pricing: https://piktochart.com/blog/canva-pricing-2026-costs-raised/ · https://stylefactoryproductions.com/blog/canva-pricing · https://eesel.ai/blog/canva-ai-pricing
23. Canva backlash: https://www.techeconomy.ng/canva-faces-backlash-over-300-price-hikes-for-business-subscriptions
24. Photoroom: https://ecommercefastlane.com/photoroom-review/ · https://usagepricing.com/blueprint/activity/photoroom-2026-07-22-free-plan-dropped-allowances · https://dailyaifixs.com/blog/photoroom-pricing-2026-the-api-isn-t-included
25. Pixlr: https://pricingsaas.com/companies/pixlr · https://toolradar.com/tools/pixlr/pricing
26. Fotor: https://www.capterra.com/p/181589/Fotor/pricing/ · https://www.softwareadvice.com/photo-editing/fotor-profile/
27. Remini: https://unstar.app/blog/is-remini-legit-safe-photo-enhancer-app-reviews-2026 · https://morphed.app/blog/remini-free-limits · https://www.sikayetvar.com/en/remini-us/remini-kept-charging-me-after-i-canceled-how-can-i-get-a-refund-q-22739
28. Snapseed: https://en.wikipedia.org/wiki/Snapseed · https://mezha.ua/en/news/google-snapseed-ios-update-302647/amp/
29. Darkroom+: https://darkroom.co/help/membership/darkroom+
30. VSCO: https://vsco.co/pricing
31. Polarr / Polarr Next: https://getpulsesignal.com/pricing/polarr · https://thedailyworkflow.com/service/Polarr%20Next
32. Topaz: https://www.renderahouse.com/blog/topaz-ai-pricing · https://www.myarchitectai.com/blog/topaz-ai-pricing
33. Google Photos "Help me edit": https://blog.google/products/photos/android-conversational-editing-google-photos/ · https://9to5google.com/2025/09/23/google-photos-help-me-edit/
34. Autoenhance.ai: https://autoenhance.ai/blog/autoenhance-ai-s-new-pricing · https://imagen-ai.com/post/imagen-vs-autoenhance/
35. AI-to-sliders in Lightroom (Imagen/Aftershoot): https://imagen-ai.com/post/best-lightroom-plugins/ · https://aftershoot.com/edit/
36. Claude Vision docs (image tokens, limits, data handling): https://platform.claude.com/docs/en/build-with-claude/vision
37. Claude pricing (models, cache, Batch −50%, inference_geo): https://platform.claude.com/docs/en/about-claude/pricing
38. Stripe fees (secondary; confirm at stripe.com/pricing): https://dodopayments.com/blogs/stripe-fees-calculator
39. Cloudflare R2 pricing (secondary; confirm at developers.cloudflare.com/r2/pricing): https://www.spendbase.co/?p=35561
40. USPTO LUMEN Reg. 5560647 (Justia): https://trademarks.justia.com/877/85/lumen-87785245.html
41. Lumen Technologies marks: https://trademark.justia.com/886/42/lumen-88642312.html · https://search.ipaustralia.gov.au/trademarks/search/view/2063116/details
42. "Lumen" photo apps: https://www.appbrain.com/appstore/lumen-camera/ios-6767933252 · https://apps.appfollow.io/ios/rollei-lumen/1465120665?country=us · https://apps.apple.com/us/app/-/id1503176746
43. "Kelvin" conflicts: https://github.com/wmwallace/Kelvin/releases · https://www.creativeforce.io/blog/seamlessly-integrate-capture-software-into-your-workflow-with-the-creative-force-app-kelvin/
44. Halation / Tonecraft crowding: https://mwm.ai/apps/halationify-analog-photos/6739345616 · https://appshunter.io/ios/app/tonecraft-tuner-studio/id6785127245
45. BRIA RMBG-2.0 license: https://github.com/Bria-AI/RMBG-2.0
46. SAM 2 license: https://roboflow.com/model-licenses/segment-anything-2
47. BiRefNet (MIT): https://www.promptlayer.com/models/birefnet · https://arxiv.org/pdf/2401.03407
48. LaMa ONNX (Apache-2.0): https://huggingface.co/Carve/LaMa-ONNX
49. MI-GAN: https://github.com/Picsart-AI-Research/MI-GAN
50. MediaPipe Image Segmenter: https://ai.google.dev/mediapipe/solutions/vision/image_segmenter
51. Transformers.js WebGPU background removal: https://huggingface.co/spaces/Rene78/remove-background-webgpu/blob/main/README.md · https://blog.logrocket.com/building-background-remover-vue-transformers-js
52. MODNet (Apache-2.0): https://docs.openvino.ai/2024/omz_models_model_modnet_webcam_portrait_matting.html
53. FTC v. Everalbum: https://www.ftc.gov/node/48633 · https://worldprivacyforum.org/posts/ftc-proposes-precedent-setting-face-recognition-settlement-photo-app-company-must-delete-consumers-photos-and-the-algorithmic-models-it-developed-using-the-photos
54. BIPA photo-app suits: https://www.businessinsurance.com/illinois-biometric-suit-against-apple-proceeds-roslyn-hazlitt-et-al-v-apple-in/ · https://blogs.duanemorris.com/classactiondefense/2025/01/13/trend-3-privacy-class-actions-continue-to-proliferate-as-plaintiffs-search-for-winning-theories/
55. EU AI Act Art. 50 timing: https://www.cooley.com/news/insight/2026/2026-08-03-eu-ai-act-transparency-obligations-take-effect-2-august-2026 · https://www.goodwinlaw.com/en/insights/publications/2026/08/alerts-technology-dpc-eu-ai-act-transparency-obligations-now-in-force
56. Market size estimates (low confidence): https://www.technavio.com/report/photo-editing-software-market-size-industry-analysis · https://alliedmarketresearch.com/photo-editing-software-market

**Not verified or caveats:**
- Most competitor prices come from aggregators. Adobe was the only competitor plans page verified directly. Aftershoot and Imagen vendor pages failed to load (redirect or 403); Photoroom now hides prices.
- Re-check all prices before external use.
- The trademark screen is a web search, not a legal clearance.
