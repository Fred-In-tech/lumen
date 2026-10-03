import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

double _log2(double x) => math.log(x) / math.ln2;

void main() {
  group('SceneRandom', () {
    test('is deterministic per seed and uniform in [0,1)', () {
      final a = SceneRandom(42), b = SceneRandom(42), c = SceneRandom(7);
      final xs = [for (var i = 0; i < 1000; i++) a.nextDouble()];
      final ys = [for (var i = 0; i < 1000; i++) b.nextDouble()];
      expect(xs, ys);
      expect(c.nextDouble(), isNot(xs.first));
      expect(xs.every((x) => x >= 0 && x < 1), isTrue);
      final mean = xs.reduce((p, q) => p + q) / xs.length;
      expect(mean, closeTo(0.5, 0.05));
    });

    test('gaussian has roughly unit variance', () {
      final r = SceneRandom(3);
      final xs = [for (var i = 0; i < 4000; i++) r.nextGaussian()];
      final mean = xs.reduce((p, q) => p + q) / xs.length;
      final variance =
          xs.map((x) => (x - mean) * (x - mean)).reduce((p, q) => p + q) /
          xs.length;
      expect(mean, closeTo(0, 0.08));
      expect(variance, closeTo(1, 0.1));
    });
  });

  group('SyntheticScenes', () {
    test('every scene is 512 px on the long edge and deterministic', () {
      for (final id in SceneId.values) {
        final a = SyntheticScenes.build(id);
        final b = SyntheticScenes.build(id);
        expect(a.name, id.name);
        expect(math.max(a.image.width, a.image.height), 512, reason: id.name);
        expect(
          SceneMetrics.hash(a.image),
          SceneMetrics.hash(b.image),
          reason: id.name,
        );
      }
    });

    test('pixel hashes are pinned (generators are deterministic)', () {
      // FNV-1a of the RGBA bytes. A change here means a scene generator
      // changed: update deliberately, together with any tuned constants.
      const pinned = {
        SceneId.darkInterior: 0x30cd1058,
        SceneId.overexposedBeach: 0x0e0a5ee4,
        SceneId.tungstenCast: 0xa1599586,
        SceneId.daylightCoolCast: 0x5677becf,
        SceneId.greenCast: 0x57c25fd3,
        SceneId.hazyLandscape: 0x66689108,
        SceneId.wellExposedChart: 0x72a0ee7d,
        SceneId.goldenHourPortrait: 0xb380165d,
        SceneId.noisyFlat: 0x5d66b98a,
        SceneId.markerCorners: 0x27e99fc0,
        SceneId.allFeatures: 0x4e8f3753,
      };
      for (final e in pinned.entries) {
        expect(
          SceneMetrics.hash(SyntheticScenes.build(e.key).image),
          e.value,
          reason: e.key.name,
        );
      }
    });

    test('scenes are pairwise different', () {
      final hashes = {
        for (final id in SceneId.values)
          SceneMetrics.hash(SyntheticScenes.build(id).image),
      };
      expect(hashes.length, SceneId.values.length);
    });

    test('size can be changed', () {
      final s = SyntheticScenes.build(SceneId.darkInterior, longEdge: 256);
      expect(s.image.width, 256);
      expect(s.image.height, 171);
    });

    test('darkInterior: median luma about 0.10 and about 3 % crushed', () {
      final img = SyntheticScenes.darkInterior().image;
      expect(SceneMetrics.medianLuma(img), closeTo(0.10, 0.015));
      expect(SceneMetrics.crushFraction(img), closeTo(0.03, 0.005));
      expect(SceneMetrics.clipFraction(img), 0);
    });

    test('overexposedBeach: median about 0.85 and about 4 % clipped', () {
      final img = SyntheticScenes.overexposedBeach().image;
      expect(SceneMetrics.medianLuma(img), closeTo(0.85, 0.02));
      expect(SceneMetrics.clipFraction(img), closeTo(0.04, 0.005));
    });

    test('tungstenCast: neutral patches carry the (1.35, 1, 0.65) cast', () {
      final s = SyntheticScenes.tungstenCast();
      expect(s.neutralPatches, isNotEmpty);
      expect(
        SceneMetrics.castA(s.image, s.neutralPatches),
        closeTo(_log2(1.35 / 0.65), 0.03),
      );
    });

    test('daylightCoolCast: neutral patches carry the (0.8, 1, 1.25) cast', () {
      final s = SyntheticScenes.daylightCoolCast();
      expect(
        SceneMetrics.castA(s.image, s.neutralPatches),
        closeTo(_log2(0.8 / 1.25), 0.03),
      );
    });

    test('greenCast: neutral patches carry G x 1.2', () {
      final s = SyntheticScenes.greenCast();
      expect(
        SceneMetrics.castM(s.image, s.neutralPatches),
        closeTo(_log2(1.2), 0.03),
      );
      expect(SceneMetrics.castA(s.image, s.neutralPatches), closeTo(0, 0.03));
    });

    test('hazyLandscape: P0.5 about 0.2 and low contrast', () {
      final img = SyntheticScenes.hazyLandscape().image;
      expect(SceneMetrics.percentileLuma(img, 0.005), closeTo(0.2, 0.02));
      expect(SceneMetrics.sigmaLStar(img), lessThan(15));
    });

    test('wellExposedChart: median about 0.46, has neutral patches', () {
      final s = SyntheticScenes.wellExposedChart();
      expect(SceneMetrics.medianLuma(s.image), closeTo(0.46, 0.02));
      expect(s.neutralPatches.length, greaterThanOrEqualTo(6));
      expect(SceneMetrics.castA(s.image, s.neutralPatches), closeTo(0, 0.02));
    });

    test('goldenHourPortrait: warm cast, sunset EXIF time', () {
      final s = SyntheticScenes.goldenHourPortrait();
      expect(SceneMetrics.castA(s.image, s.neutralPatches), greaterThan(0.4));
      expect(s.exif?.capturedAt?.hour, 18);
    });

    test('noisyFlat: mid gray with sigma about 6/255', () {
      final img = SyntheticScenes.noisyFlat().image;
      var sum = 0.0, sum2 = 0.0;
      final n = img.pixelCount;
      for (var i = 0; i < n; i++) {
        final v = img.data[i * 4 + 1].toDouble();
        sum += v;
        sum2 += v * v;
      }
      final mean = sum / n;
      final sd = math.sqrt(sum2 / n - mean * mean);
      expect(mean, closeTo(128, 1));
      expect(sd, closeTo(6, 0.5));
    });

    test('markerCorners: four distinct corner colors', () {
      final img = SyntheticScenes.markerCorners().image;
      final w = img.width, h = img.height;
      final corners = {
        for (final p in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)])
          (img.r(p.$1, p.$2), img.g(p.$1, p.$2), img.b(p.$1, p.$2)),
      };
      expect(corners.length, 4);
    });

    test('allFeatures: wide luma range and saturated colors', () {
      final img = SyntheticScenes.allFeatures().image;
      expect(SceneMetrics.percentileLuma(img, 0.01), lessThan(0.1));
      expect(SceneMetrics.percentileLuma(img, 0.99), greaterThan(0.85));
      expect(SceneMetrics.meanChroma(img), greaterThan(15));
    });
  });
}
