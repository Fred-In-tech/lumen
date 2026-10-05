import 'dart:typed_data';

import '../model/develop_settings.dart';
import '../model/param_registry.dart';
import 'aux_maps.dart';
import 'develop_kernel.dart';
import 'float_buffer.dart';
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
  final job = _prepare(
    settings,
    sourceWidth: source.width,
    sourceHeight: source.height,
    aux:
        aux ??
        (needsAuxMaps(settings)
            ? AuxMaps.compute(AuxMaps.proxy(source))
            : AuxMaps.neutral()),
    showClipping: showClipping,
    masks: masks,
    maskRasters: maskRasters,
    warp: warp,
    faces: faces,
  );
  final kernel = DevelopKernel(
    source,
    job.floats,
    ToneLut.bake(settings),
    job.aux,
    job.masks,
    job.warp,
  );
  final out = RgbaBuffer(job.width, job.height);
  final px = Float64List(4);
  var o = 0;
  for (var y = 0; y < job.height; y++) {
    for (var x = 0; x < job.width; x++, o += 4) {
      kernel.shade(x, y, px);
      out.data[o] = (px[0] * 255).round();
      out.data[o + 1] = (px[1] * 255).round();
      out.data[o + 2] = (px[2] * 255).round();
      out.data[o + 3] = (px[3] * 255).round();
    }
  }
  return out;
}

/// An output tile of a render: offset and size inside the full output.
typedef OutputTile = ({int x, int y, int width, int height});

/// [renderReference] for a float source (the float editing path,
/// docs/HIGH_BIT_DEPTH.md): [source] holds extended-range encoded values,
/// so exposure, white balance, highlights and shadows work on real
/// headroom and shadow precision. Returns the encoded output (0..1,
/// unrounded); `toRgba()` gives what an 8-bit target stores.
///
/// [profile] is the source's rendering profile (shoulder, extra highlight
/// range). With an 8-bit-equivalent source and [HbdProfile.none] the result
/// rounds to exactly what [renderReference] returns.
///
/// Export windows: [source] may hold only [window] of the full source
/// (then pass [aux], which always covers the whole photo), and [tile]
/// renders one tile of the full output.
FloatBuffer renderReferenceFloat(
  FloatBuffer source,
  DevelopSettings settings, {
  AuxMaps? aux,
  HbdProfile profile = HbdProfile.none,
  SourceWindow? window,
  OutputTile? tile,
  bool showClipping = false,
  MaskAtlases? masks,
  Map<String, MaskRaster> maskRasters = const {},
  WarpField? warp,
  FaceAnalysis? faces,
}) {
  if (window != null && aux == null && needsAuxMaps(settings)) {
    throw ArgumentError('a windowed render needs the aux maps of the photo');
  }
  final job = _prepare(
    settings,
    sourceWidth: window?.fullWidth ?? source.width,
    sourceHeight: window?.fullHeight ?? source.height,
    aux:
        aux ??
        (needsAuxMaps(settings)
            ? AuxMaps.computeFloat(AuxMaps.proxyFloat(source))
            : AuxMaps.neutral()),
    showClipping: showClipping,
    masks: masks,
    maskRasters: maskRasters,
    warp: warp,
    faces: faces,
    profile: profile,
    window: window == null
        ? null
        : (
            x: window.x,
            y: window.y,
            width: source.width,
            height: source.height,
          ),
    tile: tile,
  );
  final kernel = DevelopKernel.float(
    source,
    job.floats,
    ToneLut.bake(settings),
    job.aux,
    job.masks,
    job.warp,
  );
  final out = FloatBuffer(job.width, job.height);
  final px = Float64List(4);
  var o = 0;
  for (var y = 0; y < job.height; y++) {
    for (var x = 0; x < job.width; x++, o += 4) {
      kernel.shade(x, y, px);
      out.data[o] = px[0];
      out.data[o + 1] = px[1];
      out.data[o + 2] = px[2];
      out.data[o + 3] = px[3];
    }
  }
  return out;
}

typedef _Job = ({
  Float32List floats,
  AuxMaps aux,
  MaskAtlases masks,
  WarpField? warp,
  int width,
  int height,
});

/// Everything a reference render needs besides the source pixels.
_Job _prepare(
  DevelopSettings settings, {
  required int sourceWidth,
  required int sourceHeight,
  required AuxMaps aux,
  required bool showClipping,
  required MaskAtlases? masks,
  required Map<String, MaskRaster> maskRasters,
  required WarpField? warp,
  required FaceAnalysis? faces,
  HbdProfile profile = HbdProfile.none,
  OutputTile? window,
  OutputTile? tile,
}) {
  final field =
      warp ??
      (hasWarpEdits(settings, faces)
          ? buildWarpField(
              WarpRequest.fromSettings(
                settings,
                faces,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
              ),
            )
          : null);
  final warpOn = field != null && !field.isIdentity;
  final coverage =
      masks ??
      (settings.masks.any((m) => m.hasAdjustments)
          ? MaskRasterizer.build(
              settings.masks,
              sourceWidth,
              sourceHeight,
              rasters: maskRasters,
            )
          : MaskAtlases.empty());
  final size = outputSizeFor(sourceWidth, sourceHeight, settings.geometry);
  final f = DevelopUniforms.pack(
    settings,
    DevelopContext(
      outWidth: tile?.width ?? size.width,
      outHeight: tile?.height ?? size.height,
      tileX: (tile?.x ?? 0).toDouble(),
      tileY: (tile?.y ?? 0).toDouble(),
      fullWidth: size.width.toDouble(),
      fullHeight: size.height.toDouble(),
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      auxWidth: aux.width,
      auxHeight: aux.height,
      airlight: aux.airlight,
      showClipping: showClipping,
      maskWidth: coverage.width,
      maskHeight: coverage.height,
      warpWidth: warpOn ? field.width : 1,
      warpHeight: warpOn ? field.height : 1,
      warpRange: warpOn ? field.range : 0,
      profile: profile,
      windowX: window?.x ?? 0,
      windowY: window?.y ?? 0,
      windowWidth: window?.width,
      windowHeight: window?.height,
    ),
  );
  return (
    floats: f,
    aux: aux,
    masks: coverage,
    warp: warpOn ? field : null,
    width: tile?.width ?? size.width,
    height: tile?.height ?? size.height,
  );
}
