/// Everything `RetouchMaps` needs for one face, over its work rect
/// (research 09 §4.12: masks → heal → bands → per-slider deltas).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../render/rgba_buffer.dart';
import 'band_split.dart';
import 'blemish_detect.dart';
import 'blemish_heal.dart';
import 'blemish_types.dart';
import 'face_frame.dart';
import 'face_parsing_input.dart';
import 'face_regions.dart';
import 'filters.dart';
import 'glare.dart';
import 'lab_planes.dart';
import 'map_rect.dart';
import 'shine_core.dart';
import 'skin_deltas.dart';
import 'spot_anchors.dart';
import 'wrinkle_map.dart';

/// The Texture slider scales the source minus this low-pass (IOD; at
/// least [kTextureSigmaMinPx] map px).
const double kTextureSigmaIod = 0.012;
const double kTextureSigmaMinPx = 1.0;

/// Iris (§4.9): local contrast = this share of the iris' own mid band.
const double kIrisContrast = 0.20;

/// Red veins: at most this share of the fine red excess is removed.
const double kVeinCut = 0.5;

class FaceMapPlanes {
  const FaceMapPlanes({
    required this.frame,
    required this.regions,
    required this.heal,
    required this.low,
    required this.deltas,
    required this.irisL,
    required this.veinA,
    required this.veinL,
    required this.blemishes,
    required this.wrinkles,
    this.hasForcedSpots = false,
  });

  final FaceFrame frame;
  final FaceRegionPlanes regions;

  /// True when the user forced at least one spot removal on this face (it
  /// heals even with every slider at 0).
  final bool hasForcedSpots;
  final HealPlanes heal;

  /// Low-pass of the source at [kTextureSigmaIod] (Texture slider).
  final LabPlanes low;

  /// Per-slider skin deltas and the skin measurements.
  final SkinDeltas deltas;

  /// Eye deltas at 100: iris local contrast (L), vein redness (a) and
  /// vein darkness (L).
  final Float32List irisL;
  final Float32List veinA;
  final Float32List veinL;
  final List<BlemishCandidate> blemishes;
  final WrinklePlanes wrinkles;
}

/// Computes the per-face planes of [f] on a `gridW × gridH` map grid.
/// [pixels] holds the grid window that starts at ([originX], [originY])
/// and covers `f.rect` (the whole grid by default; a per-face tile in
/// `face_tiles.dart`).
FaceMapPlanes computeFaceMaps(
  FaceFrame f,
  RgbaBuffer pixels, {
  int originX = 0,
  int originY = 0,
  int? gridW,
  int? gridH,
  FaceParsingPlanes? parsing,
  BlemishOverrides overrides = BlemishOverrides.none,
}) {
  final rect = f.rect, w = rect.w, h = rect.h, n = rect.area;
  final gw = gridW ?? pixels.width, gh = gridH ?? pixels.height;
  final local = MapRect(rect.x0 - originX, rect.y0 - originY, w, h);
  final read = LabPlanes.fromRgba(pixels, local);
  final lab = LabPlanes(rect, read.l, read.a, read.b);
  final grid = (width: gw, height: gh);
  final regions = buildFaceRegions(
    f,
    lab,
    gridW: grid.width,
    gridH: grid.height,
    parsing: parsing,
    clip: clipPlane(pixels, local),
  );
  final detected = detectBlemishes(
    f,
    lab,
    regions,
    gridW: grid.width,
    gridH: grid.height,
  );
  final resolved = resolveSpotAnchors(
    f,
    detected,
    overrides,
    gridW: grid.width,
    gridH: grid.height,
  );
  final spots = [...detected, ...resolved.manual];
  final spotHeal = healBlemishes(
    f,
    lab,
    spots,
    gridW: grid.width,
    gridH: grid.height,
    overrides: resolved.overrides,
    core: regions.shineCore,
  );
  // Glasses glare: a subtracted veil, merged as spot code kGlareCode.
  final glare = detectGlare(f, lab);
  final heal = glare == null ? spotHeal : mergeGlare(spotHeal, glare);
  // Wrinkles are found on the spot-healed image; the bands come from the
  // healed, wrinkle-filled image, so Smooth never counts a spot or a
  // detected line twice.
  final wrinkles = computeWrinkles(
    f,
    heal.healed.l,
    regions.skin,
    exclude: regions.shineCore,
  );
  final clean = LabPlanes(
    rect,
    addPlanes(heal.healed.l, wrinkles.delta),
    heal.healed.a,
    heal.healed.b,
  );
  final bands = SkinBands.split(clean, regions.masks.norm, f.iod);
  final deltas = computeSkinDeltas(
    f,
    bands,
    regions.masks,
    underEye: regions.underEye,
    blush: regions.blush,
  );
  // Eyes: iris contrast on its own mid band; veins are the fine red
  // excess over the sclera's low-pass.
  final irisL = Float32List(n), veinA = Float32List(n), veinL = Float32List(n);
  for (var i = 0; i < n; i++) {
    if (regions.iris[i] > 0) {
      irisL[i] = kIrisContrast * (bands.l0.l[i] - bands.l2.l[i]);
    }
    if (regions.sclera[i] > 0) {
      final red = math.max(0.0, lab.a[i] - bands.l1.a[i]);
      veinA[i] = -kVeinCut * red;
      veinL[i] =
          kVeinCut *
          math.max(0.0, bands.l1.l[i] - lab.l[i]) *
          smoothstep(0.004, 0.02, red);
    }
  }
  final sigmaT = math.max(kTextureSigmaMinPx, kTextureSigmaIod * f.iod);
  return FaceMapPlanes(
    frame: f,
    regions: regions,
    heal: heal,
    low: lab.mapChannels((c) => gaussianBlur(c, w, h, sigmaT)),
    deltas: deltas,
    irisL: irisL,
    veinA: veinA,
    veinL: veinL,
    blemishes: spots,
    hasForcedSpots: spots.any(
      (s) =>
          resolved.overrides.remove.contains(s.id) &&
          !resolved.overrides.keep.contains(s.id),
    ),
    wrinkles: wrinkles,
  );
}
