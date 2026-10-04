import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// A synthetic green-screen portrait: a skin-coloured disc (the subject)
/// whose last few pixels blend into the backdrop (soft edge with spill),
/// dark "hair" wisps sticking out of its top, plus a coarse person raster
/// like the segmentation model's (low resolution, blurry).
class SwapScene {
  SwapScene._(this.image, this.alpha, this.people, this.cx, this.cy, this.r);

  factory SwapScene.make({
    int w = 240,
    int h = 180,
    List<int> backdrop = const [40, 170, 60],
    List<int> subject = const [210, 140, 110],
    int seed = 1,
  }) {
    final cx = w / 2, cy = h * 0.55, r = h * 0.28;
    final img = RgbaBuffer(w, h);
    final alpha = Float32List(w * h);
    final rnd = math.Random(seed);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        final d = math.sqrt(dx * dx + dy * dy);
        var a = ((r + 2 - d) / 4).clamp(0.0, 1.0); // 4 px soft edge
        // Hair wisps: thin dark strands above the disc.
        final ang = math.atan2(dy, dx);
        final wisp =
            dy < 0 && d < r + 14 && (ang * 18).remainder(1).abs() < 0.12;
        var c = subject;
        if (wisp && d > r - 2) {
          a = math.max(a, 0.85);
          c = const [70, 50, 35];
        }
        alpha[y * w + x] = a;
        final n = rnd.nextInt(7) - 3;
        int mix(int i) =>
            (a * c[i] + (1 - a) * backdrop[i] + n).round().clamp(0, 255);
        img.setPixel(x, y, mix(0), mix(1), mix(2));
      }
    }
    // Coarse raster: the true matte area-averaged to 1/8 resolution.
    final gw = (w / 8).ceil(), gh = (h / 8).ceil();
    final coarse = Uint8List(gw * gh);
    for (var j = 0; j < gh; j++) {
      for (var i = 0; i < gw; i++) {
        var s = 0.0, n = 0;
        for (var y = j * 8; y < math.min(h, j * 8 + 8); y++) {
          for (var x = i * 8; x < math.min(w, i * 8 + 8); x++) {
            s += alpha[y * w + x];
            n++;
          }
        }
        coarse[j * gw + i] = (s / n * 255).round();
      }
    }
    return SwapScene._(img, alpha, MaskRaster(gw, gh, coarse), cx, cy, r);
  }

  final RgbaBuffer image;

  /// The true coverage of the subject (for checks).
  final Float32List alpha;

  /// The coarse person raster a segmentation model would give.
  final MaskRaster people;
  final double cx;
  final double cy;
  final double r;

  int get width => image.width;
  int get height => image.height;

  /// Pixel offset at distance [d] from the centre along angle [deg].
  (int, int) at(double d, double deg) {
    final t = deg * math.pi / 180;
    return ((cx + d * math.cos(t)).floor(), (cy + d * math.sin(t)).floor());
  }
}
