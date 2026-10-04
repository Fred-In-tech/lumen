import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen/engine/warp_textures.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'engine_harness.dart';
import 'mask_harness.dart';
import 'retouch_harness.dart';

/// GPU vs CPU with a warp field (§6.3: max ≤ 3/255, mean ≤ 1/255), the
/// identity skip, the overlay and tiled export.
/// `--dart-define=LUMEN_PARITY_REPORT=true` logs the stats.
const _report = bool.fromEnvironment('LUMEN_PARITY_REPORT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SynthPortrait p;

  setUpAll(() => p = onePortrait(size: 320).p);

  final shapeAll = portraitOf({
    PortraitIds.faceWidth: -80,
    PortraitIds.vShape: 70,
    PortraitIds.chin: 60,
    PortraitIds.eyeSize: 90,
    PortraitIds.noseWidth: -60,
    PortraitIds.mouthSize: 40,
  });
  const strokes = [
    LiquifyStroke(
      tool: LiquifyTool.push,
      points: [(0.3, 0.7), (0.4, 0.68), (0.45, 0.6)],
      radius: 0.08,
      strength: 0.9,
    ),
    LiquifyStroke(
      tool: LiquifyTool.bloat,
      points: [(0.7, 0.3), (0.72, 0.32)],
      radius: 0.1,
      strength: 1,
    ),
    LiquifyStroke(
      tool: LiquifyTool.pucker,
      points: [(0.2, 0.2)],
      radius: 0.07,
      strength: 0.8,
    ),
  ];

  void log(String name, ({int max, double mean}) d) {
    if (_report) {
      debugPrint(
        'warp parity $name: max ${d.max}/255, '
        'mean ${d.mean.toStringAsFixed(3)}/255',
      );
    }
  }

  Future<({int max, double mean})> parity(
    String name,
    RgbaBuffer src,
    DevelopSettings s,
    WarpField field, {
    Map<String, MaskRaster> rasters = const {},
  }) async {
    final aux = AuxMaps.compute(src);
    final gpu = await gpuRender(
      src,
      s,
      aux: aux,
      warp: field,
      maskRasters: rasters,
    );
    final cpu = renderReference(
      src,
      s,
      aux: aux,
      warp: field,
      maskRasters: rasters,
    );
    final d = diffStats(gpu, cpu);
    log(name, d);
    expect(d.max, lessThanOrEqualTo(3), reason: name);
    expect(d.mean, lessThanOrEqualTo(1), reason: name);
    return d;
  }

  WarpField field(DevelopSettings s, {FaceAnalysis? faces}) => buildWarpField(
    WarpRequest.fromSettings(
      s,
      faces,
      sourceWidth: p.image.width,
      sourceHeight: p.image.height,
    ),
  );

  test('identity warp is bit-exact (warp sampler skipped)', () async {
    final s = DevelopSettings.defaults.withValue(P.contrast, 30);
    final plain = await gpuRender(p.image, s);
    final warped = await gpuRender(p.image, s, warp: WarpField.identity());
    expect(warped.data, plain.data);
  });

  test('face reshape: all six sliders', () async {
    final s = DevelopSettings.defaults.copyWith(portrait: shapeAll);
    final f = field(s, faces: p.analysis);
    expect(f.isIdentity, isFalse);
    await parity('face reshape', p.image, s, f);
  });

  test('liquify push, bloat and pucker', () async {
    final s = DevelopSettings.defaults.copyWith(liquify: strokes);
    await parity('liquify', p.image, s, field(s));
  });

  test('warp + masks + global edits + geometry', () async {
    final rnd = math.Random(17);
    final masks = [
      for (var i = 0; i < 5; i++)
        randomMask(rnd, MaskKind.values[(i * 2) % 8], 'w$i'),
    ];
    final s = randomPointSettings(rnd).copyWith(
      masks: masks,
      liquify: strokes,
      portrait: shapeAll,
      // Texel-aligned geometry: a fractional straighten with hard-edged
      // masks already reaches ~10/255 without any warp (float32 uv
      // precision at a hard mask edge); warp + straighten is tested below.
      geometry: Geometry.none.copyWith(
        rotate90: 1,
        crop: const CropRect(0.05, 0.1, 0.95, 0.9),
      ),
    );
    await parity(
      'warp + masks + global + geometry',
      p.image,
      s,
      field(s, faces: p.analysis),
      rasters: rastersFor(masks),
    );
  });

  test('warp + straighten', () async {
    final s = DevelopSettings.defaults.copyWith(
      liquify: strokes,
      portrait: shapeAll,
      // Straighten always comes with a crop that hides the empty corners
      // (the in/out-of-source edge decision flips in float32 otherwise).
      geometry: Geometry.none.copyWith(
        angle: 4,
        crop: const CropRect(0.08, 0.08, 0.92, 0.92),
      ),
    );
    await parity('warp + straighten', p.image, s, field(s, faces: p.analysis));
  });

  test('warp over a swapped (healed) source', () async {
    final shaders = await ShaderLibrary.load();
    final healed = TestScenes.texture(p.image.width, p.image.height);
    final s = DevelopSettings.defaults.copyWith(liquify: strokes);
    final f = field(s);
    final a = await imageFromBuffer(p.image), b = await imageFromBuffer(healed);
    final maps = AuxMaps.compute(healed);
    final aux = await AuxTextures.fromMaps(maps);
    final graph = RenderGraph(shaders: shaders, source: a, aux: aux)
      ..warpField = f
      ..replaceSource(b, aux: aux);
    final out = await graph.render(s);
    final gpu = await bufferFromImage(out);
    final d = diffStats(gpu, renderReference(healed, s, aux: maps, warp: f));
    log('healed source', d);
    expect(d.max, lessThanOrEqualTo(3));
    expect(d.mean, lessThanOrEqualTo(1));
    EngineImages.dispose(out);
    graph.dispose();
    aux.dispose();
    EngineImages.dispose(a);
    EngineImages.dispose(b);
  });

  test('warp after portrait retouch (pass R)', () async {
    final one = onePortrait(size: 320);
    final s = DevelopSettings.defaults.copyWith(
      portrait: shapeAll.withGroupValue(
        FaceGroup.all,
        PortraitIds.skinSoftening,
        70,
      ),
      liquify: strokes,
    );
    final f = field(s, faces: one.p.analysis);
    final shaders = await ShaderLibrary.load();
    final img = await imageFromBuffer(one.p.image);
    final maps = AuxMaps.compute(one.p.image);
    final aux = await AuxTextures.fromMaps(maps);
    final graph = RenderGraph(shaders: shaders, source: img, aux: aux)
      ..retouchMaps = one.maps
      ..faceAnalysis = one.p.analysis
      ..warpField = f;
    final out = await graph.render(s);
    final gpu = await bufferFromImage(out);
    final retouched = applyRetouch(
      one.p.image,
      one.maps,
      RetouchUniforms.fromSettings(s.portrait, one.p.analysis),
    );
    final d = diffStats(gpu, renderReference(retouched, s, aux: maps, warp: f));
    log('retouch + warp', d);
    expect(d.max, lessThanOrEqualTo(3));
    expect(d.mean, lessThanOrEqualTo(1));
    EngineImages.dispose(out);
    graph.dispose();
    aux.dispose();
    EngineImages.dispose(img);
  });

  test('mask overlay follows the warp', () async {
    final live = EngineImages.live;
    final shaders = await ShaderLibrary.load();
    final img = await imageFromBuffer(p.image);
    final aux = await AuxTextures.fromMaps(AuxMaps.neutral());
    final masks = [
      const LocalMask(
        id: 'r',
        name: 'r',
        kind: MaskKind.radial,
        shape: {'cx': 0.7, 'cy': 0.3, 'rx': 0.12, 'ry': 0.12, 'feather': 0.3},
        adjustments: {P.exposure: 1},
      ),
    ];
    final s = DevelopSettings.defaults.copyWith(masks: masks, liquify: strokes);
    final f = field(s);
    final graph = RenderGraph(shaders: shaders, source: img, aux: aux)
      ..warpField = f;
    final o = await graph.renderMaskOverlay(s, 0);
    final gpu = await bufferFromImage(o);
    final cpu = renderMaskOverlayReference(
      p.image.width,
      p.image.height,
      s,
      MaskRasterizer.build(masks, p.image.width, p.image.height),
      0,
      warp: f,
    );
    var worst = 0;
    for (var i = 0; i < gpu.data.length; i++) {
      worst = math.max(worst, (gpu.data[i] - cpu.data[i]).abs());
    }
    expect(worst, lessThanOrEqualTo(1));
    EngineImages.dispose(o);
    graph.dispose();
    await Future<void>.delayed(Duration.zero);
    aux.dispose();
    EngineImages.dispose(img);
    expect(EngineImages.live, live);
  });

  test(
    'tiled export with warp equals the single pass; builds its own field',
    () async {
      final live = EngineImages.live;
      final shaders = await ShaderLibrary.load();
      final img = await imageFromBuffer(p.image);
      final aux = await AuxTextures.fromMaps(AuxMaps.compute(p.image));
      final s = DevelopSettings.defaults
          .withValues({P.sharpenAmount: 40, P.contrast: 10})
          .copyWith(liquify: strokes, portrait: shapeAll);
      final renderer = ExportRenderer(shaders);
      final tiled = await renderer.render(
        source: img,
        aux: aux,
        settings: s,
        tileSize: 96,
        faceAnalysis: p.analysis,
      );
      final single = await renderer.render(
        source: img,
        aux: aux,
        settings: s,
        tileSize: 4096,
        warp: field(s, faces: p.analysis),
      );
      final w = tiled.width, h = tiled.height;
      final d = diffStats(
        RgbaBuffer(w, h, tiled.rgba),
        RgbaBuffer(w, h, single.rgba),
      );
      expect(d.max, lessThanOrEqualTo(1));
      final none = await renderer.render(
        source: img,
        aux: aux,
        settings: s.copyWith(liquify: const []),
      );
      expect(
        diffStats(
          RgbaBuffer(w, h, none.rgba),
          RgbaBuffer(w, h, single.rgba),
        ).max,
        greaterThan(3),
      );
      aux.dispose();
      EngineImages.dispose(img);
      expect(EngineImages.live, live);
    },
  );

  test('warp cache uploads each field once', () async {
    final live = EngineImages.live;
    final cache = WarpFieldCache();
    final f = field(DevelopSettings.defaults.copyWith(liquify: strokes));
    final t1 = await cache.obtain(f);
    expect(identical(await cache.obtain(f), t1), isTrue);
    expect(await cache.obtain(WarpField.identity()), isNull);
    expect(cache.uploads, 1);
    cache.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(EngineImages.live, live);
  });
}
