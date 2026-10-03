import 'dart:typed_data';

import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import 'engine_constants.dart';

/// Per-render context for [FinishUniforms.pack].
class FinishContext {
  const FinishContext({
    required this.width,
    required this.height,
    this.tileX = 0,
    this.tileY = 0,
    this._fullWidth,
    this._fullHeight,
    this.seed = 0,
    this.previewScale = 1,
    this.dither = true,
  });

  /// Size of the image this pass renders.
  final int width;
  final int height;

  /// Offset of this pass inside the full output (grain and dither use
  /// global pixel coordinates, so tiles are seamless).
  final double tileX;
  final double tileY;
  final double? _fullWidth;
  final double? _fullHeight;
  double get fullWidth => _fullWidth ?? width.toDouble();
  double get fullHeight => _fullHeight ?? height.toDouble();

  /// Grain seed, see [FinishUniforms.seedFor].
  final double seed;

  /// Full-resolution pixels per rendered pixel (≥ 1 for previews).
  final double previewScale;

  /// Adds ±0.5/255 dither before 8-bit quantization.
  final bool dither;
}

/// Float offsets into the packed finish uniforms.
///
/// `finish.frag`: `vec2 uSize`, `vec4 uTile` (offset x, y, full w, h),
/// `vec4 uSharpen` (amount 0–1.5, radius px, detail 0–1, masking 0–1),
/// `vec4 uGrain` (amount 0–1, size px, roughness 0–1, seed),
/// `vec4 uDither` (enabled, previewScale, 0, 0); sampler 0 = develop output.
abstract final class FinishIndex {
  static const size = 0;
  static const tile = 2;
  static const sharpen = 6;
  static const grain = 10;
  static const dither = 14;
}

abstract final class FinishUniforms {
  /// True when the finish pass can be skipped (no sharpening, no grain).
  static bool isIdentity(DevelopSettings s) =>
      s.value(P.sharpenAmount) == 0 && s.value(P.grainAmount) == 0;

  /// Stable grain seed in 0..1000 from an asset id (FNV-1a).
  static double seedFor(String assetId) {
    var h = 0x811c9dc5;
    for (final c in assetId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return (h % 100000) / 100;
  }

  static Float32List pack(DevelopSettings s, FinishContext ctx) {
    final f = Float32List(kFinishFloatCount);
    double n(ParamId id) => s.value(id) / 100;
    f
      ..[FinishIndex.size] = ctx.width.toDouble()
      ..[FinishIndex.size + 1] = ctx.height.toDouble()
      ..[FinishIndex.tile] = ctx.tileX
      ..[FinishIndex.tile + 1] = ctx.tileY
      ..[FinishIndex.tile + 2] = ctx.fullWidth
      ..[FinishIndex.tile + 3] = ctx.fullHeight
      ..[FinishIndex.sharpen] = n(P.sharpenAmount)
      ..[FinishIndex.sharpen + 1] = s.value(P.sharpenRadius)
      ..[FinishIndex.sharpen + 2] = n(P.sharpenDetail)
      ..[FinishIndex.sharpen + 3] = n(P.sharpenMasking)
      ..[FinishIndex.grain] = n(P.grainAmount)
      ..[FinishIndex.grain + 1] = 0.5 + 3.5 * n(P.grainSize)
      ..[FinishIndex.grain + 2] = n(P.grainRoughness)
      ..[FinishIndex.grain + 3] = ctx.seed
      ..[FinishIndex.dither] = ctx.dither ? 1 : 0
      ..[FinishIndex.dither + 1] = ctx.previewScale;
    return f;
  }
}

/// `denoise.frag`: `vec2 uSize`, `vec4 uNr` (luminance 0–1, color 0–1, 0, 0).
abstract final class DenoiseUniforms {
  static bool isIdentity(DevelopSettings s) =>
      s.value(P.noiseLuminance) == 0 && s.value(P.noiseColor) == 0;

  static Float32List pack(DevelopSettings s, int width, int height) =>
      Float32List.fromList([
        width.toDouble(),
        height.toDouble(),
        s.value(P.noiseLuminance) / 100,
        s.value(P.noiseColor) / 100,
        0,
        0,
      ]);
}
