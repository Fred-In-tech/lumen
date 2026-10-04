import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

const _w = 512, _h = 512;
const _face = SynthFace(id: 'a', cx: 256, cy: 200, iod: 140);

PortraitSettings _settings(Map<String, double> values) {
  var s = PortraitSettings.empty;
  for (final e in values.entries) {
    s = e.key == PortraitIds.skinTexture || e.key == PortraitIds.lidProtect
        ? s.withGroupValue(FaceGroup.all, e.key, e.value)
        : s.withGroupValue(FaceGroup.all, e.key, e.value);
  }
  return s;
}

void main() {
  late SynthPortrait p;
  late RetouchMaps maps;
  late ({Float64List l, Float64List a, Float64List b}) inLab;
  late Uint8List interior;

  /// [interior] minus a margin of the metric blurs' reach.
  late Uint8List core;

  RgbaBuffer run(Map<String, double> values) => applyRetouch(
    p.image,
    maps,
    RetouchUniforms.fromSettings(_settings(values), p.analysis),
  );

  double region(RetouchChannel c, int i) =>
      regionAt(maps, c, i % _w, i ~/ _w, _w, _h);

  setUpAll(() {
    p = renderSynthPortrait(_w, _h, [_face]);
    maps = computeRetouchMaps(p.image, p.analysis);
    inLab = labOf(p.image);
    // Skin interior away from spots and the flat test patch.
    interior = Uint8List(_w * _h);
    for (var i = 0; i < _w * _h; i++) {
      final q = _face.toLocal(i % _w + 0.5, i ~/ _w + 0.5);
      final nearSpot = _face.spots.any(
        (s) =>
            math.sqrt(math.pow(q.x - s.x, 2) + math.pow(q.y - s.y, 2)) <
            2.5 * s.radius,
      );
      final inPatch =
          q.x > kPatchX0 - 0.05 &&
          q.x < kPatchX1 + 0.05 &&
          q.y > kPatchY0 - 0.05 &&
          q.y < kPatchY1 + 0.05;
      // Broad base-band features smoothing must keep (shine, dark circles).
      final baseBand =
          math.pow(q.x, 2) + math.pow(q.y + 0.6, 2) < 0.35 * 0.35 ||
          math.pow(q.x, 2) + math.pow(q.y - 0.68, 2) < 0.15 * 0.15 ||
          (q.y > -0.05 && q.y < 0.35 && q.x.abs() > 0.15 && q.x.abs() < 0.85);
      if (!nearSpot &&
          !inPatch &&
          !baseBand &&
          region(RetouchChannel.skin, i) >= 0.98) {
        interior[i] = 1;
      }
    }
    core = erodeMask(interior, _w, _h, (0.12 * _face.iod).round());
  });

  /// Variance of the mid band (G(0.02 IOD) − G(0.06 IOD)) on the skin.
  double midVariance(Float64List l) {
    final b1 = blur(l, _w, _h, 0.02 * _face.iod);
    final b2 = blur(l, _w, _h, 0.06 * _face.iod);
    bool m(int i) => core[i] == 1;
    expect(meanWhere(_w * _h, m, (i) => 1), 1, reason: 'non-empty core');
    final mean = meanWhere(_w * _h, m, (i) => b1[i] - b2[i]);
    return meanWhere(
      _w * _h,
      m,
      (i) => math.pow(b1[i] - b2[i] - mean, 2).toDouble(),
    );
  }

  /// Mean |centre − ring| L contrast of the mid-band blotches.
  double blotchContrast(Float64List l) {
    var sum = 0.0;
    for (final b in kBlotches) {
      final c = _face.toPx(b.x, b.y), f = _face.iod;
      sum +=
          (discMean(l, _w, c.x, c.y, 0.012 * f) -
                  ringMean(l, _w, c.x, c.y, 0.06 * f, 0.08 * f))
              .abs();
    }
    return sum / kBlotches.length;
  }

  double fineEnergy(Float64List l) {
    final b = blur(l, _w, _h, 1.0);
    return meanWhere(
      _w * _h,
      (i) => interior[i] == 1,
      (i) => math.pow(l[i] - b[i], 2).toDouble(),
    );
  }

  group('skin smoothing (§3.1)', () {
    late ({Float64List l, Float64List a, Float64List b}) smooth;
    late RgbaBuffer smoothImg;

    setUpAll(() {
      smoothImg = run({PortraitIds.skinSoftening: 100});
      smooth = labOf(smoothImg);
    });

    test('lowers the mid-band variance on skin', () {
      expect(kBlotches.length, greaterThan(40));
      expect(midVariance(smooth.l) / midVariance(inLab.l), lessThan(0.5));
      expect(blotchContrast(smooth.l) / blotchContrast(inLab.l), lessThan(0.5));
    });

    test('leaves every pixel outside the skin map bit-exact', () {
      var outside = 0, changedInside = 0;
      for (var i = 0; i < _w * _h; i++) {
        final same =
            smoothImg.data[i * 4] == p.image.data[i * 4] &&
            smoothImg.data[i * 4 + 1] == p.image.data[i * 4 + 1] &&
            smoothImg.data[i * 4 + 2] == p.image.data[i * 4 + 2];
        if (region(RetouchChannel.skin, i) == 0) {
          outside++;
          expect(same, isTrue, reason: 'pixel ${i % _w},${i ~/ _w}');
        } else if (!same) {
          changedInside++;
        }
      }
      expect(outside, greaterThan(_w * _h ~/ 2));
      expect(changedInside, greaterThan(10000));
    });

    test('keeps the fine band (pores) at the default texture', () {
      final ratio = fineEnergy(smooth.l) / fineEnergy(inLab.l);
      expect(ratio, inInclusiveRange(0.85, 1.15));
    });

    test('Texture −100 softens the fine band, +100 boosts it', () {
      final soft = fineEnergy(labOf(run({PortraitIds.skinTexture: -100})).l);
      final hard = fineEnergy(labOf(run({PortraitIds.skinTexture: 100})).l);
      final base = fineEnergy(inLab.l);
      expect(soft / base, lessThan(0.5));
      expect(hard / base, greaterThan(1.4));
    });

    test('is amplitude selective: a high-contrast edge survives', () {
      final c = _face.toPx(kStripeX, 0.8), f = _face.iod;
      double stripe(Float64List l) =>
          (discMean(l, _w, c.x - 0.07 * f, c.y, 0.03 * f) +
                  discMean(l, _w, c.x + 0.07 * f, c.y, 0.03 * f)) /
              2 -
          discMean(l, _w, c.x, c.y, 0.012 * f);
      final b = _face.toPx(kPatchBlotchX, kPatchBlotchY);
      double blotch(Float64List l) =>
          ringMean(l, _w, b.x, b.y, 0.1 * f, 0.14 * f) -
          discMean(l, _w, b.x, b.y, 0.02 * f);
      expect(stripe(inLab.l), greaterThan(0.08));
      // The edge-aware base B2 holds ~90 % of a strong edge; the rest leaks
      // into mid like a blotch would, so ≥ 80 % survives maximum smoothing
      // while low-amplitude blotches lose most of their contrast.
      expect(stripe(smooth.l) / stripe(inLab.l), greaterThan(0.8));
      expect(blotch(smooth.l) / blotch(inLab.l), lessThan(0.6));
    });
  });

  group('eyes and under-eye', () {
    bool underEye(int i) =>
        region(RetouchChannel.underEye, i) > 0.6 &&
        region(RetouchChannel.lash, i) < 0.1;

    test('dark circles close most of the gap to the cheek', () {
      final out = labOf(run({PortraitIds.darkCircles: 100})).l;
      final cheeks = [_face.toPx(-0.5, 0.42), _face.toPx(0.5, 0.42)];
      double cheek(Float64List l) =>
          cheeks
              .map((c) => discMean(l, _w, c.x, c.y, 0.06 * _face.iod))
              .reduce((x, y) => x + y) /
          2;
      double gap(Float64List l) =>
          cheek(l) - meanWhere(_w * _h, underEye, (i) => l[i]);
      expect(gap(inLab.l), greaterThan(0.02));
      expect(gap(out) / gap(inLab.l), lessThan(0.6));
    });

    test('lower-lid protection shields the lash line', () {
      bool lashBand(int i) =>
          region(RetouchChannel.lash, i) > 0.8 &&
          region(RetouchChannel.underEye, i) > 0.3;
      double lift(double protect) {
        final out = labOf(
          run({PortraitIds.darkCircles: 100, PortraitIds.lidProtect: protect}),
        ).l;
        return meanWhere(_w * _h, lashBand, (i) => out[i] - inLab.l[i]);
      }

      expect(lift(100), lessThan(0.5 * lift(0)));
    });

    test('eye whites lose red/yellow and never darken', () {
      final out = labOf(run({PortraitIds.eyeWhites: 100}));
      bool sclera(int i) => region(RetouchChannel.sclera, i) > 0.9;
      expect(
        meanWhere(_w * _h, sclera, (i) => out.b[i]),
        lessThan(0.75 * meanWhere(_w * _h, sclera, (i) => inLab.b[i])),
      );
      expect(
        meanWhere(_w * _h, sclera, (i) => out.l[i] - inLab.l[i]),
        greaterThanOrEqualTo(0),
      );
    });

    test('iris gains chroma', () {
      final out = labOf(run({PortraitIds.iris: 100}));
      bool iris(int i) => region(RetouchChannel.iris, i) > 0.9;
      double chroma(({Float64List l, Float64List a, Float64List b}) c, int i) =>
          math.sqrt(c.a[i] * c.a[i] + c.b[i] * c.b[i]);
      expect(
        meanWhere(_w * _h, iris, (i) => chroma(out, i)),
        greaterThan(1.15 * meanWhere(_w * _h, iris, (i) => chroma(inLab, i))),
      );
    });
  });

  test('reduce shine pulls the forehead highlight down', () {
    final c = _face.toPx(0, -0.6);
    final out = labOf(run({PortraitIds.skinShine: 100})).l;
    final before = discMean(inLab.l, _w, c.x, c.y, 0.05 * _face.iod);
    final after = discMean(out, _w, c.x, c.y, 0.05 * _face.iod);
    expect(before - after, greaterThan(0.02));
  });

  test('even tone flattens broad redness without moving L', () {
    final out = labOf(run({PortraitIds.skinEven: 100}));
    final red = _face.toPx(kRednessX, kRednessY);
    final ref = _face.toPx(-kRednessX, kRednessY);
    final r = 0.05 * _face.iod;
    double redness(Float64List a) =>
        discMean(a, _w, red.x, red.y, r) - discMean(a, _w, ref.x, ref.y, r);
    expect(redness(inLab.a), greaterThan(0.012));
    expect(redness(out.a) / redness(inLab.a), lessThan(0.65));
    expect(
      discMean(out.l, _w, red.x, red.y, r),
      closeTo(discMean(inLab.l, _w, red.x, red.y, r), 0.003),
    );
  });

  group('identity', () {
    test('defaults return the input itself, bit-exact', () {
      final u = RetouchUniforms.fromSettings(
        PortraitSettings.empty,
        p.analysis,
      );
      expect(u.isIdentity, isTrue);
      expect(identical(applyRetouch(p.image, maps, u), p.image), isTrue);
      expect(
        identical(
          retouchImage(p.image, p.analysis, PortraitSettings.empty),
          p.image,
        ),
        isTrue,
      );
    });

    test('explicit default values are still the identity', () {
      final s = _settings({
        PortraitIds.skinTexture: 0,
        PortraitIds.lidProtect: 100,
        PortraitIds.skinSoftening: 0,
      });
      final u = RetouchUniforms.fromSettings(s, p.analysis);
      expect(u.isIdentity, isTrue);
      expect(identical(retouchImage(p.image, p.analysis, s), p.image), isTrue);
    });

    test('a zero-strength row inside the face changes nothing', () {
      // Lid protection alone is inert: rows stay identity.
      final s = _settings({PortraitIds.lidProtect: 0});
      final out = applyRetouch(
        p.image,
        maps,
        RetouchUniforms.fromSettings(s, p.analysis),
      );
      expect(out.data, p.image.data);
    });
  });
}
