import 'package:lumen/platform/background.dart';

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:lumen_core/lumen_core.dart';

/// The export file formats (JPEG and PNG 8-bit, PNG and TIFF 16-bit).
typedef ExportFormat = ExportFileFormat;

/// Finished output pixels of one export, before encoding.
sealed class ExportRaster {
  int get width;
  int get height;
}

/// 8 bits per channel (RGBA8888).
final class Raster8 implements ExportRaster {
  const Raster8(this.pixels);
  final RgbaBuffer pixels;

  @override
  int get width => pixels.width;

  @override
  int get height => pixels.height;
}

/// 16 bits per channel, RGB, row-major.
final class Raster16 implements ExportRaster {
  Raster16(this.width, this.height, this.rgb, {required this.fromFloat}) {
    if (rgb.length != width * height * 3) {
      throw ArgumentError('rgb ${rgb.length} != ${width}x${height}x3');
    }
  }

  /// [pixels] widened (v × 257): the file is 16-bit, the detail 8-bit.
  factory Raster16.widened(RgbaBuffer pixels) => Raster16(
    pixels.width,
    pixels.height,
    widenRgba8To16(pixels.data, pixels.width, pixels.height),
    fromFloat: false,
  );

  @override
  final int width;
  @override
  final int height;
  final Uint16List rgb;

  /// Rendered from a float source (more than 256 levels are real).
  final bool fromFloat;
}

/// EXIF tags removed besides the whole GPS directory: orientation (pixels
/// are exported upright), serial numbers, user comment.
const _kStrippedExif = [0xA431, 0xA435, 0xC62F, 0x9286];

/// Camera EXIF of [sourceJpeg] for an export: no GPS, no serial numbers,
/// no orientation, no thumbnail. Null when there is none to keep.
img.ExifData? exportExif(Uint8List? sourceJpeg, {required bool keep}) {
  if (!keep || sourceJpeg == null) return null;
  final exif = img.decodeJpgExif(sourceJpeg);
  if (exif == null) return null;
  exif.gpsIfd.data.clear();
  exif.gpsIfd.sub.clear();
  exif.imageIfd.sub.directories.remove('gps');
  exif.imageIfd.data.remove(0x0112);
  exif.imageIfd.data.remove(0x8825);
  for (final tag in _kStrippedExif) {
    exif.exifIfd.data.remove(tag);
    exif.imageIfd.data.remove(tag);
  }
  exif.thumbnailIfd.data.clear();
  return exif;
}

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
  if (format.sixteenBit) {
    throw ArgumentError('$format needs encodeRaster');
  }
  final image = img.Image.fromBytes(
    width: pixels.width,
    height: pixels.height,
    bytes: pixels.data.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final rgb = image.convert(numChannels: 3);
  final exif = exportExif(sourceJpeg, keep: keepMetadata);
  if (exif != null) rgb.exif = exif;
  return switch (format) {
    ExportFormat.jpeg => Uint8List.fromList(
      img.encodeJpg(rgb, quality: quality.clamp(1, 100)),
    ),
    _ => Uint8List.fromList(img.encodePng(rgb)),
  };
});

/// Encodes [raster] as [format]; the file is the concatenation of the
/// returned chunks. A 16-bit TIFF is its header plus a view of the
/// raster's samples (no copy of the pixels).
Future<List<Uint8List>> encodeRaster(
  ExportRaster raster, {
  required ExportFormat format,
  int quality = 90,
  Uint8List? sourceJpeg,
  bool keepMetadata = true,
}) async {
  switch (raster) {
    case Raster8(:final pixels):
      if (format.sixteenBit) {
        return encodeRaster(
          Raster16.widened(pixels),
          format: format,
          sourceJpeg: sourceJpeg,
          keepMetadata: keepMetadata,
        );
      }
      return [
        await encodeExport(
          pixels,
          format: format,
          quality: quality,
          sourceJpeg: sourceJpeg,
          keepMetadata: keepMetadata,
        ),
      ];
    case Raster16():
      if (!format.sixteenBit) {
        throw ArgumentError('a 16-bit raster cannot be written as $format');
      }
      if (format == ExportFormat.tiff16) {
        final exif = exportExif(sourceJpeg, keep: keepMetadata);
        final layout = Tiff16Layout(
          width: raster.width,
          height: raster.height,
          icc: srgbIccProfile(),
          ifd0: exif == null ? const [] : tiffEntries(exif.imageIfd, _ifd0Keep),
          exif: exif == null ? const [] : tiffEntries(exif.exifIfd, _exifKeep),
        );
        return [layout.header, tiff16PixelBytes(raster.rgb)];
      }
      final w = raster.width, h = raster.height, rgb = raster.rgb;
      return [
        await runInBackground(
          () => encodePng16(w, h, rgb, sourceJpeg, keepMetadata),
        ),
      ];
  }
}

/// IFD0 tags copied into a TIFF: description, make, model, date, artist,
/// copyright.
bool _ifd0Keep(int tag) => const {270, 271, 272, 306, 315, 33432}.contains(tag);

/// EXIF tags copied into a TIFF: all but pointers and the maker note (its
/// internal offsets point into the original file; it also holds serials).
bool _exifKeep(int tag) =>
    !const {0x927C, 0xA005, 0x8825, 0xA002, 0xA003}.contains(tag);

/// [dir]'s values as TIFF entries (little-endian), those [keep] accepts.
/// Values the TIFF writer cannot place are skipped.
List<TiffEntry> tiffEntries(img.IfdDirectory dir, bool Function(int) keep) {
  final out = <TiffEntry>[];
  for (final tag in dir.keys) {
    final v = dir[tag];
    if (v == null || !keep(tag)) continue;
    final buf = img.OutputBuffer(bigEndian: false);
    v.write(buf);
    try {
      out.add(TiffEntry(tag, v.type.index, v.length, buf.getBytes()));
    } on ArgumentError {
      continue;
    }
  }
  return out;
}

/// A 16-bit RGB PNG with the sRGB ICC profile and (sanitized) EXIF in an
/// `eXIf` chunk.
Uint8List encodePng16(
  int width,
  int height,
  Uint16List rgb,
  Uint8List? sourceJpeg,
  bool keepMetadata,
) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgb.buffer,
    bytesOffset: rgb.offsetInBytes,
    format: img.Format.uint16,
    numChannels: 3,
    iccp: img.IccProfile(
      'sRGB',
      img.IccProfileCompression.none,
      srgbIccProfile(),
    ),
  );
  final png = img.encodePng(image);
  final exif = exportExif(sourceJpeg, keep: keepMetadata);
  if (exif == null) return png;
  final out = img.OutputBuffer();
  exif.write(out);
  return insertPngChunk(png, 'eXIf', out.getBytes());
}

/// [png] with a chunk of [type] inserted right after IHDR.
Uint8List insertPngChunk(Uint8List png, String type, Uint8List data) {
  const ihdrEnd = 8 + 4 + 4 + 13 + 4;
  final chunk = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
    ..add(type.codeUnits)
    ..add(data);
  final body = chunk.toBytes();
  final crc = crc32(body, 4);
  final b = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(png, 0, ihdrEnd))
    ..add(body)
    ..add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List())
    ..add(Uint8List.sublistView(png, ihdrEnd));
  return b.toBytes();
}

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

/// CRC-32 (PNG, zlib) of [bytes] from [start].
int crc32(Uint8List bytes, [int start = 0]) {
  var c = 0xFFFFFFFF;
  for (var i = start; i < bytes.length; i++) {
    c = _crcTable[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

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
  return '${base}_edit.${format.extension}';
}
