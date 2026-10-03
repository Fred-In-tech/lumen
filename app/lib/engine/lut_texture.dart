/// The baked tone LUT as a GPU texture (1024×4, 16-bit packed in R/G).
///
/// Public API:
/// * `LutTexture.upload(ToneLut)` → `Future<LutTexture>`.
/// * `image` (sample with `FilterQuality.none`), `key` (=`ToneLut.key`),
///   `dispose()`.
library;

import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';

class LutTexture {
  LutTexture._(this.image, this.key, this.curvesActive);

  static Future<LutTexture> upload(ToneLut lut) async {
    final image = await uploadRgba(lut.toRgba(), kToneLutSize, kToneLutRows);
    return LutTexture._(image, lut.key, lut.curvesActive);
  }

  final ui.Image image;
  final int key;
  final bool curvesActive;

  void dispose() => EngineImages.dispose(image);
}
