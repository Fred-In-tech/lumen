import 'package:lumen/engine/float_source.dart';
import 'package:lumen/import/float_decoder_types.dart';

/// Web: no float decoder.
class PlatformFloatDecoder implements FloatDecoder {
  const PlatformFloatDecoder();

  @override
  Future<FloatSourceInfo?> info(String path) async => null;

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
  }) => throw const FloatSourceException('no float decoder on the web');

  @override
  Future<void> release(String path) async {}

  @override
  Future<CachedFloatPreview?> readPreview(
    String cachePath, {
    required int width,
    required int height,
  }) async => null;

  @override
  Future<int?> buildPreview(
    String path, {
    required String cachePath,
    required int fullWidth,
    required int fullHeight,
  }) async => null;
}
