import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'engine_harness.dart';

/// PLAN.md P2.8: denoise pre-pass and finish pass behavior.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double sigmaR(RgbaBuffer b) {
    var s = 0.0, s2 = 0.0;
    final n = b.width * b.height;
    for (var i = 0; i < b.data.length; i += 4) {
      s += b.data[i];
      s2 += b.data[i] * b.data[i];
    }
    final m = s / n;
    return math.sqrt(s2 / n - m * m);
  }

  RgbaBuffer softEdge(int w, int h) {
    final b = RgbaBuffer(w, h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final t = ((x - w / 2) / 3).clamp(-1.0, 1.0);
        final v = (128 + 60 * t).round();
        b.setPixel(x, y, v, v, v);
      }
    }
    return b;
  }

  int maxStep(RgbaBuffer b) {
    var m = 0;
    final y = b.height ~/ 2;
    for (var x = 1; x < b.width; x++) {
      m = math.max(m, (b.r(x, y) - b.r(x - 1, y)).abs());
    }
    return m;
  }

  test(
    'noise reduction at 100 lowers sigma of a noisy flat patch >= 40 %',
    () async {
      final noisy = TestScenes.noisyFlat(96, 96);
      final out = await gpuRender(
        noisy,
        DevelopSettings.defaults.withValues({
          P.noiseLuminance: 100,
          P.noiseColor: 100,
        }),
      );
      expect(sigmaR(out), lessThan(sigmaR(noisy) * 0.6));
    },
  );

  test('noise reduction keeps a strong edge', () async {
    final edge = TestScenes.markerCorners(64, 48);
    final out = await gpuRender(
      edge,
      DevelopSettings.defaults.withValue(P.noiseLuminance, 100),
    );
    expect(out.r(1, 1), greaterThan(240));
    expect(out.r(10, 10), closeTo(128, 3));
  });

  test('sharpening raises edge acutance', () async {
    final soft = softEdge(64, 16);
    final out = await gpuRender(
      soft,
      DevelopSettings.defaults.withValues({
        P.sharpenAmount: 150,
        P.sharpenRadius: 1.5,
      }),
    );
    expect(maxStep(out), greaterThan(maxStep(soft)));
  });

  test('grain is deterministic per asset and varies across assets', () async {
    final flat = RgbaBuffer.filled(64, 64, 128, 128, 128);
    final s = DevelopSettings.defaults.withValue(P.grainAmount, 80);
    final a = await gpuRender(flat, s, assetId: 'asset-a');
    final a2 = await gpuRender(flat, s, assetId: 'asset-a');
    final b = await gpuRender(flat, s, assetId: 'asset-b');
    expect(a.data, a2.data);
    expect(diffStats(a, b).mean, greaterThan(0.5));
    expect(sigmaR(a), greaterThan(1.5));
  });

  test('finish is identity when sharpen and grain amounts are 0', () async {
    final scene = TestScenes.portrait(64, 48);
    final base = await gpuRender(scene, DevelopSettings.defaults);
    final subs = await gpuRender(
      scene,
      DevelopSettings.defaults.withValues({
        P.sharpenRadius: 2.5,
        P.sharpenDetail: 80,
        P.grainSize: 90,
        P.grainRoughness: 10,
      }),
    );
    expect(subs.data, base.data);
  });
}
