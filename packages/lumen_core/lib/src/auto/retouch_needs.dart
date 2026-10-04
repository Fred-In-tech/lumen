/// What each face needs from portrait retouch, measured from the retouch
/// maps and the source they were built from (research 07 §7.1 step 10).
/// Every need is 0..1: 0 = nothing to fix, 1 = as much as the auto
/// retouch will ever do. Pure, deterministic, isolate-safe.
library;

import 'dart:math' as math;

import '../color/oklab.dart';
import '../color/srgb.dart';
import '../model/face_analysis.dart';
import '../model/portrait.dart';
import '../render/aux_maps.dart';
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
  });

  final String faceId;
  final FaceGroup group;

  /// Acne-like spots (count weighted by contrast).
  final double blemish;

  /// Fine-band L energy on clear skin (pores, texture).
  final double roughness;

  /// Mid-band L and colour energy on skin (blotches, uneven tone).
  final double unevenness;

  /// Under-eye darker than the cheek.
  final double underEye;

  /// Share of the cheek that is specular.
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

  /// The mean of [faces] (a group's typical face), named [faceId].
  static FaceNeeds mean(
    List<FaceNeeds> faces, {
    String faceId = 'mean',
    FaceGroup group = FaceGroup.all,
  }) {
    if (faces.isEmpty) return FaceNeeds(faceId: faceId, group: group);
    double avg(double Function(FaceNeeds f) v) =>
        faces.map(v).reduce((a, b) => a + b) / faces.length;
    return FaceNeeds(
      faceId: faceId,
      group: group,
      blemish: avg((f) => f.blemish),
      roughness: avg((f) => f.roughness),
      unevenness: avg((f) => f.unevenness),
      underEye: avg((f) => f.underEye),
      shine: avg((f) => f.shine),
      wrinkles: {
        for (final z in WrinkleZone.values) z: avg((f) => f.wrinkle(z)),
      },
      teethDark: avg((f) => f.teethDark),
      teethYellow: avg((f) => f.teethYellow),
      scleraRed: avg((f) => f.scleraRed),
      lipChroma: avg((f) => f.lipChroma),
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

// Calibration (OkLab units), checked on the synthetic portrait generator:
// clean skin sits near the low ends, heavy problems saturate the highs.
const double _roughLo = 0.004, _roughHi = 0.016;
const double _unevenLo = 0.004, _unevenHi = 0.02;
const double _underEyeLo = 0.012, _underEyeHi = 0.07;
const double _shineLo = 0.002, _shineHi = 0.03;
const double _wrinkleLo = 0.004, _wrinkleHi = 0.035;
const double _teethDarkLo = 0.02, _teethDarkHi = 0.16;
const double _teethYellowLo = 0.006, _teethYellowHi = 0.045;
const double _scleraRedLo = 0.004, _scleraRedHi = 0.03;

/// Acne spots that add up to a need of 1 (each weighted by contrast).
const double _blemishFull = 4;

double _ramp(double v, double lo, double hi) =>
    ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

/// Measures what each face of [analysis] needs. [maps] must come from
/// `computeRetouchMaps(source, analysis, …)`; [source] is that decode (or
/// any decode of the same photo: it is resampled to the map grid).
RetouchNeeds measureRetouchNeeds(
  RetouchMaps maps,
  RgbaBuffer source,
  FaceAnalysis analysis,
) {
  if (!maps.hasFaces) return RetouchNeeds.none;
  final grid = AuxMaps.proxy(
    source,
    longEdge: math.max(maps.width, maps.height),
  );
  final exact = grid.width == maps.width && grid.height == maps.height;
  final px = exact ? grid : _resample(source, maps.width, maps.height);
  return RetouchNeeds([
    for (final info in maps.faces)
      _measureFace(
        maps,
        px,
        info,
        analysis.faceById(info.faceId)?.group ?? FaceGroup.all,
      ),
  ]);
}

RgbaBuffer _resample(RgbaBuffer src, int w, int h) {
  final out = RgbaBuffer(w, h);
  for (var y = 0; y < h; y++) {
    final sy = ((y + 0.5) * src.height / h).floor().clamp(0, src.height - 1);
    for (var x = 0; x < w; x++) {
      final sx = ((x + 0.5) * src.width / w).floor().clamp(0, src.width - 1);
      final i = src.offset(sx, sy), o = out.offset(x, y);
      out.data.setRange(o, o + 4, src.data, i);
    }
  }
  return out;
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
  final rough = _Mean(), uneven = _Mean();
  final cheekL = _Mean(), underL = _Mean();
  final scleraL = _Mean(), scleraA = _Mean(), scleraB = _Mean();
  final lipC = _Mean();
  final mouth = <Oklab>[];
  final zone = {for (final z in WrinkleZone.values) z: _Mean()};
  final cheek = <Oklab>[];
  var shineCore = 0, skinCount = 0;
  final r = info.rect;
  for (var y = r.y0; y < r.y0 + r.h; y++) {
    for (var x = r.x0; x < r.x0 + r.w; x++) {
      if (at(rb, x, y, 1, 0) != owner) continue;
      final o = (y * w + x) * 4;
      final g = _lab(px.data, o);
      final skin = at(ra, x, y, 0, 0) / 255;
      final under = at(ra, x, y, 0, 1) / 255;
      final sclera = at(ra, x, y, 1, 1) / 255;
      final mouthW = at(ra, x, y, 1, 0) / 255;
      final lips = at(rb, x, y, 0, 0) / 255;
      final wrinkle = decodeWrinkle(at(rb, x, y, 0, 2).toDouble());
      final spot = at(rb, x, y, 1, 1);
      final zoneCode = at(rb, x, y, 1, 2);
      if (skin > 0.5) {
        skinCount++;
        if (spot >= 1 + 3 * 64) shineCore++;
        final clear = spot == 0 && wrinkle < 0.004;
        if (clear) {
          final b1 = _lab(maps.b1, o), b2 = _lab(maps.b2, o);
          rough.add(math.pow(g.l - b1.l, 2).toDouble(), skin);
          final dl = b1.l - b2.l, da = b1.a - b2.a, db = b1.b - b2.b;
          uneven.add(dl * dl + da * da + db * db, skin);
        }
        if (under < 0.05) {
          cheekL.add(g.l, 1);
          if (clear) cheek.add(g);
        }
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

  // Shine: clipped cores plus bright, desaturated cheek texels.
  final meanCheek = cheekL.value;
  final bright = cheek
      .where((c) => c.l > meanCheek + 0.1 && c.a * c.a + c.b * c.b < 0.0009)
      .length;
  final shineFrac = skinCount == 0 ? 0.0 : (shineCore + bright) / skinCount;

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

  final acne = maps.blemishes.where(
    (b) => b.faceId == info.faceId && b.kind == BlemishKind.acne,
  );
  final acneWeight = acne.fold<double>(
    0,
    (s, b) => s + (1 - b.threshold).clamp(0.0, 1.0),
  );

  return FaceNeeds(
    faceId: info.faceId,
    group: group,
    blemish: (acneWeight / _blemishFull).clamp(0.0, 1.0),
    roughness: _ramp(math.sqrt(rough.value), _roughLo, _roughHi),
    unevenness: _ramp(math.sqrt(uneven.value), _unevenLo, _unevenHi),
    underEye: underL.weight < 4
        ? 0
        : _ramp(meanCheek - underL.value, _underEyeLo, _underEyeHi),
    shine: _ramp(shineFrac, _shineLo, _shineHi),
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
