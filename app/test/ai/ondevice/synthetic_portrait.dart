import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';

/// Where the drawn features are, in pixels (for assertions).
typedef PortraitLayout = ({
  double cx,
  double cy,
  double scale,
  (double, double) rightEye,
  (double, double) leftEye,
  (double, double) mouth,
});

/// A drawn, cartoon-like frontal face: hair, skin oval with shading, eyes
/// with sclera/iris/pupil, brows, nostrils, lips and neck, softened by a
/// blur. No real person; used to exercise the real detector and mesh.
(RgbaBuffer, PortraitLayout) syntheticPortrait({
  int width = 640,
  int height = 480,
  double scale = 260,
}) {
  final cx = width / 2, cy = height / 2 + 10, s = scale;
  final img = RgbaBuffer(width, height);
  bool inEllipse(
    double x,
    double y,
    double ex,
    double ey,
    double rx,
    double ry,
  ) {
    final dx = (x - ex) / rx, dy = (y - ey) / ry;
    return dx * dx + dy * dy <= 1;
  }

  final re = (cx - 0.16 * s, cy - 0.06 * s);
  final le = (cx + 0.16 * s, cy - 0.06 * s);
  final mouth = (cx, cy + 0.26 * s);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final fx = x + 0.5, fy = y + 0.5;
      // Background: cool grey gradient.
      var r = 150 - y * 40 / height, g = 160 - y * 40 / height, b = 175.0;
      if (inEllipse(fx, fy, cx, cy - 0.12 * s, 0.46 * s, 0.56 * s)) {
        (r, g, b) = (60, 40, 28); // hair
      }
      if (fy > cy + 0.3 * s && (fx - cx).abs() < 0.17 * s) {
        (r, g, b) = (205, 150, 120); // neck
      }
      if (fy > cy + 0.62 * s) (r, g, b) = (70, 90, 130); // shirt
      if (inEllipse(fx, fy, cx, cy, 0.36 * s, 0.48 * s)) {
        final dx = (fx - cx) / (0.36 * s), dy = (fy - cy) / (0.48 * s);
        final shade = 1 - 0.18 * (dx * dx + dy * dy);
        (r, g, b) = (228 * shade, 176 * shade, 146 * shade);
        // Nose shadow down the middle.
        if ((fx - cx).abs() < 0.035 * s && fy > cy && fy < cy + 0.13 * s) {
          (r, g, b) = (r * 0.9, g * 0.88, b * 0.88);
        }
      }
      for (final e in [re, le]) {
        if (inEllipse(fx, fy, e.$1, e.$2 - 0.09 * s, 0.08 * s, 0.018 * s)) {
          (r, g, b) = (70, 48, 34); // brow
        }
        if (inEllipse(fx, fy, e.$1, e.$2, 0.075 * s, 0.035 * s)) {
          (r, g, b) = (240, 238, 232); // sclera
          if (inEllipse(fx, fy, e.$1, e.$2, 0.032 * s, 0.032 * s)) {
            (r, g, b) = (90, 60, 40); // iris
          }
          if (inEllipse(fx, fy, e.$1, e.$2, 0.013 * s, 0.013 * s)) {
            (r, g, b) = (15, 10, 10); // pupil
          }
        }
      }
      for (final side in [-1, 1]) {
        if (inEllipse(
          fx,
          fy,
          cx + side * 0.03 * s,
          cy + 0.14 * s,
          0.018 * s,
          0.01 * s,
        )) {
          (r, g, b) = (120, 70, 60); // nostril
        }
      }
      if (inEllipse(fx, fy, mouth.$1, mouth.$2, 0.11 * s, 0.03 * s)) {
        (r, g, b) = (185, 80, 90); // lips
        if ((fy - mouth.$2).abs() < 0.004 * s) (r, g, b) = (110, 40, 50);
      }
      img.setPixel(x, y, r.round(), g.round(), b.round());
    }
  }
  _blur(img, math.max(1, (s / 120).round()));
  return (
    img,
    (cx: cx, cy: cy, scale: s, rightEye: re, leftEye: le, mouth: mouth),
  );
}

void _blur(RgbaBuffer img, int radius) {
  for (var pass = 0; pass < 2; pass++) {
    final src = img.copy();
    for (var y = 0; y < img.height; y++) {
      for (var x = 0; x < img.width; x++) {
        var r = 0, g = 0, b = 0, n = 0;
        for (var dy = -radius; dy <= radius; dy++) {
          final yy = (y + dy).clamp(0, img.height - 1);
          for (var dx = -radius; dx <= radius; dx++) {
            final xx = (x + dx).clamp(0, img.width - 1);
            r += src.r(xx, yy);
            g += src.g(xx, yy);
            b += src.b(xx, yy);
            n++;
          }
        }
        img.setPixel(x, y, r ~/ n, g ~/ n, b ~/ n);
      }
    }
  }
}
