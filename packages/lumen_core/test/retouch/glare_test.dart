import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

const _w = 512, _h = 512;

SynthFace _face(SynthGlasses g) =>
    SynthFace(id: 'a', cx: 256, cy: 200, iod: 140, glasses: g);

typedef _Lab = ({Float64List l, Float64List a, Float64List b});

/// Linear luminance of OkLab L (a grey veil adds to it).
double _y(double l) => l * l * l;

void main() {
  group('glasses glare', () {
    late SynthPortrait clear;
    late RetouchMaps clearMaps;
    late _Lab clearIn;
    late SynthPortrait tinted;
    late RetouchMaps tintedMaps;
    late _Lab tintedIn;
    final f = _face(SynthGlasses.clear);

    setUpAll(() {
      clear = renderSynthPortrait(_w, _h, [f]);
      clearMaps = computeRetouchMaps(clear.image, clear.analysis);
      clearIn = labOf(clear.image);
      tinted = renderSynthPortrait(_w, _h, [_face(SynthGlasses.tinted)]);
      tintedMaps = computeRetouchMaps(tinted.image, tinted.analysis);
      tintedIn = labOf(tinted.image);
    });

    RetouchUniforms glare(SynthPortrait p, double v) =>
        RetouchUniforms.fromSettings(
          PortraitSettings.empty.withGroupValue(
            FaceGroup.all,
            PortraitIds.glare,
            v,
          ),
          p.analysis,
        );

    RgbaBuffer run(SynthPortrait p, RetouchMaps m, double v) =>
        applyRetouch(p.image, m, glare(p, v));

    /// Mean L over a disc (radius in IOD) at local (x, y).
    double at(_Lab lab, double x, double y, double r) {
      final c = f.toPx(x, y);
      return discMean(lab.l, _w, c.x, c.y, r * f.iod);
    }

    /// Share of the glare left at (x, y), in linear luminance: the other
    /// side of the face (mirrored) is the glare-free reference.
    double left(_Lab input, _Lab out, double x, double y, double r) {
      final ref = _y(at(input, -x, y, r));
      return (_y(at(out, x, y, r)) - ref) / (_y(at(input, x, y, r)) - ref);
    }

    /// Fine structure (L minus a σ 1.5 px blur) over the iris annulus of
    /// the glare eye.
    double irisDetail(_Lab lab) {
      final hp = Float64List.fromList([
        for (var i = 0; i < lab.l.length; i++) lab.l[i],
      ]);
      final b = blur(hp, _w, _h, 1.5);
      final c = f.toPx(-0.5, 0);
      final r0 = 0.05 * f.iod, r1 = 0.085 * f.iod;
      final m = ringMean(
        Float64List.fromList([
          for (var i = 0; i < hp.length; i++) (hp[i] - b[i]).abs(),
        ]),
        _w,
        c.x,
        c.y,
        r0,
        r1,
      );
      return m;
    }

    test('the band is coded as glare and only its slider selects it', () {
      final c = f.toPx(-0.65, 0.2);
      expect(
        clearMaps.nearest(RetouchChannel.spotCode, c.x / _w, c.y / _h),
        kGlareCode,
      );
      expect(spotSelection(kGlareCode, 1, 1, 1, 1), 0);
      expect(spotSelection(kGlareCode, 0, 0, 0, 0, 0.7), 0.7);
      expect(spotSelection(kShineCoreCode, 0, 0, 0, 0, 0.7), 0);
      // The lens without glare carries no glare code.
      final o = f.toPx(0.65, 0.2);
      expect(
        clearMaps.nearest(RetouchChannel.spotCode, o.x / _w, o.y / _h),
        isNot(kGlareCode),
      );
    });

    test('clear lens: the band on the skin is mostly removed', () {
      final out = labOf(run(clear, clearMaps, 100));
      expect(left(clearIn, out, -0.65, 0.2, 0.02), lessThan(0.3));
      expect(left(clearIn, out, -0.35, -0.16, 0.02), lessThan(0.3));
    });

    test('clear lens: the eye under the band comes back, its structure '
        'and catchlight intact', () {
      final out = labOf(run(clear, clearMaps, 100));
      // Most of the veil over the pupil and the iris goes.
      expect(left(clearIn, out, -0.5, 0, 0.015), lessThan(0.3));
      expect(left(clearIn, out, -0.55, 0.05, 0.01), lessThan(0.3));
      // Pupil / iris contrast: washed out by the glare, regained (the
      // pupil stays the darkest part of the eye).
      double contrast(_Lab lab, double sx) =>
          at(lab, sx * 0.5 + 0.05 * sx, 0.05, 0.01) -
          at(lab, sx * 0.5, 0, 0.015);
      expect(contrast(clearIn, -1), lessThan(0.3 * contrast(clearIn, 1)));
      expect(contrast(out, -1), greaterThan(1.3 * contrast(clearIn, -1)));
      // Iris spokes keep (and regain) their fine contrast: no mush.
      expect(irisDetail(out), greaterThan(irisDetail(clearIn)));
      // The catchlight stays a near-white highlight.
      expect(at(out, -0.47, -0.03, 0.006), greaterThan(0.95));
    });

    test('the eye and lens without glare are untouched', () {
      final out = labOf(run(clear, clearMaps, 100));
      for (final (x, y) in const [(0.5, 0.0), (0.53, -0.03), (0.65, 0.2)]) {
        expect(at(out, x, y, 0.02), closeTo(at(clearIn, x, y, 0.02), 1e-3));
      }
    });

    test('the frame is never corrected', () {
      final out = labOf(run(clear, clearMaps, 100));
      var checked = 0;
      for (var k = 0; k < 64; k++) {
        final t = 2 * math.pi * k / 64;
        final c = f.toPx(
          -kLensX + kLensRx * math.cos(t),
          kLensY + kLensRy * math.sin(t),
        );
        final i = c.y.floor() * _w + c.x.floor();
        // The frame core (its anti-aliased edge mixes with the glare).
        if ([i, i - 1, i + 1, i - _w, i + _w].any((j) => clearIn.l[j] > 0.3)) {
          continue;
        }
        checked++;
        expect((out.l[i] - clearIn.l[i]).abs(), lessThan(0.01));
      }
      expect(checked, greaterThan(16));
    });

    test('tinted lens: partial reduction, no overshoot, no mush', () {
      final out = labOf(run(tinted, tintedMaps, 100));
      final share = left(tintedIn, out, -0.35, -0.16, 0.02);
      expect(share, lessThan(0.9));
      expect(share, greaterThan(0.0));
      // Never darker than the glare-free tinted lens on the other side.
      for (final (x, y) in const [(-0.65, 0.2), (-0.35, -0.16), (-0.5, 0.0)]) {
        expect(at(out, x, y, 0.02), greaterThan(at(tintedIn, -x, y, 0.02)));
      }
      expect(irisDetail(out), greaterThan(0.9 * irisDetail(tintedIn)));
    });

    test('the slider scales the correction linearly', () {
      final full = labOf(run(clear, clearMaps, 100));
      final half = labOf(run(clear, clearMaps, 50));
      for (final (x, y) in const [(-0.65, 0.2), (-0.5, 0.0), (-0.35, -0.16)]) {
        final d100 = at(full, x, y, 0.01) - at(clearIn, x, y, 0.01);
        final d50 = at(half, x, y, 0.01) - at(clearIn, x, y, 0.01);
        expect(d50, closeTo(0.5 * d100, 0.01));
      }
    });

    test('a face without glasses has no glare and the slider is a '
        'no-op', () {
      final plain = renderSynthPortrait(_w, _h, [_face(SynthGlasses.none)]);
      final m = computeRetouchMaps(plain.image, plain.analysis);
      for (var y = 0; y < m.height; y++) {
        for (var x = 0; x < m.width; x++) {
          expect(
            m.regionB[(y * 2 * m.width + m.width + x) * 4 + 1],
            isNot(kGlareCode),
          );
        }
      }
      final out = applyRetouch(plain.image, m, glare(plain, 100));
      expect(out.data, plain.image.data);
    });

    test('Glasses glare is a face slider in the uniform row', () {
      final u = glare(clear, 100);
      expect(u.row(0).glare, 1);
      expect(u.row(0).toList()[11], 1);
      expect(u.row(0).isIdentity, isFalse);
      expect(glare(clear, 0).row(0).isIdentity, isTrue);
    });
  });
}
