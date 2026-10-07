/// Reads preset bundles (`.zip`) without writing anything to disk.
///
/// Only stored and deflated entries are supported; encrypted entries,
/// ZIP64 archives and spanned archives are rejected. Inflation is injected
/// ([Inflate]: `dart:io` on native, see `app/lib/features/looks/
/// inflate_io.dart`) and capped, so a zip bomb stops at [maxEntryBytes].
library;

import 'dart:convert';
import 'dart:typed_data';

/// Thrown for an unreadable or unsupported archive. [message] is
/// user-facing.
class ZipFormatException implements Exception {
  const ZipFormatException(this.message);
  final String message;

  @override
  String toString() => 'ZipFormatException: $message';
}

/// Inflates a raw DEFLATE stream; must throw (any exception) as soon as
/// the output would exceed [maxBytes].
typedef Inflate = Uint8List Function(Uint8List deflated, int maxBytes);

/// One file of an archive.
class ZipEntry {
  const ZipEntry(this.path, this.bytes);

  /// Path inside the archive, `/`-separated.
  final String path;
  final Uint8List bytes;
}

/// Returns the files of [zip] whose path passes [want] (directories,
/// `__MACOSX/` resource forks and hidden files are never returned).
List<ZipEntry> readZip(
  Uint8List zip, {
  required Inflate inflate,
  required bool Function(String path) want,
  int maxEntries = 5000,
  int maxEntryBytes = 32 * 1024 * 1024,
  int maxTotalBytes = 256 * 1024 * 1024,
}) {
  final d = ByteData.sublistView(zip);
  final eocd = _findEocd(zip, d);
  final count = d.getUint16(eocd + 10, Endian.little);
  final cdSize = d.getUint32(eocd + 12, Endian.little);
  final cdOffset = d.getUint32(eocd + 16, Endian.little);
  if (count == 0xffff || cdOffset == 0xffffffff || cdSize == 0xffffffff) {
    throw const ZipFormatException('ZIP64 archives are not supported.');
  }
  if (d.getUint16(eocd + 4, Endian.little) != 0) {
    throw const ZipFormatException('Split archives are not supported.');
  }
  if (count > maxEntries) {
    throw ZipFormatException('The archive has more than $maxEntries files.');
  }
  if (cdOffset + cdSize > eocd) {
    throw const ZipFormatException('The archive is damaged.');
  }
  final out = <ZipEntry>[];
  var total = 0;
  var p = cdOffset;
  for (var n = 0; n < count; n++) {
    if (p + 46 > zip.length || d.getUint32(p, Endian.little) != 0x02014b50) {
      throw const ZipFormatException('The archive is damaged.');
    }
    final flags = d.getUint16(p + 8, Endian.little);
    final method = d.getUint16(p + 10, Endian.little);
    final crc = d.getUint32(p + 16, Endian.little);
    final compSize = d.getUint32(p + 20, Endian.little);
    final size = d.getUint32(p + 24, Endian.little);
    final nameLen = d.getUint16(p + 28, Endian.little);
    final extraLen = d.getUint16(p + 30, Endian.little);
    final commentLen = d.getUint16(p + 32, Endian.little);
    final local = d.getUint32(p + 42, Endian.little);
    if (p + 46 + nameLen > zip.length) {
      throw const ZipFormatException('The archive is damaged.');
    }
    final path = utf8
        .decode(zip.sublist(p + 46, p + 46 + nameLen), allowMalformed: true)
        .replaceAll(r'\', '/');
    p += 46 + nameLen + extraLen + commentLen;
    if (!_isFile(path) || !want(path)) continue;
    if (flags & 1 != 0) {
      throw const ZipFormatException('Encrypted archives are not supported.');
    }
    if (size > maxEntryBytes) {
      throw ZipFormatException('"$path" is too large to be a preset.');
    }
    total += size;
    if (total > maxTotalBytes) {
      throw const ZipFormatException('The archive is too large.');
    }
    final bytes = _entryData(
      zip,
      d,
      local,
      compSize,
      size,
      method,
      path,
      inflate,
    );
    if (crc32(bytes) != crc) {
      throw ZipFormatException('"$path" is damaged (checksum).');
    }
    out.add(ZipEntry(path, bytes));
  }
  return out;
}

bool _isFile(String path) {
  if (path.endsWith('/')) return false;
  if (path.startsWith('__MACOSX/')) return false;
  final base = path.substring(path.lastIndexOf('/') + 1);
  return base.isNotEmpty && !base.startsWith('.');
}

int _findEocd(Uint8List zip, ByteData d) {
  if (zip.length < 22) throw const ZipFormatException('Not a zip archive.');
  final stop = zip.length - 22 - 0xffff;
  for (var p = zip.length - 22; p >= 0 && p >= stop; p--) {
    if (d.getUint32(p, Endian.little) == 0x06054b50) return p;
  }
  throw const ZipFormatException('Not a zip archive.');
}

Uint8List _entryData(
  Uint8List zip,
  ByteData d,
  int local,
  int compSize,
  int size,
  int method,
  String path,
  Inflate inflate,
) {
  if (local + 30 > zip.length ||
      d.getUint32(local, Endian.little) != 0x04034b50) {
    throw const ZipFormatException('The archive is damaged.');
  }
  final start =
      local +
      30 +
      d.getUint16(local + 26, Endian.little) +
      d.getUint16(local + 28, Endian.little);
  if (start + compSize > zip.length) {
    throw const ZipFormatException('The archive is damaged.');
  }
  final raw = Uint8List.sublistView(zip, start, start + compSize);
  switch (method) {
    case 0:
      if (compSize != size) {
        throw const ZipFormatException('The archive is damaged.');
      }
      return Uint8List.fromList(raw);
    case 8:
      final Uint8List out;
      try {
        out = inflate(raw, size);
      } on Exception {
        throw ZipFormatException('"$path" could not be unpacked.');
      }
      if (out.length != size) {
        throw ZipFormatException('"$path" could not be unpacked.');
      }
      return out;
    default:
      throw ZipFormatException(
        '"$path" uses a compression method that is not supported.',
      );
  }
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

/// CRC-32 (IEEE), as zip stores it.
int crc32(List<int> bytes) {
  var c = 0xffffffff;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}
