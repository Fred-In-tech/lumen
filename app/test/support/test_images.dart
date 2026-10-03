import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen_core/lumen_core.dart';

/// Synthetic scenes and readback helpers for the shader engine tests.
/// Deterministic (seeded), no downloads.

Future<ui.Image> imageFromBuffer(RgbaBuffer b) =>
    uploadRgba(b.data, b.width, b.height);

Future<RgbaBuffer> bufferFromImage(ui.Image img) async =>
    RgbaBuffer(img.width, img.height, await readRgba(img));

/// Max and mean absolute channel difference (RGB only), in 8-bit units.
({int max, double mean}) diffStats(RgbaBuffer a, RgbaBuffer b) {
  if (a.width != b.width || a.height != b.height) {
    throw ArgumentError(
      'size ${a.width}x${a.height} vs ${b.width}x${b.height}',
    );
  }
  var mx = 0, sum = 0, n = 0;
  for (var i = 0; i < a.data.length; i++) {
    if (i % 4 == 3) continue;
    final d = (a.data[i] - b.data[i]).abs();
    if (d > mx) mx = d;
    sum += d;
    n++;
  }
  return (max: mx, mean: sum / n);
}

int _c(num v) => v.round().clamp(0, 255);

abstract final class TestScenes {
  /// Gray ramp (top half) + saturated hue ring (bottom half).
  static RgbaBuffer rampAndHues(int w, int h) {
    final b = RgbaBuffer(w, h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (y < h ~/ 2) {
          final v = _c(x * 255 / (w - 1));
          b.setPixel(x, y, v, v, v);
        } else {
          final (r, g, bb) = _hue(x / w, 0.85, 0.9 - 0.5 * (y - h / 2) / h);
          b.setPixel(x, y, r, g, bb);
        }
      }
    }
    return b;
  }

  /// Low-key interior: dark gradient with a bright window.
  static RgbaBuffer darkInterior(int w, int h) {
    final b = RgbaBuffer(w, h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final window = x > w * 0.6 && x < w * 0.8 && y < h * 0.4;
        final v = window ? 235 : _c(10 + 50 * x / w + 20 * y / h);
        b.setPixel(x, y, v, _c(v * 0.95), _c(v * 0.85));
      }
    }
    return b;
  }

  /// Warm skin oval on a blue sky with foliage.
  static RgbaBuffer portrait(int w, int h) {
    final b = RgbaBuffer(w, h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = (x - w / 2) / (w * 0.2), dy = (y - h / 2) / (h * 0.3);
        if (dx * dx + dy * dy < 1) {
          b.setPixel(x, y, 224, 172, 140);
        } else if (y < h / 2) {
          b.setPixel(x, y, _c(90 + y * 60 / h), _c(150 + y * 40 / h), 230);
        } else {
          b.setPixel(x, y, 60, _c(120 + 40 * math.sin(x / 5)), 50);
        }
      }
    }
    return b;
  }

  /// Contrast-compressed landscape under an airlight veil.
  static RgbaBuffer hazy(int w, int h) {
    final b = RgbaBuffer(w, h);
    for (var y = 0; y < h; y++) {
      final t = y / h;
      for (var x = 0; x < w; x++) {
        final checker = ((x ~/ 8) + (y ~/ 8)).isEven ? 25.0 : 0.0;
        final v = 200 - 60 * t + checker * t;
        b.setPixel(x, y, _c(v - 10), _c(v), _c(v + 12));
      }
    }
    return b;
  }

  /// Mid-gray with seeded Gaussian noise of sigma [sigma] (8-bit units).
  static RgbaBuffer noisyFlat(int w, int h, {double sigma = 6, int seed = 1}) {
    final rnd = math.Random(seed);
    double gauss() {
      final u1 = math.max(rnd.nextDouble(), 1e-12), u2 = rnd.nextDouble();
      return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    }

    final b = RgbaBuffer(w, h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = _c(128 + sigma * gauss());
        b.setPixel(x, y, v, v, v);
      }
    }
    return b;
  }

  /// Seeded random texture (for local-contrast tests).
  static RgbaBuffer texture(int w, int h, {int seed = 3}) {
    final rnd = math.Random(seed);
    final b = RgbaBuffer(w, h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = 90 + rnd.nextInt(60);
        b.setPixel(x, y, v, _c(v * 1.05), _c(v * 0.9));
      }
    }
    return b;
  }

  /// Four distinct corner colors on gray (geometry tests).
  static RgbaBuffer markerCorners(int w, int h) {
    final b = RgbaBuffer.filled(w, h, 128, 128, 128);
    final q = math.max(1, w ~/ 8), r = math.max(1, h ~/ 8);
    void fill(int x0, int y0, int cr, int cg, int cb) {
      for (var y = y0; y < y0 + r; y++) {
        for (var x = x0; x < x0 + q; x++) {
          b.setPixel(x, y, cr, cg, cb);
        }
      }
    }

    fill(0, 0, 255, 0, 0); // top-left red
    fill(w - q, 0, 0, 255, 0); // top-right green
    fill(0, h - r, 0, 0, 255); // bottom-left blue
    fill(w - q, h - r, 255, 255, 0); // bottom-right yellow
    return b;
  }

  /// The six parity scenes.
  static List<RgbaBuffer> parityScenes(int w, int h) => [
    rampAndHues(w, h),
    darkInterior(w, h),
    portrait(w, h),
    hazy(w, h),
    texture(w, h),
    markerCorners(w, h),
  ];
}

(int, int, int) _hue(double t, double s, double v) {
  final h = t * 6;
  final i = h.floor() % 6, f = h - h.floor();
  final p = v * (1 - s), q = v * (1 - s * f), u = v * (1 - s * (1 - f));
  final (r, g, b) = switch (i) {
    0 => (v, u, p),
    1 => (q, v, p),
    2 => (p, v, u),
    3 => (p, q, v),
    4 => (u, p, v),
    _ => (v, p, q),
  };
  return (_c(r * 255), _c(g * 255), _c(b * 255));
}
