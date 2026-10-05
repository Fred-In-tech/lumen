import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/float_source.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'float_harness.dart';

/// Windowed float export (docs/HIGH_BIT_DEPTH.md §Export): every tile is
/// developed from its own source window, and the result must equal one
/// pass over the whole float source.
///
///   flutter test --enable-impeller test/engine/float_export_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scene = hotScene(TestScenes.parityScenes(300, 200)[2], peak: 2.2);

  Future<({ExportPixels px, FloatExportStats stats, MemoryFloatSource source})>
  export(
    DevelopSettings s, {
    int tileSize = 64,
    int? longEdge,
    RgbaBuffer? healOverlay,
    HbdProfile profile = HbdProfile.rawExtended,
    CancelToken? cancel,
    void Function(double)? onProgress,
  }) async {
    final shaders = await ShaderLibrary.load();
    final source = MemoryFloatSource(scene, profile: profile);
    final aux = await AuxTextures.fromFloatProxy(scene);
    FloatExportStats? stats;
    try {
      final px = await ExportRenderer(shaders).renderFloat(
        source: source,
        aux: aux,
        settings: s,
        assetId: 'test',
        tileSize: tileSize,
        longEdge: longEdge,
        healOverlay: healOverlay,
        cancel: cancel,
        onProgress: onProgress,
        onStats: (v) => stats = v,
      );
      return (px: px, stats: stats!, source: source);
    } finally {
      aux.dispose();
    }
  }

  Future<RgbaBuffer> whole(DevelopSettings s, {FloatBuffer? src}) =>
      gpuRenderFloat(
        src ?? scene,
        s,
        aux: AuxMaps.computeFloat(AuxMaps.proxyFloat(scene)),
        profile: HbdProfile.rawExtended,
      );

  test('floatSourceSize: full size, capped, scaled to the long edge', () {
    const g = Geometry();
    expect(ExportRenderer.floatSourceSize(8192, 5464, g), (
      width: 8192,
      height: 5464,
    ));
    expect(ExportRenderer.floatSourceSize(9504, 6336, g), (
      width: 8192,
      height: 5461,
    ));
    expect(ExportRenderer.floatSourceSize(8192, 5464, g, longEdge: 2048), (
      width: 2048,
      height: 1366,
    ));
    // Never upscales; a crop keeps the source density of the output.
    expect(ExportRenderer.floatSourceSize(800, 600, g, longEdge: 4000), (
      width: 800,
      height: 600,
    ));
    const half = Geometry(crop: CropRect(0, 0, 0.5, 1));
    expect(ExportRenderer.floatSourceSize(800, 600, half, longEdge: 300), (
      width: 400,
      height: 300,
    ));
    expect(floatImageBytes(3), 64); // 16 B/px plus the mip chain
  });

  test('tiles from source windows equal the single-pass render', () async {
    if (!await floatPathOrSkip()) return;
    final s = DevelopSettings.defaults.withValues({
      P.exposure: -0.8,
      P.highlights: -60,
      P.texture: 40,
      P.clarity: 30,
    });
    final r = await export(s);
    final ref = await whole(s);
    expect((r.px.width, r.px.height), (ref.width, ref.height));
    final d = diffStats(RgbaBuffer(r.px.width, r.px.height, r.px.rgba), ref);
    result('windowed export vs single pass: max ${d.max}/255, ${r.stats}');
    expect(d.max, lessThanOrEqualTo(1));
    expect(r.stats.tiles, 5 * 4);
    expect(r.source.renders, r.stats.tiles);
    // A 64 px tile reads a window of about (64 + 2·6)², far from the photo.
    expect(r.stats.largestWindow, lessThanOrEqualTo(76 * 76));
    expect(r.source.largestWindow, r.stats.largestWindow);
    expect(r.stats.peakGpuBytes, greaterThan(0));
    expect('${r.stats}', contains('20 tiles'));
    expect(EngineImages.live, 0);
  });

  test(
    'crop, rotation, flips, denoise and the finish pass stay seamless',
    () async {
      if (!await floatPathOrSkip()) return;
      final s = DevelopSettings.defaults
          .withValues({
            P.exposure: -1.2,
            P.noiseLuminance: 50,
            P.noiseColor: 40,
            P.sharpenAmount: 60,
            P.texture: 30,
          })
          .copyWith(
            geometry: const Geometry(
              crop: CropRect(0.1, 0.15, 0.85, 0.9),
              angle: 6,
              rotate90: 1,
              flipH: true,
            ),
          );
      final r = await export(s);
      final ref = await whole(s);
      final d = diffStats(RgbaBuffer(r.px.width, r.px.height, r.px.rgba), ref);
      result(
        'windowed export, geometry + denoise + finish: max ${d.max}/255, '
        'mean ${d.mean.toStringAsFixed(3)}',
      );
      expect(d.max, lessThanOrEqualTo(2));
      expect(d.mean, lessThanOrEqualTo(0.2));
      expect(EngineImages.live, 0);
    },
  );

  test('the heal overlay is drawn into each window', () async {
    if (!await floatPathOrSkip()) return;
    final overlay = RgbaBuffer(300, 200);
    for (var y = 60; y < 140; y++) {
      for (var x = 100; x < 180; x++) {
        overlay.setPixel(x, y, 40, 160, 220);
      }
    }
    final s = DevelopSettings.defaults.withValue(P.exposure, -0.5);
    final r = await export(s, healOverlay: overlay);
    final ref = await whole(s, src: composeOverlayFloat(scene, overlay));
    final d = diffStats(RgbaBuffer(r.px.width, r.px.height, r.px.rgba), ref);
    expect(d.max, lessThanOrEqualTo(1));
    // And it is really there.
    final plain = await whole(s);
    expect(ref.g(140, 100), isNot(plain.g(140, 100)));
    await expectLater(
      export(s, healOverlay: RgbaBuffer(10, 10)),
      throwsArgumentError,
    );
    expect(EngineImages.live, 0);
  });

  test('a long-edge export renders the source at the output density', () async {
    if (!await floatPathOrSkip()) return;
    final s = DevelopSettings.defaults.withValue(P.exposure, -1);
    final r = await export(s, longEdge: 150, tileSize: 2048);
    expect((r.px.width, r.px.height), (150, 100));
    expect((r.stats.sourceWidth, r.stats.sourceHeight), (150, 100));
    expect(r.stats.tiles, 1);
    // Same picture as the full render, scaled: compare the means.
    final ref = await whole(s);
    double mean(Iterable<int> px) {
      var sum = 0, n = 0;
      for (final v in px) {
        sum += v;
        n++;
      }
      return sum / n;
    }

    expect(mean(r.px.rgba), closeTo(mean(ref.data), 1.5));
  });

  test('cancellation stops between tiles and leaks nothing', () async {
    if (!await floatPathOrSkip()) return;
    final cancel = CancelToken();
    var seen = 0;
    await expectLater(
      export(
        DevelopSettings.defaults,
        cancel: cancel,
        onProgress: (p) {
          if (++seen == 2) cancel.cancel();
        },
      ),
      throwsA(isA<ExportCancelled>()),
    );
    expect(seen, 2);
    expect(EngineImages.live, 0);
  });

  test('MemoryFloatSource: windows, scaling and bad windows', () async {
    final src = MemoryFloatSource(scene);
    expect((src.width, src.height, src.profile), (300, 200, HbdProfile.none));
    final all = await src.render(fullWidth: 300, fullHeight: 200);
    expect(identical(all.rgba, scene.data), isTrue);
    expect(all.buffer.width, 300);
    final win = await src.render(
      fullWidth: 300,
      fullHeight: 200,
      x: 10,
      y: 20,
      width: 4,
      height: 2,
    );
    expect(win.rgba[0], scene.data[scene.offset(10, 20)]);
    final half = await src.render(fullWidth: 150, fullHeight: 100);
    final o = scene.offset(0, 0), o2 = scene.offset(0, 1);
    expect(
      half.rgba[0],
      closeTo(
        (scene.data[o] +
                scene.data[o + 4] +
                scene.data[o2] +
                scene.data[o2 + 4]) /
            4,
        1e-6,
      ),
    );
    await expectLater(
      src.render(fullWidth: 300, fullHeight: 200, x: 299, width: 5),
      throwsA(isA<FloatSourceException>()),
    );
    await expectLater(
      src.render(fullWidth: 300, fullHeight: 200, x: -1),
      throwsA(isA<FloatSourceException>()),
    );
    await src.release();
    expect(() => FloatPixels(2, 2, scene.data), throwsArgumentError);
    expect('${const FloatSourceException('x')}', contains('x'));
  });
}
