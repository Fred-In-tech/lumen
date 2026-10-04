/// Per-face region planes (research 07 §1.3, §1.4, §2.2, §2.3).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'face_frame.dart';
import 'face_mesh.dart';
import 'face_parsing_input.dart';
import 'filters.dart';
import 'lab_planes.dart';
import 'map_rect.dart';
import 'polygon_raster.dart';
import 'region_parts.dart';
import 'skin_model.dart';

// Region constants, in IOD units (research 07 §1.4, §2.2, §2.3).
const double kRegionFeatherIod = 0.015;
const double kEyeProtectDilateIod = 0.04;
const double kEyeShieldDilateIod = 0.01;
const double kUnderEyeFeatherIod = 0.05;
const double kLashFullIod = 0.02;
const double kLashZeroIod = 0.08;
const double kForeheadExtendIod = 0.35;
const double kSkinSampleRadiusIod = 0.15;
const double kSkinColorBlurIod = 0.03;
const double kBlemishExclusionIod = 0.08;
const double kParsingGuideRadiusIod = 0.02;
const double kParsingGuideEps = 1e-3;

/// Teeth cap when no sclera is visible (eyes closed).
const double kDefaultTeethCapL = 0.92;

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
    required this.wrinkle,
    required this.blemishExclusion,
    required this.skinModel,
    required this.teethCapL,
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
  final Float32List blush;
  final Float32List wrinkle;

  /// 1 within 0.08 IOD of the eyes, brows, lips and nostrils (§3.3 step 3).
  final Float32List blemishExclusion;
  final SkinColorModel skinModel;

  /// Sclera P90 OkLab L: teeth never get brighter (§3.6).
  final double teethCapL;
}

/// Builds every region plane for [f] from the OkLab pixels [lab] (which
/// must cover `f.rect`). [parsing] are optional multiclass planes.
FaceRegionPlanes buildFaceRegions(
  FaceFrame f,
  LabPlanes lab, {
  required int gridW,
  required int gridH,
  FaceParsingPlanes? parsing,
}) {
  final rect = f.rect, w = rect.w, h = rect.h, iod = f.iod;
  int px(double units) => math.max(1, (units * iod).round());
  Float32List feather(Float32List m, double units) =>
      gaussianBlur(m, w, h, units * iod);

  // Protected features: eyes, brows, lips, nostrils (§2.2 step 4).
  final eyePolys = [f.pts(FaceMesh.rightEye), f.pts(FaceMesh.leftEye)];
  final eyes = unionOfPolygons(eyePolys, rect);
  final features = unionOfPolygons([
    ...eyePolys,
    f.pts([...FaceMesh.rightBrowLower, ...FaceMesh.rightBrowUpper.reversed]),
    f.pts([...FaceMesh.leftBrowLower, ...FaceMesh.leftBrowUpper.reversed]),
    f.pts(FaceMesh.lipsOuter),
  ], rect);
  for (final ring in [FaceMesh.rightNostril, FaceMesh.leftNostril]) {
    final sub = boxOf(f.pts(ring), 0.05 * iod, rect);
    paintMax(features, rect, fitEllipse(f.pts(ring), sub), sub);
  }
  final protect = feather(
    maxOf([dilate(eyes, w, h, px(kEyeProtectDilateIod)), features]),
    kRegionFeatherIod,
  );

  // Colour skin model (§2.2 step 3) and the skin weight (step 4).
  final model = SkinColorModel.fit(lab, [
    for (final c in [
      f.p(FaceMesh.rightCheekApple),
      f.p(FaceMesh.leftCheekApple),
      f.mid(FaceMesh.glabellaTop, FaceMesh.foreheadTop),
    ])
      (centre: c, radius: kSkinSampleRadiusIod * iod),
  ]);
  final pColor = model.probabilityPlane(
    lab.mapChannels((c) => gaussianBlur(c, w, h, kSkinColorBlurIod * iod)),
  );
  final raw = parsing == null
      ? productOf([rasterizePolygon(_extendedOval(f), rect), pColor])
      : _parsingSkin(f, lab, parsing, pColor, gridW, gridH);
  final skin = subtractMask(feather(raw, kRegionFeatherIod), protect);

  final eye = eyeMaps(f, lab);
  final mouth = mouthMaps(f, lab, model.meanA);
  return FaceRegionPlanes(
    rect: rect,
    skin: skin,
    underEye: _underEye(f),
    lash: _lashFalloff(f),
    mouth: pasted(rect, mouth.mouth, mouth.sub),
    sclera: pasted(rect, eye.sclera, eye.sub),
    iris: pasted(rect, eye.iris, eye.sub),
    lips: pasted(rect, mouth.lips, mouth.sub),
    // TODO(retouch step 8): blush ellipse at 50/280 along 205→123 × skin.
    blush: Float32List(rect.area),
    // TODO(retouch step 8): Frangi ridge map × wrinkle zones (§3.4).
    wrinkle: Float32List(rect.area),
    blemishExclusion: dilate(features, w, h, px(kBlemishExclusionIod)),
    skinModel: model,
    teethCapL: eye.capL ?? kDefaultTeethCapL,
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

/// Face oval with the upper arc pushed up by 0.35 IOD along the face axis
/// (the mesh top 10 is mid-forehead, not the hairline).
List<MapPoint> _extendedOval(FaceFrame f) {
  final pts = f.pts(FaceMesh.faceOval);
  final tops = [for (final q in pts) math.max(0.0, -f.alongAxis(q))];
  final tMax = tops.reduce(math.max);
  if (tMax <= 0) return pts;
  final ext = kForeheadExtendIod * f.iod;
  return [
    for (var i = 0; i < pts.length; i++)
      (
        x: pts[i].x - f.axis.x * ext * tops[i] / tMax,
        y: pts[i].y - f.axis.y * ext * tops[i] / tMax,
      ),
  ];
}

/// §2.2 step 4 composition with multiclass planes, refined by a guided
/// filter against OkLab L (step 2).
Float32List _parsingSkin(
  FaceFrame f,
  LabPlanes lab,
  FaceParsingPlanes planes,
  Float32List pColor,
  int gridW,
  int gridH,
) {
  final rect = f.rect;
  final raw = Float32List(rect.area);
  for (var y = rect.y0; y < rect.y1; y++) {
    final v = (y + 0.5) / gridH;
    for (var x = rect.x0; x < rect.x1; x++) {
      final u = (x + 0.5) / gridW;
      final i = rect.index(x, y);
      final skin = math.max(
        planes.sample(ParsingClass.faceSkin, u, v),
        planes.sample(ParsingClass.bodySkin, u, v),
      );
      if (skin <= 0) continue;
      raw[i] =
          skin *
          (0.5 + 0.5 * pColor[i]) *
          (1 - planes.sample(ParsingClass.hair, u, v)) *
          (1 - 0.8 * planes.sample(ParsingClass.accessories, u, v));
    }
  }
  final r = math.max(1, (kParsingGuideRadiusIod * f.iod).round());
  final refined = guidedFilter(
    lab.l,
    [raw],
    rect.w,
    rect.h,
    r,
    kParsingGuideEps,
  ).first;
  for (var i = 0; i < refined.length; i++) {
    refined[i] = clamp01(refined[i]);
  }
  return refined;
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
