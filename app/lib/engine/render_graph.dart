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
/// * Masks: `settings.masks` are rendered automatically. Coverage atlases
///   come from the graph's `maskCache` (rebuilt only when coverage changes;
///   adjustments are uniforms). Set `maskRasters` (`maskRef` → decoded
///   `MaskRaster`) for AI masks; missing rasters cover nothing.
/// * Portrait retouch (pass R, between denoise and develop): set
///   `retouchMaps` (from `computeRetouchMaps`) and `faceAnalysis` (the same
///   analysis the maps were built from). Uniforms come from
///   `settings.portrait` on every render; the R output is cached by
///   `RetouchUniforms.key` + maps identity + denoise state, so non-portrait
///   edits do not re-run it. Identity settings skip R (bit-exact source).
/// * `renderMaskOverlay(settings, index, {scale, tint})`: one mask's
///   coverage as a premultiplied tint (default 50 % red), same size and
///   geometry as `render` (draw it over the frame for "show overlay").
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

import 'aux_cache.dart';
import 'gpu_pass.dart';
import 'lut_texture.dart';
import 'mask_atlas_cache.dart';
import 'retouch_textures.dart';
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
           originalSize ?? (width: source.width, height: source.height),
       maskCache = MaskAtlasCache(
         sourceWidth: source.width,
         sourceHeight: source.height,
       );

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

  /// Mask coverage atlases of this photo (owned by the graph).
  final MaskAtlasCache maskCache;

  /// Decoded AI mask rasters by `maskRef`.
  Map<String, MaskRaster> get maskRasters => maskCache.rasters;
  set maskRasters(Map<String, MaskRaster> value) => maskCache.rasters = value;

  LutTexture? _lut;
  ui.Image? _denoised;
  (double, double)? _denoiseKey;
  ui.Image? _retouched;
  String? _retouchKey;
  int _retouchRuns = 0;

  /// Number of times pass R actually ran (cache diagnostics, tests).
  int get retouchRuns => _retouchRuns;

  /// Uploaded retouch maps (owned by the graph).
  final RetouchMapsCache retouchCache = RetouchMapsCache();

  /// Retouch maps of this photo, or null (no portrait retouch).
  RetouchMaps? retouchMaps;

  /// The face analysis the [retouchMaps] were built from.
  FaceAnalysis? faceAnalysis;
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
    final masks = await maskCache.obtain(settings.masks);
    final retouch = await retouchCache.obtain(retouchMaps);
    if (_disposed) throw StateError('RenderGraph disposed');
    final src = _retouchedFor(settings, _sourceFor(settings), retouch);
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
          maskWidth: masks.width,
          maskHeight: masks.height,
        ),
      ),
      source: src,
      auxA: aux.auxA,
      auxB: aux.auxB,
      lut: lut.image,
      width: size.width,
      height: size.height,
      masks0: masks.atlas0,
      masks1: masks.atlas1,
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

  Future<ui.Image> renderMaskOverlay(
    DevelopSettings settings,
    int index, {
    double scale = 1,
    MaskTint tint = kDefaultMaskTint,
  }) async {
    if (_disposed) throw StateError('RenderGraph disposed');
    final masks = await maskCache.obtain(settings.masks);
    if (_disposed) throw StateError('RenderGraph disposed');
    if (index < 0 || index >= masks.count) {
      throw RangeError.range(index, 0, masks.count - 1, 'index');
    }
    final size = outputSize(settings, scale);
    return runMaskOverlay(
      shaders,
      floats: MaskOverlayUniforms.pack(
        settings,
        DevelopContext(
          outWidth: size.width,
          outHeight: size.height,
          sourceWidth: source.width,
          sourceHeight: source.height,
          auxWidth: aux.width,
          auxHeight: aux.height,
        ),
        masks.atlases,
        index,
        tint: tint,
      ),
      atlas: masks.atlasFor(index),
      width: size.width,
      height: size.height,
    );
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

  /// Pass R over [denoised] (cached), or [denoised] when inactive.
  ui.Image _retouchedFor(
    DevelopSettings s,
    ui.Image denoised,
    RetouchTextures? textures,
  ) {
    final analysis = faceAnalysis;
    final u = textures == null || analysis == null
        ? null
        : RetouchUniforms.fromSettings(s.portrait, analysis);
    if (textures == null ||
        u == null ||
        !RetouchPassUniforms.isActive(textures.maps, u)) {
      _releaseRetouched();
      return denoised;
    }
    final key =
        '${u.key}|${identityHashCode(textures)}|'
        '${identical(denoised, source) ? 'src' : _denoiseKey}';
    final cached = _retouched;
    if (cached != null && _retouchKey == key) return cached;
    _releaseRetouched();
    final out = runRetouchPass(
      shaders,
      source: denoised,
      textures: textures,
      uniforms: u,
    );
    if (out == null) return denoised;
    _retouchRuns++;
    _retouchKey = key;
    return _retouched = out;
  }

  void _releaseRetouched() {
    EngineImages.dispose(_retouched);
    _retouched = null;
    _retouchKey = null;
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
    maskCache.dispose();
    retouchCache.dispose();
    _releaseRetouched();
    EngineImages.dispose(_denoised);
    _denoised = null;
  }
}
