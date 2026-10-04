import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_core/src/retouch/backdrop_build.dart'
    show kGrainTauFloorL;
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_backdrop.dart';

RgbaBuffer _run(BackdropScene s, RetouchMaps m, Map<String, double> values) {
  var st = PortraitSettings.empty;
  for (final e in values.entries) {
    st = st.withImageValue(e.key, e.value);
  }
  return applyRetouch(s.image, m, RetouchUniforms.fromSettings(st, s.analysis));
}

/// |centre − ring| of [p] around (x, y): disc r, ring 3r..5r (pixels).
double _contrast(Float64List p, int w, double x, double y, double r) =>
    (discMean(p, w, x, y, r) - ringMean(p, w, x, y, 3 * r, 5 * r)).abs();

/// Mean L darkening along a line (centre vs 4 px to each side).
double _lineDepth(Float64List l, int w, (double, double, double, double) s) {
  final (x0, y0, x1, y1) = s;
  final dx = x1 - x0, dy = y1 - y0, len = math.sqrt(dx * dx + dy * dy);
  final nx = -dy / len, ny = dx / len;
  var sum = 0.0, n = 0;
  for (var t = 0.25; t <= 0.85; t += 0.05) {
    final x = x0 + dx * t, y = y0 + dy * t;
    final side =
        (discMean(l, w, x + 4 * nx, y + 4 * ny, 0.8) +
            discMean(l, w, x - 4 * nx, y - 4 * ny, 0.8)) /
        2;
    sum += side - discMean(l, w, x, y, 0.8);
    n++;
  }
  return sum / n;
}

void main() {
  late BackdropScene s;
  late RetouchMaps maps;
  late ({Float64List l, Float64List a, Float64List b}) inLab;

  setUpAll(() {
    s = renderBackdropScene();
    maps = computeRetouchMaps(s.image, s.analysis, backdrop: s.input);
    inLab = labOf(s.image);
  });

  /// Pixels inside the person ([margin] px from the edge) never change.
  void expectPersonUntouched(RgbaBuffer out, {int margin = 4}) {
    var inside = 0;
    final m = margin;
    for (var y = 0; y < s.height; y++) {
      for (var x = 0; x < s.width; x++) {
        var deep = true;
        for (final (dx, dy) in [(-m, 0), (m, 0), (0, -m), (0, m)]) {
          deep = deep && s.isPerson(x + 0.5 + dx, y + 0.5 + dy);
        }
        if (!deep) continue;
        inside++;
        final o = (y * s.width + x) * 4;
        for (var c = 0; c < 3; c++) {
          if (out.data[o + c] != s.image.data[o + c]) {
            fail('person pixel $x,$y changed');
          }
        }
      }
    }
    expect(inside, greaterThan(20000));
  }

  group('backdrop analysis', () {
    test('a plain studio backdrop is solid and ready', () {
      final b = maps.backdrop;
      expect(b.state, BackdropState.ready);
      expect(b.state.reason, isNull);
      expect(maps.hasFaces, isFalse);
      expect(maps.isUsable, isTrue);
      expect([b.width, b.height], [480, 360]);
      expect(b.atlas, hasLength(24 * 480 * 360));
      expect(b.clothesState, ClothesState.notRequested);
      expect(maps.hasClothes, isFalse);
      expect(b.medianL, closeTo(s.backdropL - 0.03, 0.03));
      expect(b.tauL, greaterThanOrEqualTo(kGrainTauFloorL));
    });

    test('a textured backdrop disables every effect, with a reason', () {
      final t = renderBackdropScene(textured: true);
      final m = computeRetouchMaps(t.image, t.analysis, backdrop: t.input);
      expect(m.backdrop.state, BackdropState.notSolid);
      expect(m.backdrop.state.reason, contains('plain'));
      final out = _run(t, m, {
        PortraitIds.bgClean: 100,
        PortraitIds.bgUnify: 100,
        PortraitIds.bgUnifyLuminance: 100,
        PortraitIds.strayHairs: 100,
      });
      expect(identical(out, t.image), isTrue);
    });

    test('without rasters nothing is built; a full person disables it', () {
      final none = computeRetouchMaps(s.image, s.analysis);
      expect(none.backdrop.state, BackdropState.notRequested);
      expect(none.isUsable, isFalse);
      final everywhere = MaskRaster(4, 3, Uint8List(12)..fillRange(0, 12, 255));
      final full = computeBackdropMaps(
        s.image,
        BackdropInput(people: everywhere),
      );
      expect(full.state, BackdropState.tooLittleBackdrop);
      expect(full.state.reason, isNotNull);
      final missing = computeBackdropMaps(s.image, BackdropInput.missing);
      expect(missing.state, BackdropState.noMatte);
      expect(missing.state.reason, contains('person mask'));
    });

    test('is isolate-safe and deterministic', () async {
      final image = s.image, input = s.input;
      final remote = await Isolate.run(() => computeBackdropMaps(image, input));
      expect(remote.atlas, maps.backdrop.atlas);
      expect(remote.medianL, maps.backdrop.medianL);
    });
  });

  group('Clean backdrop', () {
    late RgbaBuffer out;
    late ({Float64List l, Float64List a, Float64List b}) outLab;
    setUpAll(() {
      out = _run(s, maps, {PortraitIds.bgClean: 100});
      outLab = labOf(out);
    });

    test('removes dust specks and the scuff', () {
      for (final sp in s.specks) {
        final before = _contrast(inLab.l, s.width, sp.x, sp.y, sp.r);
        final after = _contrast(outLab.l, s.width, sp.x, sp.y, sp.r);
        expect(before, greaterThan(0.06));
        expect(after / before, lessThan(0.15), reason: 'speck at ${sp.x}');
      }
      final sx = s.width * kScuffX, sy = s.height * kScuffY;
      double scuff(Float64List l) =>
          discMean(l, s.width, sx, sy, 3) -
          ringMean(l, s.width, sx, sy, 0.06 * s.width, 0.08 * s.width);
      expect(scuff(outLab.l) / scuff(inLab.l), lessThan(0.3));
    });

    test('keeps grain, the light falloff and the person', () {
      final fineIn = blur(inLab.l, s.width, s.height, 1.0);
      final fineOut = blur(outLab.l, s.width, s.height, 1.0);
      double grain(Float64List l, Float64List b) {
        var sum = 0.0, n = 0;
        for (var y = 100; y < 160; y++) {
          for (var x = 340; x < 460; x++) {
            final i = y * s.width + x;
            sum += math.pow(l[i] - b[i], 2);
            n++;
          }
        }
        return sum / n;
      }

      expect(
        grain(outLab.l, fineOut) / grain(inLab.l, fineIn),
        inInclusiveRange(0.4, 1.2),
      );
      double fall(Float64List l) =>
          discMean(l, s.width, s.width * 0.5, s.height * 0.08, 8) -
          discMean(l, s.width, s.width * 0.04, s.height * 0.06, 8);
      expect(fall(outLab.l) / fall(inLab.l), closeTo(1, 0.15));
      expectPersonUntouched(out, margin: 2);
    });

    test('removes banding steps', () {
      final b = renderBackdropScene(banding: true);
      final m = computeRetouchMaps(b.image, b.analysis, backdrop: b.input);
      final after = labOf(_run(b, m, {PortraitIds.bgClean: 100})).l;
      final before = labOf(b.image).l;
      // Column x = 40: RMS deviation of the row profile from its 41-row
      // moving average (the steps), away from specks.
      double steps(Float64List l) {
        final prof = [
          for (var y = 0; y < b.height; y++)
            (l[y * b.width + 39] + l[y * b.width + 40] + l[y * b.width + 41]) /
                3,
        ];
        var sum = 0.0, n = 0;
        for (var y = 30; y < 260; y++) {
          var m = 0.0;
          for (var k = -20; k <= 20; k++) {
            m += prof[y + k];
          }
          sum += math.pow(prof[y] - m / 41, 2);
          n++;
        }
        return math.sqrt(sum / n);
      }

      expect(steps(before), greaterThan(0.002));
      expect(steps(after), lessThan(0.5 * steps(before)));
    });
  });

  group('Unify lighting', () {
    double corner(Float64List l) =>
        discMean(l, s.width, s.width * 0.5, s.height * 0.08, 8) -
        discMean(l, s.width, s.width * 0.04, s.height * 0.06, 8);
    double hotspot(Float64List l) =>
        discMean(l, s.width, s.width * 0.25, s.height * 0.3, 8) -
        discMean(l, s.width, s.width * 0.75, s.height * 0.3, 8);

    test('flattens the falloff and the hotspot', () {
      final out = _run(s, maps, {PortraitIds.bgUnify: 100});
      final l = labOf(out).l;
      expect(corner(inLab.l), greaterThan(0.02));
      expect(corner(l).abs() / corner(inLab.l), lessThan(0.3));
      expect(hotspot(l).abs() / hotspot(inLab.l), lessThan(0.3));
      expectPersonUntouched(out);
    });

    test('Luminance shifts the backdrop, not the person', () {
      for (final v in [100.0, -100.0]) {
        final out = _run(s, maps, {PortraitIds.bgUnifyLuminance: v});
        final l = labOf(out).l;
        final d =
            discMean(l, s.width, s.width * 0.85, s.height * 0.45, 10) -
            discMean(inLab.l, s.width, s.width * 0.85, s.height * 0.45, 10);
        expect(d, closeTo(kBackdropLumMax * v / 100, 0.02), reason: '$v');
        expectPersonUntouched(out);
      }
    });
  });

  group('Stray hairs beyond the figure', () {
    late Float64List out;
    setUpAll(() => out = labOf(_run(s, maps, {PortraitIds.strayHairs: 100})).l);

    test('flyaways off the hair are removed', () {
      for (final f in s.flyaways) {
        final before = _lineDepth(inLab.l, s.width, f);
        expect(before, greaterThan(0.05));
        expect(_lineDepth(out, s.width, f) / before, lessThan(0.25));
      }
    });

    test('lines away from the hair and the person stay', () {
      final d0 = _lineDepth(inLab.l, s.width, s.shoulderLine);
      expect(_lineDepth(out, s.width, s.shoulderLine) / d0, greaterThan(0.9));
      expectPersonUntouched(_run(s, maps, {PortraitIds.strayHairs: 100}));
    });

    test('needs a solid backdrop', () {
      final t = renderBackdropScene(textured: true);
      final m = computeRetouchMaps(t.image, t.analysis, backdrop: t.input);
      final out = _run(t, m, {PortraitIds.strayHairs: 100});
      expect(identical(out, t.image), isTrue);
    });
  });

  test('defaults are bit-exact and skipped', () {
    final u = RetouchUniforms.fromSettings(PortraitSettings.empty, s.analysis);
    expect(u.isIdentity, isTrue);
    expect(retouchPassActive(maps, u), isFalse);
    expect(identical(applyRetouch(s.image, maps, u), s.image), isTrue);
  });

  test('retouchImage builds backdrop maps only when asked', () {
    final st = PortraitSettings.empty.withImageValue(PortraitIds.bgClean, 100);
    final withInput = retouchImage(s.image, s.analysis, st, backdrop: s.input);
    expect(identical(withInput, s.image), isFalse);
    expect(
      identical(retouchImage(s.image, s.analysis, st), s.image),
      isTrue,
      reason: 'no rasters: nothing to clean with',
    );
  });
}
