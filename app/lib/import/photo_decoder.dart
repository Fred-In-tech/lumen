import 'dart:typed_data';
import 'dart:ui' as ui;

/// Thrown when the engine cannot decode a file.
class DecodeException implements Exception {
  const DecodeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The size [decodePhoto] gives a [width]×[height] image with
/// [maxLongEdge]: the long edge capped, the other one rounded (never
/// upscaled). Other decoders of the same photo (the float preview) ask for
/// exactly this size so their pixels line up.
({int width, int height}) decodedSizeFor(
  int width,
  int height,
  int? maxLongEdge,
) {
  if (maxLongEdge == null || (width <= maxLongEdge && height <= maxLongEdge)) {
    return (width: width, height: height);
  }
  return width >= height
      ? (
          width: maxLongEdge,
          height: (height * maxLongEdge / width).round().clamp(1, maxLongEdge),
        )
      : (
          width: (width * maxLongEdge / height).round().clamp(1, maxLongEdge),
          height: maxLongEdge,
        );
}

/// Decodes encoded bytes with the engine codec, optionally downscaled so the
/// long edge is at most [maxLongEdge] (decoders use scaled decode where they can).
///
/// The caller owns (and must dispose) the returned image.
Future<ui.Image> decodePhoto(Uint8List bytes, {int? maxLongEdge}) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    int? tw, th;
    if (maxLongEdge != null && (w > maxLongEdge || h > maxLongEdge)) {
      final target = decodedSizeFor(w, h, maxLongEdge);
      tw = target.width;
      th = target.height;
    }
    final codec = await descriptor.instantiateCodec(
      targetWidth: tw,
      targetHeight: th,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  } on Exception catch (e) {
    throw DecodeException('This file could not be decoded ($e).');
  }
}

/// Reads only the pixel dimensions without decoding pixels.
Future<({int width, int height})> probeSize(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (width: descriptor.width, height: descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    return size;
  } on Exception catch (e) {
    throw DecodeException('Unsupported or damaged image ($e).');
  }
}

/// Encodes an image as PNG bytes (used for thumbnails and previews).
Future<Uint8List> encodePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw const DecodeException('PNG encode failed');
  return data.buffer.asUint8List();
}
