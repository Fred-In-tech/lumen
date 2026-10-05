import 'dart:typed_data';

import 'package:lumen/import/import_file.dart';

/// Bits per channel a file stores, read from its header (never decoded):
/// 8 for JPEG and WebP, the IHDR depth for PNG, the `pixi` / codec
/// configuration depth for HEIC / AVIF, and `BitsPerSample` of the raw
/// image directory for TIFF-based RAW (DNG, NEF, ARW, …). Null when the
/// file does not declare it (e.g. Canon CR3): nothing is guessed.
int? sniffBitDepth(Uint8List b, PhotoFormat format) {
  switch (format) {
    case PhotoFormat.jpeg || PhotoFormat.webp:
      return 8;
    case PhotoFormat.png:
      return b.length > 24 ? _plausible(b[24]) : null;
    case PhotoFormat.heic:
      return _heifDepth(b);
    case PhotoFormat.unknown:
      return null;
    default:
      return format.isRaw ? _tiffRawDepth(b) : null;
  }
}

/// True when a photo of [format] storing [bitDepth] bits can gain from the
/// float editing path: every camera RAW, and PNG / HEIC above 8 bits.
bool isHighBitDepth(String format, int? bitDepth) {
  for (final f in PhotoFormat.values) {
    if (f.name == format && f.isRaw) return true;
  }
  return (format == PhotoFormat.png.name || format == PhotoFormat.heic.name) &&
      (bitDepth ?? 8) > 8;
}

int? _plausible(int bits) => bits >= 1 && bits <= 32 ? bits : null;

bool _tag(Uint8List b, int o, String fourcc) =>
    b[o] == fourcc.codeUnitAt(0) &&
    b[o + 1] == fourcc.codeUnitAt(1) &&
    b[o + 2] == fourcc.codeUnitAt(2) &&
    b[o + 3] == fourcc.codeUnitAt(3);

/// HEIF item properties live in the `meta` box at the start of the file:
/// the largest `pixi` depth, else the HEVC / AV1 configuration depth.
int? _heifDepth(Uint8List b) {
  const scan = 256 * 1024;
  final end = b.length < scan ? b.length : scan;
  int? pixi, codec;
  for (var i = 4; i + 8 < end; i++) {
    if (_tag(b, i, 'pixi') && i + 9 < end) {
      // version + flags (4), channel count (1), bits per channel.
      final n = b[i + 8];
      for (var c = 0; c < n && i + 9 + c < end; c++) {
        final bits = b[i + 9 + c];
        if (_plausible(bits) != null && (pixi == null || bits > pixi)) {
          pixi = bits;
        }
      }
    } else if (codec == null && _tag(b, i, 'hvcC') && i + 22 < end) {
      // HEVCDecoderConfigurationRecord: bitDepthLumaMinus8 at byte 17.
      codec = (b[i + 4 + 17] & 0x07) + 8;
    } else if (codec == null && _tag(b, i, 'av1C') && i + 7 < end) {
      // AV1CodecConfigurationRecord: high_bitdepth, twelve_bit flags.
      final flags = b[i + 4 + 2];
      codec = (flags & 0x40) == 0 ? 8 : ((flags & 0x20) == 0 ? 10 : 12);
    }
  }
  return pixi ?? codec;
}

/// `BitsPerSample` of the directory that holds the sensor data (CFA or
/// LinearRaw photometric interpretation), walking IFD0, its chain and the
/// SubIFDs. Null for non-TIFF containers and files without such a tag.
int? _tiffRawDepth(Uint8List b) {
  if (b.length < 8) return null;
  final little = b[0] == 0x49 && b[1] == 0x49;
  final big = b[0] == 0x4D && b[1] == 0x4D;
  if (!little && !big) return null;
  final data = ByteData.sublistView(b);
  final endian = little ? Endian.little : Endian.big;
  int u16(int o) => data.getUint16(o, endian);
  int u32(int o) => data.getUint32(o, endian);
  if (u16(2) != 42) return null;

  final pending = <int>[u32(4)];
  final seen = <int>{};
  while (pending.isNotEmpty && seen.length < 32) {
    final ifd = pending.removeLast();
    if (ifd <= 0 || ifd + 2 > b.length || !seen.add(ifd)) continue;
    final count = u16(ifd);
    if (ifd + 2 + count * 12 + 4 > b.length) continue;
    int? bits, photometric;
    for (var i = 0; i < count; i++) {
      final e = ifd + 2 + i * 12;
      final tag = u16(e), type = u16(e + 2), n = u32(e + 4);
      // SHORT (3) values fit inline when n <= 2, LONG (4) when n == 1.
      int value(int index) {
        final size = type == 3 ? 2 : 4;
        final inline = n * size <= 4;
        final at = (inline ? e + 8 : u32(e + 8)) + index * size;
        if (at + size > b.length) return 0;
        return type == 3 ? u16(at) : u32(at);
      }

      if (type != 3 && type != 4 && type != 13) continue;
      if (tag == 258 && n >= 1) {
        bits = value(0);
      } else if (tag == 262 && n >= 1) {
        photometric = value(0);
      } else if (tag == 330) {
        for (var k = 0; k < n && k < 8; k++) {
          pending.add(type == 3 ? value(k) : _sub(u32, e, n, k, b.length));
        }
      }
    }
    // 32803 = colour filter array, 34892 = LinearRaw.
    if (bits != null && (photometric == 32803 || photometric == 34892)) {
      return _plausible(bits);
    }
    pending.add(u32(ifd + 2 + count * 12));
  }
  return null;
}

/// SubIFD offset [k] of a LONG / IFD entry at [e] with [n] values.
int _sub(int Function(int) u32, int e, int n, int k, int length) {
  if (n == 1) return u32(e + 8);
  final at = u32(e + 8) + 4 * k;
  return at + 4 <= length ? u32(at) : 0;
}
