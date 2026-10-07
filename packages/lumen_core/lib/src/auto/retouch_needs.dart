/// What each face needs from portrait retouch (research 09 §4.4–4.9).
/// The skin needs come from the measurements taken while the maps were
/// built (`RetouchFaceInfo.skin`: band energies, colour excursions,
/// specular layer, under-eye gap), eyes, teeth and lines from the maps and
/// the source. Every need is 0..1: 0 = nothing to fix (the slider stays
/// at 0), 1 = as much as the auto retouch will ever do. Pure,
/// deterministic, isolate-safe.
library;

import 'dart:math' as math;

import '../color/oklab.dart';
import '../color/srgb.dart';
import '../model/face_analysis.dart';
import '../model/portrait.dart';
import '../render/rgba_buffer.dart';
import '../retouch/blemish_types.dart';
import '../retouch/retouch_maps.dart';
import '../retouch/wrinkle_map.dart' show decodeWrinkle;
import '../retouch/wrinkle_zones.dart';

/// Wrinkle zones with their own slider.
enum WrinkleZone { forehead, frown, crowsFeet, smile, marionette }

/// Needs of one face.
class FaceNeeds {
  const FaceNeeds({
    required this.faceId,
    this.group = FaceGroup.all,
    this.blemish = 0,
    this.roughness = 0,
    this.unevenness = 0,
    this.underEye = 0,
    this.shine = 0,
    this.wrinkles = const {},
    this.teethDark = 0,
    this.teethYellow = 0,
    this.scleraRed = 0,
    this.lipChroma = 0,
    this.iod = 0,
    this.pimples = 0,
  });

  /// IOD in map pixels (0 = unknown): small faces get reduced work.
  final double iod;

  /// Inflamed (red) spots found. Dark marks without redness never raise
  /// the automatic value: on made-up skin they are mostly texture.
  final double pimples;

  final String faceId;
  final FaceGroup group;

  /// Acne-like spots (count weighted by contrast).
  final double blemish;

  /// Blotch and bump energy of the mid bands (the Smooth need).
  final double roughness;

  /// Colour excursions from the local skin colour (the Even tone need).
  final double unevenness;

  /// Under-eye darker than the cheek.
  final double underEye;

  /// Area and strength of the specular layer.
  final double shine;

  /// Line depth per wrinkle zone (missing = none found).
  final Map<WrinkleZone, double> wrinkles;

  /// Teeth darker than the sclera / yellower than the sclera.
  final double teethDark;
  final double teethYellow;

  /// Redness of the eye whites.
  final double scleraRed;

  /// Mean lip chroma (OkLab, raw; makeup is never added automatically).
  final double lipChroma;

  double wrinkle(WrinkleZone z) => wrinkles[z] ?? 0;

  /// The neediest value of every need over [faces], named [faceId]: one
  /// slider serves the group, and because every effect is proportional
  /// to what it corrects, faces that need less change less.
  static FaceNeeds most(
    List<FaceNeeds> faces, {
    String faceId = 'most',
    FaceGroup group = FaceGroup.all,
  }) {
    if (faces.isEmpty) return FaceNeeds(faceId: faceId, group: group);
    double top(double Function(FaceNeeds f) v) => faces.map(v).reduce(math.max);
    return FaceNeeds(
      faceId: faceId,
      group: group,
      blemish: top((f) => f.blemish),
      roughness: top((f) => f.roughness),
      unevenness: top((f) => f.unevenness),
      underEye: top((f) => f.underEye),
      shine: top((f) => f.shine),
      wrinkles: {
        for (final z in WrinkleZone.values) z: top((f) => f.wrinkle(z)),
      },
      teethDark: top((f) => f.teethDark),
      teethYellow: top((f) => f.teethYellow),
      scleraRed: top((f) => f.scleraRed),
      lipChroma: top((f) => f.lipChroma),
      iod: top((f) => f.iod),
      pimples: top((f) => f.pimples),
    );
  }
}

/// Needs of every retouchable face of one photo.
class RetouchNeeds {
  const RetouchNeeds(this.faces);

  static const none = RetouchNeeds([]);

  final List<FaceNeeds> faces;

  bool get isEmpty => faces.isEmpty;
}

// Calibration (OkLab units, research 09 §4.4–4.9; [H] values tuned on
// the synthetic set of every skin tone and on real portraits).
const double _smoothLo = 0.003, _smoothHi = 0.011;
const double _colourLo = 0.008, _colourHi = 0.030;
const double _underEyeLo = 0.02, _underEyeHi = 0.09;
const double _shineArea = 6, _shineExcess = 6, _shineExcessLo = 0.04;
const double _wrinkleLo = 0.004, _wrinkleHi = 0.035;
const double _teethDarkLo = 0.02, _teethDarkHi = 0.16;
const double _teethYellowLo = 0.006, _teethYellowHi = 0.045;
const double _scleraRedLo = 0.004, _scleraRedHi = 0.03;

/// `blemish = (25 + 6·n) / 70`, 0 without spots (§4.5).
const double _blemishBase = 25, _blemishPerSpot = 6, _blemishTop = 70;

double _ramp(double v, double lo, double hi) =>
    ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

/// Measures what each face of [analysis] needs. [maps] must come from
/// `computeRetouchMaps(source, analysis, …)`; [source] is that decode (or
/// any decode of the same photo): each map texel reads the source pixel
/// at its uv (through the face's map transform).
RetouchNeeds measureRetouchNeeds(
  RetouchMaps maps,
  RgbaBuffer source,
  FaceAnalysis analysis,
) {
  if (!maps.hasFaces) return RetouchNeeds.none;
  return RetouchNeeds([
    for (final info in maps.faces)
      _measureFace(
        maps,
        source,
        info,
        analysis.faceById(info.faceId)?.group ?? FaceGroup.all,
      ),
  ]);
}

Oklab _lab(List<int> rgb, int o) => linearSrgbToOklab(
  kSrgbByteToLinear[rgb[o]],
  kSrgbByteToLinear[rgb[o + 1]],
  kSrgbByteToLinear[rgb[o + 2]],
);

class _Mean {
  double sum = 0, weight = 0;
  void add(double v, double w) {
    sum += v * w;
    weight += w;
  }

  double get value => weight > 0 ? sum / weight : 0;
}

FaceNeeds _measureFace(
  RetouchMaps maps,
  RgbaBuffer px,
  RetouchFaceInfo info,
  FaceGroup group,
) {
  final w = maps.width, ra = maps.regionA, rb = maps.regionB;
  int at(List<int> tex, int x, int y, int tile, int ch) =>
      tex[(y * 2 * w + tile * w + x) * 4 + ch];
  final owner = info.slot + 1;
  final cheekL = _Mean(), underL = _Mean();
  final scleraL = _Mean(), scleraA = _Mean(), scleraB = _Mean();
  final lipC = _Mean();
  final mouth = <Oklab>[];
  final zone = {for (final z in WrinkleZone.values) z: _Mean()};
  final r = info.rect, t = maps.transformOf(info);
  final sw = px.width, sh = px.height;
  for (var y = r.y0; y < r.y0 + r.h; y++) {
    final sy = ((y + 0.5 - t.ty) / t.sy * sh).floor().clamp(0, sh - 1);
    for (var x = r.x0; x < r.x0 + r.w; x++) {
      if (at(rb, x, y, 1, 0) != owner) continue;
      final sx = ((x + 0.5 - t.tx) / t.sx * sw).floor().clamp(0, sw - 1);
      final g = _lab(px.data, px.offset(sx, sy));
      final skin = at(ra, x, y, 0, 0) / 255;
      final under = at(ra, x, y, 0, 1) / 255;
      final sclera = at(ra, x, y, 1, 1) / 255;
      final mouthW = at(ra, x, y, 1, 0) / 255;
      final lips = at(rb, x, y, 0, 0) / 255;
      final wrinkle = decodeWrinkle(at(rb, x, y, 0, 2).toDouble());
      final zoneCode = at(rb, x, y, 1, 2);
      if (skin > 0.5) {
        if (under < 0.05) cheekL.add(g.l, 1);
      }
      if (under > 0.3) underL.add(g.l, under);
      if (sclera > 0.5) {
        scleraL.add(g.l, 1);
        scleraA.add(g.a, 1);
        scleraB.add(g.b, 1);
      }
      if (mouthW > 0.5 && lips < 0.2) mouth.add(g);
      if (lips > 0.5) lipC.add(math.sqrt(g.a * g.a + g.b * g.b), 1);
      final z = _zoneOf(zoneCode);
      if (z != null && wrinkle > 0.003) zone[z]!.add(wrinkle, 1);
    }
  }

  // Teeth: the near-neutral, not-dark part of the open mouth (the inner
  // mouth and gums are red), compared with the sclera.
  final teeth = mouth
      .where((m) => m.l > 0.4 && m.a < 0.04 && m.a * m.a + m.b * m.b < 0.006)
      .toList();
  double teethDark = 0, teethYellow = 0;
  if (teeth.length >= 6 && scleraL.weight >= 4) {
    final tl = teeth.map((t) => t.l).reduce((a, b) => a + b) / teeth.length;
    final tb = teeth.map((t) => t.b).reduce((a, b) => a + b) / teeth.length;
    teethDark = _ramp(scleraL.value - tl, _teethDarkLo, _teethDarkHi);
    teethYellow = _ramp(tb - scleraB.value, _teethYellowLo, _teethYellowHi);
  }

  var pimples = 0.0;
  for (final b in maps.blemishes) {
    if (b.faceId != info.faceId || b.kind != BlemishKind.acne) continue;
    if (b.score <= 0) continue; // manual spots are not a measured need
    if (!b.dark) pimples++;
  }
  final m = info.skin;
  return FaceNeeds(
    faceId: info.faceId,
    group: group,
    iod: info.iod,
    pimples: pimples,
    blemish: pimples <= 0
        ? 0
        : ((_blemishBase + _blemishPerSpot * pimples) / _blemishTop).clamp(
            0.0,
            1.0,
          ),
    // The working band only: the broad band also holds highlights and
    // make-up contour, which are not blotchiness.
    roughness: _ramp(m.n2, _smoothLo, _smoothHi),
    unevenness: _ramp(m.colourP90, _colourLo, _colourHi),
    underEye: _ramp(m.underEyeGap, _underEyeLo, _underEyeHi),
    shine:
        (_shineArea * m.shineArea +
                _shineExcess * math.max(0.0, m.shineP95 - _shineExcessLo))
            .clamp(0.0, 1.0),
    wrinkles: {
      for (final e in zone.entries)
        if (e.value.weight >= 3)
          e.key: _ramp(e.value.value, _wrinkleLo, _wrinkleHi),
    },
    teethDark: teethDark,
    teethYellow: teethYellow,
    scleraRed: scleraL.weight < 4
        ? 0
        : _ramp(scleraA.value, _scleraRedLo, _scleraRedHi),
    lipChroma: lipC.value,
  );
}

/// The wrinkle zone a zone code mostly belongs to (see `wrinkle_zones`).
WrinkleZone? _zoneOf(int code) {
  if (code <= 0) return null;
  if (code == kZoneCodeCrowsFeet) return WrinkleZone.crowsFeet;
  if (code < kZoneCodeSmile) {
    return code - kZoneCodeForehead < kZoneBlendSteps / 2
        ? WrinkleZone.forehead
        : WrinkleZone.frown;
  }
  return code - kZoneCodeSmile < kZoneBlendSteps / 2
      ? WrinkleZone.smile
      : WrinkleZone.marionette;
}
