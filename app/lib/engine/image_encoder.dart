/// JPEG/PNG encoding of export pixels with `package:image` (pure Dart,
/// identical on every target).
///
/// Public API:
/// * `ExportFormat` (jpeg, png), `EncodeRequest`.
/// * `Future<Uint8List> encodeImage(EncodeRequest)`: runs in a background
///   isolate on io platforms (`image_encoder_io.dart`), inline on the web
///   (`image_encoder_web.dart`).
/// * `Uint8List encodeImageSync(EncodeRequest)`: the shared implementation.
/// * `ExifData? sanitizedExif(Uint8List jpeg)`: EXIF of the original
///   **minus GPS and serial numbers**, orientation reset to 1 (pixels are
///   exported upright).
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

export 'image_encoder_web.dart' if (dart.library.io) 'image_encoder_io.dart';

enum ExportFormat {
  jpeg('jpg', 'image/jpeg'),
  png('png', 'image/png');

  const ExportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

class EncodeRequest {
  const EncodeRequest({
    required this.width,
    required this.height,
    required this.rgba,
    this.format = ExportFormat.jpeg,
    this.quality = 92,
    this.exifSource,
  });

  final int width;
  final int height;

  /// Opaque RGBA8888 pixels, row-major.
  final Uint8List rgba;
  final ExportFormat format;

  /// JPEG quality 1–100 (ignored for PNG).
  final int quality;

  /// Original JPEG bytes to copy EXIF from (sanitized), or null for none.
  final Uint8List? exifSource;
}

/// EXIF tags removed besides the whole GPS directory.
const _kStrippedTags = [
  0x8825, // GPSInfo pointer
  0xA431, // BodySerialNumber
  0xA435, // LensSerialNumber
  0xC62F, // CameraSerialNumber (DNG)
];

img.ExifData? sanitizedExif(Uint8List jpeg) {
  final exif = img.decodeJpgExif(jpeg);
  if (exif == null || exif.isEmpty) return null;
  final out = img.ExifData.from(exif);
  out.imageIfd.sub.directories.remove('gps');
  for (final tag in _kStrippedTags) {
    out.imageIfd[tag] = null;
    out.exifIfd[tag] = null;
  }
  out.directories.remove('ifd1'); // stale thumbnail
  if (out.imageIfd.hasOrientation) out.imageIfd.orientation = 1;
  return out;
}

Uint8List encodeImageSync(EncodeRequest r) {
  if (r.rgba.length != r.width * r.height * 4) {
    throw ArgumentError(
      'rgba length ${r.rgba.length} != ${r.width}x${r.height}x4',
    );
  }
  final image = img.Image.fromBytes(
    width: r.width,
    height: r.height,
    bytes: r.rgba.buffer,
    bytesOffset: r.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  ).convert(numChannels: 3);
  final src = r.exifSource;
  if (src != null) {
    final exif = sanitizedExif(src);
    if (exif != null) image.exif = exif;
  }
  return switch (r.format) {
    ExportFormat.jpeg => img.encodeJpg(image, quality: r.quality.clamp(1, 100)),
    ExportFormat.png => img.encodePng(image),
  };
}
