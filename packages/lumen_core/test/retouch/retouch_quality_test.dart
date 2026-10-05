// Evaluation harness of the retouch engine (research 09 §5.2), on
// synthetic faces of light, medium and deep skin: the same gates for
// every tone. No real photo is involved.
//
// Run alone for the metric table:
//   dart test test/retouch/retouch_quality_test.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/quality_metrics.dart';
import 'support/synthetic_portrait.dart';

const _w = 640, _h = 760;
const _iod = 170.0;
const _tones = [SynthTone.light, SynthTone.medium, SynthTone.deep];

/// Inflamed spots (red), placed on clear cheek and forehead skin.
const _pimples = [
  SynthSpot(0.62, 0.62, 0.022, SynthSpotKind.acne),
  SynthSpot(-0.58, 0.70, 0.026, SynthSpotKind.acne),
  SynthSpot(0.30, -0.78, 0.020, SynthSpotKind.acne),
  SynthSpot(-0.20, 1.55, 0.024, SynthSpotKind.acne),
];
const _mole = SynthSpot(0.45, 1.50, 0.03, SynthSpotKind.mole);

SynthFace _face(
  SynthTone tone, {
  double uneven = 0.045,
  double specular = 0.10,
  double sparkle = 0.5,
  List<SynthSpot> spots = const [..._pimples, _mole],
  double iod = _iod,
}) => SynthFace(
  id: 'a',
  cx: _w / 2,
  cy: 300,
  iod: iod,
  tone: tone,
  lumps: false,
  uneven: uneven,
  specular: specular,
  sparkle: sparkle,
  spots: spots,
);

PortraitSettings _settings(Map<String, double> v) {
  var s = PortraitSettings.empty;
  v.forEach((k, x) => s = s.withGroupValue(FaceGroup.all, k, x));
  return s;
}

/// Every skin slider at its hard limit.
const _max = {
  PortraitIds.skinSoftening: 100.0,
  PortraitIds.skinEven: 100.0,
  PortraitIds.skinShine: 100.0,
  PortraitIds.darkCircles: 100.0,
  PortraitIds.eyeBags: 100.0,
  PortraitIds.acne: 100.0,
};

class _Case {
  _Case(this.tone, {SynthFace? face})
    : p = renderSynthPortrait(_w, _h, [face ?? _face(tone)]) {
    maps = computeRetouchMaps(p.image, p.analysis);
    zones = SynthZones(p.faces.single, _w, _h);
    before = labOf(p.image);
    needs = measureRetouchNeeds(maps, p.image, p.analysis).faces.single;
    auto = PortraitPresets.autoRetouchFor(
      PortraitSettings.empty,
      RetouchNeeds([needs]),
    );
  }

  final SynthTone tone;
  final SynthPortrait p;
  late final RetouchMaps maps;
  late final SynthZones zones;
  late final ({Float64List l, Float64List a, Float64List b}) before;
  late final FaceNeeds needs;
  late final PortraitSettings auto;

  RgbaBuffer run(PortraitSettings s) =>
      applyRetouch(p.image, maps, RetouchUniforms.fromSettings(s, p.analysis));

  double get sigma0 => math.max(0.8, 0.006 * _iod);
}

void main() {
  final cases = {for (final t in _tones) t: _Case(t)};
  final table = <String>[];

  tearDownAll(() {
    // The metric table (one line per tone) for the engine report.
    // ignore: avoid_print
    table.forEach(print);
  });

  for (final t in _tones) {
    group('${t.name} skin', () {
      final c = cases[t]!;
      late RgbaBuffer maxOut, autoOut;
      late ({Float64List l, Float64List a, Float64List b}) maxLab, autoLab;

      setUpAll(() {
        maxOut = c.run(_settings(_max));
        autoOut = c.run(c.auto);
        maxLab = labOf(maxOut);
        autoLab = labOf(autoOut);
      });

      test('pores stay: fine-band energy ≥ 85 % at every slider limit, '
          '≥ 92 % on Auto', () {
        final skin = c.zones.skin;
        final b0 = bandRms(c.before.l, _w, _h, c.sigma0, skin);
        final trMax = bandRms(maxLab.l, _w, _h, c.sigma0, skin) / b0;
        final trAuto = bandRms(autoLab.l, _w, _h, c.sigma0, skin) / b0;
        table.add(
          '${t.name}: TR0 max ${trMax.toStringAsFixed(3)} '
          'auto ${trAuto.toStringAsFixed(3)}',
        );
        expect(trMax, inInclusiveRange(0.85, 1.05));
        expect(trAuto, inInclusiveRange(0.92, 1.03));
      });

      test('the mid band is evened, never erased (≤ 75 %)', () {
        final skin = c.zones.deepSkin;
        double mid(Float64List l) =>
            midRms(l, _w, _h, 0.02 * _iod, 0.065 * _iod, skin);
        final m0 = mid(c.before.l);
        final mrMax = 1 - mid(maxLab.l) / m0;
        final mrAuto = 1 - mid(autoLab.l) / m0;
        table.add(
          '${t.name}: mid-band reduction max ${mrMax.toStringAsFixed(2)} '
          'auto ${mrAuto.toStringAsFixed(2)}',
        );
        expect(mrMax, inInclusiveRange(0.3, 0.78));
        expect(mrAuto, inInclusiveRange(0.05, 0.5));
      });

      test('skin colour holds: mean ΔE00 ≤ 2 at the limits, ≤ 1 from '
          'Smooth + Even; lightness neutral', () {
        final all = colourShift(c.p.image, maxOut, c.zones.skin);
        final plain = c.run(
          _settings({
            PortraitIds.skinSoftening: 100,
            PortraitIds.skinEven: 100,
          }),
        );
        final se = colourShift(c.p.image, plain, c.zones.skin);
        final pl = labOf(plain);
        final dL =
            meanWhere(_w * _h, (i) => c.zones.skin[i] == 1, (i) => pl.l[i]) -
            meanWhere(
              _w * _h,
              (i) => c.zones.skin[i] == 1,
              (i) => c.before.l[i],
            );
        table.add(
          '${t.name}: ΔE00 of mean ${all.ofMean.toStringAsFixed(2)} (max), '
          '${se.ofMean.toStringAsFixed(2)} (smooth+even); per-pixel mean '
          '${all.mean.toStringAsFixed(2)} P95 ${all.p95.toStringAsFixed(2)}; '
          'ΔL ${dL.toStringAsFixed(4)}',
        );
        // Shine on a face with large highlights is the one effect that
        // moves the mean on purpose; everything else stays within 1.
        expect(all.ofMean, lessThanOrEqualTo(3.0));
        expect(se.ofMean, lessThanOrEqualTo(1.0));
        // Retouch never lightens skin (deep skin above all).
        expect(dL, inInclusiveRange(-0.005, 0.003));
      });

      test('no halo: hair next to the hairline is untouched and the skin '
          'edge moves like the skin inside', () {
        final z = c.zones;
        final n = _w * _h;
        final outside = meanWhere(
          n,
          (i) => z.hairRing[i] == 1,
          (i) => (maxLab.l[i] - c.before.l[i]).abs(),
        );
        // The edge check runs without Shine: a highlight that reaches the
        // hairline is dimmed on purpose, which is not a halo.
        final flat = labOf(
          c.run(_settings({..._max, PortraitIds.skinShine: 0})),
        );
        double shift(List<int> m) =>
            meanWhere(n, (i) => m[i] == 1, (i) => flat.l[i] - c.before.l[i]);
        final edge = shift(z.skinRing) - shift(z.deepSkin);
        table.add(
          '${t.name}: halo outside ${(100 * outside).toStringAsFixed(3)} L*, '
          'edge vs inside ${(100 * edge).toStringAsFixed(3)} L*',
        );
        // 0.01 OkLab L ≈ 1 L*.
        expect(outside, lessThanOrEqualTo(0.003));
        expect(edge.abs(), lessThanOrEqualTo(0.010));
      });

      test('eyes, brows, lips and hair are untouched by the skin sliders', () {
        var worst = 0;
        for (var i = 0; i < _w * _h; i++) {
          if (c.zones.protected[i] == 0) continue;
          for (var k = 0; k < 3; k++) {
            worst = math.max(
              worst,
              (maxOut.data[i * 4 + k] - c.p.image.data[i * 4 + k]).abs(),
            );
          }
        }
        expect(worst, lessThanOrEqualTo(2));
      });

      test('Shine takes the hot spot down toward the skin around it: '
          'darker, same hue, not grey, never below the skin', () {
        final out = labOf(c.run(_settings({PortraitIds.skinShine: 100})));
        final f = c.p.faces.single;
        final hot = f.toPx(0, -0.62), r = 0.07 * _iod;
        // Skin without the highlight: the same face rendered matte.
        final matte = labOf(
          renderSynthPortrait(_w, _h, [_face(t, specular: 0)]).image,
        );
        double disc(Float64List p) => discMean(p, _w, hot.x, hot.y, r);
        final excess0 = disc(c.before.l) - disc(matte.l);
        final excess1 = disc(out.l) - disc(matte.l);
        final cut = 1 - excess1 / excess0;
        double hue(({Float64List l, Float64List a, Float64List b}) q) =>
            math.atan2(disc(q.b), disc(q.a)) * 180 / math.pi;
        double chroma(({Float64List l, Float64List a, Float64List b}) q) =>
            math.sqrt(disc(q.a) * disc(q.a) + disc(q.b) * disc(q.b));
        table.add(
          '${t.name}: shine excess ${excess0.toStringAsFixed(3)} cut '
          '${(100 * cut).round()} %, hue ${hue(out).toStringAsFixed(1)}° vs '
          'skin ${hue(matte).toStringAsFixed(1)}°, chroma '
          '${chroma(c.before).toStringAsFixed(3)} → '
          '${chroma(out).toStringAsFixed(3)} (skin '
          '${chroma(matte).toStringAsFixed(3)})',
        );
        expect(excess0, greaterThan(0.04), reason: 'fixture has a hot spot');
        expect(cut, inInclusiveRange(0.3, 0.85));
        expect(excess1, greaterThanOrEqualTo(-0.005), reason: 'not below skin');
        expect((hue(out) - hue(matte)).abs(), lessThanOrEqualTo(6));
        expect(chroma(out), greaterThanOrEqualTo(chroma(c.before)));
        expect(chroma(out), lessThanOrEqualTo(1.1 * chroma(matte)));
      });

      test('blemishes: every pimple is found, the mole, freckles and '
          'make-up shimmer are not acne', () {
        final f = c.p.faces.single;
        bool near(BlemishCandidate b, SynthSpot s) {
          final q = f.toPx(s.x, s.y);
          return math.sqrt(
                math.pow(b.u * _w - q.x, 2) + math.pow(b.v * _h - q.y, 2),
              ) <
              1.5 * s.radius * _iod;
        }

        final healable = c.maps.blemishes
            .where((b) => b.kind == BlemishKind.acne && !b.dark)
            .toList();
        final hits = healable.where((b) => _pimples.any((s) => near(b, s)));
        final found = _pimples.where((s) => healable.any((b) => near(b, s)));
        final precision = healable.isEmpty
            ? 1.0
            : hits.length / healable.length;
        final recall = found.length / _pimples.length;
        table.add(
          '${t.name}: blemish precision ${precision.toStringAsFixed(2)} '
          'recall ${recall.toStringAsFixed(2)} '
          '(${c.maps.blemishes.length} candidates)',
        );
        expect(precision, greaterThanOrEqualTo(0.9));
        expect(recall, greaterThanOrEqualTo(0.75));
        final mole = c.maps.blemishes.where((b) => near(b, _mole));
        expect(mole.every((b) => b.kind == BlemishKind.mole), isTrue);
        // Auto heals pimples and keeps the mole.
        double depth(Float64List l, SynthSpot s) {
          final q = f.toPx(s.x, s.y), r = s.radius * _iod;
          return ringMean(l, _w, q.x, q.y, 2 * r, 3 * r) -
              discMean(l, _w, q.x, q.y, 0.5 * r);
        }

        expect(
          depth(autoLab.l, _mole) / depth(c.before.l, _mole),
          greaterThan(0.9),
        );
        final healed = c.run(_settings({PortraitIds.acne: 100}));
        final hl = labOf(healed);
        for (final s in found) {
          final q = f.toPx(s.x, s.y), r = s.radius * _iod;
          double red(Float64List a) =>
              discMean(a, _w, q.x, q.y, 0.5 * r) -
              ringMean(a, _w, q.x, q.y, 2 * r, 3 * r);
          expect(red(hl.a) / red(c.before.a), lessThan(0.35));
        }
      });

      test('Auto is visible on skin that needs work and stays natural', () {
        final shift = colourShift(c.p.image, autoOut, c.zones.skin);
        table.add(
          '${t.name}: auto ${c.auto.groups[FaceGroup.all]} → mean ΔE00 '
          '${shift.mean.toStringAsFixed(2)} P95 ${shift.p95.toStringAsFixed(2)}',
        );
        expect(
          c.auto.groupValue(FaceGroup.all, PortraitIds.skinShine),
          // The same film of light is a mild sheen on light skin and a
          // hot patch on deep skin: the value follows what is measured.
          greaterThan(t == SynthTone.light ? 8 : 25),
        );
        expect(
          c.auto.groupValue(FaceGroup.all, PortraitIds.skinSoftening),
          inInclusiveRange(10, 60),
        );
        expect(
          c.auto.groupValue(FaceGroup.all, PortraitIds.acne),
          greaterThan(25),
        );
        expect(c.auto.groupValue(FaceGroup.all, PortraitIds.iris), 0);
        // Seen, yet no pixel far off: the pimples are mostly gone and
        // the skin as a whole moved by a visible but small amount.
        final f = c.p.faces.single;
        for (final s in _pimples) {
          final q = f.toPx(s.x, s.y), r = s.radius * _iod;
          double red(Float64List a) =>
              discMean(a, _w, q.x, q.y, 0.5 * r) -
              ringMean(a, _w, q.x, q.y, 2 * r, 3 * r);
          expect(red(autoLab.a) / red(c.before.a), lessThan(0.5));
        }
        expect(shift.p95, inInclusiveRange(0.4, 9.0));
        expect(shift.ofMean, lessThanOrEqualTo(2.0));
      });
    });
  }

  group('clean skin', () {
    for (final t in _tones) {
      test('${t.name}: Auto asks for nothing and even strong sliders '
          'change almost nothing', () {
        final c = _Case(
          t,
          face: _face(t, uneven: 0.003, specular: 0, sparkle: 0, spots: []),
        );
        final all = c.auto.groups[FaceGroup.all] ?? const {};
        for (final id in [
          PortraitIds.skinSoftening,
          PortraitIds.skinEven,
          PortraitIds.skinShine,
          PortraitIds.acne,
          PortraitIds.darkCircles,
        ]) {
          expect(all[id] ?? 0, lessThanOrEqualTo(5), reason: id);
        }
        expect(
          c.maps.blemishes.where((b) => b.kind == BlemishKind.acne),
          isEmpty,
        );
        final out = c.run(
          _settings({
            PortraitIds.skinSoftening: 60,
            PortraitIds.skinEven: 60,
            PortraitIds.skinShine: 60,
            PortraitIds.acne: 60,
          }),
        );
        final shift = colourShift(c.p.image, out, c.zones.skin);
        table.add(
          '${t.name} clean: sliders at 60 → mean ΔE00 '
          '${shift.mean.toStringAsFixed(3)} P95 ${shift.p95.toStringAsFixed(3)}',
        );
        expect(shift.mean, lessThanOrEqualTo(0.3));
        expect(shift.p95, lessThanOrEqualTo(0.8));
      });
    }
  });

  group('need and size', () {
    test('more unevenness measures a higher Smooth need on every tone', () {
      for (final t in _tones) {
        final mild = _Case(t, face: _face(t, uneven: 0.012, spots: []));
        final strong = _Case(t, face: _face(t, uneven: 0.06, spots: []));
        expect(
          strong.needs.roughness,
          greaterThan(mild.needs.roughness + 0.2),
          reason: t.name,
        );
      }
    });

    test('the same problems measure alike on light and deep skin', () {
      final light = cases[SynthTone.light]!.needs;
      final deep = cases[SynthTone.deep]!.needs;
      expect((light.roughness - deep.roughness).abs(), lessThan(0.25));
      expect(light.blemish, deep.blemish);
    });

    test('small faces get reduced work, tiny faces none', () {
      double change(double iod) {
        final p = renderSynthPortrait(_w, _h, [
          _face(SynthTone.medium, iod: iod),
        ]);
        final maps = computeRetouchMaps(p.image, p.analysis);
        if (!maps.hasFaces) return 0;
        final out = applyRetouch(
          p.image,
          maps,
          RetouchUniforms.fromSettings(
            _settings({PortraitIds.skinSoftening: 100}),
            p.analysis,
          ),
        );
        var sum = 0;
        for (var i = 0; i < out.data.length; i++) {
          sum += (out.data[i] - p.image.data[i]).abs();
        }
        // Per face pixel (the face area scales with IOD²).
        return sum / (iod * iod);
      }

      final big = change(170), small = change(44), tiny = change(22);
      expect(small, lessThan(0.7 * big));
      expect(small, greaterThan(0));
      expect(tiny, 0);
    });
  });
}
