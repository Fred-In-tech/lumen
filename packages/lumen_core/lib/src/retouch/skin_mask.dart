/// Skin masks of one face (research 09 §4.2).
///
/// The face mesh is only a loose prior here: on turned or tilted faces
/// its oval, brows and lips can sit several millimetres off, so the masks
/// are decided by the pixels. A pixel is skin when its colour fits this
/// face's own skin (any tone: the model is fitted per face), it is not
/// clearly darker than the skin around it (hair, brows, lashes, nostrils),
/// it is not hair-textured, and it is connected to the middle of the face.
///
/// Three masks come out of that:
/// * [SkinMasks.effect]: where skin effects apply. Eroded, then feathered
///   with a guided filter so the soft edge follows the image edge.
/// * [SkinMasks.norm]: the weight of the masked (normalised) blurs, so
///   hair, background, lips and eyes never bleed into a skin band.
/// * [SkinMasks.stats]: the confident core every measurement uses.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'band_split.dart';
import 'face_frame.dart';
import 'face_mesh.dart';
import 'face_parsing_input.dart';
import 'filters.dart';
import 'lab_planes.dart';
import 'map_rect.dart';
import 'polygon_raster.dart';
import 'skin_model.dart';

// Geometry prior (IOD units): the landmark hull grown by
// [kSkinHullGrowIod], with the forehead pushed up by
// [kForeheadExtendIod] (mesh point 10 is mid-forehead, not the hairline).
const double kSkinHullGrowIod = 0.12;
const double kForeheadExtendIod = 0.35;
const double kSkinPriorFeatherIod = 0.05;

/// Colour is judged on a slightly blurred image (pores are not colour).
const double kSkinColorBlurIod = 0.02;

/// A pixel darker than the skin around it (masked mean at
/// [kSkinLocalBaseIod]) by this fraction of that mean is not skin: hair
/// strands, brows, lashes, nostrils, deep creases.
const double kSkinLocalBaseIod = 0.10;
const double kSkinDarkRelLo = 0.14;
const double kSkinDarkRelHi = 0.26;

/// Outside the inner face (the hull eroded by [kSkinInnerErodeIod]) the
/// lightness reference is the inner face's skin, blurred this wide.
const double kSkinCarriedBaseIod = 0.25;
const double kSkinInnerErodeIod = 0.10;

/// Strong hair texture is not skin at all (ramp on `H`).
const double kHairCutLo = 0.5;
const double kHairCutHi = 0.9;

/// Hair texture map `H` (§4.2 step 3).
const double kHairFineSigmaIod = 0.012;
const double kHairWindowIod = 0.03;
const double kHairEnergyLo = 2.0;
const double kHairEnergyHi = 3.5;
const double kHairEnergyFloor = 0.004;
const double kHairDarkLo = 0.02;
const double kHairDarkHi = 0.08;
const double kHairMinFilterIod = 0.015;
const double kHairWorkIodPx = 80;

/// Enclosed non-skin islands up to this radius (IOD) count as skin.
const double kSkinHoleMaxIod = 0.06;

/// Erode, then edge-aware feather (§4.2 step 7).
const double kSkinErodeIod = 0.012;
const double kSkinFeatherIod = 0.04;
const double kSkinFeatherEps = 1e-3;

/// The measuring core is eroded further and avoids hair texture.
const double kStatsErodeIod = 0.03;
const double kStatsMaxHair = 0.3;

/// Smoothing keeps at least this share of its bands under hair (§4.2 8).
const double kHairSmoothKeep = 0.75;

/// With a parsing model, skin it finds outside the face prior (neck, ears,
/// a hand near the face) gets at most this share of the face's effects.
const double kOffFaceSkinCap = 0.6;

/// Accessories (glasses frames, jewellery) count this much as non-skin.
const double kParsingAccessoryWeight = 0.8;

/// Skin masks of one face over its work rect (all planes 0..1).
class SkinMasks {
  const SkinMasks({
    required this.effect,
    required this.norm,
    required this.stats,
    required this.spots,
    required this.skinLike,
    required this.hair,
    required this.model,
  });

  /// Skin by colour, lightness and texture alone, protected features
  /// included (the lids and the skin right under the lashes are skin):
  /// keeps zone effects such as the under-eye off hair and background
  /// when the mesh sits off.
  final Float32List skinLike;

  /// Where spots may be looked for: the core plus the small dark islands
  /// it encloses (a mole is not skin-coloured, but it is on the skin).
  final Float32List spots;

  /// Where skin effects apply (feathered).
  final Float32List effect;

  /// Weight of the normalised blurs (un-eroded skin, protect removed).
  final Float32List norm;

  /// Confident skin core for measurements (0 or 1).
  final Float32List stats;

  /// Hair / stubble / strand texture, 0..1.
  final Float32List hair;

  final SkinColorModel model;

  /// Number of core pixels.
  int get statsCount {
    var n = 0;
    for (final v in stats) {
      if (v > 0.5) n++;
    }
    return n;
  }
}

/// Builds the masks for face [f] from [lab] (covering `f.rect`).
/// [protect] is the feathered eyes / brows / lips / nostrils plane;
/// [clip] the clipped-highlight plane (excluded from the core only).
SkinMasks buildSkinMasks(
  FaceFrame f,
  LabPlanes lab, {
  required Float32List protect,
  required int gridW,
  required int gridH,
  FaceParsingPlanes? parsing,
  Float32List? clip,
}) {
  final rect = f.rect, w = rect.w, h = rect.h, n = rect.area, iod = f.iod;
  int px(double units) => math.max(1, (units * iod).round());
  final model = SkinColorModel.fit(lab, _samples(f));
  final soft = lab.mapChannels(
    (c) => gaussianBlur(c, w, h, kSkinColorBlurIod * iod),
  );
  final pColor = model.probabilityPlane(soft);
  // The geometry prior is the face; a parsing model removes hair (blond and
  // grey included), clothes and accessories from it and adds the skin it
  // finds around it (capped below).
  final face = _prior(f);
  final parse = parsing == null
      ? null
      : _parsingPlanes(f, parsing, gridW, gridH);
  final prior = parse == null ? face : _withParsing(face, parse);
  // Provisional skin, then the local skin lightness it implies.
  final m0 = Float32List(n);
  for (var i = 0; i < n; i++) {
    m0[i] = prior[i] * pColor[i] * (1 - protect[i]);
  }
  // Local skin lightness. Inside the face it follows the shading; toward
  // the hairline it is carried outward from the inner face, so hair of
  // the same hue as deep skin still reads as darker than "the skin here".
  final inner = _innerFace(f);
  final local = maskedGaussians(
    [lab.l],
    m0,
    w,
    h,
    kSkinLocalBaseIod * iod,
  ).first;
  final carried = maskedGaussians(
    [lab.l],
    productOf([m0, inner]),
    w,
    h,
    kSkinCarriedBaseIod * iod,
  ).first;
  final hair = _hairMap(f, lab.l, m0);
  final raw = Float32List(n), skinLike = Float32List(n);
  for (var i = 0; i < n; i++) {
    if (prior[i] * pColor[i] <= 0) continue;
    final base = math.max(
      local[i],
      inner[i] * local[i] + (1 - inner[i]) * carried[i],
    );
    final rel = (base - soft.l[i]) / math.max(base, 0.05);
    final like =
        prior[i] *
        pColor[i] *
        (1 - smoothstep(kSkinDarkRelLo, kSkinDarkRelHi, rel)) *
        (1 - smoothstep(kHairCutLo, kHairCutHi, hair[i]));
    skinLike[i] = like;
    raw[i] = like * (1 - protect[i]);
  }
  final connected = _connectedToFace(f, raw);
  final solid = Float32List(n);
  for (var i = 0; i < n; i++) {
    if (raw[i] > 0.5 && connected[i] > 0.5) solid[i] = 1;
  }
  final holes = _smallHoles(f, solid);
  final filled = Float32List(n);
  for (var i = 0; i < n; i++) {
    raw[i] *= connected[i];
    filled[i] = holes[i] == 1 ? prior[i] * (1 - protect[i]) : raw[i];
  }
  // Erode, then feather along image edges (guide = L).
  final eroded = erode(raw, w, h, px(kSkinErodeIod));
  final feathered = guidedFilter(
    lab.l,
    [eroded],
    w,
    h,
    px(kSkinFeatherIod),
    kSkinFeatherEps,
  ).first;
  final reach = gaussianBlur(
    dilate(raw, w, h, px(kSkinErodeIod)),
    w,
    h,
    0.5 * kSkinFeatherIod * iod,
  );
  final effect = Float32List(n);
  for (var i = 0; i < n; i++) {
    var v = clamp01(feathered[i]) * clamp01(2 * reach[i]) * (1 - protect[i]);
    if (parse != null) v *= face[i] + (1 - face[i]) * kOffFaceSkinCap;
    effect[i] = v < 0.004 ? 0 : v;
  }
  final core = erode(filled, w, h, px(kStatsErodeIod));
  final stats = Float32List(n), spots = Float32List(n);
  for (var i = 0; i < n; i++) {
    if (core[i] < 0.5) continue;
    // Measurements and spots stay on the face itself.
    if (parse != null && face[i] < 0.5) continue;
    if (holes[i] == 1) spots[i] = 1;
    if (hair[i] > kStatsMaxHair || holes[i] == 1) continue;
    if (clip != null && clip[i] > 0.25) continue;
    stats[i] = 1;
    spots[i] = 1;
  }
  return SkinMasks(
    effect: effect,
    norm: raw,
    stats: stats,
    spots: spots,
    skinLike: skinLike,
    hair: hair,
    model: model,
  );
}

/// Sample discs for the colour model: cheeks, forehead, nose bridge, chin
/// and the cheek hollows. The fit is robust, so a few discs may sit on
/// hair or background when the mesh is off.
List<({MapPoint centre, double radius})> _samples(FaceFrame f) {
  final r = 0.12 * f.iod;
  return [
    for (final c in [
      f.p(FaceMesh.rightCheekApple),
      f.p(FaceMesh.leftCheekApple),
      f.mid(FaceMesh.glabellaTop, FaceMesh.foreheadTop),
      f.p(FaceMesh.noseRidge[1]),
      f.mid(FaceMesh.chinCenterLine[1], FaceMesh.chinCenterLine[2]),
      f.mid(FaceMesh.rightCheekAxis[0], FaceMesh.rightNasolabial[2]),
      f.mid(FaceMesh.leftCheekAxis[0], FaceMesh.leftNasolabial[2]),
    ])
      (centre: c, radius: r),
  ];
}

/// 1 well inside the landmark hull (certainly face), fading to 0 at its
/// edge.
Float32List _innerFace(FaceFrame f) {
  final rect = f.rect;
  final hull = convexHull([
    for (var i = 0; i < FaceMesh.landmarkCount; i++) f.p(i),
  ]);
  final eroded = erode(
    rasterizePolygon(hull, rect),
    rect.w,
    rect.h,
    math.max(1, (kSkinInnerErodeIod * f.iod).round()),
  );
  return gaussianBlur(eroded, rect.w, rect.h, kSkinPriorFeatherIod * f.iod);
}

/// Landmark hull, grown, with the top pushed up along the face axis.
Float32List _prior(FaceFrame f) {
  final rect = f.rect, iod = f.iod;
  final pts = <MapPoint>[
    for (var i = 0; i < FaceMesh.landmarkCount; i++) f.p(i),
  ];
  final tops = [for (final q in pts) math.max(0.0, -f.alongAxis(q))];
  final tMax = tops.reduce(math.max);
  final ext = kForeheadExtendIod * iod;
  final lifted = [
    for (var i = 0; i < pts.length; i++)
      tMax <= 0
          ? pts[i]
          : (
              x: pts[i].x - f.axis.x * ext * tops[i] / tMax,
              y: pts[i].y - f.axis.y * ext * tops[i] / tMax,
            ),
  ];
  final hull = convexHull([...pts, ...lifted]);
  final mask = rasterizePolygon(hull, rect);
  final grown = dilate(
    mask,
    rect.w,
    rect.h,
    math.max(1, (kSkinHullGrowIod * iod).round()),
  );
  return gaussianBlur(grown, rect.w, rect.h, kSkinPriorFeatherIod * iod);
}

/// Parsing planes over `f.rect`: skin (face ∪ body) and how much of the
/// pixel is not hair, clothes or accessories.
typedef _Parse = ({Float32List skin, Float32List keep});

_Parse _parsingPlanes(
  FaceFrame f,
  FaceParsingPlanes planes,
  int gridW,
  int gridH,
) {
  final rect = f.rect;
  final skin = Float32List(rect.area), keep = Float32List(rect.area);
  for (var y = rect.y0; y < rect.y1; y++) {
    final v = (y + 0.5) / gridH;
    for (var x = rect.x0; x < rect.x1; x++) {
      final u = (x + 0.5) / gridW, i = rect.index(x, y);
      skin[i] = math.max(
        planes.sample(ParsingClass.faceSkin, u, v),
        planes.sample(ParsingClass.bodySkin, u, v),
      );
      keep[i] =
          (1 - planes.sample(ParsingClass.hair, u, v)) *
          (1 - planes.sample(ParsingClass.clothes, u, v)) *
          (1 -
              kParsingAccessoryWeight *
                  planes.sample(ParsingClass.accessories, u, v));
    }
  }
  return (skin: skin, keep: keep);
}

/// The face prior without what the parser calls hair / clothes /
/// accessories, plus the skin it finds outside the face.
Float32List _withParsing(Float32List face, _Parse p) {
  final out = Float32List(face.length);
  for (var i = 0; i < out.length; i++) {
    final k = clamp01(p.keep[i]);
    out[i] = math.max(face[i] * k, (1 - face[i]) * p.skin[i] * k);
  }
  return out;
}

/// `H = smoothstep(E_f / median E_f) · max(dark, orient)`: fine-band
/// energy well above this face's clear skin, on dark strands or with a
/// coherent direction (hairline, baby hairs, brows, lashes, stubble).
Float32List _hairMap(FaceFrame f, Float32List l, Float32List skin) {
  final rect = f.rect;
  // Hair texture is judged at about 80 px of IOD: enough to see strands,
  // and a quarter of the work on large faces.
  final factor = (f.iod / kHairWorkIodPx).floor().clamp(1, 4);
  if (factor == 1) return _hairMapAt(l, skin, rect.w, rect.h, f.iod);
  final sl = downsample(l, rect.w, rect.h, factor);
  final ss = downsample(skin, rect.w, rect.h, factor);
  return upsample(
    _hairMapAt(sl.plane, ss.plane, sl.w, sl.h, f.iod / factor),
    sl.w,
    sl.h,
    rect.w,
    rect.h,
    factor,
  );
}

Float32List _hairMapAt(
  Float32List l,
  Float32List skin,
  int w,
  int h,
  double iod,
) {
  final n = w * h;
  final sigmaF = math.max(1.0, kHairFineSigmaIod * iod);
  final sigmaW = math.max(1.5, kHairWindowIod * iod);
  final low = gaussianBlur(l, w, h, sigmaF);
  final sq = Float32List(n);
  for (var i = 0; i < n; i++) {
    final d = l[i] - low[i];
    sq[i] = d * d;
  }
  final energy = gaussianBlur(sq, w, h, sigmaW);
  final picked = <double>[];
  final step = math.max(1, n ~/ 6000);
  for (var i = 0; i < n; i += step) {
    if (skin[i] > 0.6) picked.add(energy[i]);
  }
  var med = kHairEnergyFloor;
  if (picked.length > 16) {
    picked.sort();
    med = math.max(med, math.sqrt(math.max(0.0, picked[picked.length ~/ 2])));
  }
  // Structure tensor of the lightly smoothed L (coherence of direction).
  final jxx = Float32List(n), jxy = Float32List(n), jyy = Float32List(n);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final gx = (l[i + 1] - l[i - 1]) * 0.5, gy = (l[i + w] - l[i - w]) * 0.5;
      jxx[i] = gx * gx;
      jxy[i] = gx * gy;
      jyy[i] = gy * gy;
    }
  }
  final sxx = gaussianBlur(jxx, w, h, sigmaW);
  final sxy = gaussianBlur(jxy, w, h, sigmaW);
  final syy = gaussianBlur(jyy, w, h, sigmaW);
  final mean = gaussianBlur(l, w, h, sigmaW);
  final lowest = rankFilter(
    low,
    w,
    h,
    math.max(1, (kHairMinFilterIod * iod).round()),
    false,
  );
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    // Running box sums can dip a hair below zero.
    final e = math.sqrt(math.max(0.0, energy[i])) / med;
    if (e <= kHairEnergyLo) continue;
    final tr = sxx[i] + syy[i];
    final det = sxx[i] * syy[i] - sxy[i] * sxy[i];
    final disc = math.sqrt(math.max(0.0, tr * tr / 4 - det));
    final coh = tr > 1e-9 ? (2 * disc / tr) * (2 * disc / tr) : 0.0;
    final dark = smoothstep(kHairDarkLo, kHairDarkHi, mean[i] - lowest[i]);
    out[i] = smoothstep(kHairEnergyLo, kHairEnergyHi, e) * math.max(dark, coh);
  }
  return out;
}

/// 1 on the skin that is 4-connected (through `raw > 0.5`) to the middle
/// of the face, 0 elsewhere; soft pixels below 0.5 keep their weight when
/// they touch a connected pixel.
Float32List _connectedToFace(FaceFrame f, Float32List raw) {
  final rect = f.rect, w = rect.w, h = rect.h, n = rect.area;
  final seen = Uint8List(n);
  final stack = <int>[];
  void seed(MapPoint p, double radius) {
    final r = radius.ceil();
    final cx = (p.x - rect.x0).floor(), cy = (p.y - rect.y0).floor();
    for (var y = cy - r; y <= cy + r; y++) {
      if (y < 0 || y >= h) continue;
      for (var x = cx - r; x <= cx + r; x++) {
        if (x < 0 || x >= w) continue;
        final i = y * w + x;
        if (seen[i] == 0 && raw[i] > 0.5) {
          seen[i] = 1;
          stack.add(i);
        }
      }
    }
  }

  for (final s in _samples(f)) {
    seed(s.centre, s.radius);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w;
    if (x > 0) _visit(i - 1, raw, seen, stack);
    if (x < w - 1) _visit(i + 1, raw, seen, stack);
    if (i >= w) _visit(i - w, raw, seen, stack);
    if (i < n - w) _visit(i + w, raw, seen, stack);
  }
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = seen[i].toDouble();
  }
  // Soft fringe: keep sub-threshold weights next to connected skin.
  final near = dilate(out, w, h, 2);
  for (var i = 0; i < n; i++) {
    if (seen[i] == 0 && raw[i] <= 0.5) out[i] = near[i];
  }
  return out;
}

/// 1 on small islands of non-skin fully enclosed by connected skin (a
/// mole, a dark scab, a jewel): they are part of the face, so the spot
/// tools can see them. Islands larger than a disc of [kSkinHoleMaxIod]
/// (eyes, brows, the mouth) and anything open to the outside (hair
/// strands, the hairline) stay non-skin.
Uint8List _smallHoles(FaceFrame f, Float32List connected) {
  final rect = f.rect, w = rect.w, h = rect.h, n = rect.area;
  final label = Uint8List(n); // 0 = unvisited, 1 = hole, 2 = not a hole
  final limit = (math.pi * kSkinHoleMaxIod * kSkinHoleMaxIod * f.iod * f.iod)
      .ceil();
  final stack = <int>[], members = <int>[];
  for (var start = 0; start < n; start++) {
    if (label[start] != 0 || connected[start] > 0.5) continue;
    stack.add(start);
    members.clear();
    label[start] = 2;
    var open = false;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      members.add(i);
      final x = i % w, y = i ~/ w;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) open = true;
      for (final j in [
        if (x > 0) i - 1,
        if (x < w - 1) i + 1,
        if (y > 0) i - w,
        if (y < h - 1) i + w,
      ]) {
        if (label[j] != 0 || connected[j] > 0.5) continue;
        label[j] = 2;
        stack.add(j);
      }
    }
    if (!open && members.length <= limit) {
      for (final i in members) {
        label[i] = 1;
      }
    }
  }
  return label;
}

void _visit(int i, Float32List raw, Uint8List seen, List<int> stack) {
  if (seen[i] != 0 || raw[i] <= 0.5) return;
  seen[i] = 1;
  stack.add(i);
}

/// Convex hull (Andrew's monotone chain), counter-clockwise.
List<MapPoint> convexHull(List<MapPoint> points) {
  final p = [...points]
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  if (p.length < 3) return p;
  double cross(MapPoint o, MapPoint a, MapPoint b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final hull = <MapPoint>[];
  for (final q in p) {
    while (hull.length >= 2 &&
        cross(hull[hull.length - 2], hull.last, q) <= 0) {
      hull.removeLast();
    }
    hull.add(q);
  }
  final lower = hull.length + 1;
  for (final q in p.reversed.skip(1)) {
    while (hull.length >= lower &&
        cross(hull[hull.length - 2], hull.last, q) <= 0) {
      hull.removeLast();
    }
    hull.add(q);
  }
  hull.removeLast();
  return hull;
}
