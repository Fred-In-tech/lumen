import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/lut_texture.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/render_scheduler.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';

/// Real GPU end to end: aux build, cache, LUT texture, graph, scheduler.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LutTexture uploads every packed entry exactly', () async {
    final lut = ToneLut.bake(
      DevelopSettings.defaults.withValues({P.contrast: 40, P.whites: -20}),
    );
    final tex = await LutTexture.upload(lut);
    expect([tex.image.width, tex.image.height], [kToneLutSize, kToneLutRows]);
    expect(await readRgba(tex.image), lut.toRgba());
    expect(tex.key, lut.key);
    tex.dispose();
  });

  test(
    'AuxTextures.build downsamples on the GPU and matches CPU maps',
    () async {
      final scene = TestScenes.darkInterior(1024, 768);
      final source = await imageFromBuffer(scene);
      final aux = await AuxTextures.build(source);
      expect([aux.width, aux.height], [512, 384]);
      final cpu = AuxMaps.compute(AuxMaps.proxy(scene));
      for (final (u, v) in [(0.1, 0.1), (0.7, 0.2), (0.5, 0.8)]) {
        final a = aux.maps.sample(u, v), b = cpu.sample(u, v);
        expect(a.baseMid, closeTo(b.baseMid, 0.01));
        expect(a.meanA * 0.5 + a.meanB, closeTo(b.meanA * 0.5 + b.meanB, 0.02));
      }
      aux.dispose();
      EngineImages.dispose(source);
      expect(EngineImages.live, 0);
    },
  );

  test(
    'AuxCache shares builds per asset and releases on evict/dispose',
    () async {
      final cache = AuxCache();
      final a = await imageFromBuffer(TestScenes.hazy(256, 128));
      final b = await imageFromBuffer(TestScenes.portrait(128, 128));
      final f1 = cache.obtain('a', a);
      expect(identical(cache.obtain('a', a), f1), isTrue);
      await f1;
      await cache.obtain('b', b);
      cache.evict('a');
      expect(cache.contains('a'), isFalse);
      cache.dispose();
      await Future<void>.delayed(Duration.zero);
      EngineImages.dispose(a);
      EngineImages.dispose(b);
      expect(EngineImages.live, 0);
    },
  );

  test('scheduler + graph publish real frames and leak nothing', () async {
    final shaders = await ShaderLibrary.load();
    final scene = TestScenes.portrait(320, 240);
    final source = await imageFromBuffer(scene);
    final aux = await AuxTextures.build(source);
    final graph = RenderGraph(
      shaders: shaders,
      source: source,
      aux: aux,
      assetId: 'p1',
    );
    final scheduler = RenderScheduler(graph);
    final frames = <int>[];
    scheduler.frame.addListener(() {
      final f = scheduler.frame.value;
      if (f != null) frames.add(f.width);
    });
    scheduler.update(DevelopSettings.defaults.withValue(P.contrast, 30));
    scheduler.update(DevelopSettings.defaults.withValue(P.contrast, 60));
    await scheduler.idle();
    expect(scheduler.frame.value, isNotNull);
    expect(scheduler.settings!.value(P.contrast), 60);

    scheduler.update(
      DevelopSettings.defaults.withValues({P.exposure: 0.5, P.grainAmount: 20}),
      interactive: true,
    );
    await scheduler.idle();
    // Drag frame at 0.5x, then the settled full-size frame.
    expect(frames, containsAllInOrder([320, 160, 320]));

    final gpu = await bufferFromImage(scheduler.frame.value!);
    expect([gpu.width, gpu.height], [320, 240]);

    scheduler.dispose(); // disposes the graph and the published frame
    aux.dispose();
    EngineImages.dispose(source);
    expect(EngineImages.live, 0);
  });
}
