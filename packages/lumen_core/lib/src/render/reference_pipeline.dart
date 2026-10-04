import 'dart:typed_data';

import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import 'aux_maps.dart';
import 'develop_kernel.dart';
import 'geometry_mapping.dart';
import 'mask_rasterizer.dart';
import '../model/face_analysis.dart';
import '../warp/warp_builder.dart';
import '../warp/warp_field.dart';
import 'rgba_buffer.dart';
import 'tone_lut.dart';
import 'uniform_layout.dart';

/// True when [s] uses a spatial op that reads the aux maps.
bool needsAuxMaps(DevelopSettings s) {
  const spatial = [P.dehaze, P.shadows, P.highlights, P.clarity];
  return spatial.any((id) => s.value(id) != 0) ||
      s.masks.any(
        (m) => spatial.any((id) => m.localAdjustments.containsKey(id)),
      );
}

/// CPU reference implementation of the develop pipeline (engine `lumen-1`).
///
/// The GPU `develop.frag` matches this within the parity thresholds of
/// PLAN.md §6.3. The local auto-tone solver and guards render proxies with
/// it. Output size follows the geometry (see [outputSizeFor]).
///
/// [aux] are the precomputed spatial maps of this photo; pass them when
/// rendering the same photo repeatedly (solver loops). When omitted they are
/// computed from [source] (only if a spatial op is active). Noise reduction,
/// sharpening and grain (pre/finish passes) are not part of the reference.
///
/// Masks: pass precomputed [masks] (`MaskRasterizer.build`) to reuse them,
/// or let them be rasterized from `settings.masks`; AI masks read their
/// decoded coverage from [maskRasters] by `ai.maskRef`.
///
/// Warp: pass a prebuilt [warp] field, or let it be built from
/// `settings.liquify` and the face-shape sliders (which need [faces], the
/// analysis of this photo). Source, aux and masks are all sampled at the
/// warped uv.
RgbaBuffer renderReference(
  RgbaBuffer source,
  DevelopSettings settings, {
  AuxMaps? aux,
  bool showClipping = false,
  MaskAtlases? masks,
  Map<String, MaskRaster> maskRasters = const {},
  WarpField? warp,
  FaceAnalysis? faces,
}) {
  final field =
      warp ??
      (hasWarpEdits(settings, faces)
          ? buildWarpField(
              WarpRequest.fromSettings(
                settings,
                faces,
                sourceWidth: source.width,
                sourceHeight: source.height,
              ),
            )
          : null);
  final warpOn = field != null && !field.isIdentity;
  final maps =
      aux ??
      (needsAuxMaps(settings)
          ? AuxMaps.compute(AuxMaps.proxy(source))
          : AuxMaps.neutral());
  final coverage =
      masks ??
      (settings.masks.any((m) => m.hasAdjustments)
          ? MaskRasterizer.build(
              settings.masks,
              source.width,
              source.height,
              rasters: maskRasters,
            )
          : MaskAtlases.empty());
  final size = outputSizeFor(source.width, source.height, settings.geometry);
  final f = DevelopUniforms.pack(
    settings,
    DevelopContext(
      outWidth: size.width,
      outHeight: size.height,
      sourceWidth: source.width,
      sourceHeight: source.height,
      auxWidth: maps.width,
      auxHeight: maps.height,
      airlight: maps.airlight,
      showClipping: showClipping,
      maskWidth: coverage.width,
      maskHeight: coverage.height,
      warpWidth: warpOn ? field.width : 1,
      warpHeight: warpOn ? field.height : 1,
      warpRange: warpOn ? field.range : 0,
    ),
  );
  final kernel = DevelopKernel(
    source,
    f,
    ToneLut.bake(settings),
    maps,
    coverage,
    warpOn ? field : null,
  );
  final out = RgbaBuffer(size.width, size.height);
  final px = Float64List(4);
  var o = 0;
  for (var y = 0; y < size.height; y++) {
    for (var x = 0; x < size.width; x++, o += 4) {
      kernel.shade(x, y, px);
      out.data[o] = (px[0] * 255).round();
      out.data[o + 1] = (px[1] * 255).round();
      out.data[o + 2] = (px[2] * 255).round();
      out.data[o + 3] = (px[3] * 255).round();
    }
  }
  return out;
}
