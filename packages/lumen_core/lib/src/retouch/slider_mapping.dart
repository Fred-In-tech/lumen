/// UI slider values (PortraitRegistry, 0–100 or ±100) → internal retouch
/// parameters (research 07 §3.13, adapted to the registry ids).
library;

import 'dart:math' as math;

/// Fine-band gain at Texture −100 / +100 (0 keeps pores exactly). The
/// range is narrow on purpose: no slider may flatten pores.
const double kTextureGainMin = 0.85;
const double kTextureGainMax = 1.15;

/// Smooth skin: `(v/100)^1.2`, gentle at the low end; 100 is the hard
/// limit of the band reductions (`skin_deltas.dart`).
double mapSmoothing(double v) =>
    math.pow((v / 100).clamp(0.0, 1.0), 1.2).toDouble();

/// Skin texture (bipolar, default 0 = keep the fine band as is).
double mapTextureGain(double v) {
  final t = (v / 100).clamp(-1.0, 1.0);
  return t <= 0 ? 1 + (1 - kTextureGainMin) * t : 1 + (kTextureGainMax - 1) * t;
}

/// Even tone: linear; 100 removes the shares of `skin_deltas.dart`.
double mapEvenTone(double v) => (v / 100).clamp(0.0, 1.0);

/// Linear 0–100 → 0..1 (under-eye, shine, eyes, teeth, blemish classes,
/// wrinkle zones, lips, blush).
double mapLinear(double v) => (v / 100).clamp(0.0, 1.0);

/// Clipped shine cores (no data left) are filled from Shine
/// [kShineFillStart] on, fully by [kShineFillStart] + [kShineFillRamp].
const double kShineFillStart = 0.2;
const double kShineFillRamp = 0.4;

/// Shine (0..1, already mapped) → core fill weight.
double mapShineFill(double shine) =>
    ((shine - kShineFillStart) / kShineFillRamp).clamp(0.0, 1.0);

// Auto Retouch values live in `PortraitPresets` (model/portrait_presets.dart).
