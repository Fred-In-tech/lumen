import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:lumen_core/lumen_core.dart';

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
