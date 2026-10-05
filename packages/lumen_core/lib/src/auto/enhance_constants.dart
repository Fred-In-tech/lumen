/// Constants of Auto Enhance v2 (research 09 §2). Values tagged "calibrated"
/// differ from the research [H] starting points; they were set against the
/// synthetic scenes in `test/auto` and the real photos listed in
/// docs/PHASE2.md ("Auto Enhance v2").
abstract final class EnhanceConstants {
  // ---- Validity (§2.2) ----
  /// Encoded max-channel at or above which a pixel counts as clipped.
  static const clipEncoded = 0.995;

  /// Linear luminance below which a pixel carries no colour information.
  static const darkY = 0.002;

  // ---- Faces and skin (§2.2, §2.4) ----
  /// Faces narrower than this many solver-proxy pixels are ignored.
  static const minFacePixels = 6.0;

  /// Skin samples a face needs before it is trusted.
  static const minSkinSamples = 12;

  /// Skin ellipse radii as a fraction of the face box.
  static const skinRadiusX = 0.40;
  static const skinRadiusY = 0.46;

  /// Seed ellipse (cheeks and nose) radii as a fraction of the face box.
  static const seedRadiusX = 0.22;
  static const seedRadiusY = 0.26;

  /// Skin luminance gate around the seed median (shadow side … specular).
  static const skinYLow = 0.30;
  static const skinYHigh = 2.4;

  /// Max log2-chromaticity distance from the seed (stops).
  static const skinChromaDistance = 0.45;

  /// Lit diffuse skin = mean of this luminance percentile range.
  static const litLow = 0.40;
  static const litHigh = 0.80;

  /// Relative skin reflectance (lit skin / scene white) of the darkest and
  /// lightest tone class (calibrated: research 0.22 / 0.75 assumed a sclera
  /// reference; scene white is brighter).
  static const rhoDark = 0.11;
  static const rhoLight = 0.50;

  /// Half-width of the tone-index interval around a trusted reference
  /// (doubled downwards when the reference sits at the clip ceiling).
  static const toneSpreadSure = 0.15;

  /// The white reference must be this much brighter than lit skin.
  static const whiteRefMinRatio = 1.25;

  /// Target centre and accept band (L*) at tone index 0 (dark) and 1 (very
  /// light); linear in between (§1.2 table).
  static const centreDark = 42.0;
  static const centreLight = 70.0;
  static const lowDark = 36.0;
  static const lowLight = 66.0;
  static const highDark = 50.0;
  static const highLight = 75.0;

  /// Diffuse skin must stay below this encoded max-channel (§1.2).
  static const skinHotMax = 0.94;

  /// Face modelling guard: skin P95 − P5 (L*) above this is harsh light.
  static const faceContrastMax = 38.0;

  /// Faces weigh in above this total area fraction … fully at the second.
  static const faceAreaLow = 0.003;
  static const faceAreaHigh = 0.04;

  /// Group rule: faces above this normalised weight may not exceed their band.
  static const groupFaceWeight = 0.08;

  /// A style may move the skin centre by at most this many L* (§2.12).
  static const styleSkinShiftMax = 6.0;

  // ---- Exposure (§2.4) ----
  /// Faces outside their band aim this far from the band edge to its centre.
  static const bandAim = 0.3;

  /// Clipped share above which the frame counts as blown: the scene white
  /// is then at least display white.
  static const blownClip = 0.02;

  /// With faces inside their band the histogram may move exposure by at
  /// most this; faces of unknown tone are never brightened past the dark
  /// class's band, nor by more than [unknownToneEvMax].
  static const inBandEvMax = 0.35;
  static const unknownToneEvMax = 0.5;

  /// Damping of the solved exposure (faces drive it / histogram only).
  static const dampFaces = 0.9;
  static const dampGlobal = 0.8;

  /// Per-click limits by scene (§2.11).
  static const evMinPortrait = -1.0;
  static const evMaxPortrait = 2.0;
  static const evMinOther = -1.5;
  static const evMaxOther = 2.5;

  /// With light that is blown as shot, exposure is not pulled below this
  /// (calibrated: the 8-bit analogue of research's non-raw multiplier).
  static const evMinBlown = -0.6;

  /// Night scenes are not pushed past this.
  static const evNightMax = 1.0;

  /// Median-luminance accept band without faces (display luma 0.36–0.62)
  /// and the inner target range (display luma 0.44–0.54).
  static const bandLowY = 0.1065;
  static const bandHighY = 0.3424;
  static const targetLowY = 0.1620;
  static const targetHighY = 0.2532;
  static const keyBase = 0.18;
  static const keyAdaptivity = 0.5;
  static const keyMin = 0.09;
  static const keyMax = 0.36;

  /// Max newly clipped fraction a positive exposure move may cause.
  static const clipGuard = 0.005;

  /// A hot face may cost at most this much of the face exposure.
  static const hotSkinEvBudget = 0.5;

  // ---- Scene flags (§2.3) ----
  static const portraitArea = 0.02;
  static const portraitFaceWidth = 0.12;
  static const smallFacesArea = 0.005;
  static const highKeyP50 = 0.68;
  static const highKeyP5 = 0.30;
  static const highKeyMaxClip = 0.01;

  /// A high-key frame has real whites; a bright frame without them is haze
  /// or fog (calibrated addition).
  static const highKeyWhite = 0.9;

  /// Every move is scaled by this on a file an editor already wrote.
  static const alreadyEditedScale = 0.4;
  static const lowKeyP50 = 0.22;
  static const lowKeyP95 = 0.55;
  static const backlitRatio = 0.5;

  // ---- White balance (§2.5), in stops of log2(R/B) and log2(G/√RB) ----
  static const minkowskiP = 6.0;

  /// Candidates disagreeing by this angle carry no statistical weight.
  static const wbAgreeAngle = 6.0;
  static const wbWeightStat = 1.0;
  static const wbWeightNeutral = 1.5;
  static const wbWeightSkin = 1.2;
  static const wbWeightAsShot = 0.8;
  static const wbAsShotQ = 0.3;
  static const wbSkinQ = 0.6;

  /// Near-neutral objects: CIELAB chroma below this, L* inside the range.
  static const neutralChroma = 7.0;
  static const neutralLMin = 35.0;
  static const neutralLMax = 97.0;

  /// Share of near-neutral pixels at which that candidate is fully trusted.
  static const neutralShareFull = 0.06;

  static const wbStrength = 0.8;
  static const wbStrengthGolden = 0.35;
  static const wbStrengthWarmInterior = 0.5;

  /// Warm cast with nobody in the frame: more is removed, some is kept
  /// (calibrated addition).
  static const wbStrengthWarmNoFaces = 0.65;

  /// A warm cast above this (stops of R/B) with skin still in its window
  /// reads as ambience, not as an error.
  static const warmAmbienceA = 0.12;

  /// Skin window: tint axis M = log2(G/√RB) (calibrated on plausible skin
  /// reflectances and the real portrait; YCbCr hue 115°–140° maps onto it).
  static const skinMLow = -0.30;
  static const skinMHigh = 0.06;

  /// Skin window: temperature axis A = log2(R/B). Wide on purpose: rendered
  /// skin spans roughly 0.9 (very light, neutral light) to 3.0 (deep skin in
  /// warm light).
  static const skinALow = 0.75;
  static const skinAHigh = 3.1;

  /// BT.601 skin hue window in degrees (§1.3).
  static const skinHueLow = 115.0;
  static const skinHueHigh = 140.0;

  /// Corrections smaller than this are dropped (slider units): with skin in
  /// its window (≈ 2.5° angular, §2.5 rule 3) / otherwise.
  static const wbDeadTempSkinOk = 12.0;
  static const wbDeadTintSkinOk = 8.0;
  static const wbDeadTemp = 5.0;
  static const wbDeadTint = 4.0;

  /// Relative limits with faces whose skin is in its window (§2.5: ±30 /
  /// ±15 on 8-bit renditions). Warming may go further than cooling: a cool
  /// cast is rarely the mood, a warm one often is.
  static const tempMax = 30.0;
  static const tempMaxWarming = 45.0;
  static const tintMax = 15.0;

  /// Limits without faces, or with skin clearly outside its window.
  static const tempMaxWide = 60.0;
  static const tintMaxWide = 45.0;

  // ---- Highlights / shadows (§2.6) ----
  static const highlightsCapPortrait = 60.0;
  static const highlightsCap = 70.0;
  static const shadowsCapPortrait = 45.0;
  static const shadowsCap = 60.0;
  static const lowKeyShadows = 0.4;
  static const whiteHotStart = 0.95;

  /// Share of near-clip pixels that is normal, and the pull per share above.
  static const nearClipFree = 0.03;
  static const nearClipGain = 120.0;
  static const skinHotStart = 0.90;

  // ---- Whites / blacks (§2.7) ----
  static const whiteTarget = 0.97;

  /// A frame whose brightest tones already reach this has its white; one
  /// below it is stretched to [whiteStretchTo] (§1.4 fabric range).
  static const whiteEnough = 0.93;
  static const whiteStretchTo = 0.95;
  static const blackTarget = 0.02;
  static const blackTargetAiry = 0.05;
  static const whitesMin = -40.0;
  static const whitesMaxPortrait = 25.0;
  static const whitesMax = 40.0;
  static const blacksMinPortrait = -30.0;
  static const blacksMin = -35.0;
  static const blacksMaxPortrait = 10.0;
  static const blacksMax = 15.0;
  static const blacksMinAiry = -10.0;

  /// No positive whites when highlights were pulled below this.
  static const whitesSkipHighlights = -40.0;

  // ---- Contrast (§2.8) ----
  static const sigmaPortrait = 17.0;
  static const sigmaGroup = 18.0;
  static const sigmaLandscape = 21.0;
  static const sigmaKeyed = 15.0;
  static const contrastMin = -10.0;
  static const contrastMaxPortrait = 15.0;
  static const contrastMaxGroup = 20.0;
  static const contrastMax = 25.0;

  /// Without faces a scene is "harsh" when σ(L*) exceeds the target by this
  /// factor and both ends are clipped.
  static const harshSigmaFactor = 1.3;
  static const harshEndFraction = 0.01;

  // ---- Vibrance / saturation (§2.9) ----
  static const chromaTarget = 28.0;
  static const vibranceMin = -15.0;
  static const vibranceMaxPortrait = 12.0;
  static const vibranceMaxGroup = 15.0;
  static const vibranceMax = 30.0;
  static const saturationMin = -5.0;

  /// With this share of already vivid pixels (C* > 45) vibrance stays low
  /// (calibrated on the real cargo-van photo: orange bags in a grey van).
  static const vividShareGuard = 0.03;
  static const vividVibranceMax = 10.0;

  /// Skin chroma (CIELAB C*) above which colour is not boosted further.
  static const skinChromaMaxLight = 34.0;
  static const skinChromaMaxDeep = 30.0;

  /// Skin by colour (no face data): share above which portrait caps apply.
  static const skinShareGuard = 0.12;

  // ---- Dehaze (01 §6.9; scenes without faces only) ----
  static const hazeThreshold = 0.12;
  static const dehazeMax = 30.0;
  static const dehazeMinBlackPoint = 0.12;

  // ---- Guardrails (§2.11) ----
  static const confFaces = 1.0;
  static const confHistogram = 0.85;
  static const confDisagree = 0.6;
  static const disagreeEv = 1.2;

  /// Exposure is damped, not confidence-scaled (calibrated: research
  /// scales it by the full confidence with a 0.4 floor, which left clearly
  /// dark frames dark). Only a face/histogram disagreement lowers it, and
  /// never below this when a face is over a stop outside its band.
  static const confFloorWrongFace = 0.9;

  /// Deltas below these are zeroed so the result is a clean edit.
  static const zeroEv = 0.07;
  static const zeroOther = 3.0;

  /// "Looks good" thresholds: nothing is changed when every delta is below.
  static const nothingEv = 0.15;
  static const nothingRecovery = 8.0;
  static const nothingLevels = 5.0;
  static const nothingContrast = 4.0;
  static const nothingVibrance = 4.0;
}
