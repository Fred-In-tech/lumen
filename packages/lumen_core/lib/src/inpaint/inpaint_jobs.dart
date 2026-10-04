/// Isolate-safe entry points: plain data in, plain data out, no closures
/// over UI state. Run them with `Isolate.run(() => runInpaintJob(job))`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/mask_shapes.dart';
import '../render/rgba_buffer.dart';
import 'crop_plan.dart';
import 'distance_transform.dart';
import 'float_image.dart';
import 'hole_mask.dart';
import 'inpaint_pipeline.dart';
import 'method_picker.dart';
import 'pixel_box.dart';
import 'push_pull.dart';

/// A classical (zero-download) removal request.
class InpaintJob {
  const InpaintJob({
    required this.source,
    required this.strokes,
    this.method,
    this.config = const InpaintConfig(),
  });

  /// Full-resolution source (or the preview, for a quick draft).
  final RgbaBuffer source;

  /// Removal strokes, normalized like mask brush strokes.
  final List<BrushStroke> strokes;

  /// Forced method; never [InpaintMethod.model] (models live in the app).
  final InpaintMethod? method;

  final InpaintConfig config;
}

/// Rasterizes [InpaintJob.strokes] and runs the classical pipeline.
Future<InpaintResult> runInpaintJob(InpaintJob job) {
  if (job.method == InpaintMethod.model) {
    throw ArgumentError(
      'runInpaintJob is classical only; use '
      'InpaintPipeline.remove with a model',
    );
  }
  final hole = rasterizeHoleMask(
    job.strokes,
    job.source.width,
    job.source.height,
  );
  return InpaintPipeline.remove(
    job.source,
    hole,
    method: job.method,
    config: job.config,
  );
}

/// Clone stamp: the hole is replaced by the source shifted by [offset]
/// (source px; pixels past the edges mirror), feathered by [featherPx].
InpaintPatch? clonePatch(
  RgbaBuffer source,
  HoleMask hole,
  (int, int) offset, {
  int featherPx = 2,
}) {
  if (hole.isEmpty) return null;
  final box = hole.bbox
      .inflate(featherPx)
      .intersect(PixelBox(0, 0, source.width, source.height));
  final alpha = _featherAlpha(hole, box, featherPx);
  final out = RgbaBuffer(box.width, box.height);
  for (var y = 0; y < box.height; y++) {
    for (var x = 0; x < box.width; x++) {
      final sx = mirrorIndex(box.x + x + offset.$1, source.width);
      final sy = mirrorIndex(box.y + y + offset.$2, source.height);
      final a = alpha[y * box.width + x];
      final s = a == 0
          ? source.offset(box.x + x, box.y + y)
          : source.offset(sx, sy);
      final o = (y * box.width + x) * 4;
      out.data.setRange(o, o + 3, source.data, s);
      out.data[o + 3] = a;
    }
  }
  return InpaintPatch(box, out);
}

/// Healing brush: membrane low band from the hole's surroundings + the
/// fine band of the area at [offset] (source px; null = best ring donor),
/// so texture is copied but colour and light match (§3.3).
InpaintPatch? healPatch(
  RgbaBuffer source,
  HoleMask hole, {
  (int, int)? offset,
  int featherPx = 2,
}) {
  if (hole.isEmpty) return null;
  final reach = offset == null
      ? 3 * (hole.bbox.maxSide + 8) + 8
      : math.max(offset.$1.abs(), offset.$2.abs()) + 8;
  final win = hole.bbox
      .inflate(reach + featherPx)
      .intersect(PixelBox(0, 0, source.width, source.height));
  // Convert only the window (a 24 MP source as floats would be ~290 MB).
  final img = FloatImage.fromRgba(extractCrop(source, win));
  final m = Uint8List(win.area);
  for (var y = 0; y < win.height; y++) {
    for (var x = 0; x < win.width; x++) {
      if (hole.isHole(win.x + x, win.y + y)) m[y * win.width + x] = 255;
    }
  }
  final filled = frequencySeparatedFill(img, m, donorOffset: offset);
  final box = hole.bbox
      .inflate(featherPx)
      .intersect(PixelBox(0, 0, source.width, source.height));
  final alpha = _featherAlpha(hole, box, featherPx);
  final out = RgbaBuffer(box.width, box.height);
  for (var y = 0; y < box.height; y++) {
    for (var x = 0; x < box.width; x++) {
      final o = (y * box.width + x) * 4;
      final a = alpha[y * box.width + x];
      for (var c = 0; c < 3; c++) {
        out.data[o + c] = filled
            .at(box.x + x - win.x, box.y + y - win.y, c)
            .round()
            .clamp(0, 255);
      }
      out.data[o + 3] = a;
    }
  }
  return InpaintPatch(box, out);
}

/// 255 in the hole, smoothstep down to 0 at [feather] px outside it.
Uint8List _featherAlpha(HoleMask hole, PixelBox box, int feather) {
  final seeds = Uint8List(box.area);
  for (var y = 0; y < box.height; y++) {
    for (var x = 0; x < box.width; x++) {
      if (hole.isHole(box.x + x, box.y + y)) seeds[y * box.width + x] = 1;
    }
  }
  final d2 = squaredDistanceTransform(seeds, box.width, box.height);
  final f = math.max(1, feather);
  return Uint8List.fromList([
    for (final v in d2)
      () {
        final t = (math.sqrt(v) / f).clamp(0.0, 1.0);
        return (255 * (1 - t * t * (3 - 2 * t))).round();
      }(),
  ]);
}
