// Segmentation-based skin masks (research 09 §4.2 with a parsing model,
// metrics of §5.2): synthetic faces of light, medium and deep skin with
// blond or grey hair close to the skin's colour over the forehead, a neck
// below the jaw, glasses and stubble; "parsing" is the generator's ground
// truth at a model's resolution (`support/synthetic_parsing.dart`).
//
// Run alone for the metric table:
//   dart test test/retouch/parsing_mask_test.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/quality_metrics.dart';
import 'support/synthetic_landmarks.dart';
import 'support/synthetic_parsing.dart';
import 'support/synthetic_portrait.dart';

const _w = 640, _h = 760;
const _iod = 170.0;

SynthFace _face(
  SynthTone tone, {
  SynthHair hair = SynthHair.blond,
  SynthGlasses glasses = SynthGlasses.none,
  bool stubble = false,
}) => SynthFace(
  id: 'a',
  cx: _w / 2,
  cy: 300,
  iod: _iod,
  tone: tone,
  lumps: false,
  uneven: 0.045,
  specular: 0.05,
  spots: const [],
  hair: hair,
  fringe: true,
  neck: true,
  glasses: glasses,
  penPatches: stubble,
);

PortraitSettings _settings(Map<String, double> v) {
  var s = PortraitSettings.empty;
  v.forEach((k, x) => s = s.withGroupValue(FaceGroup.all, k, x));
  return s;
}

/// Ground-truth masks of the image pixels of [f].
class _Truth {
  _Truth(SynthFace f)
    : fringe = Uint8List(_w * _h),
      neck = Uint8List(_w * _h),
      skin = Uint8List(_w * _h),
      rim = Uint8List(_w * _h) {
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        final q = f.toLocal(x + 0.5, y + 0.5), i = y * _w + x;
        final c = synthClassAt(f, q.x, q.y);
        if (c == ParsingClass.hair && q.y > kFringeY0 && q.y < kFringeY1) {
          // The fringe band inside the oval, away from its edges.
          if (q.y > kFringeY0 + 0.04 && q.y < kFringeY1 - 0.04) fringe[i] = 1;
        }
        // The neck well below the jaw: the mask eases from the face to the
        // capped weight over about 0.15 IOD.
        final jaw =
            kOvalCy +
            kOvalRyBottom *
                math.sqrt(math.max(0.0, 1 - math.pow(q.x / kOvalRx, 2)));
        if (c == ParsingClass.bodySkin &&
            q.x.abs() < kNeckHalfW - 0.08 &&
            q.y > jaw + 0.25 &&
            q.y < kNeckY1 - 0.08) {
          neck[i] = 1;
        }
        if (c == ParsingClass.faceSkin || c == ParsingClass.bodySkin) {
          skin[i] = 1;
        }
        if (c == ParsingClass.accessories) rim[i] = 1;
      }
    }
  }

  final Uint8List fringe;
  final Uint8List neck;
  final Uint8List skin;
  final Uint8List rim;
}

class _Case {
  _Case(this.name, SynthFace face)
    : p = renderSynthPortrait(_w, _h, [face]),
      truth = _Truth(face) {
    heuristic = computeRetouchMaps(p.image, p.analysis);
    final plans = planFaceTiles(p.analysis, _w, _h);
    parsed = computeRetouchMaps(
      p.image,
      p.analysis,
      parsing: [for (final t in plans) synthParsing(p, t)],
    );
    zones = SynthZones(face, _w, _h);
  }

  final String name;
  final SynthPortrait p;
  final _Truth truth;
  late final RetouchMaps heuristic;
  late final RetouchMaps parsed;
  late final SynthZones zones;

  /// Skin effect weight (0..1) per image pixel.
  Float64List skinOf(RetouchMaps m) {
    final out = Float64List(_w * _h);
    for (var i = 0; i < out.length; i++) {
      out[i] = regionAt(m, RetouchChannel.skin, i % _w, i ~/ _w, _w, _h);
    }
    return out;
  }

  RgbaBuffer run(RetouchMaps m, Map<String, double> v) => applyRetouch(
    p.image,
    m,
    RetouchUniforms.fromSettings(_settings(v), p.analysis),
  );
}

double _mean(Float64List v, Uint8List m) =>
    meanWhere(v.length, (i) => m[i] == 1, (i) => v[i]);

/// Share of the skin-effect weight that lands on ground-truth skin.
double _precision(Float64List e, Uint8List skin) {
  var on = 0.0, all = 0.0;
  for (var i = 0; i < e.length; i++) {
    all += e[i];
    if (skin[i] == 1) on += e[i];
  }
  return all == 0 ? 1 : on / all;
}

void main() {
  final table = <String>[];
  tearDownAll(() {
    // ignore: avoid_print
    table.forEach(print);
  });

  final cases = [
    for (final t in [SynthTone.light, SynthTone.medium, SynthTone.deep])
      _Case('${t.name} blond', _face(t)),
    _Case('light grey', _face(SynthTone.light, hair: SynthHair.grey)),
    _Case(
      'medium glasses+stubble',
      _face(
        SynthTone.medium,
        hair: SynthHair.dark,
        glasses: SynthGlasses.clear,
        stubble: true,
      ),
    ),
  ];

  for (final c in cases) {
    group(c.name, () {
      late Float64List eh, ep;
      setUpAll(() {
        eh = c.skinOf(c.heuristic);
        ep = c.skinOf(c.parsed);
      });

      test('hair over the forehead is excluded; precision vs hair', () {
        final leakH = _mean(eh, c.truth.fringe);
        final leakP = _mean(ep, c.truth.fringe);
        final precH = _precision(eh, c.truth.skin);
        final precP = _precision(ep, c.truth.skin);
        table.add(
          '${c.name}: fringe skin weight ${leakH.toStringAsFixed(3)} → '
          '${leakP.toStringAsFixed(3)}; mask precision '
          '${precH.toStringAsFixed(3)} → ${precP.toStringAsFixed(3)}',
        );
        expect(leakP, lessThanOrEqualTo(0.05));
        expect(leakP, lessThanOrEqualTo(leakH + 1e-9));
        expect(precP, greaterThanOrEqualTo(0.97));
        expect(precP, greaterThanOrEqualTo(precH - 0.005));
      });

      test('the neck gets the capped skin treatment', () {
        final nh = _mean(eh, c.truth.neck), np = _mean(ep, c.truth.neck);
        var maxP = 0.0;
        for (var i = 0; i < ep.length; i++) {
          if (c.truth.neck[i] == 1 && ep[i] > maxP) maxP = ep[i];
        }
        table.add(
          '${c.name}: neck skin weight ${nh.toStringAsFixed(3)} → '
          '${np.toStringAsFixed(3)} (max ${maxP.toStringAsFixed(3)})',
        );
        expect(nh, lessThanOrEqualTo(0.05), reason: 'heuristic: face only');
        expect(np, greaterThan(0.25));
        expect(maxP, lessThanOrEqualTo(kOffFaceSkinCap + 0.03));
      });

      test('glasses rims stay untouched', () {
        if (!c.truth.rim.contains(1)) return;
        expect(_mean(eh, c.truth.rim), lessThanOrEqualTo(0.02));
        expect(_mean(ep, c.truth.rim), lessThanOrEqualTo(0.02));
      });

      test('pores, colour and halo hold with parsing', () {
        final max = c.run(c.parsed, {
          PortraitIds.skinSoftening: 100,
          PortraitIds.skinEven: 100,
          PortraitIds.darkCircles: 100,
        });
        final before = labOf(c.p.image), after = labOf(max);
        final sigma0 = 0.006 * _iod;
        final skin = c.zones.skin;
        final tr =
            bandRms(after.l, _w, _h, sigma0, skin) /
            bandRms(before.l, _w, _h, sigma0, skin);
        final se = colourShift(c.p.image, max, skin);
        final halo = meanWhere(
          _w * _h,
          (i) => c.zones.hairRing[i] == 1,
          (i) => (after.l[i] - before.l[i]).abs(),
        );
        // The fringe itself is hair: nothing may move there.
        final fringe = meanWhere(
          _w * _h,
          (i) => c.truth.fringe[i] == 1,
          (i) => (after.l[i] - before.l[i]).abs(),
        );
        table.add(
          '${c.name}: parsed TR0 ${tr.toStringAsFixed(3)}, ΔE00 of mean '
          '${se.ofMean.toStringAsFixed(2)}, halo '
          '${(100 * halo).toStringAsFixed(3)} L*, fringe '
          '${(100 * fringe).toStringAsFixed(3)} L*',
        );
        expect(tr, inInclusiveRange(0.85, 1.05));
        expect(se.ofMean, lessThanOrEqualTo(1.0));
        expect(halo, lessThanOrEqualTo(0.003));
        expect(fringe, lessThanOrEqualTo(0.003));
      });
    });
  }

  group('fallback', () {
    test(
      'no parsing (or none for this face) is today\'s heuristic exactly',
      () {
        final c = cases.first;
        final plans = planFaceTiles(c.p.analysis, _w, _h);
        final other = synthParsing(c.p, plans.first);
        final foreign = FaceParsingPlanes(
          faceId: 'someone else',
          cropX: other.cropX,
          cropY: other.cropY,
          cropWidth: other.cropWidth,
          cropHeight: other.cropHeight,
          width: other.width,
          height: other.height,
          background: other.background,
          hair: other.hair,
          bodySkin: other.bodySkin,
          faceSkin: other.faceSkin,
          clothes: other.clothes,
          accessories: other.accessories,
        );
        for (final parsing in [
          <FaceParsingPlanes>[],
          [foreign],
        ]) {
          final m = computeRetouchMaps(
            c.p.image,
            c.p.analysis,
            parsing: parsing,
          );
          expect(m.regionA, c.heuristic.regionA);
          expect(m.regionB, c.heuristic.regionB);
          expect(m.deltaA, c.heuristic.deltaA);
        }
      },
    );
  });
}
