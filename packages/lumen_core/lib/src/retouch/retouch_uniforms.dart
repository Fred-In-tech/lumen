/// Slider-driven uniforms of the retouch pass (research 07 §3.13, §6.3).
///
/// Per-face design: the maps carry a nearest-sampled face-id channel
/// (`slot + 1`), and these uniforms carry one row of internal parameters per
/// slot. Dragging any face-scope slider (All / Female / Male / Child /
/// Senior / one person) re-resolves the rows and changes uniforms only.
///
/// Packed layout ([RetouchUniforms.pack], 196 floats = 49 vec4):
///
/// | floats | vec4 | contents |
/// |---|---|---|
/// | 0–3 | `uRetouch` | face count, any active (0/1), spot ramp, 0 |
/// | 4 + 24k + 0–3 | `uFace[6k]` | smooth, texture gain, even, amp threshold |
/// | 4 + 24k + 4–7 | `uFace[6k+1]` | dark circles, bags, lid protect, shine |
/// | 4 + 24k + 8–11 | `uFace[6k+2]` | eye whites, iris, red vein, shine fill |
/// | 4 + 24k + 12–15 | `uFace[6k+3]` | teeth bright, teeth desat, acne, freckle |
/// | 4 + 24k + 16–19 | `uFace[6k+4]` | mole, lips, blush, wrinkle crow's feet |
/// | 4 + 24k + 20–23 | `uFace[6k+5]` | wrinkle forehead, frown, smile, marionette |
///
/// for slots k = 0..7 (unused slots hold identity rows). `uFace[6k+5]`
/// holds the two blend pairs of the wrinkle zone code (forehead ↔ frown,
/// smile ↔ marionette), see `wrinkle_zones.dart`.
library;

import 'dart:typed_data';

import '../model/face_analysis.dart';
import '../model/portrait.dart';
import 'blemish_types.dart';
import 'retouch_maps.dart';
import 'slider_mapping.dart';
import 'wrinkle_zones.dart';

/// Floats per face row.
const int kFaceRowFloats = 24;

/// Header floats before the face rows.
const int kRetouchHeaderFloats = 4;

/// Total packed floats.
const int kRetouchUniformFloats =
    kRetouchHeaderFloats + kFaceRowFloats * kMaxRetouchFaces;

/// Internal retouch parameters of one face (already mapped from 0–100).
class FaceRetouchParams {
  const FaceRetouchParams({
    this.smooth = 0,
    this.textureGain = 1,
    this.even = 0,
    this.ampThreshold = kAmpThreshold,
    this.darkCircles = 0,
    this.bags = 0,
    this.lidProtect = 1,
    this.shine = 0,
    this.whites = 0,
    this.iris = 0,
    this.redVein = 0,
    this.teethBrightness = 0,
    this.teethDesaturate = 0,
    this.acne = 0,
    this.freckle = 0,
    this.mole = 0,
    this.lips = 0,
    this.blush = 0,
    this.wrinkleForehead = 0,
    this.wrinkleFrown = 0,
    this.wrinkleCrowsFeet = 0,
    this.wrinkleSmile = 0,
    this.wrinkleMarionette = 0,
  });

  /// Maps the UI values returned by [value] (registry id → 0–100).
  factory FaceRetouchParams.fromValues(double Function(String id) value) {
    final smooth = mapSmoothing(value(PortraitIds.skinSoftening));
    final shine = mapLinear(value(PortraitIds.skinShine));
    return FaceRetouchParams(
      smooth: smooth,
      textureGain: mapTextureGain(value(PortraitIds.skinTexture)),
      even: mapEvenTone(value(PortraitIds.skinEven)),
      ampThreshold: mapAmpThreshold(smooth),
      darkCircles: mapLinear(value(PortraitIds.darkCircles)),
      bags: mapLinear(value(PortraitIds.eyeBags)),
      lidProtect: mapLinear(value(PortraitIds.lidProtect)),
      shine: shine,
      whites: mapLinear(value(PortraitIds.eyeWhites)),
      iris: mapLinear(value(PortraitIds.iris)),
      redVein: mapLinear(value(PortraitIds.redVein)),
      teethBrightness: mapLinear(value(PortraitIds.teethBrightness)),
      teethDesaturate: mapLinear(value(PortraitIds.teethDesaturate)),
      acne: mapLinear(value(PortraitIds.acne)),
      freckle: mapLinear(value(PortraitIds.freckle)),
      mole: mapLinear(value(PortraitIds.mole)),
      lips: mapLinear(value(PortraitIds.lips)),
      blush: mapLinear(value(PortraitIds.blush)),
      wrinkleForehead: mapLinear(value(PortraitIds.wrinkleForehead)),
      wrinkleFrown: mapLinear(value(PortraitIds.wrinkleFrown)),
      wrinkleCrowsFeet: mapLinear(value(PortraitIds.wrinkleCrowsFeet)),
      wrinkleSmile: mapLinear(value(PortraitIds.wrinkleSmile)),
      wrinkleMarionette: mapLinear(value(PortraitIds.wrinkleMarionette)),
    );
  }

  static const identity = FaceRetouchParams();

  final double smooth;
  final double textureGain;
  final double even;
  final double ampThreshold;
  final double darkCircles;
  final double bags;
  final double lidProtect;
  final double shine;
  final double whites;
  final double iris;
  final double redVein;
  final double teethBrightness;
  final double teethDesaturate;
  final double acne;
  final double freckle;
  final double mole;
  final double lips;
  final double blush;
  final double wrinkleForehead;
  final double wrinkleFrown;
  final double wrinkleCrowsFeet;
  final double wrinkleSmile;
  final double wrinkleMarionette;

  /// Clipped-core fill weight, derived from [shine] (§3.8).
  double get shineFill => mapShineFill(shine);

  /// Slider weight of wrinkle zone code [code].
  double wrinkleWeight(int code) => wrinkleZoneWeight(
    code,
    forehead: wrinkleForehead,
    frown: wrinkleFrown,
    crowsFeet: wrinkleCrowsFeet,
    smile: wrinkleSmile,
    marionette: wrinkleMarionette,
  );

  /// True when this row changes no pixel (lid protection alone is inert).
  bool get isIdentity =>
      smooth == 0 &&
      textureGain == 1 &&
      even == 0 &&
      darkCircles == 0 &&
      bags == 0 &&
      shine == 0 &&
      whites == 0 &&
      iris == 0 &&
      redVein == 0 &&
      teethBrightness == 0 &&
      teethDesaturate == 0 &&
      acne == 0 &&
      freckle == 0 &&
      mole == 0 &&
      lips == 0 &&
      blush == 0 &&
      wrinkleForehead == 0 &&
      wrinkleFrown == 0 &&
      wrinkleCrowsFeet == 0 &&
      wrinkleSmile == 0 &&
      wrinkleMarionette == 0;

  /// The row's [kFaceRowFloats] floats in [RetouchUniforms] order.
  List<double> toList() => [
    smooth, textureGain, even, ampThreshold, //
    darkCircles, bags, lidProtect, shine,
    whites, iris, redVein, shineFill,
    teethBrightness, teethDesaturate, acne, freckle,
    mole, lips, blush, wrinkleCrowsFeet,
    wrinkleForehead, wrinkleFrown, wrinkleSmile, wrinkleMarionette,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! FaceRetouchParams) return false;
    final a = toList(), b = other.toList();
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(toList());
}

/// Uniforms of the retouch pass: one [FaceRetouchParams] per face slot
/// (slot = index in `FaceAnalysis.faces`, at most [kMaxRetouchFaces]).
class RetouchUniforms {
  const RetouchUniforms(this.faces);

  /// Resolves every face's values through
  /// `PortraitSettings.valueFor(id, group:, personId:)` (individual →
  /// group → All → default).
  factory RetouchUniforms.fromSettings(
    PortraitSettings settings,
    FaceAnalysis analysis,
  ) => RetouchUniforms(
    List.unmodifiable([
      for (final face in analysis.faces.take(kMaxRetouchFaces))
        FaceRetouchParams.fromValues(
          (id) =>
              settings.valueFor(id, group: face.group, personId: face.personId),
        ),
    ]),
  );

  static const identity = RetouchUniforms([]);

  final List<FaceRetouchParams> faces;

  /// True when no face row changes a pixel: the pass is skipped and
  /// `applyRetouch` returns its input unchanged.
  bool get isIdentity => faces.every((f) => f.isIdentity);

  FaceRetouchParams row(int slot) => slot >= 0 && slot < faces.length
      ? faces[slot]
      : FaceRetouchParams.identity;

  /// Packs the uniforms (see the library doc for the layout).
  Float32List pack() {
    final out = Float32List(kRetouchUniformFloats);
    out[0] = faces.length.toDouble();
    out[1] = isIdentity ? 0 : 1;
    out[2] = kSpotRamp;
    for (var k = 0; k < kMaxRetouchFaces; k++) {
      final values = row(k).toList();
      out.setRange(
        kRetouchHeaderFloats + k * kFaceRowFloats,
        kRetouchHeaderFloats + (k + 1) * kFaceRowFloats,
        values,
      );
    }
    return out;
  }

  /// Cache key of the retouch output for fixed maps (`R` pass cache).
  String get key {
    if (isIdentity) return 'retouch:identity';
    final rows = [
      for (final f in faces)
        f.toList().map((v) => v.toStringAsFixed(4)).join(','),
    ];
    return 'retouch:v2:${rows.join('|')}';
  }

  @override
  bool operator ==(Object other) =>
      other is RetouchUniforms && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
