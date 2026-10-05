/// Effect constants of the retouch pass (research 09 §4.9–4.10). These are
/// compiled into `retouch.frag` as literals; keep both sides in sync.
/// L/a/b values are OkLab of linear sRGB. 🔶 Tune on a licensed set.
library;

/// Wrinkles (research 09 §4.10): the pass removes `wEff·ΔW`, where
/// `wEff = kWrinkleMax · clamp(zoneSlider + kWrinkleSmooth · s)` and `s`
/// is Smooth × skin. Lines are softened, never erased: removal stops at
/// 65 %; smoothing alone softens detected lines by up to 20 %.
const double kWrinkleMax = 0.65;
const double kWrinkleSmooth = 0.3;

/// Teeth (§4.9): bright (L) and not red (a*); less yellow and red, a
/// small lift, never above the face's cap (`min(sclera P90, 0.92)`).
const double kTeethLLo = 0.55;
const double kTeethLHi = 0.72;
const double kTeethRedLo = 0.035;
const double kTeethRedHi = 0.08;
const double kTeethYellowCut = 0.60;
const double kTeethRedCut = 0.30;
const double kTeethLift = 0.10;
const double kTeethMaxLift = 0.05;

/// Eye whites (§4.9): L gate excludes lashes and lid shadow; less red
/// and yellow, a tiny lift, never above [kScleraMaxL].
const double kScleraLLo = 0.45;
const double kScleraLHi = 0.62;
const double kScleraRedCut = 0.5;
const double kScleraYellowCut = 0.4;
const double kScleraLift = 0.035;
const double kScleraMaxL = 0.90;

/// Red veins: L gate of the sclera.
const double kVeinLLo = 0.35;
const double kVeinLHi = 0.5;

/// Iris (§4.9): catchlight guard, chroma, lift (the local contrast is a
/// map delta, `face_maps.dart`).
const double kIrisCatchLo = 0.85;
const double kIrisCatchHi = 0.95;
const double kIrisChroma = 0.15;
const double kIrisLift = 0.02;

/// Lips (§3.9): gloss guard ramp clearly above the face's lip P95 L
/// (`1 − smoothstep(gloss + start, gloss + end, L)`), so lip-line texture
/// is recoloured evenly and only real highlights are skipped.
const double kLipGlossStart = 0.02;
const double kLipGlossEnd = 0.08;

/// Blush (§3.9): chroma moves this far toward the target, relative to the
/// face's skin colour (baked into the face info); L darkens slightly.
const double kBlushChroma = 0.35;
const double kBlushDarken = 0.03;

/// Red-eye (face scope): search disc around each iris centre (IOD units,
/// the iris is ≈ 0.093), its soft edge, the redness gate on the source
/// OkLab a* (and a* − b*, so brown irises and skin never qualify), the
/// catchlight guard on L, and how far a red pupil is darkened.
const double kRedEyeRadiusIod = 0.11;
const double kRedEyeEdge = 0.8;
const double kRedEyeALo = 0.05;
const double kRedEyeAHi = 0.10;
const double kRedEyeHueSpan = 0.04;
const double kRedEyeCatchLo = 0.80;
const double kRedEyeCatchHi = 0.92;
const double kRedEyeDarken = 0.5;
