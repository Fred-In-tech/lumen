import 'dart:typed_data';

import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/retouch_textures.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/retouch/support/synthetic_portrait.dart';
import '../support/test_images.dart';

export '../../../packages/lumen_core/test/retouch/support/synthetic_backdrop.dart';
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

/// A portrait with one face (veins on, for Red veins; [clippedShine] adds
/// a clipped specular core for Shine > 50) plus its maps.
({SynthPortrait p, RetouchMaps maps}) onePortrait({
  int size = 384,
  int? mapLongEdge,
  bool clippedShine = false,
}) {
  final p = renderSynthPortrait(size, size, [
    SynthFace(
      id: 'a',
      cx: size / 2,
      cy: size * 0.39,
      iod: size * 0.27,
      veins: true,
      clippedShine: clippedShine,
    ),
  ]);
  return (
    p: p,
    maps: computeRetouchMaps(p.image, p.analysis, longEdge: mapLongEdge),
  );
}

/// Settings with image-scope [values] (backdrop, stray hairs) on top of
/// [base].
PortraitSettings withImage(
  Map<String, double> values, [
  PortraitSettings base = PortraitSettings.empty,
]) {
  var s = base;
  for (final e in values.entries) {
    s = s.withImageValue(e.key, e.value);
  }
  return s;
}

/// A coarse person raster for a synthetic portrait (the head ellipse of
/// `_shadeFace`), like the vision pipeline's people plane.
MaskRaster portraitPeopleRaster(SynthPortrait p) {
  final w = p.image.width ~/ 2, h = p.image.height ~/ 2;
  final data = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var cov = 0.0;
      for (final f in p.faces) {
        final q = f.toLocal(2 * x + 1.0, 2 * y + 1.0);
        final r =
            (q.x / 1.4) * (q.x / 1.4) +
            ((q.y - 0.2) / 1.85) * ((q.y - 0.2) / 1.85);
        if (r <= 1 || (q.y > 0.9 && q.y < 2.3 && q.x.abs() < 1.6)) cov = 1;
      }
      data[y * w + x] = (cov * 255).round();
    }
  }
  return MaskRaster(w, h, data);
}
