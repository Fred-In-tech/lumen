/// Object removal pipeline (§5.2): dilate → context crops → optional
/// downscale → engine → upsample only the generated region → detail
/// restoration → feathered RGBA patch.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../render/rgba_buffer.dart';
import 'crop_plan.dart';
import 'distance_transform.dart';
import 'float_image.dart';
import 'hole_mask.dart';
import 'inpaint_model.dart';
import 'method_picker.dart';
import 'patch_match.dart';
import 'patch_match_core.dart';
import 'pixel_box.dart';
import 'push_pull.dart';

/// Plain, sendable pipeline settings.
class InpaintConfig {
  const InpaintConfig({
    this.crop = const CropPolicy(),
    this.modelSide = 512,
    this.featherFraction = 0.015,
    this.lightDilationPx = 2,
    this.seed = 1,
    this.detailRestoration = true,
    this.detailMinScale = 1.5,
    this.picker = const PickerThresholds(),
  });

  final CropPolicy crop;

  /// Input side of AI models (MI-GAN: 512).
  final int modelSide;

  /// Feather width as a fraction of the crop side (1.5 %).
  final double featherFraction;

  /// Dilation for Telea / push-pull (thin and small holes); model and
  /// PatchMatch fills use [holeDilationPx] (§5.2.1).
  final int lightDilationPx;

  /// PatchMatch seed (same seed + input → identical patch bytes).
  final int seed;

  /// Synthesize the fine band of upsampled fills from the ring (§5.2.4)
  /// when the upscale factor is at least [detailMinScale].
  final bool detailRestoration;
  final double detailMinScale;

  final PickerThresholds picker;
}

/// A fill result in source pixels: [rgba] covers [bbox] with straight
/// alpha = the feathered hole (0 = leave the source untouched).
class InpaintPatch {
  const InpaintPatch(this.bbox, this.rgba);

  final PixelBox bbox;
  final RgbaBuffer rgba;
}

class InpaintResult {
  const InpaintResult({
    required this.patches,
    required this.method,
    required this.engineId,
    required this.ai,
    required this.stats,
    required this.holeBbox,
  });

  /// One patch per context crop; their alpha regions are disjoint.
  final List<InpaintPatch> patches;
  final InpaintMethod method;
  final String engineId;

  /// True when an AI model generated the fill (C2PA / disclosure).
  final bool ai;

  /// Shape of the undilated mask.
  final HoleStats stats;

  /// Bbox of the dilated hole (source px).
  final PixelBox holeBbox;

  /// Union of the patch boxes.
  PixelBox get bbox => patches.fold(PixelBox.zero, (a, p) => a.union(p.bbox));
}

abstract final class InpaintPipeline {
  /// Removes [hole] (undilated, source px) from [source]. [method] forces
  /// an engine; otherwise [InpaintMethodPicker] chooses, using [model] when
  /// given. Throws [InpaintCancelled] once [shouldCancel] returns true and
  /// [StateError] when a model returns a buffer of the wrong size.
  static Future<InpaintResult> remove(
    RgbaBuffer source,
    HoleMask hole, {
    InpaintModel? model,
    InpaintMethod? method,
    InpaintConfig config = const InpaintConfig(),
    CancelCheck? shouldCancel,
  }) async {
    if (hole.srcWidth != source.width || hole.srcHeight != source.height) {
      throw ArgumentError('hole mask is not sized for the source');
    }
    final stats = HoleStats.measure(hole);
    final m =
        method ??
        InpaintMethodPicker.pick(
          stats,
          modelAvailable: model != null,
          t: config.picker,
        );
    final engine = _engine(m, model, config, shouldCancel);
    final heavy = m == InpaintMethod.model || m == InpaintMethod.patchMatch;
    final dilated = hole.dilated(
      heavy
          ? holeDilationPx(source.width, source.height)
          : config.lightDilationPx,
    );
    final patches = <InpaintPatch>[];
    final jobs = planCrops(
      [for (final c in dilated.components()) c.bbox],
      source.width,
      source.height,
      policy: config.crop,
    );
    for (final job in jobs) {
      if (shouldCancel?.call() ?? false) throw const InpaintCancelled();
      final p = await _fillCrop(
        source,
        dilated,
        job.crop,
        engine,
        config,
        shouldCancel,
      );
      if (p != null) patches.add(p);
    }
    return InpaintResult(
      patches: List.unmodifiable(patches),
      method: m,
      engineId: engine.id,
      ai: engine is! ClassicalInpaintModel,
      stats: stats,
      holeBbox: dilated.bbox,
    );
  }
}

InpaintModel _engine(
  InpaintMethod m,
  InpaintModel? model,
  InpaintConfig config,
  CancelCheck? shouldCancel,
) => switch (m) {
  InpaintMethod.telea => const TeleaInpaintModel(),
  InpaintMethod.pushPull => const PushPullInpaintModel(),
  InpaintMethod.patchMatch => PatchMatchInpaintModel(
    params: PatchMatchParams(seed: config.seed),
    shouldCancel: shouldCancel,
  ),
  InpaintMethod.model =>
    model ?? (throw ArgumentError('InpaintMethod.model needs a model')),
};

/// Side the engine works at, or null to run on the full-size crop.
int? _workingSide(InpaintModel engine, int side, InpaintConfig config) {
  if (engine is ClassicalInpaintModel) {
    final max = engine.maxSide;
    return max == null || side <= max ? null : max;
  }
  return side == config.modelSide ? null : config.modelSide;
}

Future<InpaintPatch?> _fillCrop(
  RgbaBuffer source,
  HoleMask dilated,
  PixelBox crop,
  InpaintModel engine,
  InpaintConfig config,
  CancelCheck? shouldCancel,
) async {
  final side = crop.width;
  final rgba = extractCrop(source, crop);
  final keep = dilated.keepMaskFor(crop);
  final hole = Uint8List(keep.length);
  for (var i = 0; i < hole.length; i++) {
    if (keep[i] == 0) hole[i] = 255;
  }
  final holeBox = maskBounds(hole, side, side);
  if (holeBox == null) return null;
  final cropBounds = PixelBox(0, 0, side, side);
  final feather = math.max(1, (config.featherFraction * side).round());
  final region = holeBox.inflate(feather + 1).intersect(cropBounds);
  final orig = FloatImage.fromRgba(rgba);
  final work = _workingSide(engine, side, config);
  if (work == null) {
    final out = await engine.inpaint(rgba, keep);
    _checkSize(engine, out, side);
    final gen = FloatImage.fromRgba(out)
        .window(region.x, region.y, region.width, region.height);
    return _toPatch(source, crop, hole, region, gen, region, feather);
  }
  final small = resizeArea(orig, work, work).toRgba();
  final out = await engine.inpaint(small, _shrinkKeep(keep, side, work));
  _checkSize(engine, out, work);
  final ctx = math.max(feather + 2, math.max(16, holeBox.maxSide ~/ 2));
  final win = holeBox.inflate(ctx).intersect(cropBounds);
  final gen = _restore(
    orig.window(win.x, win.y, win.width, win.height),
    _subMask(hole, side, win),
    _upsampleWindow(FloatImage.fromRgba(out), side, win),
    side / work,
    config,
    shouldCancel,
  );
  return _toPatch(source, crop, hole, region, gen, win, feather);
}

void _checkSize(InpaintModel engine, RgbaBuffer out, int side) {
  if (out.width != side || out.height != side) {
    throw StateError(
      '${engine.id} returned ${out.width}x${out.height}, '
      'expected ${side}x$side',
    );
  }
}

/// Keep mask at [work]² : a pixel is a hole if any covered pixel is.
Uint8List _shrinkKeep(Uint8List keep, int side, int work) {
  final out = Uint8List(work * work)..fillRange(0, work * work, 255);
  for (var y = 0; y < side; y++) {
    final sy = y * work ~/ side;
    for (var x = 0; x < side; x++) {
      if (keep[y * side + x] == 0) out[sy * work + x * work ~/ side] = 0;
    }
  }
  return out;
}

Uint8List _subMask(Uint8List m, int stride, PixelBox b) {
  final out = Uint8List(b.area);
  for (var y = 0; y < b.height; y++) {
    final s = (b.y + y) * stride + b.x;
    out.setRange(y * b.width, (y + 1) * b.width, m, s);
  }
  return out;
}

/// Bilinear upsample of [small] to `side × side`, evaluated only on [win].
FloatImage _upsampleWindow(FloatImage small, int side, PixelBox win) {
  final s = small.width / side, ch = small.channels;
  final out = FloatImage(win.width, win.height, channels: ch);
  for (var y = 0; y < win.height; y++) {
    final v = (win.y + y + 0.5) * s - 0.5;
    final y0 = v.floor(), fy = v - y0;
    final ya = y0.clamp(0, small.height - 1);
    final yb = (y0 + 1).clamp(0, small.height - 1);
    for (var x = 0; x < win.width; x++) {
      final u = (win.x + x + 0.5) * s - 0.5;
      final x0 = u.floor(), fx = u - x0;
      final xa = x0.clamp(0, small.width - 1);
      final xb = (x0 + 1).clamp(0, small.width - 1);
      for (var c = 0; c < ch; c++) {
        final top = small.at(xa, ya, c) * (1 - fx) + small.at(xb, ya, c) * fx;
        final bot = small.at(xa, yb, c) * (1 - fx) + small.at(xb, yb, c) * fx;
        out.set(x, y, c, top + (bot - top) * fy);
      }
    }
  }
  return out;
}

/// Hole: guide low band + fine band synthesized from the ring. Outside
/// the hole (the feather band): the original with the guide's low-band
/// offset, so the seam blends in colour without blurring real detail.
FloatImage _restore(
  FloatImage orig,
  Uint8List hole,
  FloatImage guide,
  double scale,
  InpaintConfig config,
  CancelCheck? shouldCancel,
) {
  final sigma = math.max(1.0, 0.6 * scale);
  final filled = config.detailRestoration && scale >= config.detailMinScale
      ? patchMatchDetail(
          orig,
          hole,
          guide,
          sigma: sigma,
          params: PatchMatchParams.detail(seed: config.seed),
          shouldCancel: shouldCancel,
        )
      : guide;
  final known = Float32List(orig.pixelCount);
  for (var i = 0; i < known.length; i++) {
    known[i] = hole[i] == 0 ? 1 : 0;
  }
  final lowG = gaussianBlur(guide, sigma);
  final lowO = gaussianBlur(orig, sigma, weights: known);
  final out = orig.copy();
  final ch = orig.channels;
  for (var i = 0; i < hole.length; i++) {
    for (var c = 0; c < ch; c++) {
      final k = i * ch + c;
      out.data[k] = hole[i] != 0
          ? filled.data[k]
          : orig.data[k] + lowG.data[k] - lowO.data[k];
    }
  }
  return out;
}

/// Feathered RGBA patch: alpha 1 in the hole, smoothstep to 0 over
/// [feather] px outside it; clipped to the source.
InpaintPatch? _toPatch(
  RgbaBuffer source,
  PixelBox crop,
  Uint8List hole,
  PixelBox region,
  FloatImage gen,
  PixelBox genBox,
  int feather,
) {
  final side = crop.width;
  final seeds = _subMask(hole, side, region);
  final d2 = squaredDistanceTransform(seeds, region.width, region.height);
  final alpha = Uint8List(region.area);
  for (var i = 0; i < alpha.length; i++) {
    final t = (math.sqrt(d2[i]) / feather).clamp(0.0, 1.0);
    alpha[i] = (255 * (1 - t * t * (3 - 2 * t))).round();
  }
  // Tight box of alpha > 0 inside the source.
  final inSrc = region
      .translate(crop.x, crop.y)
      .intersect(PixelBox(0, 0, source.width, source.height))
      .translate(-crop.x, -crop.y);
  var x0 = 1 << 30, y0 = 1 << 30, x1 = -1, y1 = -1;
  for (var y = inSrc.y; y < inSrc.bottom; y++) {
    for (var x = inSrc.x; x < inSrc.right; x++) {
      if (alpha[(y - region.y) * region.width + x - region.x] == 0) continue;
      x0 = math.min(x0, x);
      x1 = math.max(x1, x);
      y0 = math.min(y0, y);
      y1 = math.max(y1, y);
    }
  }
  if (x1 < 0) return null;
  final box = PixelBox.fromLTRB(x0, y0, x1 + 1, y1 + 1);
  final out = RgbaBuffer(box.width, box.height);
  for (var y = 0; y < box.height; y++) {
    for (var x = 0; x < box.width; x++) {
      final cx = box.x + x, cy = box.y + y;
      final a = alpha[(cy - region.y) * region.width + cx - region.x];
      final o = (y * box.width + x) * 4;
      if (a == 0) {
        final s = source.offset(crop.x + cx, crop.y + cy);
        out.data.setRange(o, o + 3, source.data, s);
        continue;
      }
      for (var c = 0; c < 3; c++) {
        out.data[o + c] = gen
            .at(cx - genBox.x, cy - genBox.y, c)
            .round()
            .clamp(0, 255);
      }
      out.data[o + 3] = a;
    }
  }
  return InpaintPatch(box.translate(crop.x, crop.y), out);
}
