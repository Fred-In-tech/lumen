import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/face_cache.dart';

/// Folder under `assets/<id>/cache/` holding AI mask rasters.
const kMaskCacheDir = 'masks';

final _maskRef = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$');

/// Rejects refs that could escape the masks folder.
String checkMaskRef(String maskRef) {
  if (!_maskRef.hasMatch(maskRef) || maskRef.contains('..')) {
    throw ArgumentError.value(maskRef, 'maskRef', 'not a valid mask ref');
  }
  return maskRef;
}

/// 8-bit grayscale PNG of [r] (lossless, deterministic).
Uint8List encodeMaskPng(MaskRaster r) => img.encodePng(
  img.Image.fromBytes(
    width: r.width,
    height: r.height,
    bytes: Uint8List.fromList(r.data).buffer,
    numChannels: 1,
  ),
);

/// Decodes a mask PNG (any channel layout; the first channel is coverage).
/// Null when the bytes are not a PNG.
MaskRaster? decodeMaskPng(Uint8List bytes) {
  final image = img.decodePng(bytes);
  if (image == null) return null;
  final w = image.width, h = image.height;
  final out = Uint8List(w * h);
  if (image.numChannels == 1 && image.format == img.Format.uint8) {
    final data = image.toUint8List();
    for (var y = 0; y < h; y++) {
      out.setRange(y * w, y * w + w, data, y * image.rowStride);
    }
  } else {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        out[y * w + x] = image.getPixel(x, y).r.toInt().clamp(0, 255);
      }
    }
  }
  return MaskRaster(w, h, out);
}

/// Local, regenerable AI mask rasters: `assets/<id>/cache/masks/<ref>.png`
/// (excluded from export, sync and backup like the rest of `cache/`).
abstract interface class AiRasterStore {
  Future<MaskRaster?> read(String assetId, String maskRef);
  Future<void> write(String assetId, String maskRef, MaskRaster raster);
  Future<bool> exists(String assetId, String maskRef);
}

/// Web and tests (stores the PNG bytes, so the codec runs too).
class MemoryAiRasterStore implements AiRasterStore {
  final Map<String, Uint8List> files = {};

  String _key(String assetId, String maskRef) =>
      '${checkAssetId(assetId)}/$kAssetCacheDir/$kMaskCacheDir/'
      '${checkMaskRef(maskRef)}.png';

  @override
  Future<MaskRaster?> read(String assetId, String maskRef) async {
    final bytes = files[_key(assetId, maskRef)];
    return bytes == null ? null : decodeMaskPng(bytes);
  }

  @override
  Future<void> write(String assetId, String maskRef, MaskRaster raster) async =>
      files[_key(assetId, maskRef)] = encodeMaskPng(raster);

  @override
  Future<bool> exists(String assetId, String maskRef) async =>
      files.containsKey(_key(assetId, maskRef));
}
