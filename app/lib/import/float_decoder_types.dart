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
  /// Throws [FloatSourceException].
  Future<FloatPixels> render(
    String path, {
    required int fullWidth,
    required int fullHeight,
    required int x,
    required int y,
    required int width,
    required int height,
  });

  /// Drops the native decoder cache of [path].
  Future<void> release(String path);
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

  @override
  Future<void> release() => _decoder.release(path);
}
