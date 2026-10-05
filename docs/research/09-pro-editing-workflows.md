# 09 · Professional editing workflows → Auto Enhance and Auto Retouch engineering spec

Researched 2026-10-04. Builds on `01-ai-auto-edit.md` §6 (classical auto-tone formulas) and `07-portrait-retouch-tech.md` §3 (retouch shader). Where this document gives a different number, **this one wins**, because it is grounded in how professionals actually work; §2.12 and §4.14 list the deltas.

**Evidence tags used on every number**

| Tag | Meaning |
|---|---|
| `[S:x]` | Stated by source `x` in §6 (read during this research) |
| `[D:x]` | Derived by me arithmetically from a sourced value (derivation shown) |
| `[H]` | My synthesis / engineering default. Not sourced. Tune with the §5 harness |
| `[U]` | Widely repeated but I could not confirm it in a source I read. Treat as a hypothesis |

Colour maths conventions: `Y` = linear relative luminance (Rec.709 weights), `v = enc(Y)` = sRGB-encoded luma 0–1 (≈ IRE/100 for display-referred video), `L*` = CIELAB lightness, OkLab for retouch (as in 07). IOD = inter-ocular (pupil-to-pupil) distance in source pixels.

---

## 0. The fifteen findings that drive the design

1. **Order matters and pros agree on it:** white balance → exposure (set by the *subject's midtones*, ignoring highlights) → highlight/shadow recovery → white/black points → contrast → colour (vibrance, HSL) → detail → local/retouch `[S:dt-filmic, S:dt-sigmoid, S:wed-order]`.
2. **Exposure is anchored on the subject, not the histogram.** Scene-referred tools pin middle grey at 18 % and let the tone curve compress the ends `[S:dt-filmic]`. Portrait practice pins *skin*: light skin about one stop above middle grey (Zone VI) `[S:zone]`.
3. **Histogram-equalising auto is the known failure.** Users complain Lightroom Auto is "too bright" on most images, brightens night scenes, and adds too much saturation `[S:lr-auto-bright]`. darktable's own auto-tuner "usually fails for portraits and indoor scenes" `[S:dt-filmic]`.
4. **Face-priority exposure must adapt to skin tone.** A fixed face-brightness target over- or under-exposes depending on skin tone; the published fix is to move the *bounds* of the target by skin-tone likelihood `[S:ely]`. Cameras still under-expose darker skin `[S:imatest]`.
5. **DxO's design is the right shape:** weight exposure toward detected faces "without radically modifying the rest", and fall back to uniform when no face is found `[S:dxo]`.
6. **White balance: neutralise casts, keep light.** Golden-hour warmth is wanted; AWB removing it is a complaint `[S:golden]`. Statistical estimators are weak on portraits/monochrome scenes; skin is a usable cue `[S:bianco]`. Good auto WB needs a *confidence* and an *intent* gate more than a better estimator.
7. **Skin has invariants that can be checked numerically:** R > G > B always `[S:lr-rgb]`; yellow ≥ magenta; cyan a fraction of magenta `[S:cmyk-smug]`; hue near the vectorscope skin line `[S:kdenlive]`.
8. **Vibrance, not saturation,** because vibrance is biased to protect orange/red/yellow and already-saturated colours `[S:jkost]`.
9. **Clip tolerances in pro tools are tiny:** 0.1 % per end in Capture One auto-levels `[S:c1]`, 0.2 % in RawTherapee thumbnails `[S:rt-exp]`.
10. **Retouch is layered, and smoothing is the *last and smallest* layer.** Clean-up (heal temporary things) → even out luminance (dodge & burn / low-frequency) → even out colour → features (eyes, teeth) → restore/keep texture `[S:fs-guide, S:phlearn-wf]`.
11. **The band that carries "bad skin" is the mid frequencies.** Adobe built Texture on exactly this: it targets mid-frequency and leaves pores and lashes `[S:adobe-texture]`. Wavelet retouchers smooth only the two coarsest detail scales and leave the fine ones untouched `[S:pixls-wavelet]`. A single blur (what Lumen does today) removes the fine band first, which is backwards.
12. **"Plastic" has one reliable tell: no visible pores** `[S:kelby]`. So pore-band energy inside skin is the number to protect and to test.
13. **Two-week rule:** remove what will be gone in two weeks (pimples, scratches, stray hair, shine); keep moles, freckles, scars, character lines (soften, never erase) `[S:two-week]`.
14. **Fake-looking features come from over-correction of whites:** "radioactive" eye whites (especially the corners), over-white teeth, enlarged or over-sharpened eyes `[S:kelby, S:dps-5]`. Under-eye fixes are deliberately partial (60–70 % opacity) and need colour added back or they go grey `[S:phlearn-eye, S:tutkit]`.
15. **Market signal:** Evoto presets are criticised as too heavy ("plasticky, flat" until backed off) `[S:evoto-pf]`; PortraitPro defaults likewise `[S:ppro]`; Retouch4me is praised precisely because it does not blur (dodge-and-burn approach) but can be heavy-handed or miss things `[S:r4m]`. **Default strength should be low and need-scaled.**

---

## 1. Professional RAW develop workflow

### 1.1 Order of operations and why

| # | Step | Why here | What pros look at |
|---|---|---|---|
| 0 | Profile, lens corrections, demosaic, highlight reconstruction, denoise | Must precede anything that judges colour or clipping. darktable default reconstruction is "inpaint opposed" `[S:dt-hl]` | Clipped channels, noise floor |
| 1 | **White balance** | Changes channel gains → changes clipping and luminance, so it must precede exposure `[S:wed-order]` | Neutrals, then skin |
| 2 | **Exposure** (global, linear) | Set the *midtones/subject* right and ignore highlights for now; the tone mapper brings them back `[S:dt-filmic, S:dt-sigmoid]` | Skin level; grey card; subject midtone |
| 3 | **Highlights / Shadows** (tone-mapping the ends) | Recover what exposure pushed out; only after the middle is fixed | Skin hot-spots, white clothing, sky; shadow noise |
| 4 | **Whites / Blacks** (end points) | Decide how much true white and true black the picture has | 0.1–0.2 % clip `[S:c1, S:rt-exp]` |
| 5 | **Contrast / tone curve** | S-curve pivoting on middle grey; must not move the anchor from step 2 `[S:dt-sigmoid]` | Midtone separation, face modelling |
| 6 | **Vibrance → Saturation → HSL** | Tone changes alter perceived saturation, so colour comes after tone. Vibrance first, saturation to fine-tune `[S:jkost]` | Skin (orange) saturation and luminance |
| 7 | **Texture / Clarity / Dehaze** | Mid-frequency contrast; clarity is unflattering on faces `[S:dps-5]` | Skin vs. environment |
| 8 | **Sharpening / NR** | Output-ish; mask sharpening off skin | Lashes and eyes at 100 % `[S:dps-5]` |
| 9 | **Local corrections and retouch** | After global look is fixed, so retouch strength is judged on the final tones | §3 |

Lumen note: retouch *executes* before develop in the engine (07 §3.0) but its **strength must be decided after** Auto Enhance has run, on the developed preview (§4.12).

### 1.2 Skin exposure targets

Anchors that are sourced:

| Anchor | Value | Source |
|---|---|---|
| Middle grey | 18 % linear → L\* 49.5, v ≈ 0.46 | `[S:dt-filmic]`; conversion `[D]` |
| Light ("Caucasian") skin, lit side | Zone VI = +1 stop over middle grey → 36 % linear → L\* ≈ 66.5, v ≈ 0.64 | `[S:zone]`; conversion `[D]` |
| Darker skin | "about −1 stop" from light skin → around Zone V (L\* ≈ 50) and below | `[S:zone]` (vague) |
| False-colour practice | skin overall 50–70 IRE; lighter skin 61–70 IRE; dark skin "sweet spot" spans the green-to-pink bands (≈ 41–70 IRE) | `[S:fc]` |
| Lightroom readout | light skin around R 70–80 %, G 60–70 %, B 50–60 %; any channel ≥ 94 % means overexposed | `[S:lr-rgb]` |
| Where to measure | brightest diffuse skin: the cheek nearest the light, not highlights; forehead/chin/neck for colour | `[S:zone, S:tuts-skin]` |

**Target bands** for the *lit diffuse skin* statistic `Ls` (defined in §2.4). Class by Individual Typology Angle, `ITA = atan((L* − 50)/b*)·180/π`, thresholds 55/41/28/10/−30 `[S:ita]`. The bands themselves are `[H]`, interpolated through the sourced anchors above:

| ITA class | ITA° | Target `Ls` centre (L\*) | Accept band (no correction inside) | v centre |
|---|---|---|---|---|
| Very light | > 55 | 70 | 66–75 | 0.67 |
| Light | 41–55 | 67 | 62–72 | 0.64 |
| Intermediate | 28–41 | 62 | 57–68 | 0.59 |
| Tan | 10–28 | 56 | 50–62 | 0.53 |
| Brown | −30–10 | 49 | 43–56 | 0.46 |
| Dark | ≤ −30 | 42 | 36–50 | 0.39 |

Caveats to respect in code: ITA binning has no consensus and maps poorly to Fitzpatrick `[S:ita]`; ITA measured from an image depends on the exposure and WB you are trying to solve (§2.4 handles this with an exposure-independent estimate and wide bands). The sources disagree on how bright dark skin should sit: false-colour practice allows it as high as light skin `[S:fc]`, zone practice puts it a stop lower `[S:zone]`. The table sits between and the accept bands are wide on purpose.

Hard skin limits (all classes): diffuse skin `P99` of max(R,G,B) ≤ 0.94 encoded `[S:lr-rgb]`; skin `P5` L\* ≥ 18 `[H]` (below that, shadow-side skin loses colour).

### 1.3 White balance on skin

| Check | Rule | Source |
|---|---|---|
| Channel order | `R > G > B` on diffuse skin for every skin tone | `[S:lr-rgb]` |
| Light-skin example | R 80 / G 70 / B 60 %: G about midway, R ≈ 20 points above B | `[S:lr-rgb]` |
| CMY relationships (print numbers) | Y ≥ M always (else sunburn); typically Y is 5–20 % above M; C = 30–50 % of M (< 30 % reads sunburnt, > 50 % ghostly) | `[S:cmyk-smug]` |
| Alternative statement | Y within ~10 points of M; C = 1/5–1/3 of M | `[S:cmyk-smug]` (Margulis-style, as quoted on forums) |
| Darker skin | more C and M; C rises to about half of M | `[S:cmyk-smug]` |
| Asian / Hispanic guidance | C = 1/4–1/2 of Y; Y = M + 0…15 | `[S:cmyk-web]` |
| Vectorscope | all skin sits on the I ("skin tone") line; only saturation and brightness vary | `[S:kdenlive]` |

Engine form `[H]`, on encoded sRGB medians of diffuse skin, using naive complements `c = 1−R′, m = 1−G′, y = 1−B′` (not a real CMYK separation, so use wide tolerances):

```
qY = y/m   healthy 1.02 … 1.35     (< 1.00 → too magenta/pink, > 1.45 → too yellow)
qC = c/m   healthy 0.25 … 0.60     (< 0.20 → too red,          > 0.70 → grey/cyan/green cast)
hueYCbCr = atan2(Cr, Cb)  healthy 115° … 140°   (BT.601; centre 127°)
```

**Source disagreement (flagged):** the vectorscope skin line is conventionally at ≈ 123° `[U]`; the Lightroom rule-of-thumb light-skin triple (80/70/60 %) computes to ≈ 138° and a more saturated skin (88/67/54 %) to ≈ 132° `[D]`. So "on the line" and "80/70/60" are not the same colour. The window above spans both; do **not** drive skin to a single hue.

### 1.4 What "good" looks like, by genre

Ranges are Lightroom-scale slider values. Wedding ranges are sourced; the rest is `[H]` practice lore that the harness must confirm.

| Aspect | Portrait / headshot | Group / wedding / event | Non-portrait (landscape, travel, product) |
|---|---|---|---|
| Exposure anchor | lit skin in §1.2 band | *brightest-skinned* face not over its band; darkest face lifted with Shadows, not Exposure | log-average to a scene key (01 §6.4) |
| Highlights | −15…−50; skin hot-spots and white clothing keep detail | wedding practice −10…−20 as a baseline `[S:wed-order]`; −30…−70 with a white dress in sun `[H]` | −30…−80 with sky |
| Shadows | +5…+30; keep face modelling | +10…+90 seen in wedding practice `[S:wed-order]`; auto cap +45 `[H]` | +20…+60 |
| Whites / blacks | clip ≤ 0.1 % each end `[S:c1]`; whites stop where the dress keeps texture `[S:dress]` | same | up to 0.2 % `[S:rt-exp]` |
| Contrast | modest, +0…+15; too much ages skin | +5…+20 | +10…+30 |
| Vibrance / saturation | 0…+12 / 0…+3; skin protected | 0…+15 / 0…+5 | +10…+30 / 0…+8 |
| Clarity / texture | clarity ≤ 0 on faces `[S:dps-5]`; texture 0 (retouch handles skin) | clarity 0…+8 masked off faces | +5…+20 |
| WB | skin inside §1.3 window; keep ambient mood | consistent across the series matters more than per-frame accuracy `[S:lr-batch]` | neutral unless golden/blue hour |
| Sharpen | default amount, **masking 50–80** so skin is not sharpened `[H]` | same | masking 0–30 |

White clothing target `[H]`: brightest fabric `P99.5` of max-channel at 0.93–0.97 encoded, never ≥ 0.985. Practice statement behind it: the dress must be white *with detail*, "edge against overexposing, but only just" `[S:dress]`.

Capture defaults worth mirroring: ACR applies default sharpening and colour NR to every raw `[S:acr-sharp]`. Amount is 25 in the help page I read; current versions are widely reported as 40 / radius 1.0 / detail 25 / masking 0, colour NR 25 `[U]`. Lumen: keep its own raw defaults, and let Auto touch only `sharpen.masking` and `noise.*`.

---

## 2. Auto Enhance: algorithm spec

Inputs: linear scene-referred RGB proxy (long edge 1024 for stats, float16+), EXIF, masks `face[i]` (bbox + mesh), `skin`, `hair`, `clothes`, `sky`, `subject`. Output: slider deltas + `confidence` + `reasons[]`. Everything is solved on the proxy with the "solve-on-proxy" secant loop from 01 §6.2, so it stays correct if slider implementations change.

### 2.1 Pipeline

```
A  measure        → stats, masks, clipped maps (pre-WB)
B  classify scene → sceneType, intent flags, confidence priors
C  white balance  → temp, tint (+ wbConfidence)
D  exposure       → EV (face-weighted where faces exist)
E  recovery       → highlights, shadows
F  end points     → whites, blacks
G  contrast/curve → contrast (+ optional parametric curve)
H  colour         → vibrance, saturation, optional HSL orange/red nudges
I  detail         → sharpen.masking, noise.luminance/color (ISO based)
J  guardrails     → per-scene clamps, skin re-check, do-nothing test, confidence scaling
K  (optional) style layer on top
```
Re-measure the proxy after each stage (same rule as 01 §6.1). Stages D–G iterate once more if the skin statistic left its band after G (contrast moves skin).

### 2.2 Stage A: measurements

- `valid` = not clipped (`max(R,G,B) < 0.995·white`) and `Y > 0.002`.
- `skinD` (diffuse skin) = `skin` ∩ face region, eroded by 0.02 IOD, minus specular pixels (`Y > 1.6 × median skin Y` or chroma < 0.5 × median skin chroma) and minus pixels below `P20` of skin Y (shadow side, beard) `[H]`.
- Face weight `wf[i] = area_i^0.5 × sharpness_i × frontalness_i`, normalised; faces with IOD < 12 proxy px get weight 0 `[H]`. Square root so one close face does not erase five behind it.
- Global: `P0.1, P0.5, P1, P5, P50, P95, P99, P99.5, P99.9` of `v` and of encoded max-channel; log-average `L_avg`; dynamic range `DR = log2(P99.5(Y)/P0.5(Y))` EV; `clipHi`, `clipLo` fractions; per-mask medians for sky, clothes, subject.
- Colour: illuminant candidates (§2.5), mean chroma `C̄` non-skin, hue histogram concentration `κ` (share of the dominant 60° hue sector among pixels with C\* > 15).

### 2.3 Stage B: scene classification

Rule-based first (cheap, explainable); a small classifier or the vision model can overwrite the flags later.

| Flag | Rule `[H]` | Effect |
|---|---|---|
| `portrait` | Σ face area ≥ 2 % of frame, or largest face IOD ≥ 6 % of long edge | face weight high (§2.4) |
| `group` | ≥ 3 faces with weight > 0.1 | group exposure rule |
| `smallFaces` | faces present but Σ area < 0.5 % | faces are a guard only, not the anchor |
| `backlit` | faces present and `median(Y skinD) < 0.5 × median(Y of frame)` | Shadows budget ↑, EV on face, highlights ↑ |
| `highKey` | `P50(v) > 0.68` and `P5(v) > 0.30` | no darkening toward mid-grey; EV ≤ 0 clamp unless face under band |
| `lowKey` | `P50(v) < 0.22` and `P95(v) > 0.55` (bright accents on dark) | no brightening of background; shadows × 0.4; EV only from face |
| `night` | `L_avg < 0.02` or (ISO ≥ 1600 and t ≥ 1/15 s) (01 §6.4) | EV ≤ +1.0, blacks not lifted |
| `silhouette` | subject mask median `v < 0.08`, background median `v > 0.55`, no face with weight > 0.1 | do nothing to exposure/shadows |
| `stageLight` | faces present and skin hue outside 95°–160° (YCbCr) *or* illuminant candidate chroma > 0.25 (rg-chromaticity distance from neutral) | WB off, vibrance ≤ 0, exposure by face luminance only |
| `mixedLight` | ≥ 2 faces whose skin hue differ by > 14°, or sky/clothes neutral estimates differ from skin estimate by > 8° angular | wbConfidence × 0.4 |
| `goldenHour` | warm cast `a > 0.25` (01 §6.3 metric), skin still inside 105°–140°, low sun cue: EXIF time within 90 min of sunrise/sunset when GPS/timezone exists, else `sky` mask present with warm lower sky | WB strength 0.35 and never cooler than as-shot − 30 % of the estimated correction |
| `monochromeScene` | `κ > 0.65` (forest, sea, a coloured wall) | grey-world family disabled |
| `flatDocument` | very low chroma, bimodal histogram, no faces | levels only |
| `alreadyEdited` | non-raw and (`P0.5(v) < 0.03` and `P99.5(v) > 0.95` and contrast σ(L\*) ≥ 18) or XMP/EXIF Software tag from an editor | all moves × 0.4; see §2.11 |
| `bw` | mean chroma < 2 | skip C, H |

### 2.4 Stage D: exposure solve (stage C comes first in execution; described after)

**Skin statistic.** Per face: `Ys[i]` = mean of `Y` over `skinD` pixels between the 40th and 80th percentile (the lit diffuse side, mirroring "meter the cheek nearest the light" `[S:zone]`). `Ls[i] = L*(Ys[i])`.

**Skin-tone class without circularity** `[H]`. Exposure and ITA are entangled, so estimate reflectance relative to an in-image reference:

```
ref = first available of:
   sclera median Y (weight 0.9; sclera ≈ a near-neutral, fairly constant reflector, but often in shadow)
   teeth median Y  (weight 0.6)
   scene white     = P98 of Y over valid, non-specular, non-light-source pixels (weight 0.5)
ρ[i] = Ys[i] / ref                      (relative skin reflectance)
toneIdx[i] = clamp( (log2 ρ − log2 0.22) / (log2 0.75 − log2 0.22), 0, 1 )   # 0 = dark … 1 = very light
classConf[i] = weight of the reference used × (1 − |disagreement between references| / 1 stop)
```
Map `toneIdx` linearly onto the §1.2 centres (42 → 70) and bands. When `classConf < 0.4`, **do not classify**: use the union band L\* 40–72 with centre 60 and apply only half the correction. This is the published idea of adapting the *bounds* of face brightness to skin-tone likelihood `[S:ely]`, implemented without a classifier network. The constants 0.22 / 0.75 are guesses and are the first thing to calibrate on the test set.

**Face EV.** For each face, out-of-band error only (dead-band):

```
e[i](EV) = max(0, Lo[i] − Ls[i](EV)) − max(0, Ls[i](EV) − Hi[i])      # + means too dark
EV_face = argmin_EV  Σ wf[i] · ( e[i](EV)² + 0.15·(Ls[i](EV) − centre[i])² )
```
The small centre term pulls gently toward the centre; the band term dominates. Closed-form start: `EV0 = Σ wf·log2(Ycentre[i]/Ys[i])`, then two secant steps on the proxy.

**Group rule.** After solving, enforce: no face with `wf > 0.08` above its `Hi` band (reduce EV until true), and send the residual under-exposure of darker faces to Shadows (§2.6), up to +45. Rationale: mixed skin tones in one frame are the classic failure `[S:imatest]`; clipping the lightest face is unrecoverable, lifting the darkest is.

**Global EV** (no faces, or as the second opinion): 01 §6.4 key-based solve with two changes: use the **subject mask** median when a subject is found (weight 0.6 subject / 0.4 frame) and keep the `highKey`/`lowKey`/`night` flags as clamps.

**Blend.**

```
A  = Σ face area fraction;  wF = smoothstep(0.003, 0.04, A) × mean(classConf∨0.5) ;  cap 0.9
EV* = wF·EV_face + (1 − wF)·EV_global
EV  = clamp( d·EV*, −1.5, +2.5 ),   d = 0.9 if faces drive it, else 0.75 (01)
```
`d < 1` because users report auto as too bright far more often than too dark `[S:lr-auto-bright]`. Extra asymmetric damping for positive moves without faces: `EV > 0 → EV × 0.85`.

**Highlight guard (replaces 01 §6.4 step 4).** After EV, compute on unclipped-at-capture pixels: `skinHot = P99(max-channel) over skinD`, `whiteHot = P99.5(max-channel) over clothes ∪ sky ∪ frame`. If `skinHot > 0.94` `[S:lr-rgb]` after the Highlights stage has used its full budget, reduce EV in 0.05 steps until satisfied, but not below `EV_face − 0.5` (a slightly hot forehead beats a muddy face; shine reduction in retouch handles the rest).

**Limits.** RAW: −1.5…+2.5 EV. Non-raw (8-bit JPEG/HEIC): −0.8…+1.2 EV `[H]`, since pushing 8-bit data further bands and shows noise.

### 2.5 Stage C: white balance

**Candidates** (each returns illuminant chromaticity `e` and a self-confidence `q`):

| Id | Method | Notes |
|---|---|---|
| `asShot` | camera multipliers | prior; almost always "plausible"; `q = 0.5` |
| `sog` | Shades-of-Grey, Minkowski p = 6 | the L6 norm performed best overall in the original study `[S:sog]` |
| `ge` | 1st-order Grey-Edge, p = 6, σ = 1 | average edge colour is achromatic `[S:ge]` |
| `wp` | robust white-patch `P99.5` per channel on unclipped pixels | Max-RGB is the p = ∞ case of the same family `[S:sog]`; only if `clipHi < 1 %` |
| `neutral` | median of near-neutral *objects*: sclera, teeth (weight 0.5, they are yellowish), white/grey clothing or paper found as low-chroma (C\* < 6 after `asShot`) bright connected regions | `q` grows with area and with agreement between regions |
| `skin` | gains that move the weighted skin chromaticity onto the skin locus target (§1.3 window centre, per tone class) | skin clusters in colour space and is a valid illuminant cue `[S:bianco]`; `q = 0.6 × classConf`, 0 if make-up/stage flags |

Disable `sog/ge/wp` under `monochromeScene`; gray-world-type assumptions fail on scenes without a neutral average `[S:dt-cc]`. RawTherapee's correlation method is documented as good for daylight 4000–12000 K and blackbody 2000–4000 K and unreliable for low-CRI sources (fluorescent, LED, underwater) `[S:rt-itcwb]`: treat estimates that land far off the daylight/Planckian locus (|Duv| > 0.02 `[H]`) as "invalid illuminant" exactly as darktable flags them `[S:dt-cc]`, and halve their weight.

**Combine** `[H]`:

```
stat  = normalised geometric mean of the enabled {sog, ge, wp} (channel-wise)
agree = 1 − clamp( maxPairwiseAngle(enabled statistical candidates) / 6°, 0, 1 )
e_hat = normalise( Σ q_k·w_k·log e_k ),  w = {stat: 1.0·agree, neutral: 1.5, skin: 1.2, asShot: 0.8}
wbConfidence = clamp( 0.25 + 0.5·agree + 0.25·(q_neutral ∨ q_skin), 0, 1 ) × flagFactors
```
Angular thresholds: differences under about 3° are generally taken as barely noticeable `[U]`; 6° is "clearly different".

**Strength and intent.**

```
s = 0.8 (default) ; 0.35 if goldenHour ; 0.5 if tungsten interior with warm skin still in-window ;
    0 if stageLight ; ×0.4 if mixedLight ; ×0.4 if alreadyEdited
correction = s · wbConfidence · (e_hat − asShot)   (in log-chromaticity; then → temp, tint)
```

**Skin-locus check (always run when faces exist).** Re-measure skin after the proposed correction:

1. If skin leaves the §1.3 window (`hue ∉ [115°,140°]`, or `qY < 1.0`, or `qC > 0.7`), shrink the correction by bisection until it is back inside or the correction reaches zero.
2. If skin is *outside* the window before correction and the proposal moves it further out, flip to the `skin` candidate alone at strength 0.6.
3. If skin is inside the window as shot **and** the proposed correction is < 2.5° angular, **do nothing** (report "white balance looks right"). Small corrections on good skin are where auto WB loses trust.
4. Never drive skin to the window centre; in-window is enough (sources disagree on the centre, §1.3).

**Limits.** RAW: 2500–9500 K absolute result; per-click change ≤ ±1800 K-equivalent and tint ≤ ±25 `[H]`. Non-raw: relative `temp` ±30, `tint` ±15 (the camera's WB is baked in and channel data is clipped/quantised). Series consistency: when Auto is applied to a selection, solve WB per *scene cluster* (time gap < 60 s and similar histogram) and apply one value per cluster; users notice frame-to-frame WB flicker more than a small absolute error, and already complain that batch auto differs from single auto `[S:lr-batch]`.

### 2.6 Stage E: highlights and shadows

Measured after EV. Budgets depend on the scene:

```
needHi = max( 300·max(0, hiMean − 0.82) + 1500·hiClipRecoverable ,          # 01 §6.6
              220·max(0, skinHot − 0.90) ,                                    # skin hot-spots
              250·max(0, whiteHot_clothes − 0.95) )                           # dress / shirt detail
highlights = −clamp(needHi, 0, capHi),  capHi = 70 (portrait 60; group/wedding with white clothing 80)

needLo = 250·max(0, 0.14 − loMean) + 500·max(0, loCrush − 0.02)               # 01 §6.6
       + 60·(under-band error of darker faces, in stops)                      # group rule
shadows = +clamp(needLo, 0, capLo), capLo = 45 portrait/group, 60 landscape, ×0.4 lowKey, 0 silhouette
```
`hiClipRecoverable` counts only pixels clipped in the render but not at capture; sensor-clipped areas go to highlight reconstruction, not the slider `[S:dt-hl]`. Shadows are additionally capped by noise: `capLo × clamp(1.6 − log2(ISO/400)·0.2, 0.4, 1)` `[H]`. Wedding practice supports the asymmetry (small highlight pulls, large shadow lifts are common) `[S:wed-order]`, but large shadow lifts are also what produces the flat "HDR" look users dislike, hence the caps.

Rule: **recover with Highlights/Shadows before reducing EV**, and never use local histogram equalisation. CLAHE-type operators amplify noise in flat regions and need clip limits and tile interpolation just to stay tolerable `[S:clahe]`; they are unsuitable on skin. Lumen's highlights/shadows should stay an edge-aware base/detail tone operator (guided-filter base: the guided filter avoids the gradient-reversal artefacts bilateral filtering shows near edges `[S:gf]`).

### 2.7 Stage F: whites and blacks

Targets tightened to pro-tool tolerances:

| Quantity | Target | Source |
|---|---|---|
| White point | `P99.9` of encoded max-channel → 0.97 (so ≈ 0.1 % of pixels may exceed it) | 0.1 % `[S:c1]` |
| Black point | `P0.1` of `v` → 0.02 | 0.1 % `[S:c1]` |
| Looser fallback for low-detail thumbnails/batch | 0.2 % | `[S:rt-exp]` |

- Whites: `w = clamp(solve(P99.9 → 0.97), −40, +40)`; **skip positive whites** if `highlights < −40` (fighting yourself) or if white clothing is already ≥ 0.95; with faces, positive whites are capped so `skinHot ≤ 0.94`.
- Blacks: `b = clamp(solve(P0.1 → 0.02), −35, +15)`; under `night`/`lowKey` only negative; `highKey`/fog: target 0.05 and cap −10 (airy scenes should not get a hard black).
- Dark hair/clothing guard: if hair or dark clothing makes up > 15 % of the frame, set the black target from `P0.1` of that mask to 0.03 so hair keeps separation `[H]`.

### 2.8 Stage G: contrast and tone curve

Principle from scene-referred tools: contrast is an S-curve that **pivots on middle grey and leaves it unchanged** `[S:dt-sigmoid]`; more contrast means less dynamic range fits, so contrast is chosen from the scene's range after recovery, not added by habit.

```
σ = std(L*) over valid pixels after E–F ;  σ_t by scene: portrait 17, group/event 18, landscape 21, lowKey/highKey 15 (don't force)
contrast = clamp(150·(σ_t − σ)/σ_t, −10, +25)            # tighter than 01 §6.7
portrait cap +15 ; if DR_scene > 10 EV → contrast ≤ +5 (already using both ends)
```
Face modelling guard: after contrast, skin `P95 − P5` (L\*) inside the face must stay ≤ 38 `[H]`; if exceeded, back contrast off. Pivot guard: contrast must not move `Ls` by more than 1.5 L\*; if it does, re-solve EV once.

Optional parametric curve (only if `contrast` hit its cap or the look needs it): `lights +6…+12`, `darks −4…−10` for a gentle S; never touch `curve.points` in Auto (reserved for styles).

### 2.9 Stage H: vibrance, saturation, HSL

- Vibrance is the lever: it protects already-saturated colours and is biased to move orange/red/yellow less `[S:jkost]`. Lumen's vibrance must implement **explicit skin protection** rather than rely on hue bias: `gain(p) = 1 + k·(1 − sat(p))^1.5 · (1 − 0.8·skinMask(p)) · (1 − 0.5·skinHueWeight(p))` `[H]`.
- Amount: `vibrance = clamp(120·(C_t − C̄)/C_t, −15, cap)`, `C_t = 28` (01 §6.8), `cap` = 12 portrait, 15 group, 30 landscape; `saturation = clamp(0.2·vibrance, −5, cap/4)`. Lower than 01 because Auto adding "too much saturation" is a live complaint `[S:lr-auto-bright]`.
- **Skin saturation check after the move:** skin chroma `C*` median must stay inside 14–34 (very light … tan) or 12–30 (brown/dark) `[H]`; if above, apply `hsl.orange.sat −5…−15`, and only if hue is in-window. If skin is orange after golden-hour light, prefer `hsl.orange.sat −8` and `hsl.orange.lum +5` over a WB change `[S:golden]`.
- `hsl.red.lum`/`hsl.orange.lum` brighten or calm skin without touching WB `[S:wed-order]`; Auto may use ±10 at most and only with faces.
- Sky/foliage nudges from 01 §6.10 stay optional and masked.

### 2.10 Stage I: detail (optional, off by default in v1)

| Param | Rule `[H]` |
|---|---|
| `sharpen.masking` | portrait 60, group 45, else leave |
| `sharpen.amount/radius/detail` | leave the raw default; never raise with faces; pros lean on converter defaults and check lashes at 100 % `[S:dps-5]` |
| `noise.luminance` | `clamp(8·log2(ISO/800), 0, 40)`; +5 if shadows > 35 |
| `noise.color` | default (25 `[U]`), +10 above ISO 6400 |
| `texture`, `clarity`, `dehaze` | 0 with faces. Clarity emphasises blemishes and wrinkles `[S:dps-5]`. Landscape: clarity ≤ +10, dehaze per 01 §6.9 |

### 2.11 Stage J: guardrails, confidence, "do nothing"

**Maximum moves per click** (after all stages):

| Slider | Portrait | Group/event | Landscape/other | Non-raw multiplier |
|---|---|---|---|---|
| exposure (EV) | −1.0…+2.0 | −1.0…+2.0 | −1.5…+2.5 | × 0.6 |
| highlights | −60…0 | −80…0 | −80…0 | × 0.7 |
| shadows | 0…+45 | 0…+45 | 0…+60 | × 0.6 |
| whites / blacks | −40…+25 / −30…+10 | −40…+30 / −30…+10 | −40…+40 / −35…+15 | × 0.7 |
| contrast | −10…+15 | −10…+20 | −10…+25 | × 0.7 |
| vibrance / saturation | −10…+12 / −5…+3 | −10…+15 / −5…+4 | −15…+30 / −5…+8 | × 0.7 |
| temp / tint (relative) | ±1800 K / ±25 | same | same | ±30 / ±15 units |

**Overall confidence** `conf = min(exposureConf, 0.5 + 0.5·wbConfidence) × flagFactor`, where `exposureConf` = 1 with a confident face, 0.8 with a subject mask, 0.6 histogram only, and × 0.6 when `EV_face` and `EV_global` disagree by > 1.2 EV without the `backlit` flag explaining it. Every slider delta is multiplied by `conf` (floor 0.4 for exposure when a face is > 1 stop outside its band: a clearly wrong face is worth fixing even when unsure).

**Do-nothing rules.** Auto returns "Looks good; no changes" (and says why) when all hold: skin inside band or no faces and `|EV*| < 0.15`; WB rule 3 of §2.5; `|highlights|, shadows < 8`; whites/blacks within ±5; `|contrast| < 4`; vibrance < 4. Partial: any single slider whose delta is below `{EV 0.07, others 3}` is zeroed so the UI shows a clean edit. Never apply Auto on top of Auto: Auto always solves from the *un-autoed* state of the sliders it owns and replaces them.

**Intent preservation.** `silhouette`, `lowKey`, `highKey`, `night`, `stageLight`, `bw` each disable the stages listed in §2.3 and add a reason string. `alreadyEdited` scales everything by 0.4 and disables WB unless skin is out-of-window.

**Skin re-check (final).** After all stages: `Ls` in band (else one more EV iteration), skin hot ≤ 0.94, skin hue/ratios in window, skin `C*` in range. Any failure that cannot be repaired within limits reduces `conf` and is reported.

### 2.12 Stage K: styles and looks on top

1. **Auto Enhance = technical normalisation** (neutral, correct, subject well exposed). It writes only the "correction" sliders listed above.
2. **A style is a separate layer** applied after: either *target shifts* fed into the same solver (01 §6.12: Bright & Airy = skin centre +3 L\*, black target 0.05, σ_t −3, C_t −2; Moody = skin centre −4 L\*, σ_t +3, C_t −6, WB strength × 0.5 `[H]`) or *relative deltas + curve/grade/HSL*, which Auto never touches (`curve.points`, `grade.*`, `hsl.*` beyond the ±10/−15 skin nudges, `grain`, `vignette`).
3. Order of evaluation: solve Auto with the style's target shifts → add the style's fixed deltas → run the §2.11 skin re-check again with the style's own band (a style may move the skin centre by at most ±6 L\* and may not break hue/ratio windows unless flagged "creative colour").
4. Personal style learning (Imagen/Aftershoot model: thousands of the user's own edits, about 2,500–3,000 images to train `[S:ai-cmp]`) maps onto this cleanly: learn the user's **target shifts and deltas relative to the neutral Auto result**, which needs far fewer examples than learning absolute sliders `[H]`.

**Deltas vs 01 §6:** face/skin-anchored exposure with tone-adaptive bands (new); WB candidates + skin-locus gate + do-nothing rule (replaces single combined estimate); clip targets 0.1 % (was 0.5 %); contrast cap +15…+25 (was +40); vibrance cap 12–30 (was 35) with explicit skin mask; per-scene max-move table; confidence scaling of every delta.

---

## 3. Professional skin retouch workflow

### 3.1 The layers, in order

| # | Layer | What the pro does | What it must not do |
|---|---|---|---|
| 1 | **Raw develop** | Exposure, WB, skin colour first; retouch on a correct file `[S:phlearn-wf]` | Retouch to compensate for bad exposure |
| 2 | **Clean-up (heal/clone)** | Remove temporary things: pimples, scratches, stray hairs on the face, lint, crumbs. Two-week rule `[S:two-week]`. Hard-edged tool sized to the blemish so texture is not smeared `[S:fs-mistakes]` | Remove moles, freckles, scars, birthmarks (identity) |
| 3 | **Evenness of luminance** | Dodge & burn (micro: 1–5 mm bumps and patches; macro: form) or the low layer of a frequency separation. Low opacity/flow: 1–2 % flow on the texture layer is the stated guidance `[S:fs-mistakes]`. Work along the light gradient, with smaller brushes near mouth corners, eyes, nose `[S:fs-mistakes]` | Blur or paint the low layer flat: it merges shadows and highlights and flattens the face `[S:fs-mistakes]` |
| 4 | **Evenness of colour** | Reduce redness/blotchiness on a colour-only layer (Color blend mode between the frequency layers) `[S:fs-mistakes]`; match neck/face/hands | Change the person's skin colour; remove natural cheek colour entirely |
| 5 | **Texture decisions** | Keep pores. Several separations at different radii per region (forehead ≠ cheek ≠ neck), 2–3 rounds rather than one aggressive pass `[S:fs-guide]`. Mid frequencies live on the low layer; ignoring them gives skin that is sharp at 100 % but blurry zoomed out `[S:fs-mistakes]` | One global radius; one global strength |
| 6 | **Under-eye** | Lighten toward cheek tone with a low-opacity tool (15–20 % brush), then **back the layer off to 60–70 %**; add colour back at about 30 % on a Color layer so it does not go grey `[S:phlearn-eye, S:tutkit]` | Remove the lid crease, the tear trough completely, or the lower lash shadow |
| 7 | **Eyes** | Remove a few veins, reduce red and yellow in the whites, brighten *only the ring next to the iris*, never the corners `[S:kelby]`; darken the iris rim, lighten the inside slightly; keep catchlights | White-out the sclera, sharpen until lashes halo, enlarge eyes `[S:dps-5]` |
| 8 | **Teeth** | Shift yellow toward neutral (selective colour: less yellow, a little more cyan) with a mask on teeth only; small lightness lift `[S:kelby]` | Brighter than the scene's lighting supports; uniform white (teeth have variation) `[S:teeth]` |
| 9 | **Lips** | Clean edges, heal cracks, even colour; keep vertical texture and gloss highlights | Smooth lips with the skin filter |
| 10 | **Hair** | Remove flyaways crossing the face and the outline strays; fill small gaps | Cut a hard, helmet-like outline |
| 11 | **Shine** | Reduce hot-spots (forehead, nose, chin, cheekbones), keep some specular for dimension | Flat matte face |
| 12 | **Contour (optional, style)** | Macro dodge & burn: reinforce existing light, never invent it | Re-light the face |
| 13 | **Output sharpen + grain** | Sharpen eyes/lashes/lips/hair, not skin; a little grain unifies retouched and untouched areas `[H]` | Global clarity on faces `[S:dps-5]` |

### 3.2 Standards: how far each grade goes

`[H]` synthesis from the sources above; the grade names are common industry usage, the percentages are mine.

| Grade | Use | Blemishes | Mid-band evenness | Pore band | Wrinkles | Under-eye | Eyes/teeth |
|---|---|---|---|---|---|---|---|
| **Natural** (default for families, weddings, events) | client galleries | temporary only | 20–35 % | 100 % kept | 10–25 % softer | 30–50 % | barely visible |
| **Commercial** (headshots, portraits, seniors) | deliverables | temporary + redness | 40–55 % | ≥ 90 % kept | 30–45 % | 50–65 % | visible in A/B only |
| **High-end / beauty** | hero images | everything temporary, selected permanent on request | 60–75 %, by local D&B rather than blur | ≥ 85 % kept, sometimes enhanced | 50–65 %, never erased | 60–75 % | polished but physically plausible |

Reference heuristics: "never do more than good makeup can achieve" `[S:pixls-wavelet]`; if pores are still there, the retouch was done well `[S:kelby]`. Client taste is moving toward visible texture (an Imagen-published survey claims 95 % of Gen-Z portrait clients prefer it; vendor claim, unverified `[U]`).

### 3.3 What makes a retouch look fake, and the specific prevention

| Artefact | Cause | Prevention used by pros → rule for Lumen |
|---|---|---|
| Plastic / wax skin | Fine band attenuated; uniform strength everywhere | Never attenuate the pore band; attenuate mid band only, amplitude-selectively (§4.3) |
| "Sharp but blurry" skin | Only the very fine band kept; all mid frequencies removed `[S:fs-mistakes]` | Cap mid-band removal (≤ 75 %); keep 25 % always |
| Flat face, no shape | Low-frequency luminance blurred `[S:fs-mistakes]` | Base band (> 0.25 IOD) untouched; no luminance evening by default |
| Halos at jaw, hairline, nostril | Blur kernel crossing a mask boundary; soft mask over hard edge | Masked (normalised) convolution; guided feather; erode before feather (§4.2) |
| Smudged brows, lashes, lip edges, stubble | Skin mask includes them | Explicit exclusions + stubble/texture map (§4.2) |
| Grey / ashy under-eyes | Lightness raised without restoring chroma `[S:phlearn-eye, S:ue-color]` | Move L *and* chroma toward the cheek reference; cap at 70 % |
| Missing lid crease, "pillow" under-eye | Mid band flattened across the crease | Protect lash line and high-amplitude crease; keep ≥ 40 % of crease contrast |
| Radioactive eye whites | Whole sclera brightened, corners included `[S:kelby]` | Weight by proximity to iris; cap ΔL\*; desaturate rather than brighten |
| Glowing "Chiclet" teeth | Lightness pushed; all yellow removed | Cap at eye-white brightness; remove ≤ 60 % of yellow; keep inter-tooth shading |
| Alien eyes | Iris over-sharpened/saturated; eyes enlarged `[S:dps-5]` | Caps on iris contrast/saturation; **no geometry in Auto** |
| Spotty "leopard" healing | Many heals each slightly different from surroundings | Heal only the low/mid band and keep original fine band (07 §3.3); cap heal count |
| Vanished moles/freckles | Detector treats every dark spot as a blemish | Classification + keep-by-default (§4.5) |
| Mask-like face vs untouched neck/hands | Only the face treated | Apply evenness to all connected skin (neck, ears, shoulders, hands) at 60–100 % |
| Uniform result across ages | One preset | Need-scaled strength; age-aware caps (§4.11) |

---

## 4. Auto Retouch: algorithm spec

Processing space: OkLab of linear sRGB (07). Thresholds below in OkLab units unless stated; 0.01 OkLab L ≈ 1 L\* `[D, approximate]`. All sizes relative to IOD so one set of numbers serves every resolution. Physical grounding: adult interpupillary distance averages about 63 mm `[U]`, so 0.01 IOD ≈ 0.6 mm on the face.

### 4.1 Why the current implementation fails (diagnosis to confirm against code)

A single blur + blend removes the finest frequencies first and the mid frequencies last, which is the reverse of what a retoucher does (§0 finding 11). It also (a) crosses mask edges → halos, (b) treats beard, brows and lips as skin, (c) uses one strength regardless of need or face size, and (d) heals spots by replacing all bands, which leaves smooth discs. Each item maps to a section below.

### 4.2 Skin mask refinement

Inputs: `segSkin`, `segHair`, `segClothes` (soft, 0–1), 478-point mesh per face.

```
1  M0 = segSkin · (1 − segHair) · (1 − segClothes)
2  Protect polygons from the mesh, rasterised then dilated (IOD units):
     eyes (incl. lids to the crease) 0.060 · eyebrows 0.035 · lips (outer contour) 0.025
     nostrils 0.030 · inside mouth/teeth 0.020 · ear canal n/a
   P = max of the feathered polygons (feather 0.02)
3  Hairline / beard / stubble / brow texture map (no gender classifier):
     E_f  = local RMS of the fine band (σ 0.004–0.012 IOD) in a 0.06-IOD window
     dark = smoothstep(0.02, 0.08, L_local − L_pixel_min-filter)        # dark strands on lighter skin
     orient = structure-tensor coherence of the fine band
     H = smoothstep(2.0, 3.5, E_f / median skin E_f on forehead/upper cheek) · max(dark, orient)
     limited to: beard zone (below nose, jaw, neck), sideburns, hairline band 0.12 IOD, brows
4  Glasses: frame = strong, long, thin edges (|∇L| > 0.08 over length > 0.5 IOD) crossing the eye region;
            lens glare = desaturated bright blobs inside the lens. Both → protect; shadow of frames on cheeks → keep.
5  Speculars & clipped: S = pixels with max-channel ≥ 0.98 → excluded from statistics, handled by shine (§4.8)
6  M1 = M0 · (1 − P) · (1 − glasses)
7  Erode M1 by 0.012 IOD, then edge-aware feather: guided filter(guide = L, r = 0.04 IOD, ε = 1e−3)
8  skinSmooth = M1 · (1 − 0.75·H)        # stubble keeps ≥ 75 % of its bands
   skinColour = M1                         # colour evenness may run under stubble
   skinStats  = erode(M1, 0.03 IOD) · (1 − H) · (1 − S)   # for all measurements
```
Why guided feathering: it tracks luminance edges without the gradient-reversal artefacts of bilateral weights, though any local filter can still halo across very strong edges, hence the erosion first `[S:gf]`. The ε and radii are `[H]`.

Body skin (neck, shoulders, arms, hands): use `M0` connected to a face; apply bands with the nearest face's IOD and strength × 0.7; no blemish healing beyond 1.5 × IOD from a face in Auto.

**Resolution gate** (pores do not exist below a certain sampling):

| IOD (source px) | What runs |
|---|---|
| ≥ 160 | everything |
| 80–160 | everything; fine band B0 passes through untouched (no restore/enhance) |
| 40–80 | B2/B3 evenness at × 0.6, colour evenness, under-eye × 0.6, blemishes with radius ≥ 0.02 IOD only; no wrinkle, no iris |
| 20–40 | colour evenness × 0.5 and shine only |
| < 20 | nothing |

### 4.3 Multi-band separation

Five components by difference of low-passes. Radii are Gaussian σ:

| Band | Scale (σ, IOD) | ≈ on face | Contains | Low-pass used |
|---|---|---|---|---|
| **B0 fine** | < 0.006 | < 0.4 mm | pores, vellus hair, grain | Gaussian σ0 = 0.006 |
| **B1 small** | 0.006–0.020 | 0.4–1.3 mm | fine lines, small bumps, stubble dots, lash shadows | Gaussian σ1 = 0.020 |
| **B2 mid** | 0.020–0.065 | 1.3–4 mm | blemish bodies, enlarged-pore clusters, blotches, acne swelling | masked Gaussian σ2 = 0.065 |
| **B3 broad** | 0.065–0.22 | 4–14 mm | patchiness, under-eye bags, uneven tan, D&B territory | masked guided/box³ σ3 = 0.22 |
| **Base** | > 0.22 | > 14 mm | form, lighting, make-up contour | — |

"Masked" = normalised convolution over `skinStats` (`blur(M·x)/blur(M)`) so hair, background, lips and eyes never bleed in: this is the halo fix. Support for the layout: retouchers pick the split so that no "bulky textures and volumes" enter the high layer `[S:fs-guide]`; the commonly taught band-stop ("inverted high pass") uses a high-pass radius R and a blur of R/3, i.e. it removes the band between R/3 and R and keeps everything finer `[U]` (σ2/σ1 ≈ 3.25 here); a rule of thumb puts the main split near 1.5 % of face width ≈ 0.033 IOD `[S:fs-radius]`, which falls inside B2 as it should; wavelet practice smooths only the two coarsest of five detail scales `[S:pixls-wavelet]`; Adobe's Texture acts on mid frequencies and leaves pore detail `[S:adobe-texture]`.

**Gains** (`s` = smoothing amount 0–1 after slider mapping; `A(x)` = amplitude selectivity):

```
A_k(x) = 1 − smoothstep(τ_k, 2.5·τ_k, |Bk.L(x)|)          # 1 for low-amplitude variation, 0 for strong structure
τ1 = 0.020, τ2 = 0.035, τ3 = 0.050  (OkLab L; lower τ2 to 0.028 when s > 0.6)

g0 = 1.00                                   # pore band: never attenuated by Smooth
g1 = 1 − 0.30·s·A_1·skinSmooth
g2 = 1 − 0.75·s·A_2·skinSmooth              # the working band
g3 = 1 − 0.40·s·A_3·skinSmooth   (L channel) ;  chroma of B2,B3 handled by §4.6
out = Base + g3·B3 + g2·B2 + g1·B1 + g0·B0·texGain
texGain = mix(0.85, 1.15, texture/100)     # Texture slider; default 50 → 1.00
```
Amplitude selectivity is what keeps nostril shadows, lid creases, dimples and the jaw line while flattening blotches (same idea as 07 §3.1, now per band). τ values are `[H]`; calibrate so that `A_2` ≈ 1 on cheek blotches and ≈ 0 on the nasolabial fold.

Regional multipliers on `s` `[H]`, following the per-region practice `[S:fs-guide]`: forehead 1.0, cheeks 1.0, nose 0.6 (pores are expected there), chin 0.8, upper lip 0.5, under-eye 0.7 (thin skin: over-smoothing shows first), neck 0.7, ears 0.5, hands 0.5.

### 4.4 Slider mapping for Smooth, and auto strength

`s = (smooth/100)^1.2 × 1.0`, so slider 100 = the hard limits above (30 / 75 / 40 % band reduction), slider 50 ≈ 44 % of that. Compared with 07 the exponent is > 1 so the low end is gentle `[H]`.

**Need-scaled auto value:**

```
n2 = robust RMS (1.4826·MAD) of B2.L over skinStats on cheeks+forehead      # blotch/bump energy
n3 = robust RMS of B3.L residual after removing a planar lighting fit per region
need = clamp( (0.6·n2 + 0.4·n3 − 0.006) / (0.022 − 0.006), 0, 1 )            # constants [H], OkLab L
smooth_auto = round( need × cap_style ),  cap_style = 35 Natural · 55 Commercial · 70 High-end
```
Clear skin (need ≈ 0) gets 0. That is the single biggest behavioural change: **strength follows measured need**, so the same button is right for a teenager with acne, a bride in make-up and a 70-year-old.

### 4.5 Blemish detection and healing

Detection keeps the 07 §3.3 machinery (DoG scale-space on L and a\*, robust local σ, roundness), with the decision rules below. Work on a face crop normalised to IOD = 200 px.

**Candidate features:** radius `r` (IOD), contrast `zL` (local z-score of darkness), redness `Δa` vs local skin (OkLab a, also expressed as z-score `za`), brownness `Δb`, roundness (axis ratio), edge sharpness (gradient magnitude at the border / contrast), specular (bright centre), count density of similar spots per face.

| Class | Rule `[H]` | Auto action |
|---|---|---|
| **Pimple / inflamed spot** | 0.006 ≤ r ≤ 0.04; `za ≥ 2.5` (red) with any `zL`; soft border; often a bright or yellow centre | heal |
| **Dark spot / scab / post-acne mark** | 0.006 ≤ r ≤ 0.03; `zL ≥ 3`; `za` 0…2; soft border; not brown-saturated | heal at slider ≥ 30 |
| **Mole (nevus)** | `zL ≥ 4` and darker than local skin by ≥ 0.12 OkLab L; brown (Δb > 0, Δa small); **sharp border**; roundness > 0.6; r ≥ 0.012 | **keep** (toggle "Remove moles", off) |
| **Freckles / lentigines** | r ≤ 0.012; brown; low contrast (`zL` 1.5–3); **≥ 12 similar spots** on nose/cheeks/forehead | **keep all**; raise the healing threshold for brown spots on this face to `zL ≥ 4.5` |
| **Scar / crease** | elongated (axis ratio > 3) or length > 0.08 | never auto-heal; mid-band softening only |
| **Piercing, jewellery, glitter, glare** | specular centre, metallic chroma, or inside a protect polygon | never touch |
| **Stray hair on skin** | thin (width < 0.008), long, dark, coherent | heal only at slider ≥ 60 and if length < 0.6 IOD |
| **Vein, cold sore, stubble dot** | inside H map, lips, or under-eye zone | leave to the dedicated tool |

Selection: `k = mix(4.0, 2.0, v/100)` on the governing z-score; `maxR = mix(0.02, 0.05, v/100)`. Auto value: `blemish_auto = clamp(25 + 6·nPimples, 0, 70)`, and 0 if no candidate has z ≥ 3. **Cap** 40 heals per face in Auto; if more candidates exist (acne), heal the 40 highest-scoring and let B2 + redness correction (§4.6) carry the rest. Hundreds of heals read as fake.

Healing: band-limited membrane fill of `Base+B3+B2+B1` inside the spot (push-pull, 07 §3.3), **original B0 kept**, B1 kept at 50 %; soft disc radius 1.3 r, feather 30 %; a healed spot must end within ±0.008 OkLab L and ±0.006 a/b of the ring mean or it is rejected (prevents light/dark discs). Order: heal first, then compute bands for §4.3 from the healed image.

Policy summary (two-week rule `[S:two-week]`): Auto removes temporary marks only. Moles, freckles, scars, birthmarks, tattoos and vitiligo patches are never removed automatically; manual tools remain available.

### 4.6 Colour evenness (redness, blotchiness)

In OkLab, chroma channels only, bands B2 + B3 (+ a slow term against the face reference):

```
ref(x)  = masked blur of (a,b) over skinStats at σ = 0.22 IOD                # local "this person's skin"
faceRef = median (a,b) of skinStats on forehead+cheeks+chin
d(x)    = (a,b)(x) − ref(x)                                                   # local excursion
redEx   = max(0, d.a) ;   w = smoothstep(0.006, 0.020, |d|)                   # ignore sub-JND noise
(a,b)_out = (a,b) − e · w · [ κr·redEx·â  +  κo·(d − redEx·â) ]
   κr = 0.75 (red excursions: spots, nose sides, chin)   κo = 0.50 (other hue/patch excursions)
   e  = even/100
slow term: (a,b)_out += 0.25·e · zoneW · (faceRef − ref)                      # nose/ears/neck toward face
```
Guards: natural blush is real. On the cheek-apple zone multiply `κr` by 0.5 so at most ~40 % of cheek colour goes at slider 100. Lips, areola-like regions, tattoos excluded. The **mean face colour must not move**: after the pass, shift (a,b) so the skinStats mean equals the input mean (ΔE00 of the mean < 1.0). Luminance is untouched here (blotch luminance is handled by `g2/g3`). Optional L-evening stays off (07 §3.2).

Auto value: `need_c = clamp((P90(|d|) − 0.008)/(0.030 − 0.008), 0, 1)`; `even_auto = need_c × {40, 60, 75}` by grade.

Skin-tone adaptation: thresholds scale with the face's chroma, `τ → τ·clamp(C_face/0.06, 0.7, 1.4)`; for brown/dark skin, hyper-pigmentation shows as luminance + brown shifts rather than redness, so `κo` does the work and `κr` rarely triggers `[H]`.

### 4.7 Under-eye

Zone: mesh under-eye rings (07 §1.3), from 0.02 IOD below the lower lash line to the orbital rim; weight falls to 0 at the lash line and at the cheek.

```
cheekRef = masked mean OkLab over the upper cheek patch below the zone (σ 0.12 IOD), same side
dL = max(0, cheekRef.L − Lbase(x)) ,  dC = cheekRef.ab − ab_base(x)          # on Base+B3, not on fine bands
L  += u · 0.70 · dL · zoneW · (1 − creaseKeep)
ab += u · 0.60 · dC · zoneW                                                   # restores warmth → no grey
B2/B3 extra attenuation in zone: × (1 − 0.5·u·A_3)                            # softens the bag, keeps structure
creaseKeep = smoothstep(τc, 2.5·τc, |B1.L| + |B2.L|) , τc = 0.03              # tear trough / lid crease
u = underEye/100
```
Limits: never brighter than `cheekRef.L`; maximum lift 0.70·dL at slider 100 (pro practice backs the layer off to 60–70 % `[S:phlearn-eye, S:tutkit]`); chroma always moved with lightness (colour added back in practice at about 30 % `[S:phlearn-eye]`; the grey-under-eye failure is a missing colour correction `[S:ue-color]`); B0 untouched; crease keeps ≥ 40 % contrast by construction.

Auto: `need_u = clamp((mean dL in zone − 0.02)/(0.09 − 0.02), 0, 1)`; `underEye_auto = need_u × {45, 65, 75}`.

### 4.8 Shine

Detection as 07 §3.8 (bright vs broad base and desaturated vs skin), restricted to `skinColour` and weighted to T-zone, cheekbones, chin.

```
L  −= sh · 0.60 · rel · Sh           # at most 60 % of the hot-spot excess is removed
ab  = mix(ab, ref.ab, sh · 0.5 · Sh) # put skin colour back into the washed-out highlight
```
Clipped cores (no data): band-limited fill as in 07, only when `shine > 50`. Caps: remove ≤ 60 % at 100; **brown/dark skin: cap 40 %**, because specular highlights there carry the face's modelling and matte-ing them reads as ashy `[H]`. Auto: `shine_auto = clamp(300·areaFraction(Sh > 0.5) + 200·(P95(rel) − 0.05), 0, 60)`.

### 4.9 Teeth, eye whites, iris, lips

| Feature | Operation | Hard limits (slider 100) | Auto default |
|---|---|---|---|
| **Teeth** | mask = mouth interior ∩ bright ∩ not red; reduce yellow (OkLab b) then small L lift; keep B0–B2 (inter-tooth shading) | b reduced ≤ 60 %; a reduced ≤ 30 %; ΔL ≤ +0.05; never brighter than `min(scleraP90, 0.92)`; never bluer than neutral (b ≥ 0) | 0 if teeth not visible; `need = clamp((b_teeth − 0.02)/0.05,0,1)` × {30, 45, 55} |
| **Eye whites** | weight `wI = exp(−dist_to_iris / 0.05 IOD)` so corners stay; reduce a (red) and b (yellow); tiny L lift | a reduced ≤ 50 %, b ≤ 40 %; ΔL ≤ +0.035; veins (B0/B1) attenuated ≤ 50 %; corners (wI < 0.3) unchanged; sclera never above 0.90 L | `need` from redness × {20, 35, 45} |
| **Iris** | local contrast on B1/B2 inside iris, slight chroma; protect pupil and catchlight (L > 0.9) | contrast ≤ +20 %, chroma ≤ +15 %, ΔL ≤ +0.02; **no size change, no colour change** | {0, 15, 25} |
| **Lips** | heal cracks (B1 only), even colour 30 %; keep gloss highlights and vertical texture | no recolour in Auto; edge protect 0.01 IOD | {0, 15, 25} |

Rationale: brighten only next to the iris, corners left alone `[S:kelby]`; teeth get a colour shift more than a brightness lift `[S:kelby, S:teeth]`. For calibration, Lightroom's own brush presets are stronger than these caps (Iris Enhance: exposure +0.35, clarity +10, saturation +40 `[S:lr-brush]`; Teeth Whitening exposure +0.40, saturation −60 `[U]`); they are applied by hand to tiny areas and are commonly dialled back, so Auto sits at roughly half.

### 4.10 Wrinkles and expression lines

Ridge map as 07 §3.4 (Frangi-style on L at 2 scales), multiplied by zone masks. Softening = extra attenuation of B1 and B2 along the ridge only; B0 untouched.

| Zone | Type | Max reduction of line contrast at slider 100 |
|---|---|---|
| Forehead lines, glabella | static/dynamic | 65 % |
| Crow's feet | **expression** (present when smiling) | 45 % |
| Nasolabial fold, marionette | **structural/expression** | 35 % (separate sub-slider, 07) |
| Under-eye fine lines | fine | 55 % |
| Neck rings | static | 50 % |
| Lip lines | fine | 30 % |

Rules: never 100 % anywhere (07's 85 % ceiling drops to these values `[H]`); if a smile is detected (mouth-corner raise + cheek lift from the mesh), halve the crow's-feet and nasolabial values, because those lines *are* the expression. Auto: `wrinkle_auto = clamp(ridgeEnergy_norm, 0, 1) × {15, 35, 55}`, then × age factor (§4.11). Character lines are softened, not erased `[S:two-week]`.

### 4.11 Adaptation: age, gender, skin tone

- **No demographic classifiers.** Use measured, local cues, which are both more accurate and safer: stubble/beard map `H` (§4.2), ridge energy (wrinkles), need metrics, tone index (§2.4), face size.
- **Texture-coded faces** (visible stubble/beard, coarse pores: typically but not only men): where `H > 0.3` smoothing is already ≤ 25 %; additionally cap face-wide `smooth` at 0.7 × grade cap when mean `H` over the lower face > 0.25.
- **Age proxy** `ageIdx` = normalised ridge energy on forehead + crow's feet + nasolabial (0 young … 1 old). Caps: `wrinkle` max = `mix(grade, 0.6·grade, ageIdx)` (older faces keep more lines in proportion: reducing depth, not count); `smooth` unaffected; under-eye cap × 0.85 at `ageIdx = 1`.
- **Children / babies** (face proportions from the mesh: eye-to-chin / face-width ratio and large eye spacing; or user flag): all strengths × 0.3; teeth, wrinkles, shine off; blemish healing for scratches only.
- **Skin tone:** all thresholds are in OkLab (perceptually uniform), then: tone index < 0.35 (brown/dark) → shine cap 40 %, under-eye L factor 0.55 with chroma factor 0.7 (ashiness risk), **mean skin L must not rise** (ΔL mean ≤ +0.003) because retouch must never lighten skin; tone index > 0.8 (very light) → redness κr unchanged but cheek-blush guard 0.4 (redness is most visible and most natural there).
- **Make-up present** (high lip chroma, sharp eyeliner edges, very low n2 already): cap `smooth` at 20 and skip colour evenness on cheeks (blush/contour is intentional).

### 4.12 Orchestration

```
1 detect faces, mesh, segmentation → masks (§4.2) ; resolution gate per face
2 measure needs on the *developed* preview (after Auto Enhance): n2, n3, need_c, need_u, shine, blemish candidates, ridges
3 choose grade (user preference; default Natural) → auto slider values (need × cap)
4 apply per face: heal → bands → colour evenness → under-eye → shine → wrinkles → eyes/teeth/lips
5 verify (cheap, on the proxy): §5.2 gates. If texture retention < 0.85 or mean ΔE00 > 2, scale smooth/even down by 0.8 and retry (max 3)
6 report: per-face values, what was skipped and why ("3 moles kept", "beard protected", "face too small for detail work")
```
Per-face sliders are multipliers on the global ones (07 §3.13). A group shot gets **per-face need-scaled values**, not one value for all.

### 4.13 Slider → internal mapping and hard limits (summary)

| Slider (0–100) | Internal | At 100 (hard limit) | Auto default: Natural / Commercial / High-end caps |
|---|---|---|---|
| Smooth | `s = (v/100)^1.2` | B1 −30 %, B2 −75 %, B3(L) −40 %, B0 0 % | need × 35 / 55 / 70 |
| Texture | `texGain = mix(0.85, 1.15, v/100)` | pore band ×0.85…×1.15 | 50 (=1.00) / 50 / 55 |
| Even tone | `e = v/100` | red excursions −75 %, other −50 %, mean ΔE00 < 1 | need × 40 / 60 / 75 |
| Blemishes | `k = mix(4.0, 2.0)`, `maxR = mix(0.02, 0.05)` IOD | ≤ 40 heals/face in Auto; moles/freckles kept | 25 + 6·n, ≤ 70 |
| Under-eye | `u = v/100` | 70 % of ΔL to cheek, 60 % of Δchroma | need × 45 / 65 / 75 |
| Shine | `sh = v/100` | −60 % excess (−40 % dark skin) | measured, ≤ 60 |
| Wrinkles | `w = v/100` × zone table | 30–65 % by zone | need × 15 / 35 / 55 |
| Teeth | `t = v/100` | b −60 %, ΔL +0.05, ≤ sclera | need × 30 / 45 / 55 |
| Eye whites | `ew = v/100` | a −50 %, b −40 %, ΔL +0.035, near iris only | need × 20 / 35 / 45 |
| Iris | `ir = v/100` | contrast +20 %, chroma +15 % | 0 / 15 / 25 |
| Lips | `lp = v/100` | crack heal + 30 % colour evening | 0 / 15 / 25 |

Global hard limits (cannot be exceeded by any slider combination): pore-band RMS retention inside skin ≥ 0.85; mean skin colour ΔE00 ≤ 2.0 (≤ 1.0 from evenness alone); mean skin L change within −0.005…+0.003 for tone index < 0.35 and ±0.01 otherwise; no geometry; no change outside masks + 0.03 IOD.

### 4.14 Deltas vs 07 §3

| Topic | 07 | 09 |
|---|---|---|
| Bands | 3 (σ 0.012; guided r 0.06; base) | 5, with a protected pore band below 0.006 and the working band at 0.020–0.065 |
| Fine band | gain 0.4–1.1 via Texture | gain 0.85–1.15; Smooth never touches it |
| Mid reduction | up to 100 % of low-amplitude mid | ≤ 75 % (B2), ≤ 30 % (B1), ≤ 40 % (B3 L) |
| Low-pass | plain Gaussian B1, guided B2 | masked (normalised) convolution for σ2, σ3: halo fix |
| Stubble/brows | polygons only | measured texture map `H`, no classifier |
| Strength | preset "scaled by need" (sketch) | explicit need metrics, grade caps, verify loop |
| Under-eye | L 0.8, chroma 0.6 | L 0.7 with crease keep, chroma 0.6, dark-skin factors |
| Wrinkles | ≤ 85 % | 30–65 % by zone, smile-aware |
| Teeth/eyes | sclera cap | adds yellow/redness removal caps, iris-proximity weight, no corners |
| Small faces | per-face sigmas | resolution gate table |

---

## 5. Automatic evaluation

### 5.1 Auto Enhance metrics

| Metric | Definition | Pass gate `[H]` |
|---|---|---|
| Skin exposure error | `|Ls − centre|` and out-of-band distance per face, by tone class | out-of-band = 0 for ≥ 90 % of faces; mean abs error ≤ 4 L\* |
| Tone-class fairness | same metric split by ITA class; darker classes are where devices fail and vary most `[S:imatest]` | worst class ≤ 1.5 × best class |
| Grey-card exposure | on frames containing a grey card / ColorChecker: card L\* after Auto vs 50 | ≤ ±4 L\* |
| WB angular error | recovery angular error between the corrected neutral patch and (1,1,1): report mean, median, tri-mean, worst-25 % | median ≤ 3°, worst-25 % ≤ 6° |
| Skin WB | skin hue (YCbCr) inside 115°–140°, `qY`, `qC` in window; ΔE00 of skin vs the expert rendition | ≥ 95 % in window |
| Do-no-harm rate | share of images where Auto increases the error vs the input (exposure and WB separately) | ≤ 8 % |
| Do-nothing precision | on a curated "already good / intentional" subset: share left (nearly) untouched | ≥ 85 % |
| Clipping | skin `P99` max-channel ≤ 0.94; white fabric ≤ 0.985; global clip ≤ 0.2 % each end | 100 % / 98 % |
| Expert agreement | vs expert renditions: mean ΔE\*ab and PSNR, plus the human-region-weighted and group-consistency variants defined for portrait retouching `[S:ppr10k]` | track, no absolute gate |
| Series consistency | std of solved EV, temp, tint within near-duplicate bursts; batch vs single-image result (a known user complaint `[S:lr-batch]`) | EV σ ≤ 0.10, temp σ ≤ 120 K-eq, batch = single |
| Slider sanity | distribution of each slider vs §2.11 limits; fraction at clamp | ≤ 5 % at clamp |
| Preference | blind A/B vs Lightroom Auto and vs current Lumen on 100 images, 3+ photographer raters | ≥ 60 % wins vs current |

### 5.2 Auto Retouch metrics

| Metric | Definition | Gate `[H]` |
|---|---|---|
| **Texture retention (TR)** | `RMS(B0_after)/RMS(B0_before)` over `skinStats` (B0 = image − Gaussian σ 0.006 IOD, L channel). Also report for band B1 | TR0 ≥ 0.85 always, ≥ 0.92 Natural; TR1 ≥ 0.70 |
| Mid-band reduction (MR) | `1 − RMS(B2_after)/RMS(B2_before)` | 0.15–0.45 Natural, ≤ 0.75 ever; must correlate with need (ρ > 0.6 across test faces) |
| Pore-spectrum check | radially averaged power spectrum of a cheek patch: ratio after/before per octave | no octave above 0.5 mm⁻¹-equivalent drops > 20 % |
| Skin tone shift | CIEDE2000 between mean skin colour before/after; and P95 of per-pixel ΔE00 outside healed spots | mean ≤ 2.0 (≤ 1.0 Natural); P95 ≤ 6 |
| Lightness neutrality | Δ mean skin L\* by tone class | within ±1.0; never > +0.3 for brown/dark |
| Edge halo | rings of width 0.03 IOD inside and outside each mask boundary (jaw, hairline, nostril, lips, brows): (a) mean |after − before| in the *outside* ring; (b) signed mean difference between the inner ring and deeper skin, after minus before | (a) ≤ 0.3 L\*; (b) |·| ≤ 1.0 L\* |
| Protected-region integrity | SSIM and gradient-energy ratio before/after inside brows, lashes, lips, hair, beard map, glasses | SSIM ≥ 0.98; gradient energy ≥ 0.95 |
| Form preservation | correlation of Base band L before/after; face contrast (P95−P5 of Base L) ratio | corr ≥ 0.995; ratio 0.92–1.02 |
| Under-eye | residual ΔL to cheek; chroma difference to cheek (must not *increase*); crease contrast ratio | lift ≤ 70 %; Δchroma ↓; crease ≥ 0.4 |
| Teeth / sclera | L vs sclera cap; b ≥ 0; sclera corner change | caps hold 100 % |
| Blemish precision/recall | on hand-labelled faces: healed ∩ labelled temporary; **moles/freckles removed** | precision ≥ 0.9; recall ≥ 0.7 (z ≥ 3); moles removed = 0 |
| Heal quality | per heal: ring-vs-inside colour difference, TR0 inside the heal | ≤ 0.8 ΔE00; TR0 ≥ 0.8 |
| Geometry | landmark displacement before/after | 0 px |
| Idempotence / stability | Auto twice = Auto once; small crops/resizes give the same per-face values | value drift ≤ 3 slider points |
| Preference | blind A/B vs Evoto/Retouch4me outputs on the same files (user supplies), "which looks retouched but real?" | majority |

### 5.3 Test-set composition (failure cases to include)

Auto Enhance: backlit portrait; window light with deep shadow side; mixed skin tones in one frame; very light skin with white dress in sun; dark skin with white shirt; dark skin on dark background; golden hour; blue hour; tungsten interior; mixed tungsten + window; stage/DJ coloured light; candlelight; snow/high-key studio; low-key studio; silhouette; night street; fog; forest-green and sea-blue dominant scenes; overcast landscape; high-DR sunset; flash at reception (near-far falloff); already-edited JPEG; phone HEIC; B&W; burst sequences (consistency); under/over by ±2 EV brackets of the same scene (the auto result should converge).

Auto Retouch: clear skin (expect ≈ no change); heavy acne; freckled face; face with several moles; scars; vitiligo; full beard; stubble; shaved head (large skin area, hairline ambiguity); bangs over forehead; glasses with glare and frame shadows; heavy make-up; no make-up; elderly; baby; teenage; all six ITA classes; oily forehead with clipped speculars; deep under-eye circles; smiling with teeth vs closed mouth; profile and three-quarter views; hand touching face; veil/hair across face; group of 20 (small faces); 8-bit JPEG with compression blocks; high ISO noise (noise is not texture: TR must be measured on a denoised reference too); harsh sun with hard nose shadow; tattoos on face/neck; piercings; tears/sweat; masks/occlusion.

### 5.4 Data sources and licences

Nothing here has been downloaded. **Anything marked "needs approval" must be approved by the user before download** (disk space on this Mac is tight, and several licences are restrictive). Record whatever is used in `docs/LICENSES.md`.

| Source | Use | Licence as found | Commercial-product testing OK? | Needs approval |
|---|---|---|---|---|
| Own captures: ~50–100 frames with grey card / ColorChecker, models of varied skin tone, signed releases | exposure, WB, skin ground truth; retouch test faces | ours | yes; **best option** | time, not download |
| `docs/samples/` already in the repo | regression | check per file | — | no |
| raw.pixls.us | real RAWs across cameras | "most" files CC0; some differ, check each `[S:rpu]` | yes for CC0 files | yes (size) |
| Signature Edits free RAWs | wedding/portrait RAWs | free for personal and commercial use; no claiming authorship; no competing site `[S:sigedits]` (read the current terms before use) | likely yes for internal testing | yes |
| Wikimedia Commons portraits (CC0 / PD / CC BY) | varied faces, JPEG | per file; CC0 has no restrictions; CC BY needs attribution | yes per file; mind personality rights for any publication | yes |
| Pexels | portraits, JPEG | Pexels licence: free commercial use, no resale of unaltered copies `[S:pexels]`; ML/testing terms not verified `[U]` | probably for private tests; do not redistribute | yes |
| Unsplash | portraits, JPEG | standard licence allows use, but compiling images into a competing service is barred and the dataset/ML terms are non-commercial `[S:unsplash]` | avoid for anything beyond ad-hoc manual checks | yes |
| MIT-Adobe FiveK (5,000 DNG + 5 expert renditions) | expert-agreement metric for Auto Enhance | "for research" under two licence files `[S:fivek]` | **unclear for a commercial product**; internal benchmarking only after reading the licence text; never train or ship | yes (~50 GB, licence) |
| PPR10K (11,161 raw portraits, 3 expert targets, masks) | portrait-specific expert agreement, group consistency | code Apache-2.0; **data non-commercial research only**; 406 GB `[S:ppr10k]` | **no** without a legal decision | yes; recommend not |
| FFHQ (70k faces) | varied faces | per-image CC BY / BY-NC / PD / CC0 / US-Gov; dataset packaging CC BY-NC-SA `[S:ffhq]` | only the CC0 / PD / US-Gov / CC BY subset via the per-image metadata; not the package as a whole | yes |
| FFHQR (retouched FFHQ) | paired retouch reference | CC BY-NC-SA (07 §3.14) | no | — |
| CelebAMask-HQ | parsing masks | non-commercial research only `[S:celebamask]` | no | — |
| EasyPortrait | parsing masks | reported as CC BY-NC-ND 4.0 in the search result I saw `[U]`; verify against the repo | verify | yes |
| ACNE04 | blemish detector precision/recall | reported CC BY 4.0 on a mirror `[U]`; verify at source | if confirmed | yes |
| SCIN (Google) | diverse skin conditions | open access for research/education; exact licence text not read `[U]` | verify | yes |
| INTEL-TAU (7,022 images, faces masked) | global AWB angular error | paper CC BY 4.0; dataset terms not confirmed `[S:tau]` `[U]` | verify; no skin (faces masked) | yes |
| Gehler-Shi ColorChecker (568), NUS-8 (1,736), Cube+ (1,707) | AWB angular error | research datasets; licence terms not found `[U]` | verify | yes |

Recommendation: build the core test set from **own captures + CC0 RAWs**, with hand labels (grey-card values, skin patches, blemish/mole/freckle labels on ~60 faces). Use research datasets only for private benchmarking and only after the user accepts the licence reading.

---

## 6. Sources

### 6.1 Develop, auto-tone, exposure, white balance

| Key | Source | Contribution |
|---|---|---|
| `dt-filmic` | https://docs.darktable.org/usermanual/development/en/module-reference/processing-modules/filmic-rgb/ | Middle grey fixed at 18 %; set midtones in exposure first and ignore highlights; auto-tuner fails on portraits/indoor; workflow order |
| `dt-sigmoid` | https://docs.darktable.org/usermanual/development/en/module-reference/processing-modules/sigmoid/ | Contrast pivots on unchanged middle grey; more contrast = less range; adjust midtones first |
| `dt-exp` | https://docs.darktable.org/usermanual/development/en/module-reference/processing-modules/exposure/ | Percentile-based automatic exposure; spot mapping default target 50 % lightness |
| `dt-cc` | https://docs.darktable.org/usermanual/development/en/module-reference/processing-modules/color-calibration/ | Gray-world limits; daylight / black-body / "invalid" illuminant validity; mapping a target colour (e.g. skin) across a series |
| `dt-hl` | https://docs.darktable.org/usermanual/development/en/module-reference/processing-modules/highlight-reconstruction/ | Reconstruction methods; "inpaint opposed" default; reconstruction ≠ highlight slider |
| `rt-exp` | https://rawpedia.rawtherapee.com/Exposure (via search summary; page fetch failed) | Auto Levels drives exposure/black/contrast from a Clip % (0–0.99); thumbnails use 0.2 % |
| `rt-itcwb` | https://rawpedia.pixls.us/white_balance/ and https://discuss.pixls.us/t/new-algorithm-for-white-balance-auto/8340 | Temperature-correlation auto WB; valid ranges; unreliable for low-CRI light |
| `c1` | https://support.captureone.com/hc/en-us/articles/360002609238 | Auto Adjust scope (WB, exposure, HDR, levels); auto-levels clip threshold 0.10 % |
| `dxo` | https://forum.dxo.com/t/any-tips-on-using-the-spot-weighted-tool/3705 (and DxO docs quoted in search) | Smart Lighting spot-weighted: face-priority exposure without wrecking the rest; uniform fallback |
| `lr-auto` | https://blog.adobe.com/en/publish/2017/12/12/announcing-december-update-lightroom | Auto = neural net trained on pro edits; sets exposure, contrast, highlights, shadows, whites, blacks, vibrance, saturation |
| `lr-auto-bright` | https://www.dpreview.com/forums/thread/3588829 ; https://community.adobe.com/t5/lightroom-ecosystem-cloud-based-discussions/auto-tone-results-in-overexposed-photos/m-p/11595586 ; https://community.adobe.com/questions-675/auto-button-adds-too-much-saturation-962122 | User complaints: too bright, night scenes over-brightened, too much saturation |
| `lr-batch` | https://community.adobe.com/bug-reports-674/p-auto-tone-of-a-batch-of-photos-gives-different-results-than-if-you-do-them-one-at-a-time-663629 | Users expect batch = single and consistent series |
| `jkost` | https://jkost.com/blog/?p=21196 ; https://www.adobe.com/ca/learn/lightroom-cc/web/make-colors-pop | Vibrance is relative, protects saturated colours and skin hues; use before saturation |
| `acr-sharp` | https://helpx.adobe.com/camera-raw/using/sharpening-noise-reduction-camera-raw.html | Default capture sharpening and colour NR on raws; masking control |
| `adobe-texture` | https://blog.adobe.com/en/publish/2019/05/14/from-the-acr-team-introducing-the-texture-control | Texture = mid frequencies; born as skin smoothing; negative values keep pores and lashes; clarity is broader/stronger |
| `sog` | https://ueaeprints.uea.ac.uk/23682 | Shades of Grey: gray-world and max-RGB as Minkowski norms; p = 6 best overall |
| `ge` | https://lear.inrialpes.fr/people/vandeweijer/papers/cr2542.pdf | Grey-Edge hypothesis |
| `bianco` | https://mlanthology.org/cvpr/2012/bianco2012cvpr-color ; https://mlanthology.org/eccv/2012/bianco2012eccv-face | Skin colour of detected faces as an illuminant cue (abstracts only; no error figures read) |
| `ely` | https://library.imaging.org/ei/articles/31/4/art00004 | Face-priority AE should adapt target-brightness bounds to predicted skin tone (abstract only; no numbers) |
| `imatest` | https://www.imatest.com/equity | Cameras under-expose darker skin; larger and more variable errors on darker tones; ΔE2000 / L\* error methodology |
| `ita` | https://arxiv.org/pdf/2308.09640 ; https://arxiv.org/pdf/2202.02832 | ITA formula and class thresholds; no consensus on binning or Fitzpatrick mapping |
| `zone` | https://thelenslounge.com/zone-system-photography-exposure/ ; https://www.thephotoforum.com/threads/zone-system-for-portraits.277422/ | Light skin on Zone VI (+1 stop); darker skin lower; meter the lit cheek |
| `fc` | https://www.4kshooters.net/2021/05/20/how-to-expose-perfectly-every-time-using-false-color ; https://4kshooters.net/2022/12/11/how-to-get-optimal-exposure-for-dark-skin-tones-using-false-color | False-colour skin bands: 50–70 IRE; light 61–70; dark skin across green–pink |
| `lr-rgb` | https://digital-photography-school.com/skin-tones-using-lightrooms-color-curves/ ; https://retouch4.me/blog/en/how-to-correct-skin-tone-lightroom-photoshop-retouch4me | R > G > B for all skin; 80/70/60 example; ≥ 94 % = overexposed |
| `cmyk-smug` | https://www.smugmughelp.com/hc/en-us/articles/18212554759700-Correct-skin-tones-for-print ; https://photoshopgurus.com/forum/threads/skin-tones-by-the-numbers-a-la-margulis-and-varis.27550 | CMY skin ratios by the numbers (Margulis/Varis tradition, as relayed) |
| `cmyk-web` | https://www.startmotionmedia.com/skin-tone-that-travels-a-ratio-first-method-for-real-faces ; https://weekend.sunstar.com.ph/blog/2014/06/13/skin-tone/ | Additional ratio statements (lower authority) |
| `tuts-skin` | https://photography.tutsplus.com/tutorials/balancing-skin-tone-and-creating-skin-tone-references--cms-22231 | Where and how to sample skin (11×11 average; forehead/chin/neck; avoid highlights and cheeks) |
| `kdenlive` | https://docs.kdenlive.org/en/tips_and_tricks/scopes/vectorscope_i_and_q_lines.html | I-line = skin tone line; all skin on it, varying only in saturation/brightness |
| `golden` | https://scottwyden.com/golden-hour-photography-tips-for-better-light/ ; https://thesocialcat.com/blog/how-to-edit-your-photos-to-enhance-golden-hour-glow | AWB strips golden-hour warmth; keep warmth, fix orange skin with HSL |
| `wed-order` | https://shootdotedit.com/2020/11/top-15-lightroom-tips-for-wedding-photographers/ ; https://expertphotography.com/wedding-photo-editing-lightroom | WB then exposure then highlights/whites then blacks/shadows; typical highlight and shadow ranges; orange/red luminance for skin |
| `dress` | https://neilvn.com/tangents/exposure-metering-bride-and-brides-dress/ ; https://www.speedlighter.ca/2011/09/07/of-blinkies-histograms-and-the-dress/ | White dress: white with detail, right at the edge of clipping |
| `clahe` | https://www.wikipedia.org/wiki/CLAHE | CLAHE noise amplification, clip limit, tile interpolation |
| `gf` | https://people.csail.mit.edu/kaiming/publications/pami12guidedfilter.pdf | Guided filter; ε as edge threshold; gradient-reversal in bilateral filtering; halos near strong edges remain possible |
| `ai-cmp` | https://fixthephoto.com/aftershoot-vs-imagen.html | Personal-profile AI editors need ≈ 2,500–3,000 edited images; residual manual skin-tone fixes |

### 6.2 Retouching practice and product behaviour

| Key | Source | Contribution |
|---|---|---|
| `fs-guide` | https://fstoppers.com/post-production/ultimate-guide-frequency-separation-technique-8699 | What lives in high vs low frequency; choose radius by eye until volumes appear; 2–3 rounds; per-region radii; hard tools on texture, soft on tone |
| `fs-mistakes` | https://fstoppers.com/photoshop/common-frequency-separation-mistakes-which-will-ruin-your-retouching-results-30913 | 1–2 % flow; small brushes at contours; do not blur/paint the low layer; mid frequencies matter; colour layer between |
| `fs-radius` | https://www.slrlounge.com/frequency-separation-photoshop/ (via search summary) | Split radius ≈ 1.5 % of face width; judge visually; several conservative passes |
| `pixls-wavelet` | https://pixls.us/articles/skin-retouching-with-wavelet-decompose/ | Smooth only the coarsest detail scales; leave fine scales; "never do more than good makeup can achieve" |
| `phlearn-wf` | https://phlearn.com/tutorial/advanced-portrait-retouching-photoshop/ (and course outline in search) | Workflow order: raw → even exposure → blemishes → frequency separation → dodge & burn → sharpen |
| `two-week` | https://www.diyphotography.net/?p=119945 ; https://traceyjophoto.format.com/blog/in-favour-of-natural-retouching | Two-week rule; temporary vs permanent features |
| `kelby` | https://insider.kelbyone.com/top-three-signs-of-over-retouching-and-how-to-protect-yourself-by-kristina-sherk/ | Three tells: over-bright eye whites (corners), over-white teeth, no pores; fix by colour shift, inner ring only |
| `dps-5` | https://digital-photography-school.com/five-common-portrait-retouching-mistakes-avoid/ | Too much smoothing; enlarged eyes; over-bright/sharp eyes; clarity on faces; over-sharpening |
| `phlearn-eye` | https://phlearn.com/tutorial/dark-circles-eyes/ | Under-eye: reduce layer to ≈ 61 % to bring texture back; add colour at ≈ 30 % |
| `tutkit` | https://tutkit.com/en/text-tutorials/1607-removing-dark-circles-with-photoshop | Lighten-mode clone at 15–20 %, layer ≈ 70 % |
| `ue-color` | https://www.livetinted.com/blogs/learn/makeup-to-cover-dark-circles-a-to-z-guide | Make-up analogue: lightening without colour correction goes grey/ashy, especially on deeper skin |
| `teeth` | https://proedu.com/blogs/photoshop-skills/6-retouching-mistakes-to-avoid-for-flawless-images-enhance-your-photos-like-a-pro | Teeth must match scene lighting; natural variation |
| `lr-brush` | https://digital-photography-school.com/?p=110793 ; https://lightroomkillertips.com/presets-more-retouching-presets/ | Lightroom local presets (Iris Enhance values; soften-skin = negative clarity + sharpness) |
| `evoto-pf` | https://photofocus.com/software/is-evoto-worth-it-for-editing-and-retouching-photos-of-people/ (via search summary; fetch failed) | Presets too heavy, plasticky and flat until reduced |
| `evoto-dcw` | https://www.digitalcameraworld.com/tech/software/evoto-ai-review | Praise: speed, slider-level frequency separation, flyaways; complaints: credits, watermark, trust |
| `r4m` | https://digital-photography-school.com/retouch4me-review/ ; https://shotkit.com/retouch4me-review/ ; https://www.frontproofmedia.com/reviews/retouch4me-photoshop-plug-in-suite | One-task plugins; heal without losing texture; dodge & burn instead of blur; sometimes heavy-handed or misses |
| `ppro` | https://digital-photography-school.com/image-editing-software-review-portraitpro-15/ ; https://www.talkphotography.co.uk/threads/portrait-professional-software.255787/ | Default smoothing too high; plastic look unless sliders are pulled back |

### 6.3 Datasets and licences

| Key | Source | Contribution |
|---|---|---|
| `ppr10k` | https://github.com/csjliang/PPR10K | Size, expert targets, masks, metrics; data non-commercial research only |
| `fivek` | https://data.csail.mit.edu/graphics/fivek/ | Contents; research-use licences |
| `ffhq` | https://github.com/NVlabs/ffhq-dataset | Per-image licences; dataset CC BY-NC-SA |
| `celebamask` | https://github.com/lorcll/CelebAMask-HQ | Non-commercial research only |
| `rpu` | https://pixls.us/blog/2017/01/new-year-new-raw-samples-website ; https://discuss.pixls.us/t/can-i-use-some-raw-files-from-raw-pixls-us-to-make-a-web-app-demo-video/44619 | CC0 preferred; most but not all files CC0 |
| `sigedits` | https://www.diyphotography.net/?p=146082 | Free RAWs, commercial use allowed, authorship/competing-site limits |
| `pexels` | https://help.pexels.com/hc/en-us/articles/360042295174-What-is-the-license-of-the-photos-and-videos-on-Pexels | Pexels licence |
| `unsplash` | https://help.unsplash.com/en/articles/2612332-what-do-you-mean-by-compiling-photos-to-replicate-a-similar-or-competing-service | Compilation restriction; dataset ML terms non-commercial |
| `tau` | https://arxiv.org/pdf/1910.10404 | INTEL-TAU description; faces masked |

### 6.4 Where sources disagree, and what is my own synthesis

1. **Skin hue target.** Vectorscope skin line (≈ 123° `[U]`) vs the Lightroom 80/70/60 rule (≈ 138° by my computation). Resolved with a window, not a point (§1.3).
2. **Exposure of dark skin.** False-colour practice allows the same band as light skin; zone practice puts it about a stop lower; Real-Tone-era guidance says "not under-exposed, not ashy" without numbers. The §1.2 table is my interpolation.
3. **CMY ratios.** "C = 30–50 % of M" vs "C = 1/5–1/3 of M"; and these are print (CMYK separation) numbers that I apply as naive RGB complements. Wide tolerances; treat as sanity checks, never as targets.
4. **Frequency separation vs dodge & burn.** High-end retouchers often avoid FS entirely; commercial workflows rely on it. The spec uses band processing for speed but imposes D&B-like constraints (amplitude selectivity, fine band untouched, base untouched).
5. **ACR default sharpening.** Help page states 25; current versions are reported as 40 `[U]`. Irrelevant to the design, noted for accuracy.
6. **Shadow lifting.** Wedding tutorials show up to +90; users also complain about flat HDR-looking auto results. Auto is capped at +45/+60.
7. **Unverified but used:** inverted-high-pass 3:1 radius rule; 3° "just noticeable" angular error; 63 mm mean IPD; Lightroom Teeth Whitening preset values; several dataset licences (marked `[U]` in §5.4). None of them is load-bearing: each only motivates a default that the harness will tune.
8. **Entirely my synthesis `[H]`:** every formula constant in §2 and §4 not carrying an `[S]` tag, including the tone-index reflectance mapping (0.22/0.75), band radii in IOD, amplitude thresholds τ, need-metric constants, grade caps, all pass gates in §5. They are engineering starting points consistent with the sourced principles, and must be calibrated on the §5.3 test set before being treated as final.
9. **Could not be read:** RawPedia Exposure page, Photofocus Evoto review, PetaPixel Retouch4me review (fetch errors; search-result summaries used instead), and the full texts of the Bianco–Schettini and El-Yamany papers (abstracts only).
