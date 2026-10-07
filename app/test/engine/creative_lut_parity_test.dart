import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/lut_fixtures.dart';
import '../support/test_images.dart';
import 'engine_harness.dart';
import 'float_harness.dart';

/// The creative LUT stage of `develop.frag` against the CPU twin
/// (`CubeLut.sample` in `DevelopKernel`): §6.3 thresholds, max ≤ 3/255,
/// mean ≤ 1/255. `--dart-define=LUMEN_PARITY_REPORT=true` logs the stats.
const _report = bool.fromEnvironment('LUMEN_PARITY_REPORT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scenes = TestScenes.parityScenes(128, 96);
  final teal = tealOrangeLut();
  final twist = twistLut();

  setUp(() {
    CreativeLuts.reset();
    CreativeLuts.remember(teal);
    CreativeLuts.remember(twist);
  });
  tearDown(CreativeLuts.reset);

  void log(String what, int max, double mean) {
    if (_report) {
      debugPrint('parity $what: max $max/255, mean ${mean.toStringAsFixed(3)}');
    }
  }

  test('LUT alone and with develop settings, two LUTs, two amounts', () async {
    final rnd = math.Random(7);
    var worst = 0;
    var meanSum = 0.0, n = 0;
    for (final scene in scenes) {
      for (final lut in [teal, twist]) {
        for (final amount in [100.0, 40.0]) {
          final base = n.isEven
              ? DevelopSettings.defaults
              : randomPointSettings(rnd);
          final s = base.withLut(refOf(lut, amount: amount));
          final gpu = await gpuRender(scene, s);
          final cpu = renderReference(scene, s, creativeLut: lut);
          final d = diffStats(gpu, cpu);
          worst = math.max(worst, d.max);
          meanSum += d.mean;
          n++;
          expect(d.max, lessThanOrEqualTo(3), reason: '${lut.title} $amount');
          expect(d.mean, lessThanOrEqualTo(1));
        }
      }
    }
    log('creative LUT, 8-bit ($n renders)', worst, meanSum / n);
    expect(EngineImages.live, 0);
  });

  test('the LUT really changes the picture on the GPU', () async {
    final scene = scenes.first;
    final plain = await gpuRender(scene, DevelopSettings.defaults);
    final looked = await gpuRender(
      scene,
      DevelopSettings.defaults.withLut(refOf(twist)),
    );
    expect(diffStats(plain, looked).max, greaterThan(40));
  });

  test('a LUT missing from the library renders without it', () async {
    CreativeLuts.reset();
    final scene = scenes[1];
    final plain = await gpuRender(scene, DevelopSettings.defaults);
    final missing = await gpuRender(
      scene,
      DevelopSettings.defaults.withLut(refOf(teal)),
    );
    expect(diffStats(plain, missing).max, 0);
  });

  test('tiled export includes the LUT and equals the CPU twin', () async {
    final shaders = await ShaderLibrary.load();
    final scene = TestScenes.portrait(700, 500);
    final s = DevelopSettings.defaults
        .withValues({P.exposure: 0.2, P.contrast: 20})
        .withLut(refOf(teal, amount: 80));
    final source = await imageFromBuffer(scene);
    final aux = await AuxTextures.fromMaps(
      AuxMaps.compute(AuxMaps.proxy(scene)),
    );
    try {
      final tiled = await ExportRenderer(shaders)
          .render(source: source, aux: aux, settings: s, tileSize: 256);
      final cpu = renderReference(scene, s, creativeLut: teal);
      final d = diffStats(RgbaBuffer(700, 500, tiled.rgba), cpu);
      log('creative LUT, tiled export', d.max, d.mean);
      expect(d.max, lessThanOrEqualTo(3));
      expect(d.mean, lessThanOrEqualTo(1));
    } finally {
      aux.dispose();
      EngineImages.dispose(source);
    }
    expect(EngineImages.live, 0);
  });

  test('float path: LUT parity on an extended-range source', () async {
    if (!await floatPathOrSkip()) return;
    var worst = 0;
    var meanSum = 0.0, n = 0;
    for (final scene in scenes.take(3)) {
      final src = hotScene(scene);
      final s = DevelopSettings.defaults
          .withValue(P.exposure, -0.5)
          .withLut(refOf(teal));
      final gpu = await gpuRenderFloat(src, s);
      final cpu = renderReferenceFloat(src, s, creativeLut: teal).toRgba();
      final d = diffStats(gpu, cpu);
      worst = math.max(worst, d.max);
      meanSum += d.mean;
      n++;
      expect(d.max, lessThanOrEqualTo(3));
      expect(d.mean, lessThanOrEqualTo(1));
    }
    log('creative LUT, float path', worst, meanSum / n);
  });

  group('CreativeLutCache / CreativeLuts', () {
    test('uploads once per LUT, swaps on change, frees on dispose', () async {
      final cache = CreativeLutCache();
      final a = await cache.obtain(refOf(teal));
      expect(a, isNotNull);
      expect(a!.size, 33);
      expect(a.image.width, 66);
      expect(a.image.height, 33 * 33);
      expect(identical(await cache.obtain(refOf(teal, amount: 20)), a), isTrue);
      expect(await cache.obtain(refOf(teal, amount: 0)), isNull);
      expect(await cache.obtain(null), isNull);
      final b = await cache.obtain(refOf(twist));
      expect(b!.hash, twist.contentHash);
      cache.dispose();
      expect(EngineImages.live, 0);
      expect(await cache.obtain(refOf(teal)), isNull);
    });

    test('resolve: memory, loader, wrong data and failures', () async {
      CreativeLuts.reset();
      expect(await CreativeLuts.resolve(teal.contentHash), isNull);
      var loads = 0;
      CreativeLuts.configure((h) async {
        loads++;
        if (h == teal.contentHash) return teal;
        if (h == twist.contentHash) return teal; // corrupted store
        throw const FormatException('disk');
      });
      expect(await CreativeLuts.resolve(teal.contentHash), teal);
      expect(await CreativeLuts.resolve(teal.contentHash), teal);
      expect(loads, 1);
      expect(CreativeLuts.cached(teal.contentHash), teal);
      expect(await CreativeLuts.resolve(twist.contentHash), isNull);
      expect(await CreativeLuts.resolve('0123456789abcdef'), isNull);
      final s = DevelopSettings.defaults.withLut(refOf(teal));
      expect(await CreativeLuts.forSettings(s), teal);
      expect(
        await CreativeLuts.forSettings(s.withLut(refOf(teal, amount: 0))),
        isNull,
      );
      expect(await CreativeLuts.forSettings(DevelopSettings.defaults), isNull);
      for (var i = 0; i < 10; i++) {
        CreativeLuts.remember(CubeLut.identity(2 + i));
      }
      expect(CreativeLuts.cached(teal.contentHash), isNull);
    });
  });
}
