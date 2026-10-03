import 'package:lumen/platform/background.dart';

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:lumen_core/lumen_core.dart';

enum ExportFormat { jpeg, png }

/// Pure-Dart encoder (identical on all platforms), run in an isolate.
///
/// When [sourceJpeg] is given and [keepMetadata] is true, its EXIF is copied
/// with GPS, serial numbers and orientation removed (pixels are already upright).
Future<Uint8List> encodeExport(
  RgbaBuffer pixels, {
  required ExportFormat format,
  int quality = 90,
  Uint8List? sourceJpeg,
  bool keepMetadata = true,
}) => runInBackground(() {
  final image = img.Image.fromBytes(
    width: pixels.width,
    height: pixels.height,
    bytes: pixels.data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final rgb = image.convert(numChannels: 3);
  if (keepMetadata && sourceJpeg != null) {
    final exif = img.decodeJpgExif(sourceJpeg);
    if (exif != null) {
      exif.gpsIfd.data.clear();
      exif.gpsIfd.sub.clear();
      exif.imageIfd.data.remove(0x0112);
      for (final tag in const [0xA431, 0xA435, 0xC62F, 0x9286]) {
        exif.exifIfd.data.remove(tag);
      }
      exif.thumbnailIfd.data.clear();
      rgb.exif = exif;
    }
  }
  return switch (format) {
    ExportFormat.jpeg => Uint8List.fromList(
      img.encodeJpg(rgb, quality: quality.clamp(1, 100)),
    ),
    ExportFormat.png => Uint8List.fromList(img.encodePng(rgb)),
  };
});

/// Output size for [srcW]×[srcH] limited to [longEdge] (null = original).
({int width, int height}) exportSize(int srcW, int srcH, int? longEdge) {
  final le = srcW > srcH ? srcW : srcH;
  if (longEdge == null || longEdge >= le) return (width: srcW, height: srcH);
  final s = longEdge / le;
  return (
    width: (srcW * s).round().clamp(1, longEdge),
    height: (srcH * s).round().clamp(1, longEdge),
  );
}

/// `IMG_2041.HEIC` → `IMG_2041_edit.jpg`
String exportFileName(String original, ExportFormat format) {
  final dot = original.lastIndexOf('.');
  final base = dot > 0 ? original.substring(0, dot) : original;
  return '${base}_edit.${format == ExportFormat.jpeg ? 'jpg' : 'png'}';
}
