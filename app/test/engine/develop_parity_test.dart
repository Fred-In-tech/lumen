import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'engine_harness.dart';

/// PLAN.md §6.3: GPU `develop.frag` vs the CPU `renderReference`.
/// Point ops: max |Δ| ≤ 3/255, mean ≤ 1/255. Identity: ±1/255.
/// Run with `--dart-define=LUMEN_PARITY_REPORT=true` to log the stats.
const _report = bool.fromEnvironment('LUMEN_PARITY_REPORT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scenes = TestScenes.parityScenes(128, 96);

  void log(String stage, int max, double mean) {
    if (_report) {
      debugPrint(
        'parity $stage: max $max/255, mean ${mean.toStringAsFixed(3)}/255',
      );
    }
  }

  test('identity: all defaults reproduce the input within 1/255', () async {
    var worst = 0;
    for (final scene in scenes) {
      final gpu = await gpuRender(scene, DevelopSettings.defaults);
      final d = diffStats(gpu, scene);
      worst = math.max(worst, d.max);
      expect(d.max, lessThanOrEqualTo(1));
    }
    log('identity vs input', worst, 0);
  });

  group('point ops per stage', () {
    for (final entry in pointStages.entries) {
      test(entry.key, () async {
        final rnd = math.Random(entry.key.hashCode & 0xffff);
        var worst = 0;
        var meanSum = 0.0, n = 0;
        for (final scene in scenes) {
          for (var k = 0; k < 2; k++) {
            final s = entry.value(rnd);
            final gpu = await gpuRender(scene, s);
            final cpu = renderReference(scene, s);
            final d = diffStats(gpu, cpu);
            worst = math.max(worst, d.max);
            meanSum += d.mean;
            n++;
            expect(d.max, lessThanOrEqualTo(3), reason: '$s');
            expect(d.mean, lessThanOrEqualTo(1), reason: '$s');
          }
        }
        log(entry.key, worst, meanSum / n);
      });
    }
  });

  test('6 scenes x 12 seeded random point-op settings', () async {
    final rnd = math.Random(2026);
    var worst = 0;
    var meanSum = 0.0, n = 0;
    for (final scene in scenes) {
      for (var k = 0; k < 12; k++) {
        final s = randomPointSettings(rnd);
        final gpu = await gpuRender(scene, s);
        final cpu = renderReference(scene, s);
        final d = diffStats(gpu, cpu);
        worst = math.max(worst, d.max);
        meanSum += d.mean;
        n++;
        expect(d.max, lessThanOrEqualTo(3), reason: '$s');
        expect(d.mean, lessThanOrEqualTo(1), reason: '$s');
      }
    }
    log('all point ops (72 renders)', worst, meanSum / n);
    expect(EngineImages.live, 0);
  });

  group('spatial ops share CPU aux maps, so they are parity-checked too', () {
    for (final entry in spatialStages.entries) {
      test(entry.key, () async {
        final rnd = math.Random(entry.key.length * 31);
        var worst = 0;
        var meanSum = 0.0, n = 0;
        for (final scene in scenes) {
          final aux = AuxMaps.compute(scene);
          for (var k = 0; k < 2; k++) {
            final s = entry.value(rnd);
            final gpu = await gpuRender(scene, s, aux: aux);
            final cpu = renderReference(scene, s, aux: aux);
            final d = diffStats(gpu, cpu);
            worst = math.max(worst, d.max);
            meanSum += d.mean;
            n++;
            expect(d.max, lessThanOrEqualTo(3), reason: '$s');
            expect(d.mean, lessThanOrEqualTo(1), reason: '$s');
          }
        }
        log('spatial ${entry.key}', worst, meanSum / n);
      });
    }
  });

  test('clipping overlay matches', () async {
    final scene = scenes.first;
    final s = DevelopSettings.defaults.withValue(P.exposure, 1.5);
    final gpu = await gpuRender(scene, s, showClipping: true);
    final cpu = renderReference(scene, s, showClipping: true);
    final d = diffStats(gpu, cpu);
    expect(d.mean, lessThanOrEqualTo(1));
  });
}
