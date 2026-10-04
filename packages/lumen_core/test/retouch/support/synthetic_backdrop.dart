/// Deterministic studio scenes for the backdrop tests: a seamless paper
/// backdrop (vignette falloff, a hotspot, grain, dust specks, a scuff,
/// optionally banding), a person (head with a hair cap, shoulders),
/// flyaway hair lines off the hair, a control line by the shoulder away
/// from the hair, and the person / hair rasters on a coarser grid like the
/// vision pipeline's. The textured variant is a brick wall.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// A small dark dust speck (centre and radius in pixels).
typedef Speck = ({double x, double y, double r});

class BackdropScene {
  const BackdropScene({
    required this.image,
    required this.people,
    required this.hair,
    required this.analysis,
    required this.backdropL,
    required this.headX,
    required this.headY,
    required this.headR,
    required this.specks,
    required this.flyaways,
    required this.shoulderLine,
  });

  final RgbaBuffer image;
  final MaskRaster people;
  final MaskRaster hair;

  /// No faces: backdrop effects are image scope.
  final FaceAnalysis analysis;

  /// Backdrop L before falloff and hotspot.
  final double backdropL;
  final double headX;
  final double headY;
  final double headR;
  final List<Speck> specks;

  /// Flyaway lines: start (on the hair) and end (outside), pixels.
  final List<(double, double, double, double)> flyaways;
  final (double, double, double, double) shoulderLine;

  int get width => image.width;
  int get height => image.height;

  BackdropInput get input => BackdropInput(people: people, hair: hair);

  /// 1 inside the person (head + shoulders), 0 outside (hard edge).
  bool isPerson(double x, double y) => _personAt(this, x, y) > 0.5;
}

/// Scuff centre (fraction of the frame), in open backdrop.
const kScuffX = 0.88, kScuffY = 0.55;

const _vignette = 0.10, _hotspot = 0.06, _hotX = 0.25, _hotY = 0.3;

/// Renders a `w × h` scene. [banding] posterizes the backdrop gradient into
/// steps of [bandStep] L (with little grain); [textured] makes a brick wall.
BackdropScene renderBackdropScene({
  int w = 480,
  int h = 360,
  bool banding = false,
  bool textured = false,
  double bandStep = 0.012,
}) {
  final headX = w * 0.5, headY = h * 0.39, headR = h * 0.14;
  final specks = <Speck>[
    (x: w * 0.10, y: h * 0.15, r: 2.0),
    (x: w * 0.86, y: h * 0.20, r: 1.5),
    (x: w * 0.12, y: h * 0.80, r: 2.5),
    (x: w * 0.90, y: h * 0.72, r: 2.0),
    (x: w * 0.72, y: h * 0.10, r: 1.5),
  ];
  final flyaways = [
    for (final deg in const [-60.0, -90.0, -125.0])
      (
        headX + headR * math.cos(deg * math.pi / 180),
        headY + headR * math.sin(deg * math.pi / 180),
        headX + headR * 1.4 * math.cos(deg * math.pi / 180),
        headY + headR * 1.4 * math.sin(deg * math.pi / 180),
      ),
  ];
  final shoulderLine = (w * 0.16, h * 0.86, w * 0.16, h * 0.97);
  final scene = BackdropScene(
    image: RgbaBuffer(w, h),
    people: MaskRaster(1, 1, Uint8List(1)),
    hair: MaskRaster(1, 1, Uint8List(1)),
    analysis: FaceAnalysis(
      imageWidth: w,
      imageHeight: h,
      modelVersion: 'synthetic',
    ),
    backdropL: 0.82,
    headX: headX,
    headY: headY,
    headR: headR,
    specks: specks,
    flyaways: flyaways,
    shoulderLine: shoulderLine,
  );
  final img = scene.image;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = x + 0.5, py = y + 0.5;
      double l, a, b;
      if (textured) {
        final row = (py / 24).floor();
        final bx = (px + (row.isOdd ? 26 : 0)) % 52, by = py % 24;
        final mortar = bx < 4 || by < 4;
        l = mortar ? 0.78 : 0.48 + 0.08 * math.sin(px * 0.31 + row);
        a = mortar ? 0.0 : 0.06;
        b = mortar ? 0.01 : 0.05;
        l += 0.03 * _hash(x, y);
      } else {
        final nx = px / w - 0.5, ny = py / h - 0.5;
        final r2 = (nx * nx + ny * ny) / 0.5;
        l = scene.backdropL - _vignette * r2;
        l +=
            _hotspot *
            math.exp(
              -(math.pow(px / w - _hotX, 2) + math.pow(py / h - _hotY, 2)) /
                  (2 * 0.12 * 0.12),
            );
        if (banding) {
          l = (l / bandStep).floorToDouble() * bandStep + bandStep / 2;
        }
        a = 0.004;
        b = 0.012;
        l += (banding ? 0.002 : 0.006) * _hash(x, y);
        for (final s in specks) {
          final d = math.sqrt(math.pow(px - s.x, 2) + math.pow(py - s.y, 2));
          if (d < s.r) l -= 0.18;
        }
        // Scuff: a faint bright streak.
        final sx = (px - w * kScuffX) / (w * 0.03),
            sy = (py - h * kScuffY) / 3.0;
        l += 0.06 * math.exp(-(sx * sx + sy * sy) / 2);
      }
      // Flyaways and the control line: thin dark lines on the backdrop.
      for (final f in [...flyaways, shoulderLine]) {
        final d = _segDist(px, py, f);
        if (d < 2) l = l * (1 - 0.35 * math.exp(-d * d / (2 * 0.45 * 0.45)));
      }
      final cov = _personAt(scene, px, py);
      if (cov > 0) {
        final hairCap =
            py < headY - 0.25 * headR &&
            math.sqrt(math.pow(px - headX, 2) + math.pow(py - headY, 2)) <
                headR;
        final pl = hairCap
            ? 0.24
            : (py > h * 0.62 ? 0.40 + 0.04 * math.sin(px * 0.2) : 0.68);
        final pa = hairCap ? 0.01 : (py > h * 0.62 ? -0.02 : 0.03);
        final pb = hairCap ? 0.02 : (py > h * 0.62 ? -0.05 : 0.045);
        l = l * (1 - cov) + (pl + 0.01 * _hash(x + 7, y)) * cov;
        a = a * (1 - cov) + pa * cov;
        b = b * (1 - cov) + pb * cov;
      }
      final rgb = oklabToLinearSrgb(Oklab(l, a, b));
      img.setPixel(
        x,
        y,
        (linearToSrgb(rgb.r) * 255).round().clamp(0, 255),
        (linearToSrgb(rgb.g) * 255).round().clamp(0, 255),
        (linearToSrgb(rgb.b) * 255).round().clamp(0, 255),
      );
    }
  }
  // Rasters on a half-size grid with soft (model-like) edges.
  final mw = w ~/ 2, mh = h ~/ 2;
  final people = Uint8List(mw * mh), hair = Uint8List(mw * mh);
  for (var y = 0; y < mh; y++) {
    for (var x = 0; x < mw; x++) {
      var p = 0.0, hr = 0.0;
      for (var sy = 0; sy < 2; sy++) {
        for (var sx = 0; sx < 2; sx++) {
          final px = 2 * x + sx + 0.5, py = 2 * y + sy + 0.5;
          p += _personAt(scene, px, py) / 4;
          final dh = math.sqrt(
            math.pow(px - headX, 2) + math.pow(py - headY, 2),
          );
          if (dh < headR * 1.05 && py < headY - 0.2 * headR) hr += 0.25;
        }
      }
      people[y * mw + x] = (p * 255).round();
      hair[y * mw + x] = (hr * 255).round();
    }
  }
  return BackdropScene(
    image: img,
    people: MaskRaster(mw, mh, people),
    hair: MaskRaster(mw, mh, hair),
    analysis: scene.analysis,
    backdropL: scene.backdropL,
    headX: headX,
    headY: headY,
    headR: headR,
    specks: specks,
    flyaways: flyaways,
    shoulderLine: shoulderLine,
  );
}

/// Person coverage (head disc + shoulder ellipse, 1-px soft edge).
double _personAt(BackdropScene s, double px, double py) {
  final w = s.image.width, h = s.image.height;
  final dHead =
      math.sqrt(math.pow(px - s.headX, 2) + math.pow(py - s.headY, 2)) -
      s.headR;
  final ex = (px - w * 0.5) / (w * 0.32), ey = (py - h * 1.02) / (h * 0.40);
  final dBody = (math.sqrt(ex * ex + ey * ey) - 1) * h * 0.40;
  final d = math.min(dHead, dBody);
  return (0.5 - d).clamp(0.0, 1.0);
}

double _segDist(double px, double py, (double, double, double, double) s) {
  final (x0, y0, x1, y1) = s;
  final dx = x1 - x0, dy = y1 - y0;
  final t = (((px - x0) * dx + (py - y0) * dy) / (dx * dx + dy * dy)).clamp(
    0.0,
    1.0,
  );
  return math.sqrt(
    math.pow(x0 + t * dx - px, 2) + math.pow(y0 + t * dy - py, 2),
  );
}

/// Deterministic per-pixel noise in [-1, 1].
double _hash(int x, int y) {
  var v = (x * 73856093) ^ (y * 19349663) ^ 0x2f6b9d35;
  v = (v ^ (v >> 13)) * 0x5bd1e995 & 0x7fffffff;
  v ^= v >> 15;
  return (v & 0xffff) / 32767.5 - 1;
}
