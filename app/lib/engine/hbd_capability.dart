/// Start-up probe of the float editing path (docs/HIGH_BIT_DEPTH.md).
///
/// The float path needs four things from the renderer, none of which the
/// engine guarantees on every device (research 08 §7): a float32 upload
/// that keeps its values, a FragmentProgram pass into a float32 render
/// target, bilinear filtering of float32 textures, and float readback.
/// Headless Skia, some mobile GPUs and GLES without float extensions fail
/// one of them; photos then keep the 8-bit path.
///
/// Public API:
/// * `HbdCapability.probe(shaders)` → cached `Future<bool>`: one tiny round
///   trip per process. Never throws.
/// * `HbdCapability.available()`: the same, loading the shaders itself
///   (false when they cannot load).
/// * `HbdCapability.override`: force the answer (tests, a user setting).
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';
import 'shader_library.dart';

final _log = Logger('HbdCapability');

abstract final class HbdCapability {
  static Future<bool>? _probe;

  /// When set, [probe] returns it without touching the GPU.
  static bool? override;

  /// Encoded test values: a highlight above white, a level between two
  /// 8-bit steps, black, and a second highlight.
  static const _strip = [4.0, 0.5 + 1 / 4096, 0.0, 2.0];
  static const double _tolerance = 1e-4;

  static Future<bool> probe(ShaderLibrary shaders) {
    final forced = override;
    if (forced != null) return Future.value(forced);
    return _probe ??= _run(shaders);
  }

  static Future<bool> available() async {
    final forced = override;
    if (forced != null) return forced;
    try {
      return await probe(await ShaderLibrary.load());
    } on ShaderLoadException {
      return false;
    }
  }

  /// Forgets the cached result (tests).
  static void reset() {
    _probe = null;
    override = null;
  }

  static Future<bool> _run(ShaderLibrary shaders) async {
    final owned = <ui.Image>[];
    try {
      final px = Float32List(_strip.length * 4);
      for (var i = 0; i < _strip.length; i++) {
        px
          ..[i * 4] = _strip[i]
          ..[i * 4 + 1] = _strip[i]
          ..[i * 4 + 2] = _strip[i]
          ..[i * 4 + 3] = 1;
      }
      final uploaded = await uploadFloat(px, _strip.length, 1);
      owned.add(uploaded);
      if (!_matches(await readFloat(uploaded), 'upload')) return false;
      // Two shader passes into float targets (identity denoise): values
      // above white and sub-8-bit levels must survive the chain.
      var image = uploaded;
      for (var pass = 0; pass < 2; pass++) {
        image = runDenoise(
          shaders,
          floats: DenoiseUniforms.pack(
            DevelopSettings.defaults,
            _strip.length,
            1,
          ),
          image: image,
          float: true,
        );
        owned.add(image);
      }
      if (!_matches(await readFloat(image), 'float pass')) return false;
      // Bilinear filtering of a float32 texture (develop samples its
      // source with FilterQuality.low): 0 | 2 stretched over 8 pixels.
      final pair = await uploadFloat(
        Float32List.fromList([0, 0, 0, 1, 2, 2, 2, 1]),
        2,
        1,
      );
      owned.add(pair);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        pair,
        const ui.Rect.fromLTWH(0, 0, 2, 1),
        const ui.Rect.fromLTWH(0, 0, 8, 1),
        ui.Paint()
          ..blendMode = ui.BlendMode.src
          ..filterQuality = ui.FilterQuality.low,
      );
      final picture = recorder.endRecording();
      final stretched = EngineImages.track(
        picture.toImageSync(8, 1, targetFormat: kFloatTarget),
      );
      picture.dispose();
      owned.add(stretched);
      final s = await readFloat(stretched);
      final ok =
          (s[3 * 4] - 0.75).abs() < 0.05 &&
          (s[4 * 4] - 1.25).abs() < 0.05 &&
          (s[7 * 4] - 2).abs() < 0.05;
      if (!ok) _log.info('float path off: float32 textures are not filtered');
      return ok;
    } on Object catch (e) {
      // Any failure (unsupported format, readback error) means 8-bit.
      _log.info('float path off: probe failed ($e)');
      return false;
    } finally {
      owned.forEach(EngineImages.dispose);
    }
  }

  static bool _matches(Float32List got, String step) {
    for (var i = 0; i < _strip.length; i++) {
      if ((got[i * 4] - _strip[i]).abs() > _tolerance) {
        _log.info(
          'float path off: $step gave ${got[i * 4]} for ${_strip[i]} '
          '(8-bit or clamped storage)',
        );
        return false;
      }
    }
    return true;
  }
}
