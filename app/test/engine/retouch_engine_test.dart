import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/retouch_textures.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'retouch_harness.dart';

/// Pass R inside the render graph and the tiled export.
///
/// The timing probe is opt-in (`--dart-define=LUMEN_TIMING=true`): headless
/// `flutter_tester` rasterizes in software, so only ratios are meaningful.
const _timing = bool.fromEnvironment('LUMEN_TIMING');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SynthPortrait p;
  late RetouchMaps maps;

  setUpAll(() {
    final one = onePortrait();
    p = one.p;
    maps = one.maps;
  });

  final portrait = portraitOf({
    PortraitIds.skinSoftening: 70,
    PortraitIds.acne: 80,
    PortraitIds.eyeWhites: 60,
    PortraitIds.teethBrightness: 50,
  });

  Future<RgbaBuffer> graphRender(
    DevelopSettings s, {
    bool withMaps = true,
    void Function(RenderGraph g)? inspect,
  }) async {
    final shaders = await ShaderLibrary.load();
    final src = await imageFromBuffer(p.image);
    final aux = await AuxTextures.fromMaps(AuxMaps.compute(p.image));
    final graph = RenderGraph(shaders: shaders, source: src, aux: aux);
    if (withMaps) {
      graph
        ..retouchMaps = maps
        ..faceAnalysis = p.analysis;
    }
    try {
      final out = await graph.render(s);
      final buf = await bufferFromImage(out);
      EngineImages.dispose(out);
      inspect?.call(graph);
      return buf;
    } finally {
      graph.dispose();
      aux.dispose();
      EngineImages.dispose(src);
    }
  }

  test('graph R → D matches applyRetouch → renderReference', () async {
    final s = DevelopSettings.defaults
        .withValues({P.exposure: 0.3, P.contrast: 20, P.vibrance: 15})
        .copyWith(portrait: portrait);
    final gpu = await graphRender(s);
    final retouched = applyRetouch(
      p.image,
      maps,
      RetouchUniforms.fromSettings(portrait, p.analysis),
    );
    final cpu = renderReference(retouched, s, aux: AuxMaps.compute(p.image));
    final d = diffStats(gpu, cpu);
    expect(d.max, lessThanOrEqualTo(3));
    expect(d.mean, lessThanOrEqualTo(1));
    expect(EngineImages.live, 0);
  });

  test('identity portrait settings skip R bit-exactly', () async {
    final s = DevelopSettings.defaults.withValue(P.contrast, 25);
    final withMaps = await graphRender(
      s.copyWith(portrait: portraitOf({PortraitIds.lidProtect: 100})),
      inspect: (g) => expect(g.retouchRuns, 0),
    );
    final without = await graphRender(s, withMaps: false);
    expect(withMaps.data, without.data);
  });

  test('R is cached: only portrait or denoise changes re-run it', () async {
    final shaders = await ShaderLibrary.load();
    final src = await imageFromBuffer(p.image);
    final aux = await AuxTextures.fromMaps(AuxMaps.neutral());
    final graph = RenderGraph(shaders: shaders, source: src, aux: aux)
      ..retouchMaps = maps
      ..faceAnalysis = p.analysis;
    Future<void> render(DevelopSettings s) async =>
        EngineImages.dispose(await graph.render(s));
    final base = DevelopSettings.defaults.copyWith(portrait: portrait);
    await render(base);
    await render(base.withValue(P.exposure, 1));
    await render(base.withValue(P.contrast, -30));
    expect(graph.retouchRuns, 1);
    expect(graph.retouchCache.uploads, 1);
    await render(
      base.copyWith(
        portrait: portrait.withGroupValue(FaceGroup.all, PortraitIds.iris, 50),
      ),
    );
    expect(graph.retouchRuns, 2);
    await render(base.withValue(P.noiseLuminance, 40));
    expect(graph.retouchRuns, 3);
    graph.retouchMaps = computeRetouchMaps(p.image, p.analysis, longEdge: 256);
    await render(base);
    expect(graph.retouchCache.uploads, 2);
    expect(graph.retouchRuns, 4);
    graph.dispose();
    await Future<void>.delayed(Duration.zero);
    aux.dispose();
    EngineImages.dispose(src);
    expect(EngineImages.live, 0);
  });

  test('tiled export with retouch equals the single-pass render', () async {
    final shaders = await ShaderLibrary.load();
    final src = await imageFromBuffer(p.image);
    final aux = await AuxTextures.fromMaps(AuxMaps.compute(p.image));
    final s = DevelopSettings.defaults
        .withValues({P.sharpenAmount: 50, P.contrast: 10})
        .copyWith(portrait: portrait);
    final renderer = ExportRenderer(shaders);
    final tiled = await renderer.render(
      source: src,
      aux: aux,
      settings: s,
      tileSize: 100,
      faceAnalysis: p.analysis,
      retouchMaps: maps,
    );
    final textures = await RetouchTextures.upload(maps);
    final single = await renderer.render(
      source: src,
      aux: aux,
      settings: s,
      tileSize: 4096,
      faceAnalysis: p.analysis,
      retouchTextures: textures,
    );
    final w = tiled.width, h = tiled.height;
    final d = diffStats(
      RgbaBuffer(w, h, tiled.rgba),
      RgbaBuffer(w, h, single.rgba),
    );
    expect(d.max, lessThanOrEqualTo(1));
    final plain = await renderer.render(source: src, aux: aux, settings: s);
    expect(
      diffStats(
        RgbaBuffer(w, h, plain.rgba),
        RgbaBuffer(w, h, single.rgba),
      ).max,
      greaterThan(3),
    );
    textures.dispose();
    aux.dispose();
    EngineImages.dispose(src);
    expect(EngineImages.live, 0);
  });

  test(
    'timing: pass R at 2560 px preview and per 2048² export tile',
    () async {
      final shaders = await ShaderLibrary.load();
      final small = await imageFromBuffer(p.image);
      final textures = await RetouchTextures.upload(maps);
      final u = RetouchUniforms.fromSettings(
        portraitOf({
          for (final id in kAutoRetouchValues.keys) id: kAutoRetouchValues[id]!,
        }),
        p.analysis,
      );

      ui.Image upscale(int size) {
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawImageRect(
          small,
          ui.Rect.fromLTWH(
            0,
            0,
            small.width.toDouble(),
            small.height.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.low,
        );
        final pic = rec.endRecording();
        final img = EngineImages.track(pic.toImageSync(size, size));
        pic.dispose();
        return img;
      }

      /// Forces GPU completion with a 1×1 readback of [img].
      Future<void> settle(ui.Image img) async {
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawImageRect(
          img,
          const ui.Rect.fromLTWH(0, 0, 1, 1),
          const ui.Rect.fromLTWH(0, 0, 1, 1),
          ui.Paint(),
        );
        final pic = rec.endRecording();
        final one = await pic.toImage(1, 1);
        await one.toByteData();
        one.dispose();
        pic.dispose();
      }

      Future<int> timeIt(ui.Image Function() run) async {
        var best = 1 << 30;
        for (var i = 0; i < 3; i++) {
          final sw = Stopwatch()..start();
          final out = run();
          await settle(out);
          sw.stop();
          EngineImages.dispose(out);
          if (i > 0 && sw.elapsedMicroseconds < best) {
            best = sw.elapsedMicroseconds;
          }
        }
        return best;
      }

      final preview = upscale(2560);
      await settle(preview);
      final previewUs = await timeIt(
        () => runRetouchPass(
          shaders,
          source: preview,
          textures: textures,
          uniforms: u,
        )!,
      );
      final big = upscale(4096);
      await settle(big);
      final tileUs = await timeIt(
        () => runRetouch(
          shaders,
          floats: RetouchPassUniforms.pack(
            maps,
            u,
            width: 2048,
            height: 2048,
            tileX: 1024,
            tileY: 512,
            fullWidth: 4096,
            fullHeight: 4096,
          ),
          source: big,
          maps: textures.images,
          width: 2048,
          height: 2048,
        ),
      );
      final copyUs = await timeIt(() {
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawImage(preview, ui.Offset.zero, ui.Paint());
        final pic = rec.endRecording();
        final img = EngineImages.track(pic.toImageSync(2560, 2560));
        pic.dispose();
        return img;
      });
      final lut = await uploadRgba(
        ToneLut.bake(DevelopSettings.defaults).toRgba(),
        kToneLutSize,
        kToneLutRows,
      );
      final aux = await AuxTextures.fromMaps(AuxMaps.neutral());
      final developUs = await timeIt(
        () => runDevelop(
          shaders,
          floats: DevelopUniforms.pack(
            DevelopSettings.defaults.withValue(P.vibrance, 20),
            const DevelopContext(
              outWidth: 2560,
              outHeight: 2560,
              sourceWidth: 2560,
              sourceHeight: 2560,
              auxWidth: 1,
              auxHeight: 1,
            ),
          ),
          source: preview,
          auxA: aux.auxA,
          auxB: aux.auxB,
          lut: lut,
          width: 2560,
          height: 2560,
        ),
      );
      EngineImages.dispose(lut);
      aux.dispose();
      debugPrint(
        'develop 2560² = ${developUs / 1000} ms (baseline); '
        'retouch timing (flutter_tester, face ≈27 % of width, Auto Retouch '
        'values): R 2560² = ${previewUs / 1000} ms, R 2048² export tile = '
        '${tileUs / 1000} ms, plain 2560² copy = ${copyUs / 1000} ms',
      );
      expect(previewUs, greaterThan(0));
      for (final i in [preview, big, small]) {
        EngineImages.dispose(i);
      }
      textures.dispose();
      expect(EngineImages.live, 0);
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: _timing ? false : 'timing probe: --dart-define=LUMEN_TIMING=true',
  );
}
