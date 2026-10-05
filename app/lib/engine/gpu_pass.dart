/// GPU pass plumbing shared by the preview graph and the export renderer.
///
/// Public API:
/// * `runPass(shader, w, h, {target})`: draws a full-rect shader into a
///   `ui.Image` via `PictureRecorder` → `toImageSync` (GPU resident):
///   8-bit by default, 32-bit float with `target: kFloatTarget` (the float
///   editing path, docs/HIGH_BIT_DEPTH.md).
/// * `uploadRgba(bytes, w, h)`: RGBA8888 bytes → `ui.Image`.
/// * `uploadFloat(floats, w, h)` / `readFloat(image)`: float32 RGBA
///   (extended range, alpha 1) ↔ a float32 `ui.Image`.
/// * `compositeOverlay(base, overlay)`: a premultiplied 8-bit overlay drawn
///   over a float image (heal patches on a float source).
/// * `readRgba(image)`: `ui.Image` → RGBA8888 bytes (premultiplied; every
///   engine image is opaque, so this equals straight RGBA).
/// * `runDevelop`, `runFinish`, `runDenoise`, `runMaskOverlay`: one pass
///   each, given packed uniforms from `lumen_core`. The caller owns (and
///   disposes) the result. `runDenoise`, `runRetouch` and `runBackdrop`
///   take `float: true` to render into a float32 target.
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

/// Render-target storage of the float path: 32-bit float RGBA, values kept
/// as the shader writes them (no clamp, no colour conversion). The only
/// float target `Picture.toImageSync` offers.
const ui.TargetPixelFormat kFloatTarget = ui.TargetPixelFormat.rgbaFloat32;

/// 8-bit target (today's pipeline).
const ui.TargetPixelFormat kByteTarget = ui.TargetPixelFormat.dontCare;

ui.TargetPixelFormat targetFor({required bool float}) =>
    float ? kFloatTarget : kByteTarget;

ui.Image runPass(
  ui.FragmentShader shader,
  int width,
  int height, {
  ui.TargetPixelFormat target = kByteTarget,
}) {
  final recorder = ui.PictureRecorder();
  final paint = ui.Paint()..shader = shader;
  // A float target takes the shader output as is (every pass writes
  // alpha 1, so this equals source-over; stated for clarity).
  if (target != kByteTarget) paint.blendMode = ui.BlendMode.src;
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    paint,
  );
  final picture = recorder.endRecording();
  final image = target == kByteTarget
      ? picture.toImageSync(width, height)
      : picture.toImageSync(width, height, targetFormat: target);
  picture.dispose();
  return EngineImages.track(image);
}

/// Float32 RGBA pixels (row-major, extended range, alpha 1.0) → a float32
/// GPU image. Uses `ImageDescriptor.raw` + `instantiateCodec(targetFormat:)`:
/// `decodeImageFromPixelsSync` silently produces 8 bits, and the default
/// upload target is half float (research 08).
Future<ui.Image> uploadFloat(Float32List rgba, int width, int height) async {
  if (rgba.length != width * height * 4) {
    throw ArgumentError('float data ${rgba.length} != ${width * height * 4}');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
  );
  ui.ImageDescriptor? desc;
  ui.Codec? codec;
  try {
    desc = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgbaFloat32,
    );
    codec = await desc.instantiateCodec(targetFormat: kFloatTarget);
    final frame = await codec.getNextFrame();
    return EngineImages.track(frame.image);
  } finally {
    codec?.dispose();
    desc?.dispose();
    buffer.dispose();
  }
}

/// A float image → float32 RGBA pixels (straight alpha, extended range).
Future<Float32List> readFloat(ui.Image image) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawExtendedRgba128,
  );
  if (data == null) throw StateError('Float image readback failed');
  return data.buffer.asFloat32List(data.offsetInBytes, data.lengthInBytes ~/ 4);
}

/// [base] (float) with the premultiplied 8-bit [overlay] of the same size
/// drawn source-over, into a new float image: the GPU twin of
/// `composeOverlayFloat`. Pixels the overlay leaves transparent keep their
/// float values exactly. The caller owns the result.
ui.Image compositeOverlay(ui.Image base, ui.Image overlay) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawImage(
      base,
      ui.Offset.zero,
      ui.Paint()
        ..blendMode = ui.BlendMode.src
        ..filterQuality = ui.FilterQuality.none,
    )
    ..drawImage(
      overlay,
      ui.Offset.zero,
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
  final picture = recorder.endRecording();
  final out = picture.toImageSync(
    base.width,
    base.height,
    targetFormat: kFloatTarget,
  );
  picture.dispose();
  return EngineImages.track(out);
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
  int height, [
  ui.TargetPixelFormat target = kByteTarget,
]) {
  final shader = program.fragmentShader();
  try {
    _setFloats(shader, floats);
    for (var i = 0; i < samplers.length; i++) {
      shader.setImageSampler(i, samplers[i].$1, filterQuality: samplers[i].$2);
    }
    return runPass(shader, width, height, target: target);
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
/// each: [emptyMaskAtlas]). [source] may be an 8-bit or a float image;
/// [float] selects a float32 target for the (0..1) output instead of the
/// 8-bit one (precision tests; a future 16-bit export).
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
  bool float = false,
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
  targetFor(float: float),
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
/// [float]: render into a float32 target (float sources keep highlights
/// above white).
ui.Image runDenoise(
  ShaderLibrary shaders, {
  required Float32List floats,
  required ui.Image image,
  bool float = false,
}) => _run(
  shaders.denoise,
  floats,
  [(image, ui.FilterQuality.none)],
  image.width,
  image.height,
  targetFor(float: float),
);

/// One tile of retouch pass R over [source] (all samplers nearest; manual
/// bilinear in the shader). [floats] from `RetouchPassUniforms.pack`;
/// [maps] = low, deltaA, deltaB, deltaC, regionA, regionB, backdrop images.
ui.Image runRetouch(
  ShaderLibrary shaders, {
  required Float32List floats,
  required ui.Image source,
  required List<ui.Image> maps,
  required int width,
  required int height,
  bool float = false,
}) => _run(
  shaders.retouch,
  floats,
  [
    (source, ui.FilterQuality.none),
    for (final m in maps) (m, ui.FilterQuality.none),
  ],
  width,
  height,
  targetFor(float: float),
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
  bool float = false,
}) => _run(
  shaders.backdrop,
  floats,
  [
    (source, ui.FilterQuality.none),
    for (final m in maps) (m, ui.FilterQuality.none),
  ],
  width,
  height,
  targetFor(float: float),
);

/// Renders a [width]×[height] image as tiles of at most [tileSize] with
/// [tile] (offset, size → a tile image) and composes them 1:1 (exact
/// copies) into an 8-bit image, or a float32 one with [float]. The caller
/// owns the result.
ui.Image renderTiled(
  int width,
  int height,
  int tileSize,
  ui.Image Function(int x0, int y0, int w, int h) tile, {
  bool float = false,
}) {
  if (width <= tileSize && height <= tileSize) {
    return tile(0, 0, width, height);
  }
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  if (float) paint.blendMode = ui.BlendMode.src;
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
  final out = EngineImages.track(
    float
        ? picture.toImageSync(width, height, targetFormat: kFloatTarget)
        : picture.toImageSync(width, height),
  );
  picture.dispose();
  parts.forEach(EngineImages.dispose);
  return out;
}
