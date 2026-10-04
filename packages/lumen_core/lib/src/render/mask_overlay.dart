/// "Show overlay" for one mask: its coverage as a premultiplied color tint
/// in OUTPUT space (crop/rotation applied, like the develop pass).
///
/// `mask_overlay.frag` uniforms (26 floats): `vec2 uOutSize`, `vec4 uTile`,
/// `vec4 uCrop`, `vec4 uGeom`, `vec4 uSrc` (source wh, mask grid wh),
/// `vec4 uSlot` (one-hot channel), `vec4 uTint` (r, g, b, max alpha).
library;

import 'dart:typed_data';

import '../model/develop_settings.dart';
import 'geometry_mapping.dart';
import 'mask_rasterizer.dart';
import 'rgba_buffer.dart';
import 'uniform_layout.dart';

const int kMaskOverlayFloatCount = 26;

/// Straight (non-premultiplied) overlay color; default: 50 % red.
typedef MaskTint = ({double r, double g, double b, double a});

const MaskTint kDefaultMaskTint = (r: 1, g: 0, b: 0, a: 0.5);

abstract final class MaskOverlayUniforms {
  /// Packs the overlay uniforms for mask [index] of [masks]. [ctx] gives the
  /// pass/tile/source sizes exactly as for the develop pass.
  static Float32List pack(
    DevelopSettings settings,
    DevelopContext ctx,
    MaskAtlases masks,
    int index, {
    MaskTint tint = kDefaultMaskTint,
  }) {
    final d = DevelopUniforms.pack(settings, ctx);
    final f = Float32List(kMaskOverlayFloatCount)
      ..setRange(0, 16, d)
      ..[16] = masks.width.toDouble()
      ..[17] = masks.height.toDouble();
    final slot = index % 4;
    f[18 + slot] = 1;
    f
      ..[22] = tint.r
      ..[23] = tint.g
      ..[24] = tint.b
      ..[25] = tint.a;
    return f;
  }

  /// Which atlas (0 or 1) holds mask [index].
  static int atlasOf(int index) => index ~/ 4;
}

/// CPU twin of `mask_overlay.frag` (for the CPU fallback renderer):
/// premultiplied RGBA of the output size for [settings].
RgbaBuffer renderMaskOverlayReference(
  int sourceWidth,
  int sourceHeight,
  DevelopSettings settings,
  MaskAtlases masks,
  int index, {
  MaskTint tint = kDefaultMaskTint,
}) {
  final size = outputSizeFor(sourceWidth, sourceHeight, settings.geometry);
  final f = DevelopUniforms.pack(
    settings,
    DevelopContext(
      outWidth: size.width,
      outHeight: size.height,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      auxWidth: 1,
      auxHeight: 1,
    ),
  );
  final out = RgbaBuffer(size.width, size.height);
  for (var y = 0; y < size.height; y++) {
    for (var x = 0; x < size.width; x++) {
      final (su, sv) = sourceUvFor(
        (x + 0.5) / size.width,
        (y + 0.5) / size.height,
        f,
      );
      if (su < 0 || su > 1 || sv < 0 || sv > 1) continue;
      final a = masks.sample(index, su, sv).clamp(0.0, 1.0) * tint.a;
      out.setPixel(
        x,
        y,
        (tint.r * a * 255).round(),
        (tint.g * a * 255).round(),
        (tint.b * a * 255).round(),
        (a * 255).round(),
      );
    }
  }
  return out;
}
