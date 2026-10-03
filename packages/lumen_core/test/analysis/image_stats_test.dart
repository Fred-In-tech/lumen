import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

ImageStats _stats(SceneId id) =>
    ImageStats.compute(SyntheticScenes.build(id).image);

void main() {
  group('ImageStats basics', () {
    test('uniform gray: percentiles, lAvg, no clipping, neutral', () {
      final s = ImageStats.compute(RgbaBuffer.filled(64, 48, 128, 128, 128));
      final v = 128 / 255;
      expect(s.width, 64);
      expect(s.height, 48);
      expect(s.lumaP.p0_5, closeTo(v, 1e-3));
      expect(s.lumaP.p50, closeTo(v, 1e-3));
      expect(s.lumaP.p99_5, closeTo(v, 1e-3));
      expect(s.lAvg, closeTo(srgbToLinear(v), 1e-3));
      expect(s.clipFraction, 0);
      expect(s.crushFraction, 0);
      expect(s.sigmaLStar, closeTo(0, 1e-6));
      expect(s.wb.a, closeTo(0, 1e-6));
      expect(s.wb.m, closeTo(0, 1e-6));
      expect(s.meanChroma, closeTo(0, 0.01));
      expect(s.skinShare, 0);
    });

    test('pure blue is all blue band; pure red is red band', () {
      final blue = ImageStats.compute(RgbaBuffer.filled(16, 16, 0, 0, 255));
      expect(blue.hslShare[HslBand.blue], closeTo(1, 1e-9));
      final red = ImageStats.compute(RgbaBuffer.filled(16, 16, 255, 0, 0));
      expect(red.hslShare[HslBand.red], closeTo(1, 1e-9));
      expect(() => red.hslShare[HslBand.red] = 0, throwsUnsupportedError);
    });

    test('a skin-colored image has full skin share', () {
      final s = ImageStats.compute(RgbaBuffer.filled(16, 16, 194, 150, 130));
      expect(s.skinShare, closeTo(1, 1e-9));
    });

    test('compute is deterministic', () {
      final img = SyntheticScenes.wellExposedChart().image;
      expect(
        ImageStats.compute(img).toJson(),
        ImageStats.compute(img).toJson(),
      );
    });
  });

  group('ImageStats on synthetic scenes', () {
    test('clip and crush fractions', () {
      expect(
        _stats(SceneId.overexposedBeach).clipFraction,
        closeTo(0.04, 0.005),
      );
      expect(_stats(SceneId.darkInterior).crushFraction, closeTo(0.03, 0.005));
    });

    test('WB cast sign: warm, cool, green, neutral', () {
      final t = _stats(SceneId.tungstenCast).wb;
      expect(t.a, greaterThan(0.6));
      expect(t.confidence, greaterThan(0.5));
      expect(_stats(SceneId.daylightCoolCast).wb.a, lessThan(-0.3));
      final g = _stats(SceneId.greenCast).wb;
      expect(g.m, greaterThan(0.15));
      expect(g.a.abs(), lessThan(0.1));
      final n = _stats(SceneId.wellExposedChart).wb;
      expect(n.a.abs(), lessThan(0.08));
      expect(n.m.abs(), lessThan(0.08));
    });

    test('dark channel: hazy scene is hazy, others are not', () {
      final hazy = _stats(SceneId.hazyLandscape);
      expect(hazy.haze, greaterThan(0.2));
      expect(hazy.airlight.r, greaterThan(0.6));
      expect(hazy.haze, greaterThan(_stats(SceneId.wellExposedChart).haze));
      expect(_stats(SceneId.darkInterior).haze, lessThan(0.12));
    });

    test('contrast and key statistics are ordered sensibly', () {
      final hazy = _stats(SceneId.hazyLandscape);
      final chart = _stats(SceneId.wellExposedChart);
      expect(hazy.sigmaLStar, lessThan(20));
      expect(hazy.lumaP.p0_5, closeTo(0.2, 0.02));
      expect(_stats(SceneId.darkInterior).lAvg, lessThan(0.02));
      expect(chart.lumaP.p50, closeTo(0.46, 0.02));
      expect(chart.highlightP99_5, greaterThan(0.9));
    });

    test('skin share on the portrait, none on the dark interior', () {
      expect(_stats(SceneId.allFeatures).skinShare, greaterThan(0.02));
      expect(_stats(SceneId.darkInterior).skinShare, lessThan(0.01));
    });

    test('zone statistics', () {
      final beach = _stats(SceneId.overexposedBeach);
      expect(beach.hiMean, greaterThan(0.9));
      expect(beach.hiClip, greaterThan(0.03));
      final dark = _stats(SceneId.darkInterior);
      expect(dark.loMean, lessThan(0.05));
      expect(dark.loCrush, greaterThan(0.02));
    });
  });

  group('ImageStats.toJson (gateway contract stats object)', () {
    test('has exactly the contract keys', () {
      final json = _stats(SceneId.wellExposedChart).toJson();
      expect(json.keys.toSet(), {
        'lumaP',
        'clipPct',
        'crushPct',
        'lAvg',
        'wb',
        'meanChroma',
        'skinShare',
        'haze',
        'hslShare',
      });
      expect((json['lumaP']! as Map).keys.toSet(), {
        'p0_5',
        'p5',
        'p50',
        'p95',
        'p99_5',
      });
      expect((json['wb']! as Map).keys.toSet(), {'a', 'm', 'confidence'});
    });

    test('percent fields are percentages, hsl shares use band names', () {
      final json = _stats(SceneId.overexposedBeach).toJson();
      expect(json['clipPct'] as double, closeTo(4, 0.5));
      final hsl =
          _stats(SceneId.allFeatures).toJson()['hslShare']!
              as Map<String, Object?>;
      expect(
        hsl.keys.every((k) => HslBand.values.any((b) => b.name == k)),
        isTrue,
      );
      expect(hsl['blue'] as double, greaterThan(0.2));
    });
  });
}
