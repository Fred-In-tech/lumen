import 'dart:math' as math;

import '../color/srgb.dart';
import '../model/exif_summary.dart';
import '../render/rgba_buffer.dart';
import 'scene_metrics.dart';
import 'synthetic_scenes_extra.dart';

/// Deterministic xorshift32 PRNG (no dependency on `dart:math` Random, so the
/// sequence is identical on every platform and SDK version).
class SceneRandom {
  SceneRandom(int seed) : _state = (seed & 0xFFFFFFFF) == 0 ? 0x9E3779B9 : seed;

  int _state;
  double? _spare;

  int nextUint32() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  /// Uniform in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Standard normal (Box–Muller).
  double nextGaussian() {
    final spare = _spare;
    if (spare != null) {
      _spare = null;
      return spare;
    }
    final u1 = math.max(nextDouble(), 1e-12), u2 = nextDouble();
    final r = math.sqrt(-2 * math.log(u1));
    _spare = r * math.sin(2 * math.pi * u2);
    return r * math.cos(2 * math.pi * u2);
  }
}

/// Synthetic test scenes of PLAN.md §6.4.
enum SceneId {
  darkInterior,
  overexposedBeach,
  tungstenCast,
  daylightCoolCast,
  greenCast,
  hazyLandscape,
  wellExposedChart,
  goldenHourPortrait,
  noisyFlat,
  markerCorners,
  allFeatures,
}

/// A generated scene plus the ground truth tests need.
class SyntheticScene {
  const SyntheticScene({
    required this.name,
    required this.image,
    this.neutralPatches = const [],
    this.exif,
  });

  final String name;

  /// 8-bit sRGB pixels.
  final RgbaBuffer image;

  /// Regions that are neutral gray in the un-cast scene.
  final List<PixelRect> neutralPatches;

  /// Plausible capture metadata for the scene (e.g. sunset time).
  final ExifSummary? exif;
}

/// Linear-light RGB triple used while painting a scene.
typedef Lin = (double, double, double);

/// Paints a scene from a per-pixel function in normalized coordinates.
class ScenePainter {
  ScenePainter(this.longEdge)
    : width = longEdge,
      height = (longEdge * 2 / 3).round();

  final int longEdge;
  final int width;
  final int height;

  /// Rectangle from normalized coordinates.
  PixelRect rect(double u0, double v0, double u1, double v1) {
    final x0 = (u0 * width).round(), y0 = (v0 * height).round();
    return PixelRect(
      x0,
      y0,
      math.max(1, (u1 * width).round() - x0),
      math.max(1, (v1 * height).round() - y0),
    );
  }

  /// Renders [shade] (linear light) with optional encoded-domain noise.
  RgbaBuffer paint(
    Lin Function(double u, double v) shade, {
    double noise = 0,
    int seed = 1,
    Lin gains = (1, 1, 1),
  }) {
    final buf = RgbaBuffer(width, height);
    final rnd = SceneRandom(seed);
    for (var y = 0; y < height; y++) {
      final v = (y + 0.5) / height;
      for (var x = 0; x < width; x++) {
        final c = shade((x + 0.5) / width, v);
        int enc(double lin) {
          final e = linearToSrgb(lin) * 255 + noise * rnd.nextGaussian();
          return e.round().clamp(0, 255);
        }

        buf.setPixel(
          x,
          y,
          enc(c.$1 * gains.$1),
          enc(c.$2 * gains.$2),
          enc(c.$3 * gains.$3),
        );
      }
    }
    return buf;
  }
}

bool inRect(double u, double v, double u0, double v0, double u1, double v1) =>
    u >= u0 && u < u1 && v >= v0 && v < v1;

bool inEllipse(double u, double v, double cu, double cv, double ru, double rv) {
  final du = (u - cu) / ru, dv = (v - cv) / rv;
  return du * du + dv * dv <= 1;
}

Lin gray(double y) => (y, y, y);

Lin tinted(double y, Lin t) => (y * t.$1, y * t.$2, y * t.$3);

/// Deterministic scene generators (PLAN.md §6.4). No downloads, no I/O.
abstract final class SyntheticScenes {
  static SyntheticScene build(SceneId id, {int longEdge = 512}) => switch (id) {
    SceneId.darkInterior => darkInterior(longEdge: longEdge),
    SceneId.overexposedBeach => overexposedBeach(longEdge: longEdge),
    SceneId.tungstenCast => tungstenCast(longEdge: longEdge),
    SceneId.daylightCoolCast => daylightCoolCast(longEdge: longEdge),
    SceneId.greenCast => greenCast(longEdge: longEdge),
    SceneId.hazyLandscape => hazyLandscape(longEdge: longEdge),
    SceneId.wellExposedChart => wellExposedChart(longEdge: longEdge),
    SceneId.goldenHourPortrait => goldenHourPortrait(longEdge: longEdge),
    SceneId.noisyFlat => noisyFlat(longEdge: longEdge),
    SceneId.markerCorners => markerCorners(longEdge: longEdge),
    SceneId.allFeatures => allFeatures(longEdge: longEdge),
  };

  /// Low-key gradient room: median luma ≈ 0.10, ≈ 3 % crushed, no clipping.
  static SyntheticScene darkInterior({int longEdge = 512}) {
    final p = ScenePainter(longEdge);
    Lin shade(double u, double v) {
      if (inRect(u, v, 0, 0.81, 0.16, 1)) return gray(0);
      if (inEllipse(u, v, 0.22, 0.32, 0.022, 0.033)) {
        return tinted(0.10, (1.02, 1, 0.97));
      }
      if (inRect(u, v, 0.5, 0.52, 0.85, 0.78)) {
        return tinted(0.0045, (0.9, 1, 1.15));
      }
      if (inRect(u, v, 0.25, 0.75, 0.48, 0.95)) {
        return tinted(0.0085, (1.15, 0.95, 0.9));
      }
      if (inRect(u, v, 0.62, 0.12, 0.78, 0.3)) return gray(0.02);
      if (v < 0.62) {
        final du = (u - 0.55) / 0.3, dv = (v - 0.3) / 0.35;
        return gray(0.0063 + 0.018 * math.exp(-(du * du + dv * dv)));
      }
      return gray(0.0074 + 0.004 * (1 - (v - 0.62) / 0.38));
    }

    return SyntheticScene(
      name: SceneId.darkInterior.name,
      image: p.paint(shade, noise: 0.6, seed: 11),
      neutralPatches: [p.rect(0.62, 0.12, 0.78, 0.3)],
    );
  }

  /// Bright beach: median ≈ 0.85 with a clipped sun (≈ 4 % of pixels).
  static SyntheticScene overexposedBeach({int longEdge = 512}) {
    final p = ScenePainter(longEdge);
    Lin shade(double u, double v) {
      if (inEllipse(u, v, 0.72, 0.2, 0.092, 0.138)) return gray(1.3);
      if (inRect(u, v, 0.18, 0.55, 0.2, 0.8)) return gray(0.03);
      if (inEllipse(u, v, 0.19, 0.55, 0.08, 0.06)) {
        return (0.55, 0.06, 0.05);
      }
      if (inRect(u, v, 0.55, 0.62, 0.58, 0.82)) {
        return tinted(0.04, (1, 0.9, 0.8));
      }
      if (v < 0.42) {
        final t = v / 0.42;
        return (0.56 + 0.1 * t, 0.68 + 0.08 * t, 0.86 + 0.04 * t);
      }
      if (v < 0.52) return (0.36, 0.52, 0.6);
      final t = (v - 0.52) / 0.48;
      return tinted(0.8 - 0.06 * t, (1, 0.9, 0.72));
    }

    return SyntheticScene(
      name: SceneId.overexposedBeach.name,
      image: p.paint(shade, noise: 0.8, seed: 12),
    );
  }

  static SyntheticScene tungstenCast({int longEdge = 512}) =>
      castScene(SceneId.tungstenCast.name, longEdge, (1.35, 1.0, 0.65));

  static SyntheticScene daylightCoolCast({int longEdge = 512}) =>
      castScene(SceneId.daylightCoolCast.name, longEdge, (0.8, 1.0, 1.25));

  static SyntheticScene greenCast({int longEdge = 512}) =>
      castScene(SceneId.greenCast.name, longEdge, (1.0, 1.2, 1.0));

  static SyntheticScene hazyLandscape({int longEdge = 512}) =>
      buildHazyLandscape(longEdge);

  static SyntheticScene wellExposedChart({int longEdge = 512}) =>
      buildWellExposedChart(longEdge);

  static SyntheticScene goldenHourPortrait({int longEdge = 512}) =>
      buildGoldenHourPortrait(longEdge);

  static SyntheticScene noisyFlat({int longEdge = 512}) =>
      buildNoisyFlat(longEdge);

  static SyntheticScene markerCorners({int longEdge = 512}) =>
      buildMarkerCorners(longEdge);

  static SyntheticScene allFeatures({int longEdge = 512}) =>
      buildAllFeatures(longEdge);
}
