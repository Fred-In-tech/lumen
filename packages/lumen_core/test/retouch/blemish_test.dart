import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

const _w = 512, _h = 512;
const _face = SynthFace(id: 'a', cx: 256, cy: 200, iod: 140);

BlemishKind _kind(SynthSpotKind k) => switch (k) {
  SynthSpotKind.acne => BlemishKind.acne,
  SynthSpotKind.freckle => BlemishKind.freckle,
  SynthSpotKind.mole => BlemishKind.mole,
};

void main() {
  late SynthPortrait p;
  late RetouchMaps maps;
  late ({Float64List l, Float64List a, Float64List b}) inLab;

  setUpAll(() {
    p = renderSynthPortrait(_w, _h, [_face]);
    maps = computeRetouchMaps(p.image, p.analysis);
    inLab = labOf(p.image);
  });

  BlemishCandidate? candidateFor(RetouchMaps m, SynthSpot s) {
    final c = _face.toPx(s.x, s.y);
    BlemishCandidate? best;
    var bestD = 0.03 * _face.iod;
    for (final b in m.blemishes) {
      final d = math.sqrt(
        math.pow(b.u * _w - c.x, 2) + math.pow(b.v * _h - c.y, 2),
      );
      if (d < bestD) {
        bestD = d;
        best = b;
      }
    }
    return best;
  }

  /// |centre − ring| contrast of a spot in L and a*.
  ({double l, double a}) contrast(
    ({Float64List l, Float64List a, Float64List b}) lab,
    SynthSpot s,
  ) {
    final c = _face.toPx(s.x, s.y), r = s.radius * _face.iod;
    double one(Float64List p) =>
        (discMean(p, _w, c.x, c.y, 0.5 * r) -
                ringMean(p, _w, c.x, c.y, 2 * r, 3 * r))
            .abs();
    return (l: one(lab.l), a: one(lab.a));
  }

  RgbaBuffer run(Map<String, double> values, [RetouchMaps? m]) {
    var s = PortraitSettings.empty;
    for (final e in values.entries) {
      s = s.withGroupValue(FaceGroup.all, e.key, e.value);
    }
    return applyRetouch(
      p.image,
      m ?? maps,
      RetouchUniforms.fromSettings(s, p.analysis),
    );
  }

  group('detection', () {
    test('finds every planted spot with its class and size', () {
      for (final s in kDefaultSpots) {
        final b = candidateFor(maps, s);
        expect(b, isNotNull, reason: 'spot at ${s.x},${s.y}');
        expect(b!.kind, _kind(s.kind), reason: 'spot at ${s.x},${s.y}');
        expect(b.radiusIod, closeTo(s.radius, 0.4 * s.radius));
        expect(b.faceId, 'a');
        expect(b.slot, 0);
      }
    });

    test('obvious spots heal from a low slider value', () {
      for (final s in kAcneSpots) {
        expect(candidateFor(maps, s)!.threshold, lessThan(0.45));
      }
    });

    test('ignores line ends and features (no spot on the stripe)', () {
      final stripe = _face.toPx(kStripeX, kPatchY0 + 0.02);
      for (final b in maps.blemishes) {
        final d = math.sqrt(
          math.pow(b.u * _w - stripe.x, 2) + math.pow(b.v * _h - stripe.y, 2),
        );
        expect(d, greaterThan(0.05 * _face.iod), reason: b.toString());
      }
    });
  });

  group('healing (§3.3)', () {
    late ({Float64List l, Float64List a, Float64List b}) acneOut;

    setUpAll(() {
      acneOut = labOf(run({PortraitIds.acne: 100, PortraitIds.freckle: 0}));
    });

    test('acne-class spots are removed', () {
      for (final s in kAcneSpots) {
        final before = contrast(inLab, s), after = contrast(acneOut, s);
        expect(after.a / before.a, lessThan(0.3), reason: '${s.x},${s.y}');
        expect(after.l, lessThan(0.3 * before.l + 0.003));
      }
    });

    test('freckles and moles remain while their sliders are 0', () {
      for (final s in [...kFreckleSpots, ...kMoleSpots]) {
        final before = contrast(inLab, s), after = contrast(acneOut, s);
        expect(after.l / before.l, greaterThan(0.9), reason: '${s.x},${s.y}');
      }
    });

    test('pores continue through a healed spot', () {
      final s = kAcneSpots.first;
      final c = _face.toPx(s.x, s.y), r = s.radius * _face.iod;
      final fineIn = blur(inLab.l, _w, _h, 1.0);
      final fineOut = blur(acneOut.l, _w, _h, 1.0);
      double energy(Float64List l, Float64List b, double r0, double r1) {
        var sum = 0.0, n = 0;
        for (var y = (c.y - r1).floor(); y <= (c.y + r1).ceil(); y++) {
          for (var x = (c.x - r1).floor(); x <= (c.x + r1).ceil(); x++) {
            final d = math.sqrt(
              math.pow(x + 0.5 - c.x, 2) + math.pow(y + 0.5 - c.y, 2),
            );
            if (d < r0 || d > r1) continue;
            final i = y * _w + x;
            sum += math.pow(l[i] - b[i], 2);
            n++;
          }
        }
        return sum / n;
      }

      final inside = energy(acneOut.l, fineOut, 0, 0.8 * r);
      final ring = energy(inLab.l, fineIn, 2 * r, 3 * r);
      expect(inside / ring, greaterThan(0.4));
    });

    test('the freckle slider removes freckles', () {
      final out = labOf(run({PortraitIds.freckle: 100}));
      for (final s in kFreckleSpots) {
        expect(contrast(out, s).l / contrast(inLab, s).l, lessThan(0.3));
      }
      for (final s in kAcneSpots) {
        expect(contrast(out, s).a / contrast(inLab, s).a, greaterThan(0.9));
      }
    });

    test('the mole slider removes the mole', () {
      final out = labOf(run({PortraitIds.mole: 100}));
      final s = kMoleSpots.first;
      expect(contrast(out, s).l / contrast(inLab, s).l, lessThan(0.3));
    });

    test('keep / remove overrides pick individual spots', () {
      final keep = candidateFor(maps, kAcneSpots.first)!.id;
      final remove = candidateFor(maps, kFreckleSpots.first)!.id;
      final m = computeRetouchMaps(
        p.image,
        p.analysis,
        overrides: BlemishOverrides(keep: {keep}, remove: {remove}),
      );
      final out = labOf(run({PortraitIds.acne: 100}, m));
      final kept = kAcneSpots.first, removed = kFreckleSpots.first;
      expect(contrast(out, kept).a / contrast(inLab, kept).a, greaterThan(0.9));
      expect(
        contrast(out, removed).l / contrast(inLab, removed).l,
        lessThan(0.3),
      );
      expect(
        contrast(out, kFreckleSpots[1]).l / contrast(inLab, kFreckleSpots[1]).l,
        greaterThan(0.9),
      );
    });
  });

  group('selection math', () {
    test('threshold follows k = mix(4.5, 3, v) and maxR = mix(.02, .05, v); '
        'dark marks never heal below 30', () {
      expect(blemishThreshold(4.5, 0.01), 0);
      expect(blemishThreshold(3.75, 0.01), closeTo(0.5, 1e-9));
      expect(blemishThreshold(10, 0.035), closeTo(0.5, 1e-9));
      expect(blemishThreshold(1.0, 0.01), 1);
      expect(blemishThreshold(10, 0.01, floor: kDarkSpotMinSlider), 0.3);
    });

    test('spot codes round-trip and ramp in over kSpotRamp', () {
      final code = encodeSpotCode(BlemishKind.freckle, 0.5);
      expect(spotSelection(code, 1, 0, 1), 0, reason: 'freckle slider 0');
      expect(spotSelection(code, 0, 0.5, 0), closeTo(0, 0.02));
      expect(spotSelection(code, 0, 0.5 + kSpotRamp / 2, 0), closeTo(0.5, 0.1));
      expect(spotSelection(code, 0, 1, 0), 1);
      expect(spotSelection(0, 1, 1, 1), 0);
      final forced = encodeSpotCode(BlemishKind.mole, 0.9, forced: true);
      expect(spotSelection(forced, 0, 0, 0), 1);
      expect(encodeSpotCode(BlemishKind.mole, 1), lessThan(256));
    });
  });
}
