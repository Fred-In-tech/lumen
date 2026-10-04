import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:lumen_core/src/retouch/lab_planes.dart';
import 'package:lumen_core/src/retouch/makeup.dart';
import 'package:lumen_core/src/retouch/skin_model.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_portrait.dart';

const _w = 512, _h = 512;
const _face = SynthFace(id: 'a', cx: 256, cy: 200, iod: 140);

void main() {
  late SynthPortrait p;
  late RetouchMaps maps;
  late ({Float64List l, Float64List a, Float64List b}) inLab;

  setUpAll(() {
    p = renderSynthPortrait(_w, _h, [_face]);
    maps = computeRetouchMaps(p.image, p.analysis);
    inLab = labOf(p.image);
  });

  RgbaBuffer run(Map<String, double> values) {
    var s = PortraitSettings.empty;
    for (final e in values.entries) {
      s = s.withGroupValue(FaceGroup.all, e.key, e.value);
    }
    return applyRetouch(
      p.image,
      maps,
      RetouchUniforms.fromSettings(s, p.analysis),
    );
  }

  double region(RetouchChannel c, int i) =>
      regionAt(maps, c, i % _w, i ~/ _w, _w, _h);

  group('lip colour', () {
    late ({Float64List l, Float64List a, Float64List b}) out;
    bool lip(int i) {
      if (region(RetouchChannel.lips, i) < 0.9) return false;
      final q = _face.toLocal(i % _w + 0.5, i ~/ _w + 0.5);
      return math.sqrt(
            math.pow(q.x - kGlossX, 2) + math.pow(q.y - kGlossY, 2),
          ) >
          4 * kGlossSigma;
    }

    double chroma(({Float64List l, Float64List a, Float64List b}) c, int i) =>
        math.sqrt(c.a[i] * c.a[i] + c.b[i] * c.b[i]);

    setUpAll(() => out = labOf(run({PortraitIds.lips: 100})));

    test('the face has natural lip targets', () {
      final f = maps.faceInSlot(0)!;
      expect(f.lipChromaGain, closeTo(kLipChromaBoost, 0.05));
      expect(f.lipShiftL, closeTo(-kLipDeepenL, 1e-6));
      expect(f.lipGlossL, greaterThan(0.6));
    });

    test('raises lip chroma without moving the hue', () {
      const n = _w * _h;
      final before = meanWhere(n, lip, (i) => chroma(inLab, i));
      final after = meanWhere(n, lip, (i) => chroma(out, i));
      expect(after / before, greaterThan(1.25));
      final dh = meanWhere(n, lip, (i) {
        final h0 = math.atan2(inLab.b[i], inLab.a[i]);
        final h1 = math.atan2(out.b[i], out.a[i]);
        return (h1 - h0).abs();
      });
      expect(dh * 180 / math.pi, lessThan(1.0), reason: 'mean hue drift (°)');
      final dl = meanWhere(n, lip, (i) => out.l[i] - inLab.l[i]);
      expect(dl, inInclusiveRange(-kLipDeepenL - 0.005, -0.02));
    });

    test('keeps the lip lines and the gloss highlight', () {
      const n = _w * _h;
      double rippleStd(Float64List l) {
        final mean = meanWhere(n, lip, (i) => l[i]);
        return math.sqrt(
          meanWhere(n, lip, (i) => math.pow(l[i] - mean, 2).toDouble()),
        );
      }

      expect(rippleStd(out.l) / rippleStd(inLab.l), closeTo(1, 0.1));
      final g = _face.toPx(kGlossX, kGlossY);
      final i = g.y.floor() * _w + g.x.floor();
      expect(out.l[i], closeTo(inLab.l[i], 0.01));
      expect(chroma(out, i), closeTo(chroma(inLab, i), 0.01));
    });

    test('touches nothing outside the lips', () {
      final out = run({PortraitIds.lips: 100});
      var changed = 0;
      for (var i = 0; i < _w * _h; i++) {
        final o = i * 4;
        final same =
            out.data[o] == p.image.data[o] &&
            out.data[o + 1] == p.image.data[o + 1] &&
            out.data[o + 2] == p.image.data[o + 2];
        if (!same && region(RetouchChannel.lips, i) == 0) changed++;
      }
      expect(changed, 0);
    });

    test('is linear in the slider', () {
      final half = labOf(run({PortraitIds.lips: 50}));
      const n = _w * _h;
      final c0 = meanWhere(n, lip, (i) => chroma(inLab, i));
      final c50 = meanWhere(n, lip, (i) => chroma(half, i));
      final c100 = meanWhere(n, lip, (i) => chroma(out, i));
      expect((c50 - c0) / (c100 - c0), closeTo(0.5, 0.05));
    });
  });

  group('blush', () {
    late ({Float64List l, Float64List a, Float64List b}) out;
    setUpAll(() => out = labOf(run({PortraitIds.blush: 100})));

    ({double da, double db, double dl}) shift(double x, double y) {
      final c = _face.toPx(x, y), r = 0.04 * _face.iod;
      double d(Float64List a, Float64List b) =>
          discMean(b, _w, c.x, c.y, r) - discMean(a, _w, c.x, c.y, r);
      return (
        da: d(inLab.a, out.a),
        db: d(inLab.b, out.b),
        dl: d(inLab.l, out.l),
      );
    }

    test('warms both cheek apples toward the face blush colour', () {
      final f = maps.faceInSlot(0)!;
      final right = shift(-0.62, 0.52), left = shift(0.62, 0.52);
      for (final s in [right, left]) {
        expect(s.da, greaterThan(0.012));
        expect(s.dl, lessThan(0));
        // The shift points toward the target hue (rosier than the skin).
        final skinHue = math.atan2(0.045, 0.032);
        final targetHue = math.atan2(f.blushB, f.blushA);
        expect(targetHue, lessThan(skinHue));
        expect(math.atan2(s.db, s.da), lessThan(skinHue));
      }
      expect(left.da / right.da, closeTo(1, 0.25));
    });

    test('fades away from the cheeks and spares features', () {
      for (final (x, y) in [(0.0, -0.7), (0.0, 1.6), (0.0, 0.45)]) {
        expect(shift(x, y).da.abs(), lessThan(0.002), reason: '$x, $y');
      }
      final eye = _face.toPx(-0.5, 0.0);
      final i = eye.y.floor() * _w + eye.x.floor();
      expect(out.a[i], inLab.a[i]);
    });
  });

  test('makeupTargets falls back without lips', () {
    const rect = MapRect(0, 0, 4, 4);
    final lab = LabPlanes(
      rect,
      Float32List(16)..fillRange(0, 16, 0.7),
      Float32List(16),
      Float32List(16),
    );
    final t = makeupTargets(lab, Float32List(16), SkinColorModel.fallback);
    expect(t.lipChromaGain, 1);
    expect(t.lipShiftL, 0);
    expect(t.glossL, 1);
    expect(math.atan2(t.blushB, t.blushA), closeTo(kBlushDefaultHue, 1e-9));
  });
}
