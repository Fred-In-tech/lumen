// Synthetic test images and error metrics for the inpaint tests.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// Smooth color ramp (a linear function of x and y per channel).
FloatImage gradientImage(int w, int h) {
  final img = FloatImage(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      img.set(x, y, 0, 40 + 150 * x / w);
      img.set(x, y, 1, 60 + 120 * y / h);
      img.set(x, y, 2, 100 + 60 * (x + y) / (w + h));
    }
  }
  return img;
}

/// Deterministic value noise in −1..1 from integer coordinates.
double hashNoise(int x, int y, [int seed = 7]) {
  var n = x * 374761393 + y * 668265263 + seed * 2147483647;
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return ((n & 0xffff) / 0xffff) * 2 - 1;
}

/// Fine grain texture on a slow color drift (sinusoids + per-pixel noise).
FloatImage grainTexture(int w, int h, {double grain = 10}) {
  final img = FloatImage(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final base =
          110 + 30 * math.sin(x * 0.11) + 20 * math.cos(y * 0.07 + x * 0.03);
      final n = grain * hashNoise(x, y);
      img.set(x, y, 0, base + n);
      img.set(x, y, 1, base * 0.9 + 15 + n);
      img.set(x, y, 2, base * 0.7 + 30 + n);
    }
  }
  return img;
}

/// Running-bond bricks: [bw]×[bh] bricks, 2 px mortar, alternate rows
/// shifted by half a brick; each brick gets a slightly different shade.
FloatImage brickImage(int w, int h, {int bw = 24, int bh = 12}) {
  final img = FloatImage(w, h);
  for (var y = 0; y < h; y++) {
    final row = y ~/ bh;
    final shift = row.isOdd ? bw ~/ 2 : 0;
    for (var x = 0; x < w; x++) {
      final col = (x + shift) ~/ bw;
      final mortar = y % bh < 2 || (x + shift) % bw < 2;
      final shade = mortar ? 0.0 : 6 * hashNoise(col, row, 3);
      final r = mortar ? 200.0 : 150 + shade;
      final g = mortar ? 195.0 : 70 + shade;
      final b = mortar ? 185.0 : 50 + shade;
      img.set(x, y, 0, r);
      img.set(x, y, 1, g);
      img.set(x, y, 2, b);
    }
  }
  return img;
}

/// Hole = disc of radius [r] at ([cx], [cy]).
Uint8List discHole(int w, int h, double cx, double cy, double r) {
  final m = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      if (dx * dx + dy * dy <= r * r) m[y * w + x] = 255;
    }
  }
  return m;
}

/// Hole = axis-aligned rectangle.
Uint8List rectHole(int w, int h, int x0, int y0, int rw, int rh) {
  final m = Uint8List(w * h);
  for (var y = y0; y < y0 + rh; y++) {
    for (var x = x0; x < x0 + rw; x++) {
      m[y * w + x] = 255;
    }
  }
  return m;
}

/// Copy of [img] with the hole painted a flat "object" color.
FloatImage withObject(FloatImage img, Uint8List hole, [double v = 0]) {
  final out = img.copy();
  for (var i = 0; i < hole.length; i++) {
    if (hole[i] == 0) continue;
    for (var c = 0; c < out.channels; c++) {
      out.data[i * out.channels + c] = v;
    }
  }
  return out;
}

/// Mean absolute error over the hole pixels (all channels).
double holeMae(FloatImage a, FloatImage b, Uint8List hole) {
  var sum = 0.0, n = 0;
  for (var i = 0; i < hole.length; i++) {
    if (hole[i] == 0) continue;
    for (var c = 0; c < a.channels; c++) {
      sum += (a.data[i * a.channels + c] - b.data[i * b.channels + c]).abs();
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

/// Max absolute error over the hole pixels.
double holeMaxErr(FloatImage a, FloatImage b, Uint8List hole) {
  var m = 0.0;
  for (var i = 0; i < hole.length; i++) {
    if (hole[i] == 0) continue;
    for (var c = 0; c < a.channels; c++) {
      m = math.max(
        m,
        (a.data[i * a.channels + c] - b.data[i * b.channels + c]).abs(),
      );
    }
  }
  return m;
}

/// The mean of the known pixels written into the hole (naive baseline).
FloatImage meanFill(FloatImage img, Uint8List hole) {
  final out = img.copy();
  final mean = List<double>.filled(img.channels, 0);
  var n = 0;
  for (var i = 0; i < hole.length; i++) {
    if (hole[i] != 0) continue;
    for (var c = 0; c < img.channels; c++) {
      mean[c] += img.data[i * img.channels + c];
    }
    n++;
  }
  for (var i = 0; i < hole.length; i++) {
    if (hole[i] == 0) continue;
    for (var c = 0; c < img.channels; c++) {
      out.data[i * img.channels + c] = mean[c] / n;
    }
  }
  return out;
}

/// Standard deviation of the Laplacian over the hole: a texture measure.
double holeLaplacianStd(FloatImage img, Uint8List hole) {
  final vals = <double>[];
  for (var y = 1; y < img.height - 1; y++) {
    for (var x = 1; x < img.width - 1; x++) {
      if (hole[y * img.width + x] == 0) continue;
      final l =
          4 * img.at(x, y, 1) -
          img.at(x - 1, y, 1) -
          img.at(x + 1, y, 1) -
          img.at(x, y - 1, 1) -
          img.at(x, y + 1, 1);
      vals.add(l);
    }
  }
  final mean = vals.fold(0.0, (a, b) => a + b) / vals.length;
  final v = vals.fold(0.0, (a, b) => a + (b - mean) * (b - mean)) / vals.length;
  return math.sqrt(v);
}
