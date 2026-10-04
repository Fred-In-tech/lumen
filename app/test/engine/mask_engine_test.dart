import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/mask_atlas_cache.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'engine_harness.dart';
import 'mask_harness.dart';

/// Mask behavior on the GPU, the atlas cache, overlays and tiled export.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double luma(RgbaBuffer b, int x, int y) =>
      0.2126 * b.r(x, y) + 0.7152 * b.g(x, y) + 0.0722 * b.b(x, y);

  LocalMask radial(Map<String, double> adj, {bool invert = false}) => LocalMask(
    id: 'r',
    name: 'Radial',
    kind: MaskKind.radial,
    invert: invert,
    shape: const RadialShape(rx: 0.2, ry: 0.2, feather: 0.2).toJson(),
    adjustments: adj,
  );

  group('behavior', () {
    final scene = TestScenes.portrait(128, 96);

    test(
      'radial exposure +1 brightens inside, not outside; invert flips',
      () async {
        final plain = await gpuRender(scene, DevelopSettings.defaults);
        final on = await gpuRender(
          scene,
          DevelopSettings.defaults.copyWith(
            masks: [
              radial({P.exposure: 1}),
            ],
          ),
        );
        expect(luma(on, 64, 48), greaterThan(luma(plain, 64, 48) + 25));
        expect(luma(on, 3, 3), closeTo(luma(plain, 3, 3), 0.5));
        final inv = await gpuRender(
          scene,
          DevelopSettings.defaults.copyWith(
            masks: [
              radial({P.exposure: 1}, invert: true),
            ],
          ),
        );
        expect(luma(inv, 64, 48), closeTo(luma(plain, 64, 48), 0.5));
        expect(luma(inv, 3, 3), greaterThan(luma(plain, 3, 3) + 20));
      },
    );

    test('linear gradient is monotone along the gradient', () async {
      final out = await gpuRender(
        RgbaBuffer.filled(64, 64, 110, 110, 110),
        DevelopSettings.defaults.copyWith(
          masks: [
            const LocalMask(
              id: 'l',
              name: 'Linear',
              kind: MaskKind.linear,
              shape: {'x0': 0.5, 'y0': 0.0, 'x1': 0.5, 'y1': 1.0},
              adjustments: {P.exposure: 1.5},
            ),
          ],
        ),
      );
      for (var y = 1; y < 64; y++) {
        expect(out.r(32, y), lessThanOrEqualTo(out.r(32, y - 1)));
      }
      expect(out.r(32, 0), greaterThan(out.r(32, 63) + 40));
    });
  });

  group('MaskAtlasCache', () {
    test(
      'rebuilds on coverage or raster changes, not on adjustments',
      () async {
        final cache = MaskAtlasCache(sourceWidth: 400, sourceHeight: 300);
        final m = radial({P.exposure: 1});
        final a = await cache.obtain([m]);
        expect(cache.builds, 1);
        expect([a.width, a.height], [400, 300]);
        expect(
          identical(await cache.obtain([m.withAdjustment(P.exposure, -1)]), a),
          isTrue,
        );
        expect(cache.builds, 1);
        await cache.obtain([
          m.copyWith(shape: const RadialShape(cx: 0.3).toJson()),
        ]);
        expect(cache.builds, 2);
        const ai = LocalMask(
          id: 's',
          name: 's',
          kind: MaskKind.subject,
          shape: {'maskRef': 'masks/s.png'},
          adjustments: {P.exposure: 1},
        );
        cache.rasters = {'masks/s.png': syntheticRaster(1)};
        await cache.obtain([ai]);
        await cache.obtain([ai.withAdjustment(P.shadows, 30)]);
        expect(cache.builds, 3);
        cache.rasters = {'masks/s.png': syntheticRaster(2)};
        await cache.obtain([ai]);
        expect(cache.builds, 4);
        final empty = await cache.obtain(const []);
        expect(empty.count, 0);
        cache.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(EngineImages.live, 0);
      },
    );
  });

  group('overlay', () {
    test('GPU overlay matches the CPU overlay, follows geometry', () async {
      final shaders = await ShaderLibrary.load();
      final scene = TestScenes.portrait(120, 80);
      final source = await imageFromBuffer(scene);
      final aux = await AuxTextures.fromMaps(AuxMaps.neutral());
      final graph = RenderGraph(shaders: shaders, source: source, aux: aux);
      final rnd = math.Random(5);
      final masks = [
        radial({P.exposure: 1}),
        randomMask(rnd, MaskKind.brush, 'b'),
        randomMask(rnd, MaskKind.linear, 'l'),
        randomMask(rnd, MaskKind.radial, 'r2'),
        randomMask(rnd, MaskKind.radial, 'r3'),
      ];
      for (final g in [
        Geometry.none,
        Geometry.none.copyWith(
          rotate90: 1,
          crop: const CropRect(0.1, 0, 0.9, 1),
        ),
      ]) {
        final s = DevelopSettings.defaults.copyWith(masks: masks, geometry: g);
        for (final index in [0, 1, 4]) {
          final img = await graph.renderMaskOverlay(s, index);
          final gpu = await bufferFromImage(img);
          EngineImages.dispose(img);
          final cpu = renderMaskOverlayReference(
            120,
            80,
            s,
            MaskRasterizer.build(masks, 120, 80),
            index,
          );
          expect([gpu.width, gpu.height], [cpu.width, cpu.height]);
          var worst = 0;
          for (var i = 0; i < gpu.data.length; i++) {
            worst = math.max(worst, (gpu.data[i] - cpu.data[i]).abs());
          }
          expect(worst, lessThanOrEqualTo(1), reason: 'mask $index $g');
        }
      }
      await expectLater(
        graph.renderMaskOverlay(DevelopSettings.defaults, 0),
        throwsRangeError,
      );
      // Replaced atlases are released after the replacement is ready.
      await Future<void>.delayed(Duration.zero);
      graph.dispose();
      aux.dispose();
      EngineImages.dispose(source);
      expect(EngineImages.live, 0);
    });
  });

  test('tiled export with masks equals the single-pass render', () async {
    final shaders = await ShaderLibrary.load();
    final scene = TestScenes.portrait(1500, 1000);
    final source = await imageFromBuffer(scene);
    final aux = await AuxTextures.fromMaps(
      AuxMaps.compute(AuxMaps.proxy(scene)),
    );
    final rnd = math.Random(11);
    final masks = [
      for (var i = 0; i < 6; i++)
        randomMask(
          rnd,
          MaskKind.values[(i * 3) % MaskKind.values.length],
          'e$i',
        ),
    ];
    final rasters = rastersFor(masks);
    final s = DevelopSettings.defaults
        .withValues({P.sharpenAmount: 60, P.grainAmount: 20, P.contrast: 15})
        .copyWith(masks: masks);
    final renderer = ExportRenderer(shaders);
    final tiled = await renderer.render(
      source: source,
      aux: aux,
      settings: s,
      tileSize: 512,
      maskRasters: rasters,
    );
    final atlases = await MaskAtlasTextures.upload(
      MaskRasterizer.build(masks, 1500, 1000, rasters: rasters),
    );
    final single = await renderer.render(
      source: source,
      aux: aux,
      settings: s,
      tileSize: 4096,
      masks: atlases,
    );
    final d = diffStats(
      RgbaBuffer(1500, 1000, tiled.rgba),
      RgbaBuffer(1500, 1000, single.rgba),
    );
    expect(d.max, lessThanOrEqualTo(1));
    // Masks actually changed the image.
    final none = await renderer.render(
      source: source,
      aux: aux,
      settings: s.copyWith(masks: const []),
      tileSize: 4096,
    );
    expect(
      diffStats(
        RgbaBuffer(1500, 1000, none.rgba),
        RgbaBuffer(1500, 1000, single.rgba),
      ).mean,
      greaterThan(0.5),
    );
    atlases.dispose();
    aux.dispose();
    EngineImages.dispose(source);
    expect(EngineImages.live, 0);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
