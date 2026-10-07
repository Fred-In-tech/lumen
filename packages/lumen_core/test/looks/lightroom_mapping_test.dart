import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'preset_fixtures.dart';

LightroomConversion _conv(Map<String, Object?> crs) =>
    convertLightroomSettings(crs);

void main() {
  group('sliders copied as they are (one test per parameter)', () {
    for (final spec in ParamRegistry.all) {
      if (spec.id == P.temp || spec.id == P.tint) continue;
      test('${spec.xmp} → ${spec.id}', () {
        // A value inside both ranges, away from the default.
        final v = spec.min + (spec.max - spec.min) * 0.7;
        final c = _conv({spec.xmp: v.toStringAsFixed(2)});
        expect(c.values[spec.id], closeTo(spec.clamp(v), 0.006));
        expect(c.values.length, 1);
        expect(c.applied, isNotEmpty);
        expect(c.skipped, isEmpty);
        // Out-of-range values are clamped to the Lumen range.
        final over = _conv({spec.xmp: spec.max + 1000});
        expect(over.values[spec.id], spec.max);
      });
    }

    test('Lightroom number formats: "+0.70", "-20", numbers', () {
      expect(_conv({'Exposure2012': '+0.70'}).values[P.exposure], 0.7);
      expect(_conv({'Contrast2012': '-20'}).values[P.contrast], -20);
      expect(_conv({'Contrast2012': 15}).values[P.contrast], 15);
      expect(_conv({'Contrast2012': 'abc'}).values, isEmpty);
    });

    test('explicit zeros apply (presets set what they contain)', () {
      final c = _conv({'Clarity2012': '0', 'Vibrance': 0});
      expect(c.values, {P.clarity: 0, P.vibrance: 0});
    });
  });

  group('white balance', () {
    test('incremental temperature / tint are Lumen Temp / Tint', () {
      final c = _conv({
        'WhiteBalance': 'Custom',
        'IncrementalTemperature': '+8',
        'IncrementalTint': '-12',
      });
      expect(c.values, {P.temp: 8, P.tint: -12});
      expect(c.applied, contains('White balance'));
      expect(c.approximated, isEmpty);
    });

    test('incremental wins over absolute when both are present', () {
      final c = _conv({'IncrementalTemperature': 5, 'Temperature': 9000});
      expect(c.values[P.temp], 5);
    });

    test('Kelvin is a shift from daylight: warmer above, cooler below', () {
      expect(kelvinToRelativeTemp(5500), closeTo(0, 1e-9));
      final warm = kelvinToRelativeTemp(7500);
      final cool = kelvinToRelativeTemp(3200);
      expect(warm, inInclusiveRange(25, 70));
      expect(cool, inInclusiveRange(-100, -60));
      var last = -200.0;
      for (var k = 2500.0; k <= 12000; k += 250) {
        final t = kelvinToRelativeTemp(k);
        expect(t, greaterThanOrEqualTo(last));
        last = t;
      }
      final c = _conv({'WhiteBalance': 'Custom', 'Temperature': '7500'});
      expect(c.values[P.temp], closeTo(warm, 1e-9));
      expect(c.approximated.single, contains('White balance'));
    });

    test('Planckian whites: low Kelvin is red, high Kelvin is blue', () {
      final (r1, _, b1) = planckianLinearSrgb(2700);
      final (r2, _, b2) = planckianLinearSrgb(10000);
      expect(r1 / b1, greaterThan(2));
      expect(r2 / b2, lessThan(1));
      final (r, g, b) = planckianLinearSrgb(6504);
      expect(r / g, closeTo(1, 0.08)); // D65-ish is near white
      expect(b / g, closeTo(1, 0.08));
    });

    test('absolute tint is scaled from ±150 to ±100', () {
      expect(_conv({'Tint': 30}).values[P.tint], closeTo(20, 1e-9));
      expect(absoluteTintToRelative(-300), -100);
    });

    test('As Shot leaves white balance alone; Auto is reported', () {
      expect(
        _conv({'WhiteBalance': 'As Shot', 'Temperature': 6000}).values,
        isEmpty,
      );
      final auto = _conv({'WhiteBalance': 'Auto', 'Temperature': 6000});
      expect(auto.values, isEmpty);
      expect(auto.skipped, ['Auto white balance']);
    });
  });

  group('treatment, curves, grading, effects', () {
    test('ConvertToGrayscale sets the treatment both ways', () {
      expect(_conv({'ConvertToGrayscale': 'True'}).treatment, Treatment.bw);
      expect(_conv({'ConvertToGrayscale': true}).treatment, Treatment.bw);
      expect(_conv({'ConvertToGrayscale': 'False'}).treatment, Treatment.color);
      expect(_conv({'Exposure2012': 0}).treatment, isNull);
    });

    test('point curves from XMP strings and lrtemplate numbers', () {
      final x = _conv({
        'ToneCurvePV2012': ['0, 18', '128, 140', '255, 250'],
      });
      expect(x.curves!.master.points, const [
        CurvePoint(0, 18),
        CurvePoint(128, 140),
        CurvePoint(255, 250),
      ]);
      expect(x.curveChannels, {CurveChannel.master});
      final l = _conv({
        'ToneCurvePV2012Blue': [0, 20, 255, 240],
      });
      expect(l.curves!.blue.evaluate(0), 20);
      expect(l.curves!.master.isIdentity, isTrue);
      expect(l.curveChannels, {CurveChannel.blue});
      expect(
        _conv({
          'ToneCurvePV2012': ['bad'],
        }).curves,
        isNull,
      );
      expect(
        _conv({
          'ToneCurvePV2012': [1, 2, 3],
        }).curves,
        isNull,
      );
    });

    test('process 2010 and 17+ point curves are approximated', () {
      expect(
        _conv({
          'ToneCurve': ['0, 0', '255, 240'],
        }).approximated,
        ['Tone curve (process 2010)'],
      );
      final many = [for (var i = 0; i <= 18; i++) '${i * 14}, ${i * 14}'];
      expect(
        _conv({'ToneCurvePV2012': many}).approximated.single,
        contains('more than'),
      );
    });

    test('split toning (older presets) becomes colour grading', () {
      final c = _conv({
        'SplitToningShadowHue': 200,
        'SplitToningShadowSaturation': 15,
        'SplitToningBalance': -20,
      });
      expect(c.values[P.grade(GradeZone.shadows, 'hue')], 200);
      expect(c.values[P.gradeBalance], -20);
      expect(c.applied, ['Split toning (as color grading)']);
      final g = _conv({'ColorGradeMidtoneHue': 30, 'SplitToningShadowHue': 9});
      expect(g.applied, ['Color grading']);
    });

    test('vignette style other than highlight priority is approximated', () {
      final paint = _conv({
        'PostCropVignetteAmount': -20,
        'PostCropVignetteStyle': '3',
      });
      expect(paint.values[P.vignetteAmount], -20);
      expect(paint.approximated.single, contains('Vignette style'));
      expect(
        _conv({'PostCropVignetteAmount': -20, 'PostCropVignetteStyle': 1})
            .approximated,
        isEmpty,
      );
    });

    test('process 2010 basics where no 2012 value exists', () {
      final c = _conv({
        'Exposure': 0.5,
        'Contrast': 50,
        'Clarity': 20,
        'FillLight': 30,
        'HighlightRecovery': 40,
        'Shadows': 15,
        'Brightness': 60,
      });
      expect(c.values[P.exposure], 0.5);
      expect(c.values[P.contrast], 25);
      expect(c.values[P.clarity], 20);
      expect(c.values[P.shadows], 30);
      expect(c.values[P.highlights], -40);
      expect(c.values[P.blacks], -20);
      expect(c.approximated, ['Process 2010 basics']);
      expect(c.skipped, ['Brightness (process 2010)']);
      final both = _conv({'Exposure': 0.5, 'Exposure2012': 1});
      expect(both.values[P.exposure], 1);
    });
  });

  group('skipped settings are reported in plain language', () {
    test('the bright & airy fixture', () {
      final data = readXmpPreset(kBrightAiryXmp);
      final c = _conv(data.settings);
      expect(c.values[P.exposure], 0.7); // not the profile's +3
      expect(c.values[P.temp], 8);
      expect(c.curves, isNotNull);
      expect(c.treatment, Treatment.color);
      expect(
        c.skipped,
        containsAll([
          'Calibration',
          'Lens profile',
          'Camera profile ("Adobe Portrait")',
          'Local masks',
          'Crop',
        ]),
      );
      expect(c.skipped, isNot(contains('Camera profile')));
      expect(
        c.applied,
        containsAll([
          'Exposure',
          'Contrast',
          'White balance',
          'Color mixer (HSL)',
          'Tone curve',
          'Color grading',
          'Vignette',
          'Sharpening',
          'Noise reduction',
        ]),
      );
    });

    test('unknown keys are summarised, metadata is silent', () {
      final c = _conv({
        'Name': 'x',
        'UUID': 'y',
        'Version': '15',
        'EnableCalibration': 'True',
        'FutureSlider1': 1,
        'FutureSlider2': 1,
        'FutureSlider3': 1,
        'FutureSlider4': 1,
      });
      expect(c.skipped, [
        'Other settings (FutureSlider1, FutureSlider2, FutureSlider3 and '
            '1 more)',
      ]);
      expect(_conv({'Odd': 1}).skipped, ['Other settings (Odd)']);
      expect(lightroomSkippedLabel('Name'), '');
      expect(lightroomSkippedLabel('UprightVersion'), 'Transform');
      expect(lightroomSkippedLabel('Nope'), isNull);
    });
  });

  test('HSL band centres: each Lightroom colour lands in its own band', () {
    // Lightroom's eight colours (HSV hue at full saturation) in OkLab hue.
    const lrHues = <double>[0, 30, 60, 120, 180, 240, 270, 300];
    for (var i = 0; i < 8; i++) {
      final (r, g, b) = _hsv(lrHues[i]);
      final lab = linearSrgbToOklab(
        srgbToLinear(r),
        srgbToLinear(g),
        srgbToLinear(b),
      );
      final h = (math.atan2(lab.b, lab.a) * 180 / math.pi + 360) % 360;
      var best = 0;
      var bestD = 999.0;
      for (var k = 0; k < 8; k++) {
        final d = ((h - kHslBandCenters[k] + 540) % 360 - 180).abs();
        if (d < bestD) {
          bestD = d;
          best = k;
        }
      }
      expect(
        best,
        i,
        reason:
            '${HslBand.values[i].name} (OkLab hue $h) is nearest to '
            '${HslBand.values[best].name}',
      );
      expect(bestD, lessThan(20));
    }
  });
}

(double, double, double) _hsv(double h) {
  final x = 1 - ((h / 60) % 2 - 1).abs();
  return switch (h ~/ 60) {
    0 => (1.0, x, 0.0),
    1 => (x, 1.0, 0.0),
    2 => (0.0, 1.0, x),
    3 => (0.0, x, 1.0),
    4 => (x, 0.0, 1.0),
    _ => (1.0, 0.0, x),
  };
}
