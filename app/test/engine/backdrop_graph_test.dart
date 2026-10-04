import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'backdrop_harness.dart';

/// Pass B inside the render graph and the export, against the CPU
/// reference (`applyBackdrop` then `renderReference`).
const _report = bool.fromEnvironment('LUMEN_PARITY_REPORT');
const _blue = BackdropChange(mode: BackdropMode.color, color: 0xFF2050C0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SwapScene s;
  late BackdropAssets colour;
  late AuxMaps maps;
  late ShaderLibrary shaders;

  setUpAll(() async {
    s = SwapScene.make();
    colour = BackdropAssets.build(
      BackdropBase.build(s.image, people: s.people),
      _blue,
    );
    maps = AuxMaps.compute(AuxMaps.proxy(s.image));
    shaders = await ShaderLibrary.load();
  });

  /// Runs [body] with a graph over the scene (assets set), then disposes.
  Future<T> withGraph<T>(
    Future<T> Function(RenderGraph g) body, {
    BackdropAssets? assets,
  }) async {
    final aux = await AuxTextures.fromMaps(maps);
    final image = await imageFromBuffer(s.image);
    final g = RenderGraph(shaders: shaders, source: image, aux: aux)
      ..backdropAssets = assets ?? colour;
    try {
      return await body(g);
    } finally {
      g.dispose();
      aux.dispose();
      EngineImages.dispose(image);
    }
  }

  Future<RgbaBuffer> frame(RenderGraph g, DevelopSettings st) async {
    final out = await g.render(st);
    final buf = await bufferFromImage(out);
    EngineImages.dispose(out);
    return buf;
  }

  RgbaBuffer cpu(DevelopSettings st, BackdropAssets a) => renderReference(
    applyBackdrop(s.image, a, st.backdrop),
    st,
    aux: needsAuxMaps(st) ? backdropAuxMaps(a, st.backdrop) : maps,
  );

  void expectParity(String name, RgbaBuffer gpu, RgbaBuffer ref) {
    final d = diffStats(gpu, ref);
    if (_report) {
      debugPrint(
        'backdrop graph $name: max ${d.max}/255, '
        'mean ${d.mean.toStringAsFixed(3)}/255',
      );
    }
    expect(d.max, lessThanOrEqualTo(3), reason: name);
    expect(d.mean, lessThanOrEqualTo(1), reason: name);
  }

  final point = DevelopSettings.defaults
      .withValues({P.exposure: 0.4, P.contrast: 25, P.vibrance: 20})
      .copyWith(backdrop: _blue);
  final spatial = point.withValues({P.clarity: 40, P.shadows: 50});

  test('B then develop matches the CPU reference', () async {
    await withGraph((g) async {
      expectParity('point', await frame(g, point), cpu(point, colour));
      expect(g.backdrop.auxBuilds, 0); // no spatial maps needed
      expectParity('spatial', await frame(g, spatial), cpu(spatial, colour));
      expect(g.backdrop.auxBuilds, 1); // develop saw the composite's maps
    });
  });

  test('B is cached: develop-only edits do not re-run it', () async {
    await withGraph((g) async {
      await frame(g, point);
      await frame(g, point.withValues({P.exposure: -0.3}));
      expect(g.backdrop.runs, 1);
      await frame(g, point.copyWith(backdrop: _blue.copyWith(spill: 90)));
      expect(g.backdrop.runs, 2);
      expect(g.backdrop.textures.uploads, 1);
    });
  });

  test('off, or a mode the assets cannot draw yet: develop only', () async {
    await withGraph((g) async {
      final plain = await frame(
        g,
        point.copyWith(backdrop: BackdropChange.none),
      );
      final blur = await frame(
        g,
        point.copyWith(backdrop: const BackdropChange(mode: BackdropMode.blur)),
      );
      expect(diffStats(blur, plain).max, 0);
      expect(g.backdrop.runs, 0);
    });
  });

  test('export: tiled B + develop matches the preview graph', () async {
    final before = EngineImages.live;
    for (final st in [point, spatial]) {
      final preview = await withGraph((g) => frame(g, st));
      final aux = await AuxTextures.fromMaps(maps);
      final image = await imageFromBuffer(s.image);
      try {
        for (final tile in [4096, 64]) {
          final px = await ExportRenderer(shaders).render(
            source: image,
            aux: aux,
            settings: st,
            tileSize: tile,
            backdropAssets: colour,
          );
          final out = RgbaBuffer(px.width, px.height, px.rgba);
          expect(diffStats(out, preview).max, 0, reason: 'tile $tile');
        }
      } finally {
        aux.dispose();
        EngineImages.dispose(image);
      }
    }
    await Future<void>.delayed(Duration.zero);
    expect(EngineImages.live, before);
  });

  test('the graph leaks no images', () async {
    final before = EngineImages.live;
    await withGraph((g) async {
      await frame(g, spatial);
      await frame(g, spatial.copyWith(backdrop: _blue.copyWith(match: 50)));
      await frame(g, point.copyWith(backdrop: BackdropChange.none));
    });
    await Future<void>.delayed(Duration.zero);
    expect(EngineImages.live, before);
  });
}
