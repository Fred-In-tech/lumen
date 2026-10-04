/// Automatic choice of the fill method (§5.3).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/face_analysis.dart';
import 'distance_transform.dart';
import 'hole_mask.dart';
import 'pixel_box.dart';

enum InpaintMethod {
  /// Telea fast marching: thin scratches, wires, dust.
  telea,

  /// Frequency-separated push-pull: small round spots.
  pushPull,

  /// The on-device model (MI-GAN) when downloaded.
  model,

  /// Multi-scale PatchMatch: the zero-download fallback for the rest.
  patchMatch,
}

/// Shape measurements of an undilated removal mask.
class HoleStats {
  const HoleStats({
    required this.pixelCount,
    required this.areaFraction,
    required this.inscribedRadius,
    required this.roundness,
    required this.bbox,
    required this.longEdge,
  });

  factory HoleStats.measure(HoleMask hole) {
    final n = hole.holeCount;
    final longEdge = math.max(hole.srcWidth, hole.srcHeight);
    if (n == 0) {
      return HoleStats(
        pixelCount: 0,
        areaFraction: 0,
        inscribedRadius: 0,
        roundness: 0,
        bbox: PixelBox.zero,
        longEdge: longEdge,
      );
    }
    // Distance from each hole pixel to the nearest non-hole pixel (the
    // area outside the source counts as non-hole).
    final r = hole.bbox.inflate(1);
    final keep = Uint8List(r.area);
    for (var y = 0; y < r.height; y++) {
      for (var x = 0; x < r.width; x++) {
        if (!hole.isHole(r.x + x, r.y + y)) keep[y * r.width + x] = 1;
      }
    }
    final d2 = squaredDistanceTransform(keep, r.width, r.height);
    var maxD2 = 0.0;
    for (final v in d2) {
      if (v > maxD2) maxD2 = v;
    }
    final rin = math.sqrt(maxD2);
    return HoleStats(
      pixelCount: n,
      areaFraction: n / (hole.srcWidth * hole.srcHeight),
      inscribedRadius: rin,
      roundness: n / (math.pi * rin * rin),
      bbox: hole.bbox,
      longEdge: longEdge,
    );
  }

  final int pixelCount;

  /// Hole pixels / source pixels.
  final double areaFraction;

  /// Radius (px) of the largest disc inside the hole: half its thickness.
  final double inscribedRadius;

  /// Area / area of the inscribed disc: ≈ 1 for a disc, large for a line.
  final double roundness;

  final PixelBox bbox;
  final int longEdge;
}

/// Thresholds of [InpaintMethodPicker]; radii scale with the long edge.
class PickerThresholds {
  const PickerThresholds({
    this.maxSmallArea = 0.003,
    this.thinRadiusPx = 4,
    this.thinRadiusFraction = 0.0015,
    this.maxRoundness = 2,
    this.spotRadiusPx = 12,
    this.spotRadiusFraction = 0.005,
  });

  /// "Small": area below 0.3 % of the image (§5.3).
  final double maxSmallArea;

  /// "Thin": inscribed radius ≤ max(px, fraction × long edge).
  final double thinRadiusPx;
  final double thinRadiusFraction;

  /// "Round": area ≤ this × the inscribed disc.
  final double maxRoundness;

  /// Push-pull spots stay below max(px, fraction × long edge) in radius;
  /// larger round holes need real texture synthesis.
  final double spotRadiusPx;
  final double spotRadiusFraction;
}

abstract final class InpaintMethodPicker {
  /// §5.3: small and thin → Telea; small and round → push-pull; otherwise
  /// the model when available, else PatchMatch.
  static InpaintMethod pick(
    HoleStats s, {
    required bool modelAvailable,
    PickerThresholds t = const PickerThresholds(),
  }) {
    final small = s.areaFraction < t.maxSmallArea;
    final thin =
        s.inscribedRadius <=
        math.max(t.thinRadiusPx, t.thinRadiusFraction * s.longEdge);
    final spot =
        s.roundness <= t.maxRoundness &&
        s.inscribedRadius <=
            math.max(t.spotRadiusPx, t.spotRadiusFraction * s.longEdge);
    if (small && thin) return InpaintMethod.telea;
    if (small && spot) return InpaintMethod.pushPull;
    return modelAvailable ? InpaintMethod.model : InpaintMethod.patchMatch;
  }
}

/// True when any hole pixel lies inside one of [faces] (normalized boxes):
/// models hallucinate faces badly, so the UI warns (§5.4).
bool holeIntersectsFaces(HoleMask hole, Iterable<FaceBox> faces) {
  for (final f in faces) {
    final box = PixelBox.fromLTRB(
      (f.x * hole.srcWidth).floor(),
      (f.y * hole.srcHeight).floor(),
      ((f.x + f.width) * hole.srcWidth).ceil(),
      ((f.y + f.height) * hole.srcHeight).ceil(),
    ).intersect(hole.bbox);
    for (var y = box.y; y < box.bottom; y++) {
      for (var x = box.x; x < box.right; x++) {
        if (hole.isHole(x, y)) return true;
      }
    }
  }
  return false;
}
