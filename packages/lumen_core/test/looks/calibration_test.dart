/// Calibration of the Lightroom → Lumen mapping on the CPU twin: each
/// mapped setting moves the picture in Lightroom's direction by a
/// plausible amount. `LUMEN_CALIBRATION_REPORT=1 dart test …` prints the
/// measured numbers (docs/DESIGN.md "Looks & presets").
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'preset_fixtures.dart';

const _patch = 16;

/// Patches (encoded sRGB 0..255), 8 per row.
const List<(String, int, int, int)> _patches = [
  ('black', 12, 12, 12),
  ('shadow', 45, 45, 45),
  ('dark', 80, 80, 80),
  ('mid', 118, 118, 118),
  ('light', 170, 170, 170),
  ('bright', 205, 205, 205),
  ('highlight', 235, 235, 235),
  ('white', 250, 250, 250),
  ('red', 200, 40, 40),
  ('orange', 220, 130, 40),
  ('yellow', 210, 200, 50),
  ('green', 50, 160, 60),
  ('aqua', 50, 180, 190),
  ('blue', 40, 70, 200),
  ('purple', 120, 60, 190),
  ('magenta', 200, 50, 170),
  ('skin', 214, 160, 132),
  ('mutedBlue', 120, 130, 150),
  ('mutedGreen', 120, 140, 118),
  ('mutedRed', 150, 120, 115),
  ('sky', 140, 180, 225),
  ('foliage', 70, 100, 50),
  ('sand', 200, 180, 140),
  ('slate', 90, 100, 110),
];

RgbaBuffer _chart() {
  const cols = 8;
  final rows = (_patches.length / cols).ceil();
  final b = RgbaBuffer(cols * _patch, rows * _patch);
  for (var i = 0; i < _patches.length; i++) {
    final (_, r, g, bl) = _patches[i];
    final x0 = (i % cols) * _patch, y0 = (i ~/ cols) * _patch;
    for (var y = y0; y < y0 + _patch; y++) {
      for (var x = x0; x < x0 + _patch; x++) {
        final o = (y * b.width + x) * 4;
        b.data
          ..[o] = r
          ..[o + 1] = g
          ..[o + 2] = bl
          ..[o + 3] = 255;
      }
    }
  }
  return b;
}

/// Mean linear RGB of the centre of patch [name].
(double, double, double) _mean(RgbaBuffer img, String name) {
  final i = _patches.indexWhere((p) => p.$1 == name);
  final x0 = (i % 8) * _patch + 4, y0 = (i ~/ 8) * _patch + 4;
  var r = 0.0, g = 0.0, b = 0.0;
  var n = 0;
  for (var y = y0; y < y0 + _patch - 8; y++) {
    for (var x = x0; x < x0 + _patch - 8; x++) {
      final o = (y * img.width + x) * 4;
      r += srgbToLinear(img.data[o] / 255);
      g += srgbToLinear(img.data[o + 1] / 255);
      b += srgbToLinear(img.data[o + 2] / 255);
      n++;
    }
  }
  return (r / n, g / n, b / n);
}

double _luma(RgbaBuffer img, String p) {
  final (r, g, b) = _mean(img, p);
  return relativeLuminance(r, g, b);
}

/// Encoded luma (0..1), the scale the eye and the sliders work on.
double _lumaE(RgbaBuffer img, String p) => linearToSrgb(_luma(img, p));

double _chroma(RgbaBuffer img, String p) {
  final (r, g, b) = _mean(img, p);
  final lab = linearSrgbToOklab(r, g, b);
  return math.sqrt(lab.a * lab.a + lab.b * lab.b);
}

final bool _report = Platform.environment['LUMEN_CALIBRATION_REPORT'] == '1';

void _log(String line) {
  // ignore: avoid_print
  if (_report) print('calibration: $line');
}

RgbaBuffer _apply(RgbaBuffer src, Map<String, Object?> crs) {
  final c = convertLightroomSettings(crs);
  final preset = Preset(
    id: 'cal',
    name: 'cal',
    values: c.values,
    curves: c.curves,
    curveChannels: c.curveChannels,
    treatment: c.treatment,
  );
  return renderReference(src, preset.apply(DevelopSettings.defaults));
}

void main() {
  final src = _chart();
  final base = renderReference(src, DevelopSettings.defaults);
  String f(double v) => v.toStringAsFixed(3);

  test('Exposure +1 doubles linear light (one stop)', () {
    final out = _apply(src, {'Exposure2012': '+1.00'});
    for (final p in ['shadow', 'dark', 'mid']) {
      final k = _luma(out, p) / _luma(base, p);
      _log('Exposure +1: $p ×${f(k)} linear');
      expect(k, inInclusiveRange(1.8, 2.2), reason: p);
    }
  });

  test('Contrast +50 spreads tones around the middle', () {
    final out = _apply(src, {'Contrast2012': '+50'});
    final dark = _lumaE(out, 'dark') - _lumaE(base, 'dark');
    final mid = _lumaE(out, 'mid') - _lumaE(base, 'mid');
    final light = _lumaE(out, 'bright') - _lumaE(base, 'bright');
    _log(
      'Contrast +50: dark ${f(dark)}, mid ${f(mid)}, bright ${f(light)} '
      '(encoded)',
    );
    expect(dark, lessThan(-0.02));
    expect(light, greaterThan(0.02));
    expect(mid.abs(), lessThan(0.04));
  });

  test('Highlights −100 pulls highlights down, leaves shadows', () {
    final out = _apply(src, {'Highlights2012': '-100'});
    final hi = _lumaE(out, 'highlight') - _lumaE(base, 'highlight');
    final sh = _lumaE(out, 'shadow') - _lumaE(base, 'shadow');
    _log('Highlights −100: highlight ${f(hi)}, shadow ${f(sh)} (encoded)');
    expect(hi, lessThan(-0.04));
    expect(sh.abs(), lessThan(0.02));
  });

  test('Shadows +100 lifts shadows, leaves highlights', () {
    final out = _apply(src, {'Shadows2012': '+100'});
    final sh = _lumaE(out, 'shadow') - _lumaE(base, 'shadow');
    final hi = _lumaE(out, 'highlight') - _lumaE(base, 'highlight');
    _log('Shadows +100: shadow ${f(sh)}, highlight ${f(hi)} (encoded)');
    expect(sh, greaterThan(0.05));
    expect(hi.abs(), lessThan(0.02));
  });

  test('Whites +50 / Blacks −50 move the ends', () {
    final w = _apply(src, {'Whites2012': '+50'});
    final b = _apply(src, {'Blacks2012': '-50'});
    final dw = _lumaE(w, 'bright') - _lumaE(base, 'bright');
    final db = _lumaE(b, 'shadow') - _lumaE(base, 'shadow');
    _log('Whites +50: bright ${f(dw)}; Blacks −50: shadow ${f(db)}');
    expect(dw, greaterThan(0.01));
    expect(db, lessThan(-0.01));
  });

  test('Vibrance +50 boosts muted colours more than saturated ones', () {
    final out = _apply(src, {'Vibrance': '+50'});
    final muted = _chroma(out, 'mutedBlue') / _chroma(base, 'mutedBlue');
    final sat = _chroma(out, 'blue') / _chroma(base, 'blue');
    final skin = _chroma(out, 'skin') / _chroma(base, 'skin');
    _log(
      'Vibrance +50: muted ×${f(muted)}, saturated ×${f(sat)}, '
      'skin ×${f(skin)} chroma',
    );
    expect(muted, greaterThan(1.15));
    expect(muted, greaterThan(sat));
    expect(skin, lessThan(muted));
  });

  test('Saturation −100 and B&W remove colour', () {
    for (final crs in [
      {'Saturation': '-100'},
      {'ConvertToGrayscale': 'True'},
    ]) {
      final out = _apply(src, crs);
      for (final p in ['red', 'blue', 'skin']) {
        expect(_chroma(out, p), lessThan(0.01), reason: '$crs $p');
      }
    }
  });

  test('HSL: Blue saturation −100 greys blue only', () {
    final out = _apply(src, {'SaturationAdjustmentBlue': '-100'});
    final blue = _chroma(out, 'blue') / _chroma(base, 'blue');
    final red = _chroma(out, 'red') / _chroma(base, 'red');
    _log('HSL blue sat −100: blue ×${f(blue)}, red ×${f(red)} chroma');
    expect(blue, lessThan(0.35));
    expect(red, closeTo(1, 0.05));
  });

  test('Temperature 7500 K warms, 3200 K cools (RAW presets)', () {
    double rb(RgbaBuffer img) {
      final (r, _, b) = _mean(img, 'mid');
      return r / b;
    }

    final warm = _apply(src, {'WhiteBalance': 'Custom', 'Temperature': 7500});
    final cool = _apply(src, {'WhiteBalance': 'Custom', 'Temperature': 3200});
    _log(
      'Temperature 7500 K: Temp ${f(kelvinToRelativeTemp(7500))}, '
      'R/B ×${f(rb(warm) / rb(base))}; 3200 K: Temp '
      '${f(kelvinToRelativeTemp(3200))}, R/B ×${f(rb(cool) / rb(base))}',
    );
    expect(rb(warm) / rb(base), greaterThan(1.15));
    expect(rb(cool) / rb(base), lessThan(0.75));
  });

  test('fixture looks move the picture the way their names say', () {
    double meanE(RgbaBuffer img) =>
        [for (final p in _patches) _lumaE(img, p.$1)].reduce((a, b) => a + b) /
        _patches.length;
    double meanC(RgbaBuffer img) =>
        [for (final p in _patches) _chroma(img, p.$1)].reduce((a, b) => a + b) /
        _patches.length;
    final airy = _apply(src, readXmpPreset(kBrightAiryXmp).settings);
    final moody = _apply(src, readLrTemplate(kMoodyFilmLrTemplate).settings);
    final bw = _apply(src, readXmpPreset(kBwXmp).settings);
    _log('Bright & Airy: mean luma ${f(meanE(base))} → ${f(meanE(airy))}');
    _log(
      'Moody Film: mean luma ${f(meanE(base))} → ${f(meanE(moody))}, '
      'chroma ${f(meanC(base))} → ${f(meanC(moody))}',
    );
    _log('Classic B&W: chroma ${f(meanC(base))} → ${f(meanC(bw))}');
    expect(meanE(airy), greaterThan(meanE(base) + 0.04));
    expect(meanE(moody), lessThan(meanE(base)));
    expect(meanC(moody), lessThan(meanC(base)));
    expect(meanC(bw), lessThan(0.01));
  });

  test('a teal & orange LUT warms skin and cools shadows', () {
    final lut = tealOrangeLut();
    final out = renderReference(
      src,
      DevelopSettings.defaults.withLut(
        LutRef(hash: lut.contentHash, name: lut.title),
      ),
      creativeLut: lut,
    );
    final (sr, _, sb) = _mean(out, 'skin');
    final (br, _, bb) = _mean(base, 'skin');
    final (dr, _, db) = _mean(out, 'shadow');
    final (er, _, eb) = _mean(base, 'shadow');
    _log(
      'Teal & Orange LUT: skin R/B ×${f((sr / sb) / (br / bb))}, '
      'shadow R/B ×${f((dr / db) / (er / eb))}',
    );
    expect((sr / sb) / (br / bb), greaterThan(1.05));
    expect((dr / db) / (er / eb), lessThan(0.9));
  });
}
