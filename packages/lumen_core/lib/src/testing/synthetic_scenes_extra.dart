import 'dart:math' as math;

import '../color/srgb.dart';
import '../model/exif_summary.dart';
import 'synthetic_scenes.dart';

/// Linear value of an 8-bit sRGB code.
double _b(int code) => srgbToLinear(code / 255);

Lin _bytes(int r, int g, int b) => (_b(r), _b(g), _b(b));

/// Mid-key neutral room (gray cards, balanced colored objects) × [gains].
SyntheticScene castScene(String name, int longEdge, Lin gains) {
  final p = ScenePainter(longEdge);
  const cards = [
    (0.08, 0.15, 0.2, 0.35, 0.05),
    (0.24, 0.15, 0.36, 0.35, 0.18),
    (0.40, 0.15, 0.52, 0.35, 0.40),
    (0.86, 0.2, 0.94, 0.4, 0.55),
  ];
  Lin shade(double u, double v) {
    for (final c in cards) {
      if (inRect(u, v, c.$1, c.$2, c.$3, c.$4)) return gray(c.$5);
    }
    if (inRect(u, v, 0.04, 0.45, 0.2, 0.68)) return gray(0.006);
    if (inRect(u, v, 0.6, 0.15, 0.7, 0.35)) return (0.4, 0.08, 0.06);
    if (inRect(u, v, 0.72, 0.15, 0.82, 0.35)) return (0.06, 0.3, 0.35);
    if (inRect(u, v, 0.6, 0.45, 0.7, 0.6)) return (0.45, 0.4, 0.05);
    if (inRect(u, v, 0.72, 0.45, 0.82, 0.6)) return (0.06, 0.08, 0.4);
    if (v >= 0.7) {
      final stripe = 0.85 + 0.15 * math.sin(u * 60);
      return gray(0.07 * stripe);
    }
    return gray(0.12 + 0.1 * (1 - v) * (0.7 + 0.3 * math.sin(math.pi * u)));
  }

  return SyntheticScene(
    name: name,
    image: p.paint(shade, noise: 0.6, seed: 21, gains: gains),
    neutralPatches: [for (final c in cards) p.rect(c.$1, c.$2, c.$3, c.$4)],
  );
}

/// Contrast-compressed landscape under an airlight veil, P0.5 ≈ 0.2.
SyntheticScene buildHazyLandscape(int longEdge) {
  final p = ScenePainter(longEdge);
  const air = (0.72, 0.75, 0.8);
  Lin veil(Lin j, double t) => (
    j.$1 * t + air.$1 * (1 - t),
    j.$2 * t + air.$2 * (1 - t),
    j.$3 * t + air.$3 * (1 - t),
  );
  Lin shade(double u, double v) {
    final far = 0.33 + 0.05 * math.sin(6 * u);
    final mid = 0.5 + 0.04 * math.sin(9 * u + 1);
    final fg = 0.68 + 0.02 * math.sin(4 * u + 2);
    if (v < far) return veil((0.45, 0.55, 0.75), 0.25);
    if (v < mid) return veil((0.08, 0.1, 0.13), 0.35);
    if (v < fg) return veil((0.04, 0.07, 0.03), 0.6);
    final trunk = (u * 9) % 1.0;
    if (trunk < 0.03 && v > fg + 0.04) return veil(gray(0.004), 0.955);
    final stripe = 0.8 + 0.4 * (0.5 + 0.5 * math.sin(v * 140));
    return veil((0.06 * stripe, 0.09 * stripe, 0.02 * stripe), 0.8);
  }

  return SyntheticScene(
    name: SceneId.hazyLandscape.name,
    image: p.paint(shade, noise: 0.6, seed: 31),
  );
}

/// 24-patch chart on mid gray (median 0.46), gray ramp strip below.
SyntheticScene buildWellExposedChart(int longEdge) {
  final p = ScenePainter(longEdge);
  const patches = [
    [(115, 82, 68), (194, 150, 130), (98, 122, 157)],
    [(87, 108, 67), (133, 128, 177), (103, 189, 170)],
    [(214, 126, 44), (80, 91, 166), (193, 90, 99)],
    [(94, 60, 108), (157, 188, 64), (224, 163, 46)],
    [(56, 61, 150), (70, 148, 73), (175, 54, 60)],
    [(231, 199, 31), (187, 86, 149), (8, 133, 161)],
    [(243, 243, 243), (200, 200, 200), (160, 160, 160)],
    [(122, 122, 122), (85, 85, 85), (52, 52, 52)],
  ];
  final flat = [for (final row in patches) ...row];
  const cols = 6;
  const pw = 54 / 512, ph = 44 / 341, gw = 8 / 512, gh = 8 / 341;
  const u0 = (1 - (cols * pw + (cols - 1) * gw)) / 2;
  const v0 = 30 / 341;
  (double, double, double, double) cell(int i) {
    final c = i % cols, r = i ~/ cols;
    final cu = u0 + c * (pw + gw), cv = v0 + r * (ph + gh);
    return (cu, cv, cu + pw, cv + ph);
  }

  final bg = _b(118);
  Lin shade(double u, double v) {
    for (var i = 0; i < flat.length; i++) {
      final c = cell(i);
      if (inRect(u, v, c.$1, c.$2, c.$3, c.$4)) {
        final px = flat[i];
        return _bytes(px.$1, px.$2, px.$3);
      }
    }
    if (inRect(u, v, 0.1, 250 / 341, 0.9, 280 / 341)) {
      return gray(srgbToLinear((u - 0.1) / 0.8));
    }
    return gray(bg);
  }

  return SyntheticScene(
    name: SceneId.wellExposedChart.name,
    image: p.paint(shade, seed: 41),
    neutralPatches: [
      for (var i = 18; i < 24; i++)
        () {
          final c = cell(i);
          return p.rect(c.$1, c.$2, c.$3, c.$4);
        }(),
    ],
  );
}

/// Backlit portrait at sunset: warm cast, skin oval, bright sky.
SyntheticScene buildGoldenHourPortrait(int longEdge) {
  final p = ScenePainter(longEdge);
  Lin shade(double u, double v) {
    if (v > 0.82 && (u - 0.5).abs() < 0.3) return gray(0.25);
    if (inEllipse(u, v, 0.5, 0.5, 0.15, 0.3)) {
      final shadeK = 0.85 + 0.15 * (1 - (u - 0.5).abs() / 0.15);
      return tinted(shadeK, (0.45, 0.3, 0.22));
    }
    if (inEllipse(u, v, 0.5, 0.36, 0.17, 0.25)) return (0.04, 0.025, 0.015);
    if (v < 0.45) {
      final t = v / 0.45;
      return (0.66 - 0.1 * t, 0.68 - 0.1 * t, 0.74 - 0.1 * t);
    }
    final bokeh = 0.8 + 0.3 * math.sin(u * 23) * math.sin(v * 17);
    return tinted(bokeh, (0.1, 0.12, 0.07));
  }

  return SyntheticScene(
    name: SceneId.goldenHourPortrait.name,
    image: p.paint(shade, noise: 0.6, seed: 51, gains: (1.3, 1.0, 0.7)),
    neutralPatches: [p.rect(0.3, 0.88, 0.45, 0.98)],
    exif: ExifSummary(
      camera: 'Synthetic',
      iso: 200,
      shutter: '1/250',
      exposureSeconds: 1 / 250,
      aperture: 2.0,
      focalMm: 85,
      capturedAt: DateTime(2026, 7, 12, 18, 42),
      flash: false,
    ),
  );
}

/// Mid gray (128) with seeded Gaussian noise σ = 6/255 per channel.
SyntheticScene buildNoisyFlat(int longEdge) {
  final p = ScenePainter(longEdge);
  final g = _b(128);
  return SyntheticScene(
    name: SceneId.noisyFlat.name,
    image: p.paint((u, v) => gray(g), noise: 6, seed: 61),
  );
}

/// Four asymmetric corner colors plus an upward arrow (geometry tests).
SyntheticScene buildMarkerCorners(int longEdge) {
  final p = ScenePainter(longEdge);
  Lin shade(double u, double v) {
    if (inRect(u, v, 0, 0, 0.25, 0.3)) return (0.8, 0.05, 0.05);
    if (inRect(u, v, 0.8, 0, 1, 0.2)) return (0.05, 0.6, 0.05);
    if (inRect(u, v, 0, 0.75, 0.15, 1)) return (0.05, 0.05, 0.8);
    if (inRect(u, v, 0.7, 0.65, 1, 1)) return (0.8, 0.7, 0.02);
    if (inRect(u, v, 0.47, 0.35, 0.53, 0.8)) return gray(0.9);
    if (v >= 0.15 && v < 0.35) {
      final half = 0.1 * (v - 0.15) / 0.2;
      if ((u - 0.5).abs() <= half) return gray(0.9);
    }
    return gray(0.2);
  }

  return SyntheticScene(
    name: SceneId.markerCorners.name,
    image: p.paint(shade, seed: 71),
  );
}

Lin _hue(double h) {
  double k(double n) => (n + h / 60) % 6;
  double f(double n) =>
      1 - math.max(0, math.min(math.min(k(n), 4 - k(n)), 1)).toDouble();
  return (srgbToLinear(f(5)), srgbToLinear(f(3)), srgbToLinear(f(1)));
}

/// Quadrants: ramps, saturated hue ring, skin + sky, texture + edges.
SyntheticScene buildAllFeatures(int longEdge) {
  final p = ScenePainter(longEdge);
  Lin shade(double u, double v) {
    if (u < 0.5 && v < 0.5) {
      final t = srgbToLinear(u / 0.5);
      return switch ((v / 0.125).floor()) {
        0 => gray(t),
        1 => (t, 0, 0),
        2 => (0, t, 0),
        _ => (0, 0, t),
      };
    }
    if (u >= 0.5 && v < 0.5) {
      final du = (u - 0.75) * 1.5, dv = v - 0.25;
      final r = math.sqrt(du * du + dv * dv);
      if (r > 0.1 && r < 0.22) {
        var h = math.atan2(dv, du) * 180 / math.pi;
        if (h < 0) h += 360;
        return _hue(h);
      }
      return gray(0.2);
    }
    if (u < 0.5) {
      if (inEllipse(u, v, 0.25, 0.8, 0.12, 0.16)) return (0.45, 0.3, 0.22);
      final t = (v - 0.5) / 0.5;
      return (0.3 + 0.2 * t, 0.5 + 0.15 * t, 0.85);
    }
    if (u < 0.75) {
      final cx = (u * 128).floor(), cy = (v * 85).floor();
      return gray((cx + cy).isEven ? 0.02 : 0.9);
    }
    return gray(((u - 0.75) * 40).floor().isEven ? 0.05 : 0.6);
  }

  return SyntheticScene(
    name: SceneId.allFeatures.name,
    image: p.paint(shade, noise: 0.6, seed: 81),
  );
}
