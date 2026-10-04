/// Deterministic shirt scenes for the clothing tests: a plain backdrop and
/// a blue shirt (lower part of the frame) with a fine fabric weave, soft
/// diagonal folds, a dark seam, a panel edge (a darker side panel), lint
/// specks (light and dark) and the clothes raster on a half-size grid with
/// soft edges, like the vision pipeline's.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// A lint speck: centre, radius (pixels) and OkLab L change.
typedef Lint = ({double x, double y, double r, double dl});

/// Shirt top edge, seam x and panel edge x (fractions of the frame).
const kShirtTop = 0.3, kSeamX = 0.42, kPanelX = 0.8;

/// Fold ridges: `x + kFoldSlope·y = c` (pixels), σ and L amplitude.
const kFoldSlope = 0.6, kFoldSigma = 4.0, kFoldAmp = 0.035;

/// Fabric weave period (pixels) and amplitude (L).
const kWeavePeriod = 3.0, kWeaveAmp = 0.012;

/// Seam half width (pixels) and depth (L); panel L step.
const kSeamHalfWidth = 1.0, kSeamDepth = 0.12, kPanelStep = 0.08;

class ClothesScene {
  const ClothesScene({
    required this.image,
    required this.clothes,
    required this.folds,
    required this.lint,
  });

  final RgbaBuffer image;
  final MaskRaster clothes;

  /// Fold ridge offsets c (pixels) and their signs (+ light, − shadow).
  final List<(double, double)> folds;
  final List<Lint> lint;

  int get width => image.width;
  int get height => image.height;

  /// No faces: clothing effects are image scope.
  FaceAnalysis get analysis => FaceAnalysis(
    imageWidth: width,
    imageHeight: height,
    modelVersion: 'synthetic',
  );

  BackdropInput get input =>
      BackdropInput(clothes: clothes, wantsBackdrop: false, wantsClothes: true);

  /// True well inside the shirt ([margin] pixels from its edges).
  bool isShirt(double x, double y, [double margin = 0]) =>
      y > kShirtTop * height + margin &&
      x > margin &&
      x < width - margin &&
      y < height - margin;

  /// Distance (pixels) to the nearest fold ridge.
  double foldDistance(double x, double y) => folds
      .map((f) => (x + kFoldSlope * y - f.$1).abs() / _foldNorm)
      .reduce(math.min);
}

final _foldNorm = math.sqrt(1 + kFoldSlope * kFoldSlope);

/// Renders a `w × h` shirt scene; [folds] / [lint] / [texture] switch the
/// folds, the specks and the weave (the plain variants are references).
ClothesScene renderClothesScene({
  int w = 480,
  int h = 360,
  bool folds = true,
  bool lint = true,
  bool texture = true,
}) {
  final foldList = <(double, double)>[
    (w * 0.30, 1),
    (w * 0.30 + 3 * kFoldSigma, -1),
    (w * 0.62, 1),
    (w * 0.62 + 3 * kFoldSigma, -1),
    (w * 0.95, -1),
  ];
  final lintList = <Lint>[
    (x: w * 0.25, y: h * 0.82, r: 1.2, dl: 0.25),
    (x: w * 0.55, y: h * 0.90, r: 1.5, dl: 0.22),
    (x: w * 0.67, y: h * 0.45, r: 1.0, dl: -0.18),
    (x: w * 0.12, y: h * 0.55, r: 1.3, dl: 0.24),
  ];
  final img = RgbaBuffer(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = x + 0.5, py = y + 0.5;
      final cov = _shirtAt(w, h, px, py);
      var l = 0.80 + 0.004 * _hash(x, y), a = 0.004, b = 0.012;
      if (cov > 0) {
        var sl = 0.45, sa = -0.01, sb = -0.06;
        if (px > kPanelX * w) sl -= kPanelStep;
        if (texture) {
          sl +=
              kWeaveAmp *
                  math.sin(2 * math.pi * px / kWeavePeriod) *
                  math.sin(2 * math.pi * py / kWeavePeriod) +
              0.004 * _hash(x + 11, y);
        }
        if (folds) {
          for (final f in foldList) {
            final d = (px + kFoldSlope * py - f.$1) / _foldNorm;
            sl +=
                f.$2 *
                kFoldAmp *
                math.exp(-d * d / (2 * kFoldSigma * kFoldSigma));
          }
        }
        final ds = (px - kSeamX * w).abs();
        if (ds < kSeamHalfWidth + 0.5) {
          sl -= kSeamDepth * (kSeamHalfWidth + 0.5 - ds).clamp(0.0, 1.0);
        }
        if (lint) {
          for (final s in lintList) {
            final d = math.sqrt(math.pow(px - s.x, 2) + math.pow(py - s.y, 2));
            if (d < s.r + 0.5) sl += s.dl * (s.r + 0.5 - d).clamp(0.0, 1.0);
          }
        }
        l = l * (1 - cov) + sl * cov;
        a = a * (1 - cov) + sa * cov;
        b = b * (1 - cov) + sb * cov;
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
  final mw = w ~/ 2, mh = h ~/ 2;
  final raster = Uint8List(mw * mh);
  for (var y = 0; y < mh; y++) {
    for (var x = 0; x < mw; x++) {
      var c = 0.0;
      for (var sy = 0; sy < 2; sy++) {
        for (var sx = 0; sx < 2; sx++) {
          c += _shirtAt(w, h, 2 * x + sx + 0.5, 2 * y + sy + 0.5) / 4;
        }
      }
      raster[y * mw + x] = (c * 255).round();
    }
  }
  return ClothesScene(
    image: img,
    clothes: MaskRaster(mw, mh, raster),
    folds: foldList,
    lint: lintList,
  );
}

/// Shirt coverage (everything below [kShirtTop], 1-px soft edge).
double _shirtAt(int w, int h, double px, double py) =>
    (py - kShirtTop * h + 0.5).clamp(0.0, 1.0);

/// Deterministic per-pixel noise in [-1, 1].
double _hash(int x, int y) {
  var v = (x * 73856093) ^ (y * 19349663) ^ 0x1b873593;
  v = (v ^ (v >> 13)) * 0x5bd1e995 & 0x7fffffff;
  v ^= v >> 15;
  return (v & 0xffff) / 32767.5 - 1;
}
