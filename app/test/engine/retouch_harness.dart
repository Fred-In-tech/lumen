import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/retouch_textures.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/retouch/support/synthetic_portrait.dart';
import '../support/test_images.dart';

export '../../../packages/lumen_core/test/retouch/support/synthetic_portrait.dart';

/// Settings with [values] on the All group (or [group]).
PortraitSettings portraitOf(
  Map<String, double> values, {
  FaceGroup group = FaceGroup.all,
}) {
  var s = PortraitSettings.empty;
  for (final e in values.entries) {
    s = s.withGroupValue(group, e.key, e.value);
  }
  return s;
}

/// Pass R on the GPU for [src]; returns [src] itself when the pass is
/// skipped (identity), like `applyRetouch`. Disposes what it creates.
Future<RgbaBuffer> gpuRetouch(
  RgbaBuffer src,
  RetouchMaps maps,
  RetouchUniforms uniforms, {
  int tileSize = 4096,
}) async {
  final shaders = await ShaderLibrary.load();
  final source = await imageFromBuffer(src);
  final textures = await RetouchTextures.upload(maps);
  try {
    final out = runRetouchPass(
      shaders,
      source: source,
      textures: textures,
      uniforms: uniforms,
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

/// A portrait with one face (veins on, for Red veins) plus its maps.
({SynthPortrait p, RetouchMaps maps}) onePortrait({
  int size = 384,
  int? mapLongEdge,
}) {
  final p = renderSynthPortrait(size, size, [
    SynthFace(
      id: 'a',
      cx: size / 2,
      cy: size * 0.39,
      iod: size * 0.27,
      veins: true,
    ),
  ]);
  return (
    p: p,
    maps: computeRetouchMaps(p.image, p.analysis, longEdge: mapLongEdge),
  );
}
