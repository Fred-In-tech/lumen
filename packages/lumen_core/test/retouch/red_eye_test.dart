import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

import 'support/metrics.dart';
import 'support/synthetic_landmarks.dart';
import 'support/synthetic_portrait.dart';

const _w = 512, _h = 512;

void main() {
  RgbaBuffer run(SynthPortrait p, RetouchMaps m, double v) => applyRetouch(
    p.image,
    m,
    RetouchUniforms.fromSettings(
      PortraitSettings.empty.withGroupValue(
        FaceGroup.all,
        PortraitIds.redEye,
        v,
      ),
      p.analysis,
    ),
  );

  group('red-eye', () {
    const face = SynthFace(id: 'a', cx: 256, cy: 200, iod: 140, redEye: true);
    late SynthPortrait p;
    late RetouchMaps maps;
    late ({Float64List l, Float64List a, Float64List b}) before;
    setUpAll(() {
      p = renderSynthPortrait(_w, _h, [face]);
      maps = computeRetouchMaps(p.image, p.analysis);
      before = labOf(p.image);
    });

    /// Mean of [c] over the red pupil of both eyes, catchlight excluded.
    double pupil(Float64List c) {
      var sum = 0.0, n = 0;
      for (final ex in const [-0.5, 0.5]) {
        final e = face.toPx(ex, 0);
        final r = 0.8 * kRedPupil * kIrisRadius * face.iod;
        for (var y = (e.y - r).floor(); y <= (e.y + r).ceil(); y++) {
          for (var x = (e.x - r).floor(); x <= (e.x + r).ceil(); x++) {
            final q = face.toLocal(x + 0.5, y + 0.5);
            final d = math.sqrt(math.pow(q.x - ex, 2) + q.y * q.y);
            if (d > 0.8 * kRedPupil * kIrisRadius) continue;
            if (math.sqrt(
                  math.pow(q.x - ex - 0.03, 2) + math.pow(q.y + 0.03, 2),
                ) <
                0.03) {
              continue;
            }
            sum += c[y * _w + x];
            n++;
          }
        }
      }
      return sum / n;
    }

    test('red pupils lose their colour and darken', () {
      final out = labOf(run(p, maps, 100));
      expect(pupil(before.a), greaterThan(0.15));
      expect(pupil(out.a), lessThan(0.15 * pupil(before.a)));
      expect(pupil(out.b), lessThan(0.15 * pupil(before.b)));
      expect(pupil(before.l) - pupil(out.l), greaterThan(0.15));
    });

    test('the catchlight, the brown iris and the skin stay', () {
      final out = labOf(run(p, maps, 100));
      for (final ex in const [-0.5, 0.5]) {
        final c = face.toPx(ex + 0.03, -0.03);
        final i = c.y.floor() * _w + c.x.floor();
        expect(out.l[i], closeTo(before.l[i], 0.005), reason: 'catchlight');
        // Brown iris ring between the red pupil and the iris edge.
        final ring = face.toPx(ex + 0.8 * kIrisRadius, 0);
        final j = ring.y.floor() * _w + ring.x.floor();
        expect(out.a[j], closeTo(before.a[j], 0.003), reason: 'iris');
        // Cheek below the eye.
        final cheek = face.toPx(ex, 0.3);
        final k = cheek.y.floor() * _w + cheek.x.floor();
        expect(out.l[k], before.l[k], reason: 'skin');
      }
    });

    test('is linear in the slider', () {
      final half = labOf(run(p, maps, 50)), full = labOf(run(p, maps, 100));
      final a0 = pupil(before.a), a50 = pupil(half.a), a100 = pupil(full.a);
      expect((a0 - a50) / (a0 - a100), closeTo(0.5, 0.05));
    });
  });

  test('normal eyes are left alone', () {
    const face = SynthFace(id: 'a', cx: 256, cy: 200, iod: 140);
    final p = renderSynthPortrait(_w, _h, [face]);
    final maps = computeRetouchMaps(p.image, p.analysis);
    final out = run(p, maps, 100);
    var maxDiff = 0;
    for (var i = 0; i < out.data.length; i++) {
      if (i % 4 == 3) continue;
      maxDiff = math.max(maxDiff, (out.data[i] - p.image.data[i]).abs());
    }
    expect(maxDiff, lessThanOrEqualTo(1));
  });
}
