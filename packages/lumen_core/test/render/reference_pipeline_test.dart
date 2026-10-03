import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

/// Deterministic test scene: horizontal gray ramp on top, hue ring below.
RgbaBuffer _scene(int w, int h) {
  final b = RgbaBuffer(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (y < h ~/ 2) {
        final v = (x * 255 / (w - 1)).round();
        b.setPixel(x, y, v, v, v);
      } else {
        final hue = x / w * 6;
        final i = hue.floor(), f = hue - i;
        final q = ((1 - f) * 200).round() + 30, t = (f * 200).round() + 30;
        const hi = 230, lo = 30;
        final (r, g, bb) = switch (i % 6) {
          0 => (hi, t, lo),
          1 => (q, hi, lo),
          2 => (lo, hi, t),
          3 => (lo, q, hi),
          4 => (t, lo, hi),
          _ => (hi, lo, q),
        };
        b.setPixel(x, y, r, g, bb);
      }
    }
  }
  return b;
}

double _meanLuma(RgbaBuffer b, {int x0 = 0, int y0 = 0, int? x1, int? y1}) {
  var s = 0.0, n = 0;
  for (var y = y0; y < (y1 ?? b.height); y++) {
    for (var x = x0; x < (x1 ?? b.width); x++) {
      s += 0.2126 * b.r(x, y) + 0.7152 * b.g(x, y) + 0.0722 * b.b(x, y);
      n++;
    }
  }
  return s / n;
}

void main() {
  final scene = _scene(96, 64);

  group('renderReference point ops', () {
    test('identity reproduces the input within 1/255', () {
      final out = renderReference(scene, DevelopSettings.defaults);
      expect(out.width, scene.width);
      for (var i = 0; i < out.data.length; i++) {
        expect((out.data[i] - scene.data[i]).abs(), lessThanOrEqualTo(1));
      }
    });

    test('exposure +1 maps 128 to 176', () {
      final out = renderReference(
        RgbaBuffer.filled(4, 4, 128, 128, 128),
        DevelopSettings.defaults.withValue(P.exposure, 1),
      );
      expect([out.r(1, 1), out.g(1, 1), out.b(1, 1)], [176, 176, 176]);
    });

    test('B&W treatment gives R = G = B', () {
      final out = renderReference(
        scene,
        DevelopSettings.defaults
            .withValue(P.bw(HslBand.blue), 40)
            .copyWith(treatment: Treatment.bw),
      );
      for (var y = 0; y < out.height; y++) {
        for (var x = 0; x < out.width; x++) {
          expect((out.r(x, y) - out.g(x, y)).abs(), lessThanOrEqualTo(1));
          expect((out.g(x, y) - out.b(x, y)).abs(), lessThanOrEqualTo(1));
        }
      }
    });

    test('positive temp warms a neutral gray', () {
      final out = renderReference(
        RgbaBuffer.filled(2, 2, 128, 128, 128),
        DevelopSettings.defaults.withValue(P.temp, 50),
      );
      expect(out.r(0, 0), greaterThan(out.b(0, 0) + 10));
    });

    test('contrast darkens shadows and brightens highlights', () {
      final s = DevelopSettings.defaults.withValue(P.contrast, 60);
      final out = renderReference(scene, s);
      expect(out.r(15, 0), lessThan(scene.r(15, 0)));
      expect(out.r(85, 0), greaterThan(scene.r(85, 0)));
    });

    test('saturation -100 removes color, HSL blue sat touches blue only', () {
      final gray = renderReference(
        scene,
        DevelopSettings.defaults.withValue(P.saturation, -100),
      );
      expect((gray.r(5, 50) - gray.b(5, 50)).abs(), lessThanOrEqualTo(2));
      final blueOnly = renderReference(
        scene,
        DevelopSettings.defaults.withValue(
          P.hsl(HslBand.blue, HslChannel.sat),
          -100,
        ),
      );
      // A red pixel is untouched.
      expect(blueOnly.r(1, 50), scene.r(1, 50));
      expect(blueOnly.g(1, 50), scene.g(1, 50));
    });

    test('negative vignette darkens corners, not the center', () {
      final flat = RgbaBuffer.filled(64, 48, 150, 150, 150);
      final out = renderReference(
        flat,
        DevelopSettings.defaults.withValue(P.vignetteAmount, -80),
      );
      expect(out.r(0, 0), lessThan(120));
      expect(out.r(32, 24), 150);
    });

    test('clipping overlay paints clipped pixels red and crushed blue', () {
      final b = RgbaBuffer.filled(2, 1, 255, 255, 255)..setPixel(1, 0, 0, 0, 0);
      final out = renderReference(
        b,
        DevelopSettings.defaults,
        showClipping: true,
      );
      expect([out.r(0, 0), out.g(0, 0), out.b(0, 0)], [255, 0, 0]);
      expect([out.r(1, 0), out.g(1, 0), out.b(1, 0)], [0, 0, 255]);
    });
  });

  group('renderReference geometry', () {
    test('rotate90 swaps size and moves corners', () {
      final b = RgbaBuffer.filled(4, 2, 0, 0, 0)..setPixel(0, 0, 255, 0, 0);
      final out = renderReference(
        b,
        DevelopSettings.defaults.copyWith(
          geometry: Geometry.none.copyWith(rotate90: 1),
        ),
      );
      expect([out.width, out.height], [2, 4]);
      // Clockwise: source top-left lands at output top-right.
      expect(out.r(1, 0), 255);
    });

    test('crop produces the cropped region', () {
      final out = renderReference(
        scene,
        DevelopSettings.defaults.copyWith(
          geometry: Geometry.none.copyWith(
            crop: const CropRect(0.5, 0, 1, 0.5),
          ),
        ),
      );
      expect([out.width, out.height], [48, 32]);
      expect((out.r(0, 0) - scene.r(48, 0)).abs(), lessThanOrEqualTo(1));
    });
  });

  group('renderReference spatial ops', () {
    test('shadows +100 lifts the dark end, keeps highlights', () {
      final out = renderReference(
        scene,
        DevelopSettings.defaults.withValue(P.shadows, 100),
      );
      expect(
        _meanLuma(out, x1: 20, y1: 32),
        greaterThan(_meanLuma(scene, x1: 20, y1: 32) + 5),
      );
      expect(
        (_meanLuma(out, x0: 90, y1: 32) - _meanLuma(scene, x0: 90, y1: 32))
            .abs(),
        lessThan(4),
      );
    });

    test('highlights -100 darkens the bright end', () {
      final out = renderReference(
        scene,
        DevelopSettings.defaults.withValue(P.highlights, -100),
      );
      expect(
        _meanLuma(out, x0: 80, y1: 32),
        lessThan(_meanLuma(scene, x0: 80, y1: 32) - 5),
      );
    });

    test('dehaze raises contrast of a hazy scene', () {
      final hazy = RgbaBuffer(64, 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final v = 150 + ((x ~/ 8 + y ~/ 8).isEven ? 30 : 0);
          hazy.setPixel(x, y, v, v + 5, v + 10);
        }
      }
      for (var x = 0; x < 64; x++) {
        hazy.setPixel(x, 0, 235, 240, 245);
      }
      double spread(RgbaBuffer b) =>
          (b.r(4, 12) - b.r(12, 12)).abs().toDouble();
      final out = renderReference(
        hazy,
        DevelopSettings.defaults.withValue(P.dehaze, 80),
      );
      expect(spread(out), greaterThan(spread(hazy)));
    });

    test('clarity raises local contrast, texture too', () {
      final tex = RgbaBuffer(64, 64);
      final rnd = math.Random(3);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final v = 110 + rnd.nextInt(30);
          tex.setPixel(x, y, v, v, v);
        }
      }
      double sigma(RgbaBuffer b) {
        final m = _meanLuma(b);
        var s = 0.0;
        for (var y = 0; y < b.height; y++) {
          for (var x = 0; x < b.width; x++) {
            s += math.pow(b.r(x, y) - m, 2);
          }
        }
        return math.sqrt(s / (b.width * b.height));
      }

      final base = sigma(tex);
      final cl = renderReference(
        tex,
        DevelopSettings.defaults.withValue(P.clarity, 100),
      );
      final tx = renderReference(
        tex,
        DevelopSettings.defaults.withValue(P.texture, 100),
      );
      expect(sigma(cl), greaterThan(base * 1.05));
      expect(sigma(tx), greaterThan(base * 1.05));
    });

    test('extreme slider combos never flood to 0/255 or NaN', () {
      final s = DevelopSettings.defaults.withValues({
        P.exposure: 5,
        P.dehaze: 100,
        P.shadows: 100,
        P.highlights: -100,
        P.clarity: 100,
        P.texture: 100,
        P.contrast: 100,
        P.vibrance: 100,
        P.saturation: 100,
      });
      final out = renderReference(scene, s);
      expect(out.data.every((v) => v >= 0 && v <= 255), isTrue);
    });

    test('accepts precomputed aux maps (same result)', () {
      final s = DevelopSettings.defaults.withValue(P.shadows, 60);
      final aux = AuxMaps.compute(AuxMaps.proxy(scene));
      expect(
        renderReference(scene, s, aux: aux).data,
        renderReference(scene, s).data,
      );
    });

    test('renders a 512 px proxy fast enough for the auto-tone solver', () {
      final big = _scene(512, 384);
      final s = DevelopSettings.defaults.withValues({
        P.exposure: 0.4,
        P.contrast: 20,
        P.shadows: 30,
        P.vibrance: 15,
      });
      final aux = AuxMaps.compute(big);
      renderReference(big, s, aux: aux); // warm-up (JIT)
      final sw = Stopwatch()..start();
      renderReference(big, s, aux: aux);
      // Budget is < 150 ms AOT; the JIT test runner gets headroom.
      expect(sw.elapsedMilliseconds, lessThan(400));
    });
  });
}
