/// Tuned constants of the local auto-tone engine (research 01 §6.12).
///
/// Values marked "tuned" differ from the research [H] proposals; they were
/// set against the synthetic scenes and the CPU reference renderer so that
/// PLAN.md §9 items 17–24 hold (see the AC tests in `test/auto`).
abstract final class AutoToneConstants {
  // ---- White balance (§6.3) ----
  /// Default strength (tuned: research 0.7). Full neutralization of an
  /// unintended cast keeps Auto idempotent (AC-22).
  static const wbStrength = 1.0;

  /// Strength when the cast looks intentional (sunset, low key).
  static const wbStrengthIntentional = 0.35;

  /// Warm cast above which "intentional" is considered.
  static const intentionalCastA = 0.35;

  /// Casts inside this dead zone are left alone (log2 units; tuned so a
  /// re-run on an auto-edited render leaves temp within ±3, AC-22).
  static const castDeadZoneA = 0.08;
  static const castDeadZoneM = 0.05;

  /// Confidence ramp: no correction below lo, full above hi.
  static const wbConfidenceLo = 0.3;
  static const wbConfidenceHi = 0.7;

  /// Reference model gains (PLAN.md §1.6 step 3).
  static const kappaT = 1.0;
  static const kappaG = 0.5;

  /// Clamps (tuned: research ±40 / ±25 cannot neutralize a 1-stop cast).
  static const tempClamp = 100.0;
  static const tintClamp = 50.0;

  // ---- Exposure (§6.4) ----
  static const keyBase = 0.18;

  /// Fraction of Reinhard's scene adaptivity (tuned: research 1.0).
  static const keyAdaptivity = 0.5;
  static const keyMin = 0.09;
  static const keyMax = 0.36;

  /// Below this key a scene counts as low key.
  static const lowKey = 0.10;

  /// Exposure clamp (tuned: research [−1.5, +2.0]; AC-17 needs ≈ +4 EV).
  static const evMin = -2.0;
  static const evMax = 4.5;

  /// Accepted band of the rendered median luminance (display luma 0.36 to
  /// 0.62). A source median inside it keeps its exposure, and so does a
  /// render that stays inside it (hysteresis: good photos and
  /// already-edited renders stay put, AC-21/22). Scaled by a style's key.
  static const bandLowY = 0.1065;
  static const bandHighY = 0.3424;

  /// Safety band (display luma 0.30 to 0.70): when no correction is
  /// underway, the other sliders may move the median anywhere inside it;
  /// leaving it is corrected to the nearest edge.
  static const safetyLowY = 0.0742;
  static const safetyHighY = 0.4479;

  /// Medians outside the band are corrected to the scene key clamped into
  /// this inner range (display luma 0.44 to 0.54), leaving headroom.
  static const targetLowY = 0.1620;
  static const targetHighY = 0.2532;

  /// Highlight guard: max newly clipped fraction.
  static const clipGuard = 0.005;

  /// Lightroom habit: pre-add highlights −15·EV above +0.7 EV.
  static const preHighlightsFrom = 0.7;
  static const preHighlightsPerEv = -15.0;

  /// Night guard (EXIF only): cap exposure.
  static const nightEvCap = 1.0;

  // ---- Whites / blacks (§6.5) ----
  static const whiteTarget = 0.96;
  static const blackTarget = 0.025;
  static const whitesMin = -40.0;
  static const whitesMax = 50.0;
  static const blacksMin = -40.0;
  static const blacksMax = 20.0;

  // ---- Highlights / shadows (§6.6) ----
  /// Source clip fraction above which highlights are always pulled
  /// (tuned addition: exposure alone hides blown areas, AC-18).
  static const sourceClipRecover = 0.01;
  static const recoverBase = 10.0;
  static const recoverPerClip = 250.0;

  static const highlightsMax = 70.0;
  static const shadowsMax = 60.0;

  // ---- Contrast (§6.7) ----
  static const sigmaTarget = 20.0;
  static const contrastMin = -20.0;
  static const contrastMax = 40.0;

  // ---- Vibrance / saturation (§6.8) ----
  static const chromaTarget = 28.0;
  static const vibranceMin = -25.0;
  static const vibranceMax = 35.0;
  static const saturationMin = -10.0;
  static const saturationMax = 8.0;

  // ---- Dehaze (§6.9) ----
  static const hazeThreshold = 0.12;
  static const dehazeMax = 30.0;

  /// Dehaze only when the source has no true black and is not blown out
  /// (tuned addition: the dark-channel prior also fires on large flat gray
  /// areas and on bright overexposed scenes; see [sourceClipRecover]).
  static const dehazeMinBlackPoint = 0.12;

  /// Global refinement passes (exposure solve + whites/blacks re-check).
  static const refinePasses = 2;
}
