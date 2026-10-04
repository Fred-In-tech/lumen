/// Effect constants of the retouch pass (research 07 §3.1–3.8). These are
/// compiled into `retouch.frag` as literals; keep both sides in sync.
/// L/a/b values are OkLab of linear sRGB. 🔶 Tune on a licensed set.
library;

/// `keep = smoothstep(thr, kKeepRamp·thr, |mid.L|)` (§3.1).
const double kKeepRamp = 2.5;

/// Wrinkles (§3.4): the pass removes `wEff·ΔW`, where
/// `wEff = kWrinkleMax · clamp(zoneSlider + kWrinkleSmooth · s)` and `s`
/// is Smooth × skin. Deep folds have real shading, so removal stops at
/// 85 %; smoothing alone softens detected lines by up to 42 %.
const double kWrinkleMax = 0.85;
const double kWrinkleSmooth = 0.5;

/// Dark circles: lift toward the skin reference, pull chroma to it (§3.5).
const double kDarkCircleLift = 0.8;
const double kDarkCircleChroma = 0.6;

/// Eye bags: flatten the remaining mid band and the base L relief.
const double kBagMid = 0.7;
const double kBagBase = 0.4;

/// Shine (§3.8): brighter than the reference by [kShineRelLo]..[kShineRelHi],
/// chroma ratio below [kShineDesatLo]..[kShineDesatHi]; pull L and restore
/// chroma.
const double kShineRelLo = 0.03;
const double kShineRelHi = 0.10;
const double kShineDesatLo = 0.6;
const double kShineDesatHi = 0.95;
const double kShinePull = 0.7;
const double kShineChroma = 0.5;

/// Teeth (§3.6): bright (L) and not red (a*); desaturate b* / a*, lift L.
const double kTeethLLo = 0.55;
const double kTeethLHi = 0.72;
const double kTeethRedLo = 0.035;
const double kTeethRedHi = 0.08;
const double kTeethYellowCut = 0.85;
const double kTeethRedCut = 0.40;
const double kTeethLift = 0.10;

/// Eye whites (§3.7): L gate excludes lashes and lid shadow.
const double kScleraLLo = 0.45;
const double kScleraLHi = 0.62;
const double kScleraRedCut = 0.7;
const double kScleraYellowCut = 0.4;
const double kScleraLift = 0.05;

/// Red veins: fine-scale a* excess over B2 inside the sclera.
const double kVeinLLo = 0.35;
const double kVeinLHi = 0.5;
const double kVeinCut = 0.9;
const double kVeinLiftLo = 0.004;
const double kVeinLiftHi = 0.02;

/// Iris (§3.7): catchlight guard, local contrast, chroma, lift.
const double kIrisCatchLo = 0.85;
const double kIrisCatchHi = 0.95;
const double kIrisContrast = 0.6;
const double kIrisChroma = 0.35;
const double kIrisLift = 0.03;

/// Lips (§3.9): gloss guard ramp clearly above the face's lip P95 L
/// (`1 − smoothstep(gloss + start, gloss + end, L)`), so lip-line texture
/// is recoloured evenly and only real highlights are skipped.
const double kLipGlossStart = 0.02;
const double kLipGlossEnd = 0.08;

/// Blush (§3.9): chroma moves this far toward the target, relative to the
/// local skin reference B3; L darkens slightly.
const double kBlushChroma = 0.35;
const double kBlushDarken = 0.03;
