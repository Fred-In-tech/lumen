/// UI slider values (PortraitRegistry, 0–100 or ±100) → internal retouch
/// parameters (research 07 §3.13, adapted to the registry ids).
library;

import 'dart:math' as math;

/// Amplitude-selective threshold on |mid.L| (OkLab): structure above
/// 2.5× this survives smoothing (§3.1). Lowered when smoothing > 0.6.
const double kAmpThreshold = 0.035;
const double kAmpThresholdStrong = 0.025;
const double kStrongSmoothing = 0.6;

/// Fine-band gain at Texture −100 / +100 (0 keeps pores exactly).
const double kTextureGainMin = 0.4;
const double kTextureGainMax = 1.4;

/// Even tone at 100 pulls 80 % of the base chroma to the skin reference.
const double kEvenToneMax = 0.8;

/// Smooth skin: `(v/100)^0.8` (more resolution at the low end).
double mapSmoothing(double v) =>
    math.pow((v / 100).clamp(0.0, 1.0), 0.8).toDouble();

double mapAmpThreshold(double smooth) =>
    smooth > kStrongSmoothing ? kAmpThresholdStrong : kAmpThreshold;

/// Skin texture (bipolar, default 0 = keep the fine band as is).
double mapTextureGain(double v) {
  final t = (v / 100).clamp(-1.0, 1.0);
  return t <= 0 ? 1 + (1 - kTextureGainMin) * t : 1 + (kTextureGainMax - 1) * t;
}

double mapEvenTone(double v) => kEvenToneMax * (v / 100).clamp(0.0, 1.0);

/// Linear 0–100 → 0..1 (under-eye, shine, eyes, teeth, blemish classes,
/// wrinkle zones, lips, blush).
double mapLinear(double v) => (v / 100).clamp(0.0, 1.0);

/// Clipped shine cores are filled from Shine [kShineFillStart] on, fully
/// by [kShineFillStart] + [kShineFillRamp] (§3.8: "above 50 %").
const double kShineFillStart = 0.5;
const double kShineFillRamp = 0.4;

/// Shine (0..1, already mapped) → core fill weight.
double mapShineFill(double shine) =>
    ((shine - kShineFillStart) / kShineFillRamp).clamp(0.0, 1.0);

// Auto Retouch values live in `PortraitPresets` (model/portrait_presets.dart).
