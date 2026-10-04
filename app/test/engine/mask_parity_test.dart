import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'engine_harness.dart';
import 'mask_harness.dart';

/// GPU vs CPU parity with local masks (§6.3: max ≤ 3/255, mean ≤ 1/255).
/// `--dart-define=LUMEN_PARITY_REPORT=true` logs the stats.
const _report = bool.fromEnvironment('LUMEN_PARITY_REPORT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scenes = TestScenes.parityScenes(128, 96);

  void log(String stage, int max, double mean) {
    if (_report) {
      debugPrint(
        'mask parity $stage: max $max/255, mean ${mean.toStringAsFixed(3)}/255',
      );
    }
  }

  Future<({int max, double mean})> compare(
    RgbaBuffer scene,
    DevelopSettings s,
  ) async {
    final rasters = rastersFor(s.masks);
    final aux = AuxMaps.compute(scene);
    final gpu = await gpuRender(scene, s, aux: aux, maskRasters: rasters);
    final cpu = renderReference(scene, s, aux: aux, maskRasters: rasters);
    return diffStats(gpu, cpu);
  }

  for (final kind in MaskKind.values) {
    test('${kind.name}: 1-3 masks with random local adjustments', () async {
      final rnd = math.Random(kind.index * 101 + 7);
      var worst = 0;
      var meanSum = 0.0, n = 0;
      for (final scene in scenes) {
        final count = 1 + rnd.nextInt(3);
        final s = DevelopSettings.defaults.copyWith(
          masks: [
            for (var i = 0; i < count; i++)
              randomMask(rnd, kind, '${kind.name}$i'),
          ],
        );
        final d = await compare(scene, s);
        worst = math.max(worst, d.max);
        meanSum += d.mean;
        n++;
        expect(d.max, lessThanOrEqualTo(3), reason: '${s.masks}');
        expect(d.mean, lessThanOrEqualTo(1));
      }
      log(kind.name, worst, meanSum / n);
    });
  }

  test('8 mixed masks (both atlases) on top of random global edits', () async {
    final rnd = math.Random(88);
    var worst = 0;
    var meanSum = 0.0, n = 0;
    for (final scene in scenes) {
      final masks = [
        for (var i = 0; i < 8; i++)
          randomMask(rnd, MaskKind.values[i % MaskKind.values.length], 'm$i'),
      ];
      final s = randomPointSettings(rnd).copyWith(masks: masks);
      final d = await compare(scene, s);
      worst = math.max(worst, d.max);
      meanSum += d.mean;
      n++;
      expect(d.max, lessThanOrEqualTo(3));
      expect(d.mean, lessThanOrEqualTo(1));
    }
    log('8 mixed masks + global', worst, meanSum / n);
    expect(EngineImages.live, 0);
  });

  test('masks without adjustments render byte-identical to no masks', () async {
    final scene = scenes.first;
    final s = DevelopSettings.defaults.withValue(P.contrast, 20);
    final plain = await gpuRender(scene, s);
    final masked = await gpuRender(
      scene,
      s.copyWith(
        masks: [
          const LocalMask(id: 'a', name: 'a', kind: MaskKind.radial),
          const LocalMask(id: 'b', name: 'b', kind: MaskKind.linear),
        ],
      ),
    );
    expect(masked.data, plain.data);
  });
}
