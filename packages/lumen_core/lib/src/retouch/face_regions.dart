/// Per-face region planes (research 07 §1.3, §1.4, §2.2, §2.3).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'face_frame.dart';
import 'face_mesh.dart';
import 'face_parsing_input.dart';
import 'filters.dart';
import 'lab_planes.dart';
import 'makeup.dart';
import 'map_rect.dart';
import 'polygon_raster.dart';
import 'region_parts.dart';
import 'shine_core.dart';
import 'skin_mask.dart';
import 'skin_model.dart';

// Region constants, in IOD units (research 09 §4.2 step 2).
const double kRegionFeatherIod = 0.02;
const double kEyeProtectDilateIod = 0.045;
const double kBrowProtectDilateIod = 0.035;
const double kLipProtectDilateIod = 0.025;
const double kEyeShieldDilateIod = 0.01;
const double kUnderEyeFeatherIod = 0.05;
const double kLashFullIod = 0.02;
const double kLashZeroIod = 0.08;
const double kBlemishExclusionIod = 0.08;

/// Teeth cap when no sclera is visible (eyes closed), and its ceiling:
/// teeth never get brighter than `min(sclera P90, kTeethCapMaxL)` (§4.9).
const double kDefaultTeethCapL = 0.86;
const double kTeethCapMaxL = 0.92;

/// Region planes of one face over its work rect (all 0..1 floats).
class FaceRegionPlanes {
  const FaceRegionPlanes({
    required this.rect,
    required this.skin,
    required this.underEye,
    required this.lash,
    required this.mouth,
    required this.sclera,
    required this.iris,
    required this.lips,
    required this.blush,
    required this.blemishExclusion,
    required this.masks,
    required this.teethCapL,
    required this.makeup,
    this.shineCore,
  });

  final MapRect rect;
  final Float32List skin;
  final Float32List underEye;

  /// Lower-lash falloff (1 at the lid line → 0 by 0.08 IOD), for lid
  /// protection.
  final Float32List lash;
  final Float32List mouth;
  final Float32List sclera;
  final Float32List iris;
  final Float32List lips;

  /// Oriented cheek-apple Gaussians × skin (§3.9).
  final Float32List blush;

  /// 1 within 0.08 IOD of the eyes, brows, lips and nostrils (§3.3 step 3).
  final Float32List blemishExclusion;

  /// Every skin mask of this face ([skin] is `masks.effect`, plus the
  /// clipped shine core).
  final SkinMasks masks;

  SkinColorModel get skinModel => masks.model;

  /// Sclera P90 OkLab L: teeth never get brighter (§3.6).
  final double teethCapL;

  /// Lip and blush targets of this face (§3.9).
  final MakeupTargets makeup;

  /// Soft hole over clipped specular cores on skin (§3.8), or null. The
  /// core is part of [skin] even where the colour model rejected it.
  final Float32List? shineCore;
}

/// Builds every region plane for [f] from the OkLab pixels [lab] (which
/// must cover `f.rect`). [parsing] are optional multiclass planes; [clip]
/// is the soft clipped-highlight mask over `f.rect` (see `shine_core.dart`).
FaceRegionPlanes buildFaceRegions(
  FaceFrame f,
  LabPlanes lab, {
  required int gridW,
  required int gridH,
  FaceParsingPlanes? parsing,
  Float32List? clip,
}) {
  final rect = f.rect, w = rect.w, h = rect.h, iod = f.iod;
  int px(double units) => math.max(1, (units * iod).round());
  Float32List feather(Float32List m, double units) =>
      gaussianBlur(m, w, h, units * iod);

  // Protected features: eyes with their lids, brows, lips. Nostrils are
  // dark, so the skin mask rejects them where they really are (a mesh
  // ellipse that sits off would only hide the nose tip from Shine).
  final eyePolys = [f.pts(FaceMesh.rightEye), f.pts(FaceMesh.leftEye)];
  final eyes = unionOfPolygons(eyePolys, rect);
  final brows = unionOfPolygons([
    f.pts([...FaceMesh.rightBrowLower, ...FaceMesh.rightBrowUpper.reversed]),
    f.pts([...FaceMesh.leftBrowLower, ...FaceMesh.leftBrowUpper.reversed]),
  ], rect);
  final lipsPoly = unionOfPolygons([f.pts(FaceMesh.lipsOuter)], rect);
  final nostrils = Float32List(rect.area);
  for (final ring in [FaceMesh.rightNostril, FaceMesh.leftNostril]) {
    final sub = boxOf(f.pts(ring), 0.05 * iod, rect);
    paintMax(nostrils, rect, fitEllipse(f.pts(ring), sub), sub);
  }
  final features = maxOf([eyes, brows, lipsPoly, nostrils]);
  final protect = feather(
    maxOf([
      dilate(eyes, w, h, px(kEyeProtectDilateIod)),
      dilate(brows, w, h, px(kBrowProtectDilateIod)),
      dilate(lipsPoly, w, h, px(kLipProtectDilateIod)),
    ]),
    kRegionFeatherIod,
  );

  final masks = buildSkinMasks(
    f,
    lab,
    protect: protect,
    gridW: gridW,
    gridH: gridH,
    parsing: parsing,
    clip: clip,
  );
  final model = masks.model;
  var skin = masks.effect;
  final core = clip == null ? null : shineCoreHole(f, clip, skin);
  var exclusion = dilate(features, w, h, px(kBlemishExclusionIod));
  if (core != null) {
    skin = maxOf([skin, subtractMask(core, protect)]);
    exclusion = maxOf([exclusion, dilate(core, w, h, px(kCoreGrowIod))]);
  }

  final eye = eyeMaps(f, lab);
  final mouth = mouthMaps(f, lab, model.meanA);
  final lips = pasted(rect, mouth.lips, mouth.sub);
  final cap = eye.capL == null
      ? kDefaultTeethCapL
      : math.min(eye.capL!, kTeethCapMaxL);
  return FaceRegionPlanes(
    rect: rect,
    skin: skin,
    underEye: _underEye(f),
    lash: _lashFalloff(f),
    mouth: pasted(rect, mouth.mouth, mouth.sub),
    sclera: pasted(rect, eye.sclera, eye.sub),
    iris: pasted(rect, eye.iris, eye.sub),
    lips: lips,
    blush: blushMap(f, skin),
    blemishExclusion: exclusion,
    masks: masks,
    teethCapL: cap,
    makeup: makeupTargets(lab, lips, model),
    shineCore: core,
  );
}

/// Under-eye crescents (lower lid → ring 4), feathered 0.05 IOD and kept
/// out of the eye itself; computed on the crescents' own sub-rect.
Float32List _underEye(FaceFrame f) {
  final iod = f.iod, rect = f.rect;
  final polys = [
    f.pts([...FaceMesh.rightLowerLid, ...FaceMesh.rightUnderEye4.reversed]),
    f.pts([...FaceMesh.leftLowerLid, ...FaceMesh.leftUnderEye4.reversed]),
  ];
  final sub = boxOf(
    [...polys[0], ...polys[1], ...f.pts(FaceMesh.rightEye)],
    3 * kUnderEyeFeatherIod * iod + 2,
    rect,
  );
  final w = sub.w, h = sub.h;
  final eyes = maxOf([
    rasterizePolygon(f.pts(FaceMesh.rightEye), sub),
    rasterizePolygon(f.pts(FaceMesh.leftEye), sub),
  ]);
  final shield = gaussianBlur(
    dilate(eyes, w, h, math.max(1, (kEyeShieldDilateIod * iod).round())),
    w,
    h,
    0.006 * iod,
  );
  final crescents = gaussianBlur(
    maxOf([for (final p in polys) rasterizePolygon(p, sub)]),
    w,
    h,
    kUnderEyeFeatherIod * iod,
  );
  return pasted(rect, subtractMask(crescents, shield), sub);
}

/// 1 on the lower lid line, fading to 0 at 0.08 IOD (lid protection).
Float32List _lashFalloff(FaceFrame f) {
  final rect = f.rect, maxD = kLashZeroIod * f.iod;
  final out = Float32List(rect.area);
  for (final lid in [FaceMesh.rightLowerLid, FaceMesh.leftLowerLid]) {
    final sub = boxOf(f.pts(lid), maxD + 1, rect);
    final d = polylineDistance(f.pts(lid), sub, maxD);
    for (var i = 0; i < d.length; i++) {
      d[i] = 1 - smoothstep(kLashFullIod * f.iod, maxD, d[i]);
    }
    paintMax(out, rect, d, sub);
  }
  return out;
}
