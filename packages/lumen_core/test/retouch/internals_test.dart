import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart' hide gaussianBlur;
import 'package:lumen_core/src/retouch/filters.dart';
import 'package:lumen_core/src/retouch/lab_planes.dart';
import 'package:lumen_core/src/retouch/push_pull.dart';
import 'package:lumen_core/src/retouch/skin_model.dart';
import 'package:test/test.dart';

void main() {
  group('pushPull', () {
    const w = 40, h = 30;
    Float32List hole(double cx, double cy, double r) => Float32List.fromList([
      for (var i = 0; i < w * h; i++)
        math.sqrt(math.pow(i % w - cx, 2) + math.pow(i ~/ w - cy, 2)) < r
            ? 0.0
            : 1.0,
    ]);

    test('fills a hole in a constant field exactly', () {
      final v = Float32List(w * h)..fillRange(0, w * h, 0.42);
      final trust = hole(20, 15, 6);
      for (var i = 0; i < v.length; i++) {
        if (trust[i] == 0) v[i] = 9; // garbage inside the hole
      }
      final out = pushPull(v, trust, w, h);
      for (final x in out) {
        expect(x, closeTo(0.42, 1e-6));
      }
    });

    test('keeps trusted pixels and interpolates a ramp smoothly', () {
      final v = Float32List.fromList([
        for (var i = 0; i < w * h; i++) (i % w) / w,
      ]);
      final trust = hole(20, 15, 5);
      final out = pushPull(v, trust, w, h);
      for (var i = 0; i < v.length; i++) {
        if (trust[i] == 1) {
          expect(out[i], v[i]);
        } else {
          expect(out[i], closeTo(v[i], 0.05));
        }
      }
    });
  });

  group('filters', () {
    test('gaussianBlur preserves the mean and matches the variance', () {
      const w = 101, h = 1;
      for (final sigma in [0.8, 1.7, 3.0, 6.4]) {
        final impulse = Float32List(w)..[50] = 1;
        final g = gaussianBlur(impulse, w, h, sigma);
        var sum = 0.0, m2 = 0.0;
        for (var i = 0; i < w; i++) {
          sum += g[i];
          m2 += g[i] * (i - 50) * (i - 50);
        }
        expect(sum, closeTo(1, 1e-5));
        expect(math.sqrt(m2), closeTo(sigma, 0.12 * sigma), reason: '$sigma');
      }
    });

    test('guided filter keeps a strong edge and flattens weak texture', () {
      const w = 64, h = 8;
      final p = Float32List(w * h);
      for (var i = 0; i < p.length; i++) {
        final x = i % w;
        p[i] = (x < 32 ? 0.3 : 0.7) + 0.01 * math.sin(x * 1.7);
      }
      final q = guidedFilter(p, [p], w, h, 4, 4e-4).first;
      expect(q[4 * w + 28], closeTo(0.3, 0.02));
      expect(q[4 * w + 36], closeTo(0.7, 0.02));
      var ripple = 0.0;
      for (var x = 8; x < 24; x++) {
        ripple = math.max(ripple, (q[4 * w + x] - 0.3).abs());
      }
      expect(ripple, lessThan(0.005));
    });

    test('dilate and erode are binary square morphology', () {
      const w = 9, h = 9;
      final m = Float32List(w * h)..[4 * w + 4] = 1;
      final d = dilate(m, w, h, 1);
      expect(d.where((v) => v == 1), hasLength(9));
      expect(erode(d, w, h, 1).where((v) => v == 1), hasLength(1));
    });
  });

  test('linearToSrgbByte equals round(encode·255) without pow', () {
    for (var i = -10; i <= 200010; i++) {
      final v = i / 200000;
      final want = (linearToSrgb(v) * 255).round();
      if (linearToSrgbByte(v) != want) fail('mismatch at $v');
    }
    for (var k = 0; k < 256; k++) {
      expect(linearToSrgbByte(kSrgbByteToLinear[k]), k);
    }
  });

  group('SkinColorModel', () {
    LabPlanes patch(double l, double a, double b) {
      const rect = MapRect(0, 0, 40, 40);
      final n = rect.area;
      final rnd = SceneRandom(3);
      Float32List noisy(double v, double s) => Float32List.fromList([
        for (var i = 0; i < n; i++) v + s * rnd.nextGaussian(),
      ]);
      return LabPlanes(rect, noisy(l, 0.01), noisy(a, 0.003), noisy(b, 0.003));
    }

    final lab = patch(0.70, 0.035, 0.045);
    final model = SkinColorModel.fit(lab, const [
      (centre: (x: 20.0, y: 20.0), radius: 15.0),
    ]);

    test('fits the sampled colour', () {
      expect(model.meanA, closeTo(0.035, 0.002));
      expect(model.meanB, closeTo(0.045, 0.002));
      expect(model.meanL, closeTo(0.70, 0.005));
    });

    test('accepts skin and specular shine, rejects hair and backdrop', () {
      expect(model.probability(0.70, 0.035, 0.045), greaterThan(0.95));
      expect(model.probability(0.68, 0.045, 0.05), greaterThan(0.7));
      expect(model.probability(0.85, 0.012, 0.016), greaterThan(0.6));
      expect(model.probability(0.27, 0.02, 0.035), lessThan(0.01));
      expect(model.probability(0.60, -0.01, -0.03), lessThan(0.05));
    });

    test('falls back to a generic model without samples', () {
      final m = SkinColorModel.fit(lab, const [
        (centre: (x: -50.0, y: -50.0), radius: 3.0),
      ]);
      expect(m.meanA, SkinColorModel.fallback.meanA);
    });
  });

  test('signed encoding keeps 0 exact', () {
    expect(encodeSigned(0, kHealRangeL), 128);
    expect(decodeSigned(128, kHealRangeL), 0);
    expect(
      decodeSigned(encodeSigned(0.1, 0.25).toDouble(), 0.25),
      closeTo(0.1, 0.001),
    );
    expect(encodeSigned(9, 0.1), 255);
    expect(encodeSigned(-9, 0.1), 1);
  });

  group('band dither', () {
    test('is deterministic and roughly uniform', () {
      var sum = 0.0;
      for (var i = 0; i < 4096; i++) {
        final d = ditherAt(i % 64, i ~/ 64, kDitherSeedB2, 1);
        expect(d, inInclusiveRange(0, 0.9999999));
        expect(ditherAt(i % 64, i ~/ 64, kDitherSeedB2, 1), d);
        sum += d;
      }
      expect(sum / 4096, closeTo(0.5, 0.02));
      expect(ditherAt(3, 4, 1, 0), isNot(ditherAt(3, 4, 2, 0)));
    });

    test('is unbiased where plain rounding is off by up to half a code', () {
      for (final frac in [0.1, 0.3, 0.5, 0.8]) {
        final k = 100;
        final v = srgbToLinear((k + frac) / 255);
        var mean = 0.0;
        for (var i = 0; i < 4096; i++) {
          final byte = linearToSrgbByteDithered(
            v,
            ditherAt(i % 64, i ~/ 64, 7, 0),
          );
          expect(byte, inInclusiveRange(k, k + 1));
          mean += kSrgbByteToLinear[byte];
        }
        mean /= 4096;
        final plain = kSrgbByteToLinear[linearToSrgbByte(v)];
        final step = kSrgbByteToLinear[k + 1] - kSrgbByteToLinear[k];
        expect((mean - v).abs() / step, lessThan(0.03), reason: 'frac $frac');
        if (frac != 0.5) {
          expect((plain - v).abs() / step, greaterThan(0.09));
        }
      }
      expect(linearToSrgbByteDithered(-1, 0.5), 0);
      expect(linearToSrgbByteDithered(2, 0.5), 255);
      expect(linearToSrgbByteDithered(kSrgbByteToLinear[37], 0.999), 37);
    });
  });
}
