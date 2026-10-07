import 'dart:io';
import 'dart:typed_data';

import 'package:lumen/engine/float_source.dart';
import 'package:lumen/import/float_decoder_types.dart';
import 'package:lumen/import/float_preview_cache_types.dart';
import 'package:lumen_core/lumen_core.dart';

/// The 64-byte header the native side writes (`FloatPreviewFile`).
Uint8List floatPreviewHeader({
  required int width,
  required int height,
  int fullWidth = 600,
  int fullHeight = 400,
  double knee = 0.86,
  double gain = 0.5,
  int version = kFloatPreviewCacheVersion,
  int magic = 0x3150464C,
}) {
  final b = ByteData(kFloatPreviewHeaderBytes)
    ..setUint32(0, magic, Endian.little)
    ..setUint32(4, version, Endian.little)
    ..setUint32(8, width, Endian.little)
    ..setUint32(12, height, Endian.little)
    ..setUint32(16, fullWidth, Endian.little)
    ..setUint32(20, fullHeight, Endian.little)
    ..setFloat64(24, knee, Endian.little)
    ..setFloat64(32, gain, Endian.little);
  return b.buffer.asUint8List();
}

/// A float decoder standing in for the native one: renders a flat colour,
/// and writes / reads cache files (header + raw float32 payload) the way
/// `floatRender` with a cache path, `floatPreviewBuild` and
/// `floatPreviewRead` do.
class FakeCachingDecoder implements FloatDecoder {
  FakeCachingDecoder({this.full = const (width: 600, height: 400)});

  final ({int width, int height}) full;
  final List<String> infos = [], released = [], renders = [], builds = [];
  final List<String> reads = [];
  bool failRender = false;

  /// Builds wait for this when set (tests of overlapping work).
  Future<void>? buildGate;

  Float32List _pixels(int w, int h, double v) =>
      Float32List(w * h * 4)..fillRange(0, w * h * 4, v);

  void _write(String cachePath, int w, int h, Float32List rgba) {
    final f = File(cachePath)..parent.createSync(recursive: true);
    f.writeAsBytesSync([
      ...floatPreviewHeader(
        width: w,
        height: h,
        fullWidth: full.width,
        fullHeight: full.height,
      ),
      ...rgba.buffer.asUint8List(),
    ]);
  }

  @override
  Future<FloatSourceInfo?> info(String path) async {
    infos.add(path);
    return FloatSourceInfo(
      width: full.width,
      height: full.height,
      profile: HbdProfile.rawExtended,
    );
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
    if (failRender) throw const FloatSourceException('decode failed');
    renders.add(path);
    final px = _pixels(width, height, 1.5);
    if (cachePath != null) _write(cachePath, width, height, px);
    return FloatPixels(width, height, px);
  }

  @override
  Future<void> release(String path) async => released.add(path);

  @override
  Future<CachedFloatPreview?> readPreview(
    String cachePath, {
    required int width,
    required int height,
  }) async {
    reads.add(cachePath);
    final f = File(cachePath);
    if (!f.existsSync()) return null;
    final bytes = f.readAsBytesSync();
    final info = parseFloatPreviewHeader(
      Uint8List.sublistView(bytes, 0, kFloatPreviewHeaderBytes),
    );
    final payload = bytes.length - kFloatPreviewHeaderBytes;
    if (info == null || payload != width * height * 16) return null;
    final rgba = Float32List.fromList(
      Uint8List.fromList(bytes.sublist(kFloatPreviewHeaderBytes)).buffer
          .asFloat32List(),
    );
    return CachedFloatPreview(FloatPixels(width, height, rgba), info);
  }

  @override
  Future<int?> buildPreview(
    String path, {
    required String cachePath,
    required int fullWidth,
    required int fullHeight,
  }) async {
    builds.add(path);
    await buildGate;
    if (failRender) return null;
    _write(
      cachePath,
      fullWidth,
      fullHeight,
      _pixels(fullWidth, fullHeight, 1.5),
    );
    return File(cachePath).lengthSync();
  }
}
