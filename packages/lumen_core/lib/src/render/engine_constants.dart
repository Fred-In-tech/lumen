/// Every hand-tuned [H] constant of render engine `lumen-1`.
///
/// `app/shaders/*.frag` hard-codes the same numbers (search for the constant
/// name in the shader comments). The CPU reference pipeline reads them from
/// here, and the GPU-vs-CPU parity tests (PLAN.md §6.3) catch any drift.
/// Changing any value after release requires a new [kEngineVersion].
library;

/// Rendering "process version" pinned into every edit document.
const String kEngineVersion = 'lumen-1';

// ---- Layout -----------------------------------------------------------------

/// Number of floats in `develop.frag` uniforms (PLAN.md §1.6 table + mask
/// grid vec4 + 8 masks × 3 vec4).
const int kDevelopFloatCount = 194;

/// Number of floats in `finish.frag` uniforms.
const int kFinishFloatCount = 18;

/// Number of floats in `denoise.frag` uniforms.
const int kDenoiseFloatCount = 6;

/// Entries per tone-LUT row and number of rows (composite, R, G, B).
const int kToneLutSize = 1024;
const int kToneLutRows = 4;

/// Long edge of the analysis (aux) maps, in pixels.
const int kAnalysisLongEdge = 512;

/// Long edge of the mask coverage grid, in pixels (source-uv space).
const int kMaskLongEdge = 1024;

/// Masks rendered per develop pass (2 atlases × 4 masks).
const int kMaxRenderedMasks = 8;

// ---- Log-luma packing ---------------------------------------------------------

/// Normalized log luma: `n = (log2(Y) + kLogLumaOffset) / kLogLumaRange`.
const double kLogLumaOffset = 14;
const double kLogLumaRange = 16;

/// Luminance floor before the log (2^-14).
const double kLumaFloor = 1 / 16384;

// ---- White balance (research 01 §6.2 reference model) ------------------------

/// ±100 temp = ±1 stop of the R/B ratio.
const double kWbKappaT = 1.0;

/// +100 tint = −0.5 stop of green (magenta).
const double kWbKappaG = 0.5;

// ---- Dehaze -------------------------------------------------------------------

const double kDehazeOmega = 0.95;
const double kDehazeTMin = 0.1;

/// Strength of the veil added by negative dehaze.
const double kDehazeNegMix = 0.4;

// ---- Shadows / highlights -----------------------------------------------------

/// Maximum gain in stops at ±100.
const double kShStops = 1.5;

/// `smoothstep(kShShadowEdge0, kShShadowEdge1, Bn)` weights shadows.
const double kShShadowEdge0 = 0.55;
const double kShShadowEdge1 = 0.0;

/// `smoothstep(kShHighlightEdge0, kShHighlightEdge1, Bn)` weights highlights.
const double kShHighlightEdge0 = 0.45;
const double kShHighlightEdge1 = 1.0;

// ---- Clarity / texture --------------------------------------------------------

const double kClarityGain = 0.8;
const double kTextureGain = 0.6;

/// Local-contrast gains are clamped to ±this many stops.
const double kLocalMaxStops = 2.0;

// ---- Tone -------------------------------------------------------------------

/// Contrast pivot in the sRGB-encoded domain (≈ 18 % gray).
const double kContrastPivot = 0.46;

/// Slope at the pivot is `2^(contrast/100 * kContrastSlopeStops)`.
const double kContrastSlopeStops = 1.0;

/// Whites/blacks move their end points by up to this much (encoded) at ±100.
const double kLevelsRange = 0.25;

/// Parametric-curve zone amplitude (encoded) at ±100.
const double kParametricAmplitude = 0.12;

/// Width of the end-point taper of the parametric curve.
const double kParametricTaper = 0.08;

// ---- HSL mixer (OkLCh) ------------------------------------------------------

/// Band centers in OkLCh hue degrees: red, orange, yellow, green, aqua,
/// blue, purple, magenta.
const List<double> kHslBandCenters = [25, 55, 100, 140, 195, 255, 295, 335];

/// Hue shift in degrees at ±100.
const double kHslHueDegrees = 30;

/// Relative OkLab L change at ±100 luminance.
const double kHslLumScale = 0.3;

/// Chroma below which the mixer fades out (protects neutrals).
const double kHslChromaKnee = 0.06;

// ---- Vibrance / saturation ----------------------------------------------------

/// Vibrance fades out as OkLab chroma approaches this value.
const double kVibranceChromaKnee = 0.25;

/// Skin hue plateau (OkLCh degrees) and ramp width.
const double kSkinHueLo = 20;
const double kSkinHueHi = 75;
const double kSkinHueRamp = 10;

/// Fraction of the vibrance boost removed on skin.
const double kSkinProtect = 0.6;

// ---- Color grading ----------------------------------------------------------

/// OkLab chroma of a wheel at saturation 100.
const double kGradeMaxChroma = 0.08;

/// Relative OkLab L change at ±100 wheel luminance.
const double kGradeLumScale = 0.25;

const double kGradeBalanceShift = 0.3;
const double kGradeWidthMin = 0.12;
const double kGradeWidthMax = 0.45;

// ---- B&W mixer ----------------------------------------------------------------

/// Relative OkLab L change at ±100 band mix.
const double kBwMixScale = 0.5;

/// Chroma at which the B&W mix reaches full effect.
const double kBwChromaKnee = 0.08;

// ---- Vignette -----------------------------------------------------------------

const double kVignetteMidMin = 0.35;
const double kVignetteMidMax = 1.25;
const double kVignetteFeatherScale = 0.8;

// ---- Finish -----------------------------------------------------------------

const double kSharpenLimitMin = 0.02;
const double kSharpenLimitMax = 0.25;
const double kGrainStrength = 0.4;
