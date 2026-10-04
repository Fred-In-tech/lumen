/// The fill-engine contract and the zero-download classical engines.
library;

import 'dart:typed_data';

import '../render/rgba_buffer.dart';
import 'float_image.dart';
import 'patch_match.dart';
import 'patch_match_core.dart';
import 'push_pull.dart';
import 'telea.dart';

/// A hole-filling engine. MI-GAN semantics: [inpaint] gets a square crop
/// (512×512 for AI models) and a keep mask of `crop.width × crop.height`
/// bytes where non-zero (1 or 255) = keep and 0 = fill. It returns a
/// buffer of the same size; only the filled region is used (the pipeline
/// composites it back with a feather).
abstract interface class InpaintModel {
  /// Engine id stored in the heal op, e.g. `migan@fp16-1`.
  String get id;

  Future<RgbaBuffer> inpaint(RgbaBuffer crop, Uint8List keepMask);
}

/// Classical engines (always available, deterministic, pure Dart). They
/// run at any crop size up to [maxSide] (null = any): larger crops are
/// downscaled, filled, upsampled and detail-restored by the pipeline.
abstract class ClassicalInpaintModel implements InpaintModel {
  const ClassicalInpaintModel();

  int? get maxSide => null;

  /// Fills `hole[i] != 0` of [img]; known pixels must stay unchanged.
  FloatImage fillImage(FloatImage img, Uint8List hole);

  /// Synchronous [inpaint] (for isolates and tests).
  RgbaBuffer fill(RgbaBuffer crop, Uint8List keepMask) {
    if (keepMask.length != crop.pixelCount) {
      throw ArgumentError('keep mask ${keepMask.length} != crop pixels');
    }
    final hole = Uint8List(keepMask.length);
    for (var i = 0; i < hole.length; i++) {
      if (keepMask[i] == 0) hole[i] = 255;
    }
    return fillImage(FloatImage.fromRgba(crop), hole).toRgba();
  }

  @override
  Future<RgbaBuffer> inpaint(RgbaBuffer crop, Uint8List keepMask) async =>
      fill(crop, keepMask);
}

/// Telea fast marching (thin scratches, wires, dust).
class TeleaInpaintModel extends ClassicalInpaintModel {
  const TeleaInpaintModel({this.radius = 5});

  static const engineId = 'telea@1';

  final int radius;

  @override
  String get id => engineId;

  @override
  FloatImage fillImage(FloatImage img, Uint8List hole) =>
      teleaInpaint(img, hole, radius: radius);
}

/// Frequency-separated push-pull: membrane low band + grain from the ring
/// (small spots).
class PushPullInpaintModel extends ClassicalInpaintModel {
  const PushPullInpaintModel({this.sigma = 1.5});

  static const engineId = 'pushpull@1';

  final double sigma;

  @override
  String get id => engineId;

  @override
  FloatImage fillImage(FloatImage img, Uint8List hole) =>
      frequencySeparatedFill(img, hole, sigma: sigma);
}

/// Multi-scale PatchMatch (medium holes on texture). Crops above
/// [maxSide] are filled at that size and detail-restored at full size.
class PatchMatchInpaintModel extends ClassicalInpaintModel {
  const PatchMatchInpaintModel({
    this.params = const PatchMatchParams(),
    this.maxSide = 1024,
    this.shouldCancel,
  });

  static const engineId = 'patchmatch@1';

  final PatchMatchParams params;

  @override
  final int? maxSide;

  final CancelCheck? shouldCancel;

  @override
  String get id => engineId;

  @override
  FloatImage fillImage(FloatImage img, Uint8List hole) =>
      patchMatchFill(img, hole, params: params, shouldCancel: shouldCancel);
}
