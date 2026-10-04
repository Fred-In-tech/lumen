/// GPU pass plumbing shared by the preview graph and the export renderer.
///
/// Public API:
/// * `runPass(shader, w, h)`: draws a full-rect shader into an 8-bit
///   `ui.Image` via `PictureRecorder` → `toImageSync` (GPU resident).
/// * `uploadRgba(bytes, w, h)`: RGBA8888 bytes → `ui.Image`.
/// * `readRgba(image)`: `ui.Image` → RGBA8888 bytes (premultiplied; every
///   engine image is opaque, so this equals straight RGBA).
/// * `runDevelop`, `runFinish`, `runDenoise`, `runMaskOverlay`: one pass
///   each, given packed uniforms from `lumen_core`. The caller owns (and
///   disposes) the result.
/// * `runRetouch`: one tile of the portrait retouch pass R (source space).
/// * `runBackdrop`: one tile of the backdrop composite pass B (source space).
/// * `renderTiled`: runs a per-tile pass over a w×h image and composes the
///   tiles 1:1 into one image (one pass when it fits).
/// * `emptyMaskAtlas`: a shared 1×1 transparent image bound when no mask
///   atlas is in use (never disposed, not in the ledger).
/// * `EngineImages`: debug counter of live engine-created images.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'shader_library.dart';

/// Debug ledger: every image the engine creates is registered here and must
/// be released through [EngineImages.dispose]. Tests assert `live == 0`.
abstract final class EngineImages {
  static final Set<ui.Image> _tracked = Set.identity();

  /// Number of engine-created images not yet disposed.
  static int get live => _tracked.length;

  static ui.Image track(ui.Image image) {
    _tracked.add(image);
    return image;
  }

  /// Disposes [image] and removes it from the ledger if it was tracked.
  /// Call exactly once per image you own.
  static void dispose(ui.Image? image) {
    if (image == null) return;
    _tracked.remove(image);
    image.dispose();
  }
}

ui.Image runPass(ui.FragmentShader shader, int width, int height) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return EngineImages.track(image);
}

Future<ui.Image> uploadRgba(Uint8List rgba, int width, int height) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    (img) => done.complete(EngineImages.track(img)),
  );
  return done.future;
}

Future<Uint8List> readRgba(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('Image readback failed');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

void _setFloats(ui.FragmentShader s, Float32List floats) {
  for (var i = 0; i < floats.length; i++) {
    s.setFloat(i, floats[i]);
  }
}

ui.Image _run(
  ui.FragmentProgram program,
  Float32List floats,
  List<(ui.Image, ui.FilterQuality)> samplers,
  int width,
  int height,
) {
  final shader = program.fragmentShader();
  try {
    _setFloats(shader, floats);
    for (var i = 0; i < samplers.length; i++) {
      shader.setImageSampler(i, samplers[i].$1, filterQuality: samplers[i].$2);
    }
    return runPass(shader, width, height);
  } finally {
    shader.dispose();
  }
}

ui.Image? _emptyMaskAtlas;

/// Shared 1×1 transparent image (coverage 0) for unused mask samplers.
ui.Image get emptyMaskAtlas {
  final cached = _emptyMaskAtlas;
  if (cached != null) return cached;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1, 1);
  picture.dispose();
  return _emptyMaskAtlas = image;
}

/// Develop uber pass. [floats] from `DevelopUniforms.pack`; [masks0] and
/// [masks1] are the mask atlases, [warp] the warp field atlas (default for
/// each: [emptyMaskAtlas]).
ui.Image runDevelop(
  ShaderLibrary shaders, {
  required Float32List floats,
  required ui.Image source,
  required ui.Image auxA,
  required ui.Image auxB,
  required ui.Image lut,
  required int width,
  required int height,
  ui.Image? masks0,
  ui.Image? masks1,
  ui.Image? warp,
}) => _run(
  shaders.develop,
  floats,
  [
    (source, ui.FilterQuality.low),
    (auxA, ui.FilterQuality.none),
    (auxB, ui.FilterQuality.none),
    (lut, ui.FilterQuality.none),
    (masks0 ?? emptyMaskAtlas, ui.FilterQuality.none),
    (masks1 ?? emptyMaskAtlas, ui.FilterQuality.none),
    (warp ?? emptyMaskAtlas, ui.FilterQuality.none),
  ],
  width,
  height,
);

/// Mask overlay pass. [floats] from `MaskOverlayUniforms.pack`; [atlas]
/// holds the mask.
ui.Image runMaskOverlay(
  ShaderLibrary shaders, {
  required Float32List floats,
  required ui.Image atlas,
  required int width,
  required int height,
  ui.Image? warp,
}) => _run(
  shaders.maskOverlay,
  floats,
  [
    (atlas, ui.FilterQuality.none),
    (warp ?? emptyMaskAtlas, ui.FilterQuality.none),
  ],
  width,
  height,
);

/// Finish pass over [image]. [floats] from `FinishUniforms.pack`.
ui.Image runFinish(
  ShaderLibrary shaders, {
  required Float32List floats,
  required ui.Image image,
}) => _run(
  shaders.finish,
  floats,
  [(image, ui.FilterQuality.none)],
  image.width,
  image.height,
);

/// Denoise pre-pass over [image]. [floats] from `DenoiseUniforms.pack`.
ui.Image runDenoise(
  ShaderLibrary shaders, {
  required Float32List floats,
  required ui.Image image,
}) => _run(
  shaders.denoise,
  floats,
  [(image, ui.FilterQuality.none)],
  image.width,
  image.height,
);

/// One tile of retouch pass R over [source] (all samplers nearest; manual
/// bilinear in the shader). [floats] from `RetouchPassUniforms.pack`;
/// [maps] = B1, B2, B3, Bh, regionA, regionB images.
ui.Image runRetouch(
  ShaderLibrary shaders, {
  required Float32List floats,
  required ui.Image source,
  required List<ui.Image> maps,
  required int width,
  required int height,
}) => _run(
  shaders.retouch,
  floats,
  [
    (source, ui.FilterQuality.none),
    for (final m in maps) (m, ui.FilterQuality.none),
  ],
  width,
  height,
);

/// One tile of backdrop pass B over [source]; [floats] from
/// `BackdropUniforms.pack`; [maps] = matte, fill, plate A, plate B (all
/// nearest-sampled; the shader interpolates manually).
ui.Image runBackdrop(
  ShaderLibrary shaders, {
  required Float32List floats,
  required ui.Image source,
  required List<ui.Image> maps,
  required int width,
  required int height,
}) => _run(
  shaders.backdrop,
  floats,
  [
    (source, ui.FilterQuality.none),
    for (final m in maps) (m, ui.FilterQuality.none),
  ],
  width,
  height,
);

/// Renders a [width]×[height] image as tiles of at most [tileSize] with
/// [tile] (offset, size → a tile image) and composes them 1:1 (exact
/// copies). The caller owns the result.
ui.Image renderTiled(
  int width,
  int height,
  int tileSize,
  ui.Image Function(int x0, int y0, int w, int h) tile,
) {
  if (width <= tileSize && height <= tileSize) {
    return tile(0, 0, width, height);
  }
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  final parts = <ui.Image>[];
  for (var y0 = 0; y0 < height; y0 += tileSize) {
    for (var x0 = 0; x0 < width; x0 += tileSize) {
      final tw = width - x0 < tileSize ? width - x0 : tileSize;
      final th = height - y0 < tileSize ? height - y0 : tileSize;
      final part = tile(x0, y0, tw, th);
      parts.add(part);
      canvas.drawImage(part, ui.Offset(x0.toDouble(), y0.toDouble()), paint);
    }
  }
  final picture = recorder.endRecording();
  final out = EngineImages.track(picture.toImageSync(width, height));
  picture.dispose();
  parts.forEach(EngineImages.dispose);
  return out;
}
