// DoD 33: every develop control changes the rendered pixels.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'engine_harness.dart';

/// Params that only act when another control is active: param prefix → enabling values.
Map<ParamId, double> _enablers(ParamId id) {
  if (id.startsWith('curve.split.')) {
    return {P.curveDarks: 60, P.curveLights: -60};
  }
  if (id.startsWith('grain.') && id != P.grainAmount) {
    return {P.grainAmount: 60};
  }
  if (id.startsWith('sharpen.') && id != P.sharpenAmount) {
    return {P.sharpenAmount: 120};
  }
  if (id.startsWith('vignette.') && id != P.vignetteAmount) {
    return {P.vignetteAmount: -70};
  }
  if (id == P.noiseColor || id == P.noiseLuminance) return const {};
  final grade = RegExp(r'^grade\.(shadows|midtones|highlights|global)\.hue$')
      .firstMatch(id);
  if (grade != null) return {'grade.${grade.group(1)}.sat': 60};
  if (id == P.gradeBlending || id == P.gradeBalance) {
    return {
      'grade.shadows.sat': 60,
      'grade.shadows.hue': 220,
      'grade.highlights.sat': 60,
      'grade.highlights.hue': 40,
    };
  }
  return const {};
}

double _testValue(ParamSpec p) {
  if (p.id == P.sharpenRadius) return 3;
  if (p.id.endsWith('.hue') && p.id.startsWith('grade.')) return 300;
  // Move well away from the default toward the larger side of the range.
  return (p.max - p.defaultValue).abs() >= (p.defaultValue - p.min).abs()
      ? p.max
      : p.min;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every ParamId changes the render of a rich scene', () async {
    // Ramp + saturated hue ring, plus noise so detail/NR controls have something to act on.
    final clean = TestScenes.rampAndHues(160, 120);
    final noisy = TestScenes.noisyFlat(160, 120, sigma: 10);
    final scene = RgbaBuffer(160, 120);
    for (var i = 0; i < scene.data.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        scene.data[i +
            c] = ((clean.data[i + c] + noisy.data[i + c] - 128).clamp(
          0,
          255,
        )).toInt();
      }
      scene.data[i + 3] = 255;
    }
    final unchanged = <String>[];
    for (final spec in ParamRegistry.all) {
      var base = DevelopSettings.defaults.withValues(_enablers(spec.id));
      if (spec.group == ParamGroup.bw) {
        base = base.copyWith(treatment: Treatment.bw);
      }
      final changed = base.withValue(spec.id, _testValue(spec));
      final a = await gpuRender(scene, base);
      final b = await gpuRender(scene, changed);
      if (diffStats(a, b).max == 0) unchanged.add(spec.id);
    }
    expect(unchanged, isEmpty, reason: 'controls with no visible effect');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('geometry, curves and treatment change the render', () async {
    final scene = TestScenes.rampAndHues(160, 120);
    final base = await gpuRender(scene, DevelopSettings.defaults);
    final variants = <String, DevelopSettings>{
      'crop': DevelopSettings.defaults.copyWith(
        geometry: Geometry.none.copyWith(
          crop: const CropRect(0.1, 0.1, 0.9, 0.9),
        ),
      ),
      'straighten': DevelopSettings.defaults.copyWith(
        geometry: Geometry.none.copyWith(angle: 8),
      ),
      'rotate90': DevelopSettings.defaults.copyWith(
        geometry: Geometry.none.copyWith(rotate90: 1),
      ),
      'flipH': DevelopSettings.defaults.copyWith(
        geometry: Geometry.none.copyWith(flipH: true),
      ),
      'flipV': DevelopSettings.defaults.copyWith(
        geometry: Geometry.none.copyWith(flipV: true),
      ),
      'bw': DevelopSettings.defaults.copyWith(treatment: Treatment.bw),
      for (final ch in CurveChannel.values)
        'curve.${ch.name}': DevelopSettings.defaults.copyWith(
          curves: CurveSet.identity.withChannel(
            ch,
            const ToneCurve([
              CurvePoint(0, 30),
              CurvePoint(128, 170),
              CurvePoint(255, 240),
            ]),
          ),
        ),
    };
    for (final e in variants.entries) {
      final out = await gpuRender(scene, e.value);
      final same =
          out.width == base.width &&
          out.height == base.height &&
          diffStats(out, base).max == 0;
      expect(same, isFalse, reason: e.key);
    }
  });
}
