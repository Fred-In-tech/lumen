import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/remove/healed_source.dart';

/// Renders one photo for the editor canvas.
///
/// Implementations: `GpuPhotoRenderer` (fragment shaders, interactive) and
/// [CpuPhotoRenderer] (reference pipeline in an isolate; fallback + tests).
abstract interface class PhotoRenderer {
  /// The latest rendered frame (null until the first render completes).
  ValueListenable<ui.Image?> get output;

  /// The unedited preview (for before/after).
  ui.Image? get before;

  /// 512 px proxy of the unedited source, for analysis and auto-edit.
  RgbaBuffer? get analysisProxy;

  /// Decodes [original] into a preview and analysis proxy.
  Future<void> open(Uint8List original);

  /// Requests a render of [settings]; implementations coalesce (latest wins).
  void update(DevelopSettings settings, {bool interactive = false});

  /// Renders [settings] onto a small square-ish thumbnail and returns PNG bytes.
  Future<Uint8List> renderThumbnail(
    DevelopSettings settings, {
    int longEdge = 384,
  });

  void dispose();
}

/// Optional renderer capability: one mask's coverage as a premultiplied
/// tint in the same geometry as [PhotoRenderer.output] (the Masks "Show
/// overlay"). Check with `renderer is MaskOverlayRenderer`; renderers
/// without it simply show no tint.
abstract interface class MaskOverlayRenderer {
  /// Renders the tint of `settings.masks[index]`, or null when the photo is
  /// not open. The caller owns the returned image.
  Future<ui.Image?> renderMaskOverlay(
    DevelopSettings settings,
    int index, {
    MaskTint tint = kDefaultMaskTint,
  });
}

/// Optional renderer capability: decoded AI mask rasters by `maskRef`
/// (`AiShape.maskRef`). Without them AI masks cover nothing. Check with
/// `renderer is MaskRasterSink`.
abstract interface class MaskRasterSink {
  /// Replaces the rasters AI masks read and re-renders the last settings
  /// (frame, thumbnails and mask overlay all use them).
  void setMaskRasters(Map<String, MaskRaster> rasters);
}

/// Optional renderer capability: the portrait retouch inputs of the open
/// photo. [maps] come from `computeRetouchMaps` on any decode of the photo
/// (they are sampled in source uv); [faces] is the analysis they were built
/// from, which resolves per-face group and individual values. Null clears
/// retouch. Check with `renderer is RetouchSink`.
abstract interface class RetouchSink {
  /// Replaces the retouch inputs and re-renders the last settings.
  void setRetouch(RetouchMaps? maps, FaceAnalysis? faces);
}

/// Optional renderer capability: the photo's heal compositor. The renderer
/// develops the preview (and thumbnails) with `settings.heal` drawn in; the
/// [PhotoRenderer.before] image stays the unhealed source, and settings
/// without heal ops (e.g. the "before" render) show the unhealed photo.
/// Null stops drawing heals. Check with `renderer is HealSink`.
abstract interface class HealSink {
  /// Replaces the compositor and re-renders the last settings.
  void setHealer(HealedSourceCache? healer);
}

/// Optional renderer capability: the face analysis of the open photo for
/// the face-shape sliders (`shape.*` in `settings.portrait`, resolved per
/// face). Liquify strokes (`settings.liquify`) need nothing extra. The
/// renderer builds the warp field itself: shape changes rebuild it in an
/// isolate (debounced 80 ms, the previous field stays on screen), liquify
/// strokes update it incrementally. Falls back to the faces given to
/// [RetouchSink.setRetouch]. Check with `renderer is WarpSink`.
abstract interface class WarpSink {
  /// Replaces the faces the shape sliders warp and re-renders.
  void setWarpFaces(FaceAnalysis? faces);
}

/// [src] with the portrait retouch of [settings] applied (CPU reference),
/// or [src] itself when there is nothing to retouch.
RgbaBuffer retouchedSource(
  RgbaBuffer src,
  DevelopSettings settings,
  RetouchMaps? maps,
  FaceAnalysis? faces,
) {
  if (maps == null || faces == null || !settings.portrait.hasFaceEdits) {
    return src;
  }
  return applyRetouch(
    src,
    maps,
    RetouchUniforms.fromSettings(settings.portrait, faces),
  );
}
