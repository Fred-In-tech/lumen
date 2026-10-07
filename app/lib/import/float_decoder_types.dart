import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/engine/float_source.dart';

/// What the platform decoder reports about a file it can render in float.
class FloatSourceInfo {
  const FloatSourceInfo({
    required this.width,
    required this.height,
    required this.profile,
  });

  /// Full upright size.
  final int width;
  final int height;
  final HbdProfile profile;
}

/// Decodes files into float pixels through the OS (Apple ImageIO /
/// CoreImage on macOS and iOS; nothing elsewhere yet). Swapped for a fake
/// in tests.
abstract interface class FloatDecoder {
  /// Null when this platform or this file has no float decode.
  Future<FloatSourceInfo?> info(String path);

  /// The window of the photo at [path] scaled to [fullWidth]×[fullHeight].
  /// With [cachePath], a whole-photo render is also written to the float
  /// preview cache there (after the reply, off the caller's way).
  /// Throws [FloatSourceException].
  Future<FloatPixels> render(
    String path, {
    required int fullWidth,
    required int fullHeight,
    required int x,
    required int y,
    required int width,
    required int height,
    String? cachePath,
  });

  /// Drops the native decoder cache of [path].
  Future<void> release(String path);

  /// The cached preview at [cachePath] when it is a valid entry of exactly
  /// [width]×[height] (written by this decoder on this OS build), else
  /// null. Never decodes the original; never throws.
  Future<CachedFloatPreview?> readPreview(
    String cachePath, {
    required int width,
    required int height,
  });

  /// Decodes [path] at [fullWidth]×[fullHeight] and writes the cache entry
  /// at [cachePath] without sending pixels back, at background priority
  /// (one at a time). Returns the entry's size in bytes, null when it
  /// failed. An existing valid entry is kept.
  Future<int?> buildPreview(
    String path, {
    required String cachePath,
    required int fullWidth,
    required int fullHeight,
  });
}

/// A float preview read back from the preview cache.
class CachedFloatPreview {
  const CachedFloatPreview(this.pixels, this.info);

  final FloatPixels pixels;

  /// What the decoder reported when the entry was written.
  final FloatSourceInfo info;
}

/// A [FloatSource] over one file and a [FloatDecoder].
class DecodedFloatSource implements FloatSource {
  DecodedFloatSource(this._decoder, this.path, this._info);

  final FloatDecoder _decoder;
  final String path;
  final FloatSourceInfo _info;

  @override
  int get width => _info.width;

  @override
  int get height => _info.height;

  @override
  HbdProfile get profile => _info.profile;

  @override
  Future<FloatPixels> render({
    required int fullWidth,
    required int fullHeight,
    int x = 0,
    int y = 0,
    int? width,
    int? height,
  }) => _decoder.render(
    path,
    fullWidth: fullWidth,
    fullHeight: fullHeight,
    x: x,
    y: y,
    width: width ?? fullWidth - x,
    height: height ?? fullHeight - y,
  );

  /// Like [render] for the whole photo, also writing the preview cache
  /// entry at [cachePath].
  Future<FloatPixels> renderCaching({
    required int fullWidth,
    required int fullHeight,
    required String cachePath,
  }) => _decoder.render(
    path,
    fullWidth: fullWidth,
    fullHeight: fullHeight,
    x: 0,
    y: 0,
    width: fullWidth,
    height: fullHeight,
    cachePath: cachePath,
  );

  @override
  Future<void> release() => _decoder.release(path);
}
