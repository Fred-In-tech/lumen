import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'engine_harness.dart';

/// PLAN.md P2.6 (spatial behavior) and P2.7 (geometry) on the GPU.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double meanLuma(RgbaBuffer b, {int x0 = 0, int y0 = 0, int? x1, int? y1}) {
    var s = 0.0, n = 0;
    for (var y = y0; y < (y1 ?? b.height); y++) {
      for (var x = x0; x < (x1 ?? b.width); x++) {
        s += 0.2126 * b.r(x, y) + 0.7152 * b.g(x, y) + 0.0722 * b.b(x, y);
        n++;
      }
    }
    return s / n;
  }

  double lumaPercentile(RgbaBuffer b, double q) {
    final v = <double>[
      for (var y = 0; y < b.height; y++)
        for (var x = 0; x < b.width; x++)
          0.2126 * b.r(x, y) + 0.7152 * b.g(x, y) + 0.0722 * b.b(x, y),
    ]..sort();
    return v[(q * (v.length - 1)).round()];
  }

  double sigma(RgbaBuffer b) {
    final m = meanLuma(b);
    var s = 0.0;
    for (var y = 0; y < b.height; y++) {
      for (var x = 0; x < b.width; x++) {
        final l = 0.2126 * b.r(x, y) + 0.7152 * b.g(x, y) + 0.0722 * b.b(x, y);
        s += (l - m) * (l - m);
      }
    }
    return math.sqrt(s / (b.width * b.height));
  }

  group('spatial ops', () {
    test(
      'hazy scene: dehaze raises contrast of the far (top) region',
      () async {
        final hazy = TestScenes.hazy(128, 96);
        final out = await gpuRender(
          hazy,
          DevelopSettings.defaults.withValue(P.dehaze, 70),
        );
        double farContrast(RgbaBuffer b) {
          final top = RgbaBuffer(
            b.width,
            32,
            b.data.sublist(0, b.width * 32 * 4),
          );
          return sigma(top);
        }

        expect(farContrast(out), greaterThan(farContrast(hazy) * 1.2));
      },
    );

    test('shadows +100 lifts P10 luma', () async {
      final dark = TestScenes.darkInterior(128, 96);
      final out = await gpuRender(
        dark,
        DevelopSettings.defaults.withValue(P.shadows, 100),
      );
      expect(
        lumaPercentile(out, 0.1),
        greaterThan(lumaPercentile(dark, 0.1) + 8),
      );
    });

    test('highlights -100 pulls down the bright window', () async {
      final dark = TestScenes.darkInterior(128, 96);
      final out = await gpuRender(
        dark,
        DevelopSettings.defaults.withValue(P.highlights, -100),
      );
      expect(
        meanLuma(out, x0: 80, x1: 100, y1: 35),
        lessThan(meanLuma(dark, x0: 80, x1: 100, y1: 35) - 10),
      );
    });

    test('clarity and texture raise local sigma', () async {
      final tex = TestScenes.texture(128, 96);
      final base = sigma(tex);
      final cl = await gpuRender(
        tex,
        DevelopSettings.defaults.withValue(P.clarity, 100),
      );
      final tx = await gpuRender(
        tex,
        DevelopSettings.defaults.withValue(P.texture, 100),
      );
      expect(sigma(cl), greaterThan(base * 1.05));
      expect(sigma(tx), greaterThan(base * 1.05));
    });

    test(
      'extreme slider combos: no 0/255 floods, output stays finite',
      () async {
        final scene = TestScenes.portrait(128, 96);
        for (final sign in [1.0, -1.0]) {
          final s = DevelopSettings.defaults.withValues({
            P.exposure: 3 * sign,
            P.dehaze: 100 * sign,
            P.shadows: 100 * sign,
            P.highlights: -100 * sign,
            P.clarity: 100 * sign,
            P.texture: 100 * sign,
            P.contrast: 100 * sign,
            P.vibrance: 100 * sign,
            P.saturation: 100 * sign,
          });
          final out = await gpuRender(scene, s);
          var black = 0, white = 0;
          for (var i = 0; i < out.data.length; i += 4) {
            final m = math.max(
              out.data[i],
              math.max(out.data[i + 1], out.data[i + 2]),
            );
            if (m == 0) black++;
            if (out.data[i] == 255 &&
                out.data[i + 1] == 255 &&
                out.data[i + 2] == 255) {
              white++;
            }
            expect(out.data[i + 3], 255);
          }
          final n = out.width * out.height;
          expect(black / n, lessThan(0.9), reason: 'sign $sign black flood');
          expect(white / n, lessThan(0.9), reason: 'sign $sign white flood');
        }
      },
    );
  });

  group('geometry (marker corners: R TL, G TR, B BL, Y BR)', () {
    final marker = TestScenes.markerCorners(64, 48);

    void expectRgb(RgbaBuffer b, int x, int y, (int, int, int) want) {
      final got = [b.r(x, y), b.g(x, y), b.b(x, y)];
      final w = [want.$1, want.$2, want.$3];
      for (var i = 0; i < 3; i++) {
        expect(
          (got[i] - w[i]).abs(),
          lessThanOrEqualTo(1),
          reason: '($x,$y) $got vs $w',
        );
      }
    }

    Future<RgbaBuffer> render(Geometry g) =>
        gpuRender(marker, DevelopSettings.defaults.copyWith(geometry: g));

    test('rotate90 clockwise moves top-left red to top-right', () async {
      final out = await render(Geometry.none.copyWith(rotate90: 1));
      expect([out.width, out.height], [48, 64]);
      expectRgb(out, 47, 0, (255, 0, 0));
      expectRgb(out, 0, 0, (0, 0, 255));
    });

    test('rotate 180 and 270', () async {
      final r2 = await render(Geometry.none.copyWith(rotate90: 2));
      expectRgb(r2, 63, 47, (255, 0, 0));
      final r3 = await render(Geometry.none.copyWith(rotate90: 3));
      expectRgb(r3, 0, 63, (255, 0, 0));
    });

    test('flipH and flipV', () async {
      final h = await render(Geometry.none.copyWith(flipH: true));
      expectRgb(h, 63, 0, (255, 0, 0));
      final v = await render(Geometry.none.copyWith(flipV: true));
      expectRgb(v, 0, 47, (255, 0, 0));
    });

    test('crop keeps only the bottom-right quadrant', () async {
      final out = await render(
        Geometry.none.copyWith(crop: const CropRect(0.5, 0.5, 1, 1)),
      );
      expect([out.width, out.height], [32, 24]);
      expectRgb(out, 31, 23, (255, 255, 0));
      expectRgb(out, 0, 0, (128, 128, 128));
    });

    test('straighten matches the CPU reference geometry', () async {
      final s = DevelopSettings.defaults.copyWith(
        geometry: Geometry.none.copyWith(
          angle: 7,
          crop: const CropRect(0.1, 0.1, 0.9, 0.9),
        ),
      );
      final gpu = await gpuRender(marker, s);
      final cpu = renderReference(marker, s);
      final d = diffStats(gpu, cpu);
      expect(d.mean, lessThan(1.5));
    });

    test('pixels outside the source are transparent black', () async {
      final out = await render(Geometry.none.copyWith(angle: 30));
      expect(out.data.sublist(0, 4), [0, 0, 0, 0]);
    });
  });

  test('scale 0.5 renders a half-size frame (drag preview)', () async {
    final out = await gpuRender(
      TestScenes.rampAndHues(128, 96),
      DevelopSettings.defaults,
      scale: 0.5,
    );
    expect([out.width, out.height], [64, 48]);
  });
}
