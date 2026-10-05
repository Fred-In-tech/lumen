import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

/// Helpers of the float-path engine tests (docs/HIGH_BIT_DEPTH.md).
///
/// Float render targets exist on Impeller only: run these suites with
/// `flutter test --enable-impeller` (or on a device). Under the default
/// headless renderer (Skia, 8-bit targets) [floatPathOrSkip] marks the
/// test skipped instead of comparing a float CPU twin with an 8-bit chain.

Future<bool> floatPathOrSkip() async {
  final ok = await HbdCapability.probe(await ShaderLibrary.load());
  if (!ok) {
    markTestSkipped(
      'no float render targets in this renderer (default headless Skia); '
      'run with --enable-impeller or on a device',
    );
  }
  return ok;
}

void result(String line) => debugPrint('RESULT $line');

Future<ui.Image> imageFromFloat(FloatBuffer b) =>
    uploadFloat(b.data, b.width, b.height);

Future<FloatBuffer> floatFromImage(ui.Image img) async =>
    FloatBuffer(img.width, img.height, await readFloat(img));

/// An 8-bit scene as a float source with real float content: sub-8-bit
/// detail everywhere and highlights up to [peak]× (encoded) towards the
/// right edge.
FloatBuffer hotScene(RgbaBuffer scene, {double peak = 1.9, int seed = 5}) {
  final rnd = math.Random(seed);
  final out = FloatBuffer.fromRgba(scene);
  for (var y = 0; y < scene.height; y++) {
    for (var x = 0; x < scene.width; x++) {
      final o = out.offset(x, y);
      final t = x / (scene.width - 1);
      final gain = 1 + (peak - 1) * t * t;
      for (var c = 0; c < 3; c++) {
        final fine = (rnd.nextDouble() - 0.5) / 255;
        out.data[o + c] = math.max(0, (out.data[o + c] + fine) * gain);
      }
    }
  }
  return out;
}

/// Renders the float [src] through a float [RenderGraph] with CPU float aux
/// maps ([aux], computed from [src] when omitted). Disposes what it makes.
Future<RgbaBuffer> gpuRenderFloat(
  FloatBuffer src,
  DevelopSettings s, {
  AuxMaps? aux,
  HbdProfile profile = HbdProfile.none,
  double scale = 1,
  String assetId = 'test',
}) async {
  final shaders = await ShaderLibrary.load();
  final maps = aux ?? AuxMaps.computeFloat(AuxMaps.proxyFloat(src));
  final textures = await AuxTextures.fromMaps(maps);
  final image = await imageFromFloat(src);
  final graph = RenderGraph(
    shaders: shaders,
    source: image,
    aux: textures,
    assetId: assetId,
    float: true,
    profile: profile,
  );
  try {
    final out = await graph.render(s, scale: scale);
    final buf = RgbaBuffer(out.width, out.height, await readRgba(out));
    EngineImages.dispose(out);
    return buf;
  } finally {
    graph.dispose();
    textures.dispose();
    EngineImages.dispose(image);
  }
}

/// Distinct values of channel 1 in row [y], columns [x0]..[x1].
int rowLevels(RgbaBuffer b, int y, [int x0 = 0, int? x1]) =>
    {for (var x = x0; x < (x1 ?? b.width); x++) b.g(x, y)}.length;

/// A [w]×[h] float image whose rows are a gray ramp from [from] to [to]
/// (encoded).
FloatBuffer floatRamp(int w, int h, double from, double to) {
  final b = FloatBuffer(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = from + (to - from) * x / (w - 1);
      b.setPixel(x, y, v, v, v);
    }
  }
  return b;
}
