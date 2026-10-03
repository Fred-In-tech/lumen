/// The preview render graph: denoise? → develop → finish?
///
/// Public API:
/// * `abstract interface class FrameRenderer`:
///   `Future<ui.Image> render(settings, {scale, showClipping})`, `dispose()`.
///   `RenderScheduler` drives any `FrameRenderer` (tests use fakes).
/// * `RenderGraph(shaders:, source:, aux:, assetId:, originalSize:)`:
///   borrows `source` and `aux` (the caller keeps owning them), owns its LUT
///   texture and denoise cache. Each `render` returns a new image owned by
///   the caller. `outputSize(settings, scale)` gives the frame size.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

import 'aux_cache.dart';
import 'gpu_pass.dart';
import 'lut_texture.dart';
import 'shader_library.dart';

abstract interface class FrameRenderer {
  /// Renders [settings] at [scale] × the preview size. The caller owns the
  /// returned image.
  Future<ui.Image> render(
    DevelopSettings settings, {
    double scale = 1,
    bool showClipping = false,
  });

  void dispose();
}

class RenderGraph implements FrameRenderer {
  RenderGraph({
    required this.shaders,
    required this.source,
    required this.aux,
    this.assetId = '',
    ({int width, int height})? originalSize,
  }) : originalSize =
           originalSize ?? (width: source.width, height: source.height);

  final ShaderLibrary shaders;

  /// Preview-resolution source (borrowed).
  final ui.Image source;

  /// Aux textures of this photo (borrowed).
  final AuxTextures aux;

  /// Seeds the grain so it is stable across renders and export.
  final String assetId;

  /// Size of the original file, for resolution-dependent effects (grain,
  /// sharpen radius).
  final ({int width, int height}) originalSize;

  LutTexture? _lut;
  ui.Image? _denoised;
  (double, double)? _denoiseKey;
  bool _disposed = false;

  /// Output size for [settings] at [scale].
  ({int width, int height}) outputSize(DevelopSettings settings, double scale) {
    final full = outputSizeFor(source.width, source.height, settings.geometry);
    return (
      width: math.max(1, (full.width * scale).round()),
      height: math.max(1, (full.height * scale).round()),
    );
  }

  @override
  Future<ui.Image> render(
    DevelopSettings settings, {
    double scale = 1,
    bool showClipping = false,
  }) async {
    if (_disposed) throw StateError('RenderGraph disposed');
    final lut = await _lutFor(settings);
    if (_disposed) throw StateError('RenderGraph disposed');
    final src = _sourceFor(settings);
    final size = outputSize(settings, scale);
    final developed = runDevelop(
      shaders,
      floats: DevelopUniforms.pack(
        settings,
        DevelopContext(
          outWidth: size.width,
          outHeight: size.height,
          sourceWidth: source.width,
          sourceHeight: source.height,
          auxWidth: aux.width,
          auxHeight: aux.height,
          airlight: aux.maps.airlight,
          showClipping: showClipping,
        ),
      ),
      source: src,
      auxA: aux.auxA,
      auxB: aux.auxB,
      lut: lut.image,
      width: size.width,
      height: size.height,
    );
    if (FinishUniforms.isIdentity(settings)) return developed;
    final full = outputSizeFor(
      originalSize.width,
      originalSize.height,
      settings.geometry,
    );
    final finished = runFinish(
      shaders,
      floats: FinishUniforms.pack(
        settings,
        FinishContext(
          width: size.width,
          height: size.height,
          seed: FinishUniforms.seedFor(assetId),
          previewScale: math.max(1.0, full.width / size.width),
        ),
      ),
      image: developed,
    );
    EngineImages.dispose(developed);
    return finished;
  }

  Future<LutTexture> _lutFor(DevelopSettings s) async {
    final key = ToneLut.keyFor(s);
    final current = _lut;
    if (current != null && current.key == key) return current;
    final fresh = await LutTexture.upload(ToneLut.bake(s));
    // Images already recorded into a picture stay alive in the engine, so
    // releasing the previous LUT here is safe even mid-frame.
    _lut?.dispose();
    _lut = fresh;
    if (_disposed) _releaseLut();
    return fresh;
  }

  ui.Image _sourceFor(DevelopSettings s) {
    if (DenoiseUniforms.isIdentity(s)) return source;
    final key = (s.value(P.noiseLuminance), s.value(P.noiseColor));
    final cached = _denoised;
    if (cached != null && _denoiseKey == key) return cached;
    EngineImages.dispose(cached);
    _denoiseKey = key;
    return _denoised = runDenoise(
      shaders,
      floats: DenoiseUniforms.pack(s, source.width, source.height),
      image: source,
    );
  }

  void _releaseLut() {
    _lut?.dispose();
    _lut = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseLut();
    EngineImages.dispose(_denoised);
    _denoised = null;
  }
}
