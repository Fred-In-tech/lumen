/// Everything `RetouchMaps` needs for one face, over its work rect
/// (research 07 §3.0: B1, B2, B3, Bh, regions; IOD-relative sigmas).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../render/rgba_buffer.dart';
import 'blemish_detect.dart';
import 'blemish_heal.dart';
import 'blemish_types.dart';
import 'face_frame.dart';
import 'face_parsing_input.dart';
import 'face_regions.dart';
import 'filters.dart';
import 'lab_planes.dart';

/// `B2` guided filter: r = 0.06 IOD, ε = 4e-4, applied to the healed B1
/// band with its own OkLab L as the guide.
const double kB2RadiusIod = 0.06;
const double kB2Eps = 4e-4;

/// `B3` normalized convolution: three box passes of r = 0.25 IOD.
const double kB3RadiusIod = 0.25;

class FaceMapPlanes {
  const FaceMapPlanes({
    required this.frame,
    required this.regions,
    required this.heal,
    required this.b1,
    required this.b2,
    required this.b3,
    required this.blemishes,
  });

  final FaceFrame frame;
  final FaceRegionPlanes regions;
  final HealPlanes heal;
  final LabPlanes b1;
  final LabPlanes b2;
  final LabPlanes b3;
  final List<BlemishCandidate> blemishes;
}

/// Computes the per-face planes on the map grid [grid] (the `Rres` image).
FaceMapPlanes computeFaceMaps(
  FaceFrame f,
  RgbaBuffer grid, {
  FaceParsingPlanes? parsing,
  BlemishOverrides overrides = BlemishOverrides.none,
}) {
  final rect = f.rect, w = rect.w, h = rect.h;
  final lab = LabPlanes.fromRgba(grid, rect);
  final regions = buildFaceRegions(
    f,
    lab,
    gridW: grid.width,
    gridH: grid.height,
    parsing: parsing,
  );
  final spots = detectBlemishes(
    f,
    lab,
    regions,
    gridW: grid.width,
    gridH: grid.height,
  );
  final heal = healBlemishes(
    f,
    lab,
    spots,
    gridW: grid.width,
    gridH: grid.height,
    overrides: overrides,
  );
  final healed = heal.healed;
  final b1 = lab.mapChannels((c) => gaussianBlur(c, w, h, kB1SigmaIod * f.iod));
  // B2 filters the healed *B1 band* (guide = its L), not the source: a
  // guided filter returns a·I + b, so filtering the source would leak a
  // fraction of the pores into the base and let smoothing amplify them.
  // By linearity, G(σ1)∗(lab + Δ) = B1 + Δlow.
  final b1Healed = LabPlanes(
    rect,
    addPlanes(b1.l, heal.lowL),
    addPlanes(b1.a, heal.lowA),
    addPlanes(b1.b, heal.lowB),
  );
  final g = guidedFilter(
    b1Healed.l,
    b1Healed.channels,
    w,
    h,
    math.max(1, (kB2RadiusIod * f.iod).round()),
    kB2Eps,
  );
  return FaceMapPlanes(
    frame: f,
    regions: regions,
    heal: heal,
    b1: b1,
    b2: LabPlanes(rect, g[0], g[1], g[2]),
    b3: _skinReference(healed, regions.skin, f.iod),
    blemishes: spots,
  );
}

/// Normalized convolution over skin: `blur(skin·c) / blur(skin)`, falling
/// back to the pixel itself where there is no skin nearby.
LabPlanes _skinReference(LabPlanes lab, Float32List skin, double iod) {
  final rect = lab.rect, w = rect.w, h = rect.h, n = rect.area;
  final r = math.max(1, (kB3RadiusIod * iod).round());
  Float32List blur3(Float32List p) =>
      boxBlur(boxBlur(boxBlur(p, w, h, r), w, h, r), w, h, r);
  final den = blur3(skin);
  Float32List channel(Float32List c) {
    final num = blur3(productOf([c, skin]));
    for (var i = 0; i < n; i++) {
      num[i] = den[i] > 1e-3 ? num[i] / den[i] : c[i];
    }
    return num;
  }

  return LabPlanes(rect, channel(lab.l), channel(lab.a), channel(lab.b));
}
