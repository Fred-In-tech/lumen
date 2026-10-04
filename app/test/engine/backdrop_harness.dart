import 'package:lumen/engine/backdrop_textures.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';

export '../../../packages/lumen_core/test/backdrop/support/backdrop_scene.dart';

/// Pass B on the GPU for [src]; returns [src] itself when the pass is
/// skipped (identity), like `applyBackdrop`. Disposes what it creates.
Future<RgbaBuffer> gpuBackdrop(
  RgbaBuffer src,
  BackdropAssets assets,
  BackdropChange change, {
  int tileSize = 4096,
}) async {
  final shaders = await ShaderLibrary.load();
  final source = await imageFromBuffer(src);
  final textures = await BackdropTextures.upload(assets);
  try {
    final out = runBackdropPass(
      shaders,
      source: source,
      textures: textures,
      change: change,
      tileSize: tileSize,
    );
    if (out == null) return src;
    final buf = await bufferFromImage(out);
    EngineImages.dispose(out);
    return buf;
  } finally {
    textures.dispose();
    EngineImages.dispose(source);
  }
}

/// A [w]×[h] backdrop photo: a warm-to-cool ramp with a coarse checker.
RgbaBuffer testBackdropImage(int w, int h) {
  final b = RgbaBuffer(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final u = x / (w - 1), v = y / (h - 1);
      final check = ((x ~/ 16) + (y ~/ 16)).isEven ? 18 : 0;
      b.setPixel(
        x,
        y,
        (220 - 150 * u + check).round(),
        (90 + 80 * v).round(),
        (60 + 170 * u - check).round().clamp(0, 255),
      );
    }
  }
  return b;
}
