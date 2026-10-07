import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/engine/float_source.dart';
import 'package:lumen/import/float_decoder_types.dart';
import 'package:lumen/platform/platform_info_io.dart';

final _log = Logger('FloatDecoder');

const _channel = MethodChannel('lumen/raw');

/// Float decode on macOS and iOS over the `lumen/raw` channel
/// (`floatInfo`, `floatRender`, `floatRelease`; native side:
/// `FloatDeveloper` in the Runner). The file is handed over by path (it
/// already lives in the app container); pixels come back as one float32
/// buffer, nothing is written to disk.
class PlatformFloatDecoder implements FloatDecoder {
  const PlatformFloatDecoder({this.platform});

  final PlatformInfo? platform;

  bool get _supported => (platform ?? PlatformInfo.current()).isApple;

  @override
  Future<FloatSourceInfo?> info(String path) async {
    if (!_supported) return null;
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('floatInfo', {
        'input': path,
      });
      final w = (m?['width'] as num?)?.toInt() ?? 0;
      final h = (m?['height'] as num?)?.toInt() ?? 0;
      if (w <= 0 || h <= 0) return null;
      return FloatSourceInfo(
        width: w,
        height: h,
        profile: HbdProfile(
          shoulderKnee: (m?['shoulderKnee'] as num?)?.toDouble() ?? 0,
          highlightGain: (m?['highlightGain'] as num?)?.toDouble() ?? 0,
        ),
      );
    } on PlatformException catch (e) {
      _log.info('no float decode for $path: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      // Tests and embedders without the native handler.
      return null;
    }
  }

  @override
  Future<FloatPixels> render(
    String path, {
    required int fullWidth,
    required int fullHeight,
    required int x,
    required int y,
    required int width,
    required int height,
    String? cachePath,
  }) async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('floatRender', {
        'input': path,
        'fullWidth': fullWidth,
        'fullHeight': fullHeight,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'cachePath': ?cachePath,
      });
      final pixels = m?['pixels'];
      if (pixels is! Float32List || pixels.length != width * height * 4) {
        throw const FloatSourceException('the decoder returned no pixels');
      }
      return FloatPixels(
        width,
        height,
        pixels,
        decodeMs: (m?['ms'] as num?)?.toInt(),
      );
    } on PlatformException catch (e) {
      throw FloatSourceException('${e.code}: ${e.message}');
    } on MissingPluginException {
      throw const FloatSourceException('no float decoder');
    }
  }

  @override
  Future<void> release(String path) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('floatRelease', {'input': path});
    } on PlatformException catch (e) {
      _log.fine('float release failed: ${e.message}');
    } on MissingPluginException {
      // Nothing to release.
    }
  }

  @override
  Future<CachedFloatPreview?> readPreview(
    String cachePath, {
    required int width,
    required int height,
  }) async {
    if (!_supported) return null;
    try {
      final m = await _channel.invokeMapMethod<String, Object?>(
        'floatPreviewRead',
        {'cachePath': cachePath, 'width': width, 'height': height},
      );
      return parseCachedPreview(m, width, height);
    } on PlatformException catch (e) {
      _log.info('float preview cache read failed: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<int?> buildPreview(
    String path, {
    required String cachePath,
    required int fullWidth,
    required int fullHeight,
  }) async {
    if (!_supported) return null;
    try {
      final m = await _channel.invokeMapMethod<String, Object?>(
        'floatPreviewBuild',
        {
          'input': path,
          'cachePath': cachePath,
          'fullWidth': fullWidth,
          'fullHeight': fullHeight,
        },
      );
      final ms = (m?['ms'] as num?)?.toInt();
      if (ms != null && ms > 0) _log.fine('float preview built in $ms ms');
      return (m?['bytes'] as num?)?.toInt();
    } on PlatformException catch (e) {
      _log.info('float preview build failed: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// The reply of `floatPreviewRead`, or null when it is not a complete
/// entry of [width]×[height].
@visibleForTesting
CachedFloatPreview? parseCachedPreview(
  Map<String, Object?>? m,
  int width,
  int height,
) {
  final pixels = m?['pixels'];
  if (pixels is! Float32List || pixels.length != width * height * 4) {
    return null;
  }
  final fw = (m?['fullWidth'] as num?)?.toInt() ?? 0;
  final fh = (m?['fullHeight'] as num?)?.toInt() ?? 0;
  if (fw <= 0 || fh <= 0) return null;
  return CachedFloatPreview(
    FloatPixels(width, height, pixels, decodeMs: (m?['ms'] as num?)?.toInt()),
    FloatSourceInfo(
      width: fw,
      height: fh,
      profile: HbdProfile(
        shoulderKnee: (m?['shoulderKnee'] as num?)?.toDouble() ?? 0,
        highlightGain: (m?['highlightGain'] as num?)?.toDouble() ?? 0,
      ),
    ),
  );
}
