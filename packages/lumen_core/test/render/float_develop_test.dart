import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

/// Gray ramp on top, hue ring below (same scene as the 8-bit reference test).
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

/// A one-row gray ramp of encoded values from [from] to [to].
FloatBuffer _ramp(int n, double from, double to) {
  final b = FloatBuffer(n, 1);
  for (var x = 0; x < n; x++) {
    final v = from + (to - from) * x / (n - 1);
    b.setPixel(x, 0, v, v, v);
  }
  return b;
}

/// Distinct green levels of [b] inside columns [x0]..[x1].
int _levels(RgbaBuffer b, [int x0 = 0, int? x1]) =>
    {for (var x = x0; x < (x1 ?? b.width); x++) b.g(x, 0)}.length;

int _maxDiff(RgbaBuffer a, RgbaBuffer b) {
  var m = 0;
  for (var i = 0; i < a.data.length; i++) {
    m = math.max(m, (a.data[i] - b.data[i]).abs());
  }
  return m;
}

void main() {
  group('FloatBuffer', () {
    test('round-trips 8-bit pixels exactly', () {
      final scene = _scene(32, 16);
      final f = FloatBuffer.fromRgba(scene);
      expect(f.width, 32);
      expect(f.data[3], 1);
      expect(f.toRgba().data, scene.data);
    });

    test('toRgba clamps extended values', () {
      final f = FloatBuffer(2, 1)
        ..setPixel(0, 0, 4, -0.5, 0.5)
        ..setPixel(1, 0, 1, 0, 2);
      expect(f.toRgba().data, [255, 0, 128, 255, 255, 0, 255, 255]);
    });

    test('rejects a wrong data length', () {
      expect(() => FloatBuffer(2, 2, Float32List(3)), throwsArgumentError);
    });
  });

  group('extended sRGB', () {
    test('matches the clamped encode inside 0..1 and continues above', () {
      for (final x in [0.0, 0.001, 0.0031308, 0.18, 0.5, 1.0]) {
        expect(linearToSrgbExtended(x), closeTo(linearToSrgb(x), 1e-12));
      }
      expect(linearToSrgbExtended(-0.2), 0);
      final e = linearToSrgbExtended(4);
      expect(e, greaterThan(1.8));
      expect(srgbToLinear(e), closeTo(4, 1e-9));
    });

    test(
      'the highlight shoulder is identity below the knee, 1 at 2 - knee',
      () {
        const k = 0.86;
        expect(highlightShoulder(0.5, k), 0.5);
        expect(highlightShoulder(k, k), k);
        expect(highlightShoulder(2 - k, k), closeTo(1, 1e-12));
        expect(highlightShoulder(3, k), 1);
        // Monotone and C1 at the knee (slope 1).
        expect((highlightShoulder(k + 1e-4, k) - k) / 1e-4, closeTo(1, 1e-3));
        var prev = 0.0;
        for (var e = 0.0; e < 1.3; e += 0.01) {
          final s = highlightShoulder(e, k);
          expect(s, greaterThanOrEqualTo(prev));
          prev = s;
        }
        // Off: plain clamp.
        expect(highlightShoulder(1.4, 0), 1);
        expect(highlightShoulder(0.95, 0), 0.95);
      },
    );
  });

  group('renderReferenceFloat vs the 8-bit path', () {
    final scene = _scene(96, 64);
    final float = FloatBuffer.fromRgba(scene);
    final cases = <String, DevelopSettings>{
      'defaults': DevelopSettings.defaults,
      'exposure +1.3': DevelopSettings.defaults.withValue(P.exposure, 1.3),
      'exposure -2': DevelopSettings.defaults.withValue(P.exposure, -2),
      'tone': DevelopSettings.defaults
          .withValue(P.contrast, 40)
          .withValue(P.whites, -30)
          .withValue(P.blacks, 20),
      'spatial': DevelopSettings.defaults
          .withValue(P.highlights, -100)
          .withValue(P.shadows, 80)
          .withValue(P.clarity, 40)
          .withValue(P.dehaze, 30),
      'colour': DevelopSettings.defaults
          .withValue(P.temp, 20)
          .withValue(P.vibrance, 40)
          .withValue(P.saturation, -20)
          .withValue(P.texture, 50),
    };
    for (final e in cases.entries) {
      test('${e.key}: an 8-bit-equivalent float source gives the same '
          'bytes', () {
        final a = renderReference(scene, e.value);
        final b = renderReferenceFloat(float, e.value).toRgba();
        expect((b.width, b.height), (a.width, a.height));
        expect(_maxDiff(a, b), 0);
      });
    }

    test('geometry and the float aux maps follow the 8-bit ones', () {
      final s = DevelopSettings.defaults
          .withValue(P.shadows, 60)
          .copyWith(
            geometry: const Geometry(
              crop: CropRect(0.1, 0.2, 0.9, 0.8),
              angle: 7,
              rotate90: 1,
              flipH: true,
            ),
          );
      final a = renderReference(scene, s);
      final b = renderReferenceFloat(float, s).toRgba();
      expect(_maxDiff(a, b), lessThanOrEqualTo(1));
    });
  });

  group('highlight headroom', () {
    // 1024 encoded levels from display white up to 4x linear white.
    final top = linearToSrgbExtended(4);
    final hot = _ramp(1024, 1, top);

    test('without an edit everything above white clips (as in 8 bits)', () {
      final out = renderReferenceFloat(hot, DevelopSettings.defaults).toRgba();
      expect(_levels(out), 1);
      expect(out.g(0, 0), 255);
    });

    test('exposure -2 EV recovers the ramp without banding', () {
      final out = renderReferenceFloat(
        hot,
        DevelopSettings.defaults.withValue(P.exposure, -2),
      ).toRgba();
      // 4x white lands on white, 1x white on 0.25 linear = 137/255:
      // every output level in between is hit, in order.
      expect(out.g(1023, 0), 255);
      expect(out.g(0, 0), inInclusiveRange(136, 138));
      expect(_levels(out), 255 - out.g(0, 0) + 1);
      for (var x = 1; x < 1024; x++) {
        expect(out.g(x, 0), greaterThanOrEqualTo(out.g(x - 1, 0)));
      }
    });

    test('the same edit on the clipped 8-bit rendition recovers nothing', () {
      final clipped = hot.toRgba();
      final out = renderReference(
        clipped,
        DevelopSettings.defaults.withValue(P.exposure, -2),
      );
      expect(_levels(out), 1);
    });

    test('Highlights -100 brings a source with headroom back below white', () {
      // A wide smooth ramp so the guided base follows it.
      final wide = FloatBuffer(512, 8);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 512; x++) {
          final v = 0.6 + (top - 0.6) * x / 511;
          wide.setPixel(x, y, v, v, v);
        }
      }
      final s = DevelopSettings.defaults.withValue(P.highlights, -100);
      final plain = renderReferenceFloat(wide, s).toRgba();
      final raw = renderReferenceFloat(
        wide,
        s,
        profile: HbdProfile.rawExtended,
      ).toRgba();
      int levels(RgbaBuffer b) =>
          {for (var x = 256; x < 512; x++) b.g(x, 4)}.length;
      // 8-bit rendition of the same ramp: the top half is one flat value.
      final eight = renderReference(wide.toRgba(), s);
      expect(levels(eight), lessThanOrEqualTo(2));
      // Float source: detail above white comes back.
      expect(levels(plain), greaterThan(20));
      // With the RAW profile the very top (4x white) is back too.
      expect(levels(raw), greaterThan(40));
      expect(raw.g(511, 4), lessThan(255));
      for (var x = 1; x < 512; x++) {
        expect(raw.g(x, 4), greaterThanOrEqualTo(raw.g(x - 1, 4) - 1));
      }
    });

    test('the RAW shoulder rolls highlights off instead of clipping', () {
      final s = DevelopSettings.defaults;
      final e = FloatBuffer(3, 1)
        ..setPixel(0, 0, 0.4, 0.4, 0.4)
        ..setPixel(1, 0, 1, 1, 1)
        ..setPixel(2, 0, 1.2, 1.2, 1.2);
      final out = renderReferenceFloat(
        e,
        s,
        profile: HbdProfile.rawExtended,
      ).toRgba();
      expect(out.g(0, 0), 102); // below the knee: untouched
      // Encoded 1.0 sits inside the shoulder: 0.86 + 0.14 * (2t - t^2), t = .5
      expect(out.g(1, 0), (255 * (0.86 + 0.14 * 0.75)).round());
      expect(out.g(2, 0), 255);
    });
  });

  group('shadow precision', () {
    test('+3 EV from a float ramp keeps far more levels than 8 bits', () {
      // The darkest 2 % of the encoded range: 6 levels in 8 bits.
      final dark = _ramp(1024, 0, 0.02);
      final s = DevelopSettings.defaults.withValue(P.exposure, 3);
      final fromFloat = renderReferenceFloat(dark, s).toRgba();
      final fromBytes = renderReference(dark.toRgba(), s);
      final lf = _levels(fromFloat), lb = _levels(fromBytes);
      expect(lb, lessThanOrEqualTo(7));
      expect(lf, greaterThan(4 * lb));
      // No gaps: consecutive output levels differ by at most one step.
      for (var x = 1; x < 1024; x++) {
        final d = fromFloat.g(x, 0) - fromFloat.g(x - 1, 0);
        expect(d, inInclusiveRange(0, 1));
      }
    });
  });

  group('source window', () {
    test('a tile developed from a window equals the full render', () {
      final scene = _scene(96, 64);
      final float = FloatBuffer.fromRgba(scene);
      final s = DevelopSettings.defaults
          .withValue(P.exposure, 0.5)
          .withValue(P.texture, 40)
          .withValue(P.clarity, 20);
      final aux = AuxMaps.computeFloat(float);
      final full = renderReferenceFloat(float, s, aux: aux);
      // Output tile 40..72 x 16..48 from the source window 36..76 x 12..52.
      const wx = 36, wy = 12, ww = 40, wh = 40;
      final win = FloatBuffer(ww, wh);
      for (var y = 0; y < wh; y++) {
        for (var x = 0; x < ww; x++) {
          final o = ((wy + y) * 96 + wx + x) * 4;
          win.setPixel(
            x,
            y,
            float.data[o],
            float.data[o + 1],
            float.data[o + 2],
          );
        }
      }
      final tile = renderReferenceFloat(
        win,
        s,
        aux: aux,
        window: const SourceWindow(x: wx, y: wy, fullWidth: 96, fullHeight: 64),
        tile: (x: 40, y: 16, width: 32, height: 32),
      );
      expect((tile.width, tile.height), (32, 32));
      for (var y = 0; y < 32; y++) {
        for (var x = 0; x < 32; x++) {
          for (var c = 0; c < 3; c++) {
            expect(
              tile.data[(y * 32 + x) * 4 + c],
              closeTo(full.data[((y + 16) * 96 + x + 40) * 4 + c], 1e-6),
            );
          }
        }
      }
    });
  });

  group('AuxMaps.computeFloat', () {
    test('equals the 8-bit maps for 8-bit-equivalent input', () {
      final scene = _scene(96, 64);
      final a = AuxMaps.compute(scene);
      final b = AuxMaps.computeFloat(FloatBuffer.fromRgba(scene));
      expect(b.auxA, a.auxA);
      expect(b.auxB, a.auxB);
      expect(b.airlight.r, closeTo(a.airlight.r, 1e-6));
    });

    test('represents luminance above white', () {
      final hot = FloatBuffer(64, 64);
      for (var i = 0; i < 64 * 64; i++) {
        hot.data
          ..[i * 4] = 2
          ..[i * 4 + 1] = 2
          ..[i * 4 + 2] = 2
          ..[i * 4 + 3] = 1;
      }
      final f = AuxMaps.computeFloat(hot).sample(0.5, 0.5);
      final c = AuxMaps.compute(hot.toRgba()).sample(0.5, 0.5);
      // Clipped 8-bit: log2(1) → 14/16. Float: log2(4.95) more.
      expect(c.baseMid, closeTo(14 / 16, 1e-3));
      expect(f.baseMid, greaterThan(c.baseMid + 0.1));
    });

    test('proxyFloat averages areas and never upscales', () {
      final src = FloatBuffer(8, 4);
      for (var i = 0; i < 32; i++) {
        src.setPixel(i % 8, i ~/ 8, (i % 8) < 4 ? 2 : 0, 1, 0.5);
      }
      expect(identical(AuxMaps.proxyFloat(src, longEdge: 8), src), isTrue);
      final p = AuxMaps.proxyFloat(src, longEdge: 2);
      expect((p.width, p.height), (2, 1));
      expect(p.data.sublist(0, 4), [2, 1, 0.5, 1]);
      expect(p.data.sublist(4, 8), [0, 1, 0.5, 1]);
    });
  });
}
