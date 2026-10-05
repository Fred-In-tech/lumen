/// Deterministic synthetic portraits for the retouch tests: a skin oval
/// with pores (fine noise), blotches (mid band), dark circles, shine, an
/// optional clipped specular core, wrinkle lines in every §3.4 zone,
/// blemishes of known size and contrast, a flat cheek patch with a
/// high-contrast stripe and a low-contrast blotch, plus eyes, brows,
/// textured lips with a gloss highlight, teeth and hair.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'synthetic_landmarks.dart';

enum SynthSpotKind { acne, freckle, mole }

/// A blemish centred at local `(x, y)` with visible radius [radius] (IOD
/// units, = 2σ of its Gaussian profile).
class SynthSpot {
  const SynthSpot(this.x, this.y, this.radius, this.kind);
  final double x;
  final double y;
  final double radius;
  final SynthSpotKind kind;

  ({double l, double a, double b}) get delta => switch (kind) {
    SynthSpotKind.acne => (l: -0.035, a: 0.045, b: 0.008),
    SynthSpotKind.freckle => (l: -0.045, a: 0.006, b: 0.028),
    SynthSpotKind.mole => (l: -0.28, a: 0.01, b: 0.005),
  };
}

const kAcneSpots = [
  SynthSpot(0.55, 0.55, 0.026, SynthSpotKind.acne),
  SynthSpot(0.30, -0.70, 0.022, SynthSpotKind.acne),
  SynthSpot(0.15, 1.55, 0.03, SynthSpotKind.acne),
  SynthSpot(0.80, 0.80, 0.024, SynthSpotKind.acne),
];
const kFreckleSpots = [
  SynthSpot(-0.35, 0.40, 0.02, SynthSpotKind.freckle),
  SynthSpot(-0.45, 0.30, 0.022, SynthSpotKind.freckle),
  SynthSpot(0.40, 0.38, 0.02, SynthSpotKind.freckle),
  SynthSpot(-0.25, -0.70, 0.022, SynthSpotKind.freckle),
];
const kMoleSpots = [SynthSpot(-0.30, 1.45, 0.045, SynthSpotKind.mole)];
const kDefaultSpots = [...kAcneSpots, ...kFreckleSpots, ...kMoleSpots];

enum SynthZone { forehead, frown, crowsFeet, smile, marionette }

/// A wrinkle: a Gaussian valley of [depth] (OkLab L) and width [sigma]
/// (IOD) along the segment `(x0, y0)–(x1, y1)` (local units).
class SynthLine {
  const SynthLine(
    this.x0,
    this.y0,
    this.x1,
    this.y1,
    this.depth,
    this.sigma,
    this.zone,
  );
  final double x0;
  final double y0;
  final double x1;
  final double y1;
  final double depth;
  final double sigma;
  final SynthZone zone;

  SynthLine get mirrored => SynthLine(-x0, y0, -x1, y1, depth, sigma, zone);

  /// Distance of `(x, y)` from the segment (local units).
  double distance(double x, double y) {
    final dx = x1 - x0, dy = y1 - y0;
    final t = (((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)).clamp(
      0.0,
      1.0,
    );
    final px = x0 + t * dx - x, py = y0 + t * dy - y;
    return math.sqrt(px * px + py * py);
  }
}

const _rightSideLines = [
  // Crow's feet: three lines fanning out from the outer canthus.
  SynthLine(-0.82, -0.02, -0.95, -0.07, 0.035, 0.006, SynthZone.crowsFeet),
  SynthLine(-0.82, 0.01, -0.95, 0.01, 0.035, 0.006, SynthZone.crowsFeet),
  SynthLine(-0.82, 0.04, -0.95, 0.09, 0.035, 0.006, SynthZone.crowsFeet),
  // Nasolabial fold crease, on the landmark polyline 129 → 212.
  SynthLine(-0.244, 0.76, -0.36, 1.05, 0.05, 0.010, SynthZone.smile),
  // Marionette line, on the landmark polyline 57 → 169.
  SynthLine(-0.46, 1.25, -0.41, 1.57, 0.045, 0.009, SynthZone.marionette),
];

/// Every wrinkle of the default face.
final List<SynthLine> kWrinkles = [
  // Forehead lines (the lowest one crosses the frown zone).
  const SynthLine(-0.45, -0.62, 0.45, -0.62, 0.035, 0.007, SynthZone.forehead),
  const SynthLine(-0.40, -0.80, 0.40, -0.80, 0.035, 0.007, SynthZone.forehead),
  const SynthLine(-0.35, -0.95, 0.35, -0.95, 0.03, 0.007, SynthZone.forehead),
  // Frown lines ("11s") between the brows.
  const SynthLine(-0.06, -0.42, -0.06, -0.26, 0.045, 0.006, SynthZone.frown),
  const SynthLine(0.06, -0.42, 0.06, -0.26, 0.045, 0.006, SynthZone.frown),
  ..._rightSideLines,
  for (final l in _rightSideLines) l.mirrored,
];

/// Distance (local units) to the nearest wrinkle line.
double wrinkleDistance(double x, double y) =>
    kWrinkles.map((l) => l.distance(x, y)).reduce(math.min);

/// Lip lines (vertical L ripple) and the lower-lip gloss highlight.
const kLipLinePeriod = 0.03, kLipLineAmp = 0.02;
const kGlossX = 0.10, kGlossY = 1.21, kGlossSigma = 0.015;

/// Clipped specular core (when [SynthFace.clippedShine]).
const kCoreX = 0.62, kCoreY = 1.12, kCoreSigma = 0.045, kCoreLift = 0.45;

/// Mid-band blotches (σ = [kBlotchSigma] IOD, between B1 and B2 of §3.0):
/// a jittered grid over the skin, away from features, spots and the patch.
const kBlotchSigma = 0.025;
const kBlotchAmpL = 0.016;
final List<({double x, double y, double s})> kBlotches = _blotchGrid();

List<({double x, double y, double s})> _blotchGrid() {
  final out = <({double x, double y, double s})>[];
  for (var gy = 0; gy < 15; gy++) {
    for (var gx = 0; gx < 11; gx++) {
      final jx = _hash(gx * 7 + 3, gy * 13 + 1) * 0.05;
      final jy = _hash(gx * 11 + 5, gy * 3 + 7) * 0.05;
      final x = -0.9 + gx * 0.18 + jx, y = -0.9 + gy * 0.18 + jy;
      final nearFeature =
          (y > -0.5 && y < 0.25 && x.abs() > 0.1) || // brows, eyes
          (y > 0.55 && y < 0.9 && x.abs() < 0.3) || // nose base
          (y > 0.9 && y < 1.32 && x.abs() < 0.55) || // mouth
          (x > kPatchX0 - 0.1 && y > kPatchY0 - 0.1 && y < kPatchY1 + 0.1) ||
          x * x / (1.05 * 1.05) + math.pow((y - 0.6) / 1.3, 2) > 1 ||
          kDefaultSpots.any(
            (p) => math.pow(p.x - x, 2) + math.pow(p.y - y, 2) < 0.012,
          ) ||
          wrinkleDistance(x, y) < 0.09;
      if (nearFeature) continue;
      out.add((x: x, y: y, s: _hash(gx, gy) > 0 ? 1.0 : -1.0));
    }
  }
  return out;
}

/// Broad cheek redness (base band, for Even tone): centre and σ (IOD).
const kRednessX = 0.62, kRednessY = 0.40, kRednessSigma = 0.12;
const kRednessA = 0.02;

/// A point on the tongue inside the open mouth (local y at x = 0).
const kMouthTongueY = 1.16;

/// Sclera vein lines `y = k·dx + c` (local, relative to the eye centre).
const kVeinLines = [(0.25, 0.0), (-0.3, 0.012), (0.1, -0.02)];
const kVeinHalfWidth = 0.004;

/// True on a vein line, outside the iris (dx relative to the eye centre).
bool isVein(double dx, double y) =>
    dx.abs() > kIrisRadius * 1.15 &&
    kVeinLines.any((v) => (y - v.$1 * dx - v.$2).abs() < kVeinHalfWidth);

enum SynthGlasses { none, clear, tinted }

/// Skin tones of the fixtures (OkLab of the unlit base colour).
enum SynthTone {
  /// The tone every older fixture was written for.
  standard(0.70, 0.032, 0.045),
  light(0.80, 0.022, 0.032),
  medium(0.60, 0.040, 0.058),
  deep(0.40, 0.040, 0.050);

  const SynthTone(this.l, this.a, this.b);
  final double l;
  final double a;
  final double b;
}

/// Specular highlight weight (0..1) at local (x, y): forehead, nose
/// bridge and tip, both cheekbones.
double synthSpecular(double x, double y) => [
  _g(x, (y + 0.62) * 1.3, 0.22),
  0.9 * _g(x * 2.2, y - 0.45, 0.16),
  0.8 * _g(x, y - 0.68, 0.06),
  0.7 * _g((x - 0.62) * 0.8, (y - 0.42) * 1.6, 0.14),
  0.7 * _g((x + 0.62) * 0.8, (y - 0.42) * 1.6, 0.14),
].reduce(math.max);

/// Smooth value noise in [-1, 1] with features of about 0.05 IOD (the
/// mid band) plus a broader 0.15 IOD layer: continuous unevenness.
double synthUneven(double x, double y) =>
    0.65 * _valueNoise(x / 0.05, y / 0.05, 11) +
    0.35 * _valueNoise(x / 0.15, y / 0.15, 23);

double _valueNoise(double x, double y, int seed) {
  final x0 = x.floor(), y0 = y.floor();
  final fx = x - x0, fy = y - y0;
  final sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
  double v(int i, int j) => _hash(i * 3 + seed, j * 5 - seed);
  final top = v(x0, y0) + (v(x0 + 1, y0) - v(x0, y0)) * sx;
  final bot = v(x0, y0 + 1) + (v(x0 + 1, y0 + 1) - v(x0, y0 + 1)) * sx;
  return top + (bot - top) * sy;
}

/// [count] freckles scattered over the nose and cheeks (deterministic).
List<SynthSpot> synthFreckles(int count) => [
  for (var k = 0; k < count; k++)
    SynthSpot(
      0.75 * _hash(k * 7 + 1, 3),
      0.45 + 0.28 * _hash(5, k * 11 + 2),
      0.009 + 0.003 * (_hash(k, k) + 1),
      SynthSpotKind.freckle,
    ),
];

/// Lens ellipses (local centre ±[kLensX], [kLensY]; half-axes), rim width
/// (fraction of the radius), brown tint (linear RGB factors) and the glare
/// band (white, linear amount, through the right lens centre).
const kLensX = 0.5, kLensY = 0.02, kLensRx = 0.38, kLensRy = 0.26;
const kRim = 0.035;
const kTint = (0.55, 0.45, 0.38);
const kGlareAmount = 0.35, kGlareSigma = 0.05, kGlareSlope = -1.2;

/// Glare band weight (0..1) at local (x, y) of the right lens.
double glareBand(double x, double y) {
  // Line through (−kLensX, kLensY) with direction (1, kGlareSlope).
  final dx = x + kLensX, dy = y - kLensY;
  final n = math.sqrt(1 + kGlareSlope * kGlareSlope);
  final d = (dy - kGlareSlope * dx).abs() / n;
  return math.exp(-d * d / (2 * kGlareSigma * kGlareSigma));
}

/// Inside a lens: on the rim, or the glare to add (linear).
({bool rim, double glare})? _lens(SynthFace f, double x, double y) {
  for (final cx in const [-kLensX, kLensX]) {
    final u = (x - cx) / kLensRx, v = (y - kLensY) / kLensRy;
    final r = math.sqrt(u * u + v * v);
    if (r > 1 + kRim) continue;
    if (r > 1 - kRim) return (rim: true, glare: 0.0);
    return (rim: false, glare: cx < 0 ? kGlareAmount * glareBand(x, y) : 0.0);
  }
  return null;
}

/// Stubble patch (local centre and half-axes) when [SynthFace.penPatches].
const kStubbleX = -0.05, kStubbleY = 1.72, kStubbleRx = 0.16, kStubbleRy = 0.09;

/// Cool-tinted patch (local centre, radius) with mid-band blotches.
const kTintX = 0.58, kTintY = 0.98, kTintR = 0.11;

/// Red-eye pupil radius (× the iris radius) when [SynthFace.redEye].
const kRedPupil = 0.6;

/// Nostril centre (local), the centroid of landmarks 98, 64, 48, 115.
const kNostrilX = 0.185, kNostrilY = 0.725;

/// Flat cheek patch (local rect) with a stripe and a faint blotch.
const kPatchX0 = -0.98, kPatchX1 = -0.62, kPatchY0 = 0.62, kPatchY1 = 0.98;
const kStripeX = -0.90, kStripeHalfW = 0.02, kStripeDepth = 0.12;
const kPatchBlotchX = -0.74, kPatchBlotchY = 0.80, kPatchBlotchDepth = 0.02;

class SynthFace {
  const SynthFace({
    required this.id,
    required this.cx,
    required this.cy,
    required this.iod,
    this.group = FaceGroup.all,
    this.personId,
    this.spots = kDefaultSpots,
    this.teethL = 0.80,
    this.scleraL = 0.84,
    this.poreAmp = 0.012,
    this.veins = false,
    this.clippedShine = false,
    this.redEye = false,
    this.penPatches = false,
    this.glasses = SynthGlasses.none,
    this.tone = SynthTone.standard,
    this.uneven = 0,
    this.specular = 0,
    this.sparkle = 0,
    this.lumps = true,
  });

  /// Skin tone (the fixtures above are offsets on top of it).
  final SynthTone tone;

  /// Continuous mid-band unevenness (OkLab L amplitude; a little redness
  /// rides on it): what Smooth and Even tone are for.
  final double uneven;

  /// Specular highlights on the forehead, nose and cheekbones: this much
  /// white light (linear) added on top of the skin, like an oily film.
  final double specular;

  /// Make-up shimmer: pore-scale sparkle inside the highlights and a fine
  /// speckle on the skin (texture, not blemishes).
  final double sparkle;

  /// The legacy fixtures: sparse blotches, the lightness shine lump, dark
  /// circles, the red cheek patch and the wrinkles.
  final bool lumps;

  final String id;

  /// Eye midpoint and IOD in image pixels.
  final double cx;
  final double cy;
  final double iod;
  final FaceGroup group;
  final String? personId;
  final List<SynthSpot> spots;
  final double teethL;
  final double scleraL;
  final double poreAmp;

  /// Thin red veins in the sclera (for Red veins).
  final bool veins;

  /// A clipped specular core on the lower left cheek (for Shine > 50).
  final bool clippedShine;

  /// Flash red-eye: the dilated pupil (0.6 × the iris) is red.
  final bool redEye;

  /// Manual Tuning Pen fixtures: skin-coloured stubble on the chin (the AI
  /// calls it skin) and a cool-tinted blotchy patch on the left cheek (the
  /// colour model misses it).
  final bool penPatches;

  /// Glasses with a glare band across the right lens (image left).
  final SynthGlasses glasses;

  ({double x, double y}) toPx(double x, double y) =>
      (x: cx + x * iod, y: cy + y * iod);

  ({double x, double y}) toLocal(double px, double py) =>
      (x: (px - cx) / iod, y: (py - cy) / iod);
}

class SynthPortrait {
  const SynthPortrait(this.image, this.analysis, this.faces);
  final RgbaBuffer image;
  final FaceAnalysis analysis;
  final List<SynthFace> faces;
}

/// Renders [faces] on a `w × h` background and builds their analysis.
SynthPortrait renderSynthPortrait(int w, int h, List<SynthFace> faces) {
  final img = RgbaBuffer(w, h);
  final lms = synthLandmarksLocal();
  final polys = _Polys(lms);
  final lab = Float64List(4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      lab[0] = 0.55 + 0.1 * y / h;
      lab[1] = -0.01;
      lab[2] = -0.03;
      lab[3] = 0;
      for (final f in faces) {
        final p = f.toLocal(x + 0.5, y + 0.5);
        _shadeFace(f, polys, p.x, p.y, _hash(x, y), lab);
      }
      final rgb = oklabToLinearSrgb(Oklab(lab[0], lab[1], lab[2]));
      // The specular layer is light, so it is added in linear RGB.
      var r = rgb.r + lab[3], g = rgb.g + lab[3], b = rgb.b + lab[3];
      for (final f in faces) {
        if (f.glasses == SynthGlasses.none) continue;
        final p = f.toLocal(x + 0.5, y + 0.5);
        final lens = _lens(f, p.x, p.y);
        if (lens == null) continue;
        if (lens.rim) {
          r = g = b = 0.02;
          continue;
        }
        if (f.glasses == SynthGlasses.tinted) {
          r *= kTint.$1;
          g *= kTint.$2;
          b *= kTint.$3;
        }
        r += lens.glare;
        g += lens.glare;
        b += lens.glare;
      }
      img.setPixel(
        x,
        y,
        (linearToSrgb(r.clamp(0.0, 1.0)) * 255).round(),
        (linearToSrgb(g.clamp(0.0, 1.0)) * 255).round(),
        (linearToSrgb(b.clamp(0.0, 1.0)) * 255).round(),
      );
    }
  }
  final analysis = FaceAnalysis(
    imageWidth: w,
    imageHeight: h,
    modelVersion: 'synthetic',
    faces: [
      for (final f in faces)
        DetectedFace(
          id: f.id,
          box: _box(f, lms, w, h),
          landmarks: [
            for (var i = 0; i < FaceMesh.landmarkCount; i++) ...[
              f.toPx(lms[i]!.x, lms[i]!.y).x / w,
              f.toPx(lms[i]!.x, lms[i]!.y).y / h,
            ],
          ],
          group: f.group,
          personId: f.personId,
        ),
    ],
  );
  return SynthPortrait(img, analysis, faces);
}

FaceBox _box(SynthFace f, Map<int, LocalPt> lms, int w, int h) {
  final xs = [for (final i in FaceMesh.faceOval) f.toPx(lms[i]!.x, 0).x];
  final ys = [for (final i in FaceMesh.faceOval) f.toPx(0, lms[i]!.y).y];
  final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max);
  final y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
  return FaceBox(x0 / w, y0 / h, (x1 - x0) / w, (y1 - y0) / h);
}

class _Polys {
  _Polys(Map<int, LocalPt> m)
    : eyes = [_loop(m, FaceMesh.rightEye), _loop(m, FaceMesh.leftEye)],
      brows = [
        _loop(m, [
          ...FaceMesh.rightBrowLower,
          ...FaceMesh.rightBrowUpper.reversed,
        ]),
        _loop(m, [
          ...FaceMesh.leftBrowLower,
          ...FaceMesh.leftBrowUpper.reversed,
        ]),
      ],
      lipsOuter = _loop(m, FaceMesh.lipsOuter),
      lipsInner = _loop(m, FaceMesh.lipsInner);

  final List<List<LocalPt>> eyes;
  final List<List<LocalPt>> brows;
  final List<LocalPt> lipsOuter;
  final List<LocalPt> lipsInner;

  static List<LocalPt> _loop(Map<int, LocalPt> m, List<int> idx) => [
    for (final i in idx) m[i]!,
  ];
}

bool _inside(List<LocalPt> poly, double x, double y) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.y > y) != (b.y > y) &&
        x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

double _g(double dx, double dy, double sigma) =>
    math.exp(-(dx * dx + dy * dy) / (2 * sigma * sigma));

/// Deterministic per-pixel noise in [-1, 1].
double _hash(int x, int y) {
  var v = (x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995;
  v = (v ^ (v >> 13)) * 0x5bd1e995 & 0x7fffffff;
  v ^= v >> 15;
  return (v & 0xffff) / 32767.5 - 1;
}

void _shadeFace(
  SynthFace f,
  _Polys p,
  double x,
  double y,
  double noise,
  Float64List lab,
) {
  if (x.abs() > 1.6 || y < -1.9 || y > 2.3) return;
  final ry = y < kOvalCy ? 1.65 : kOvalRyBottom;
  final skinR = math.pow(x / kOvalRx, 2) + math.pow((y - kOvalCy) / ry, 2);
  final headR = math.pow(x / 1.4, 2) + math.pow((y - 0.2) / 1.85, 2);
  if (skinR > 1) {
    if (headR <= 1 && y < 0.9) {
      lab[0] = 0.27 + 0.03 * math.sin(x * 70);
      lab[1] = 0.02;
      lab[2] = 0.035;
    }
    return;
  }
  // Skin: base, side shading, blotches (mid band), pores (fine band).
  final t = f.tone;
  var l = t.l - 0.05 * (x / kOvalRx) * (x / kOvalRx), a = t.a, b = t.b;
  final inPatch =
      f.lumps && x > kPatchX0 && x < kPatchX1 && y > kPatchY0 && y < kPatchY1;
  if (!f.lumps) {
    l += f.poreAmp * noise;
  } else if (inPatch) {
    if ((x - kStripeX).abs() < kStripeHalfW) l -= kStripeDepth;
    l -= kPatchBlotchDepth * _g(x - kPatchBlotchX, y - kPatchBlotchY, 0.04);
  } else {
    // Mid-band blotches (σ ≈ 0.025 IOD, between B1 and B2 of §3.0).
    for (final bl in kBlotches) {
      final dx = x - bl.x, dy = y - bl.y;
      if (dx.abs() > 0.1 || dy.abs() > 0.1) continue;
      final g = _g(dx, dy, kBlotchSigma);
      l += kBlotchAmpL * bl.s * g;
      a += 0.008 * g;
    }
    l += f.poreAmp * noise;
  }
  if (f.uneven > 0) {
    final u = synthUneven(x, y);
    l += f.uneven * u;
    a += 0.15 * f.uneven * math.max(0.0, -u);
  }
  if (f.sparkle > 0) l += 0.05 * f.sparkle * noise * noise * noise;
  if (f.specular > 0) {
    final s = synthSpecular(x, y);
    lab[3] = f.specular * s * (1 + f.sparkle * math.max(0.0, noise) * s);
  }
  if (f.lumps) {
    a += kRednessA * _g(x - kRednessX, y - kRednessY, kRednessSigma);
    // Dark circles under each eye.
    for (final ex in const [-0.5, 0.5]) {
      final w = _g(x - ex, (y - 0.13) * 2.2, 0.13);
      l -= 0.06 * w;
      a += 0.006 * w;
      b -= 0.02 * w;
    }
    // Shine on the forehead centre and the nose tip.
    final shine = math.max(_g(x, y + 0.6, 0.12), 0.8 * _g(x, y - 0.68, 0.05));
    l += 0.10 * shine;
    a *= 1 - 0.6 * shine;
    b *= 1 - 0.6 * shine;
    for (final w in kWrinkles) {
      final d = w.distance(x, y);
      if (d < 4 * w.sigma) {
        l -= w.depth * math.exp(-d * d / (2 * w.sigma * w.sigma));
      }
    }
  }
  if (f.penPatches) {
    final sx = (x - kStubbleX) / kStubbleRx, sy = (y - kStubbleY) / kStubbleRy;
    if (sx * sx + sy * sy <= 1) {
      // Short dark hairs: a hash-driven speckle on a slightly darker base.
      l -=
          0.04 +
          0.05 * math.max(0.0, _hash((x * 997).floor(), (y * 991).floor()));
    }
    final d = math.sqrt(math.pow(x - kTintX, 2) + math.pow(y - kTintY, 2));
    if (d <= kTintR) {
      a = -0.03;
      b = -0.03;
      for (final (bx, by, sg) in const [
        (-0.04, -0.03, 1.0),
        (0.04, 0.02, -1.0),
        (-0.02, 0.05, 1.0),
      ]) {
        l += 0.03 * sg * _g(x - kTintX - bx, y - kTintY - by, 0.02);
      }
    }
  }
  if (f.clippedShine) {
    final g = _g(x - kCoreX, y - kCoreY, kCoreSigma);
    l += kCoreLift * g;
    a *= 1 - g;
    b *= 1 - g;
  }
  for (final s in f.spots) {
    final g = _g(x - s.x, y - s.y, s.radius / 2);
    final d = s.delta;
    l += d.l * g;
    a += d.a * g;
    b += d.b * g;
  }
  lab[0] = l;
  lab[1] = a;
  lab[2] = b;
  _features(f, p, x, y, lab);
}

void _features(SynthFace f, _Polys p, double x, double y, Float64List lab) {
  void set(double l, double a, double b) {
    lab[0] = l;
    lab[1] = a;
    lab[2] = b;
  }

  if (y > -0.5 && y < -0.2 && p.brows.any((q) => _inside(q, x, y))) {
    set(0.30, 0.02, 0.04);
  }
  if (y.abs() < 0.1 && p.eyes.any((q) => _inside(q, x, y))) {
    final ex = x < 0 ? -0.5 : 0.5;
    final d = math.sqrt((x - ex) * (x - ex) + y * y);
    if (_g(x - ex - 0.03, y + 0.03, 0.012) > 0.5) {
      set(0.97, 0, 0);
    } else if (f.redEye && d < kRedPupil * kIrisRadius) {
      set(0.50, 0.17, 0.08);
    } else if (d < 0.35 * kIrisRadius) {
      set(0.12, 0, 0);
    } else if (d < kIrisRadius) {
      set(0.42 + 0.04 * math.sin(math.atan2(y, x - ex) * 12), 0.015, 0.06);
    } else if (f.veins && isVein(x - ex, y)) {
      set(f.scleraL - 0.08, 0.07, 0.03);
    } else {
      set(f.scleraL, 0.012, 0.02);
    }
  }
  if (y > 0.95 && y < 1.3 && _inside(p.lipsOuter, x, y)) {
    if (_inside(p.lipsInner, x, y)) {
      final gap = ((x / 0.09) - (x / 0.09).roundToDouble()).abs() < 0.06;
      if (y < kMouthY + 0.012) {
        set(gap ? f.teethL - 0.15 : f.teethL, 0.0, 0.06);
      } else {
        set(0.38, 0.09, 0.03);
      }
    } else {
      final g = _g(x - kGlossX, y - kGlossY, kGlossSigma);
      final ripple = kLipLineAmp * math.sin(x * 2 * math.pi / kLipLinePeriod);
      set(
        0.58 + ripple + (0.92 - 0.58 - ripple) * g,
        0.11 * (1 - 0.8 * g),
        0.04 * (1 - 0.8 * g),
      );
    }
  }
  // Nostrils on the ellipse implied by landmarks 98/64/48/115 (and mirror).
  for (final nx in const [-kNostrilX, kNostrilX]) {
    if (math.pow((x - nx) / 0.025, 2) + math.pow((y - kNostrilY) / 0.05, 2) <=
        1) {
      set(0.28, 0.03, 0.03);
    }
  }
}
