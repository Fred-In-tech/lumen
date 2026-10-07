import 'dart:math' as math;
import 'dart:typed_data';

/// One TIFF directory entry: [tag], TIFF field [type] (3 SHORT, 4 LONG,
/// 5 RATIONAL, 7 UNDEFINED, …), [count] values and their little-endian
/// [bytes].
class TiffEntry {
  TiffEntry(this.tag, this.type, this.count, this.bytes) {
    final size = _typeSize(type);
    if (size * count != bytes.length) {
      throw ArgumentError(
        'tag $tag: $count values of type $type need ${size * count} bytes, '
        'got ${bytes.length}',
      );
    }
  }

  factory TiffEntry.ascii(int tag, String text) {
    final b = Uint8List.fromList([...text.codeUnits.map((c) => c & 0x7F), 0]);
    return TiffEntry(tag, 2, b.length, b);
  }

  factory TiffEntry.short(int tag, List<int> values) {
    final b = ByteData(values.length * 2);
    for (var i = 0; i < values.length; i++) {
      b.setUint16(i * 2, values[i], Endian.little);
    }
    return TiffEntry(tag, 3, values.length, b.buffer.asUint8List());
  }

  factory TiffEntry.long(int tag, List<int> values) {
    final b = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      b.setUint32(i * 4, values[i], Endian.little);
    }
    return TiffEntry(tag, 4, values.length, b.buffer.asUint8List());
  }

  factory TiffEntry.rational(int tag, int num, int den) {
    final b = ByteData(8)
      ..setUint32(0, num, Endian.little)
      ..setUint32(4, den, Endian.little);
    return TiffEntry(tag, 5, 1, b.buffer.asUint8List());
  }

  final int tag;
  final int type;
  final int count;
  final Uint8List bytes;
}

int _typeSize(int type) => switch (type) {
  1 || 2 || 6 || 7 => 1,
  3 || 8 => 2,
  4 || 9 || 11 || 13 => 4,
  5 || 10 || 12 => 8,
  _ => throw ArgumentError('unknown TIFF type $type'),
};

/// Tags this writer sets itself (an extra IFD0 entry with one of these is
/// dropped).
const _structural = {
  254, 256, 257, 258, 259, 262, 273, 274, 277, 278, 279, 282, 283, 284, //
  296, 305, 34665, 34675, 0x8825, 0x014A,
};

/// Header of a baseline little-endian TIFF holding [width]×[height]
/// 16-bit RGB pixels, uncompressed and chunky, written right after the
/// header ([pixelOffset]) in strips of [rowsPerStrip] rows. [icc] is
/// embedded as tag 34675, [exif] entries in an EXIF sub-IFD, [ifd0]
/// entries (Make, Model, …) in the main IFD.
///
/// The pixel data is not part of the header: the caller writes the frame
/// after it ([tiff16PixelBytes]), so a 45 MP export never holds a second
/// copy of its pixels.
class Tiff16Layout {
  factory Tiff16Layout({
    required int width,
    required int height,
    Uint8List? icc,
    List<TiffEntry> ifd0 = const [],
    List<TiffEntry> exif = const [],
    int? rowsPerStrip,
    String software = 'Lumen',
  }) {
    if (width < 1 || height < 1) {
      throw ArgumentError('bad size ${width}x$height');
    }
    final rowBytes = width * 6;
    final rps = (rowsPerStrip ?? math.max(1, (1 << 20) ~/ rowBytes)).clamp(
      1,
      height,
    );
    final strips = (height + rps - 1) ~/ rps;
    final counts = [
      for (var i = 0; i < strips; i++)
        math.min(rps, height - i * rps) * rowBytes,
    ];
    List<TiffEntry> main(List<int> offsets, int exifAt) => [
      TiffEntry.long(254, [0]),
      TiffEntry.long(256, [width]),
      TiffEntry.long(257, [height]),
      TiffEntry.short(258, [16, 16, 16]),
      TiffEntry.short(259, [1]),
      TiffEntry.short(262, [2]),
      TiffEntry.long(273, offsets),
      TiffEntry.short(274, [1]),
      TiffEntry.short(277, [3]),
      TiffEntry.long(278, [rps]),
      TiffEntry.long(279, counts),
      TiffEntry.rational(282, 300, 1),
      TiffEntry.rational(283, 300, 1),
      TiffEntry.short(284, [1]),
      TiffEntry.short(296, [2]),
      TiffEntry.ascii(305, software),
      for (final e in ifd0)
        if (!_structural.contains(e.tag)) e,
      if (exif.isNotEmpty) TiffEntry.long(34665, [exifAt]),
      if (icc != null) TiffEntry(34675, 7, icc.length, icc),
    ]..sort((a, b) => a.tag.compareTo(b.tag));
    final exifSorted = [...exif]..sort((a, b) => a.tag.compareTo(b.tag));

    // Pass 1 with placeholders gives the sizes, pass 2 the real values.
    var layout = _place(main(List.filled(strips, 0), 0), exifSorted);
    final pixelOffset = layout.end;
    final offsets = [
      for (var i = 0, o = pixelOffset; i < strips; o += counts[i], i++) o,
    ];
    layout = _place(main(offsets, layout.exifAt), exifSorted);
    return Tiff16Layout._(width, height, layout.bytes, pixelOffset);
  }

  Tiff16Layout._(this.width, this.height, this.header, this.pixelOffset);

  final int width;
  final int height;

  /// Everything before the pixels (padded to [pixelOffset] bytes).
  final Uint8List header;
  final int pixelOffset;

  int get fileSize => pixelOffset + width * height * 6;
}

int _align(int v, int a) => (v + a - 1) ~/ a * a;

({Uint8List bytes, int exifAt, int end}) _place(
  List<TiffEntry> main,
  List<TiffEntry> exif,
) {
  // Sizes.
  var pos = 8 + 2 + main.length * 12 + 4;
  final mainAt = <int>[];
  for (final e in main) {
    pos = _align(pos, 4);
    mainAt.add(pos);
    if (e.bytes.length > 4) pos += e.bytes.length;
  }
  var exifAt = 0;
  final exifData = <int>[];
  if (exif.isNotEmpty) {
    exifAt = _align(pos, 4);
    pos = exifAt + 2 + exif.length * 12 + 4;
    for (final e in exif) {
      pos = _align(pos, 4);
      exifData.add(pos);
      if (e.bytes.length > 4) pos += e.bytes.length;
    }
  }
  final end = _align(pos, 16);
  final out = Uint8List(end);
  final bd = ByteData.sublistView(out)
    ..setUint8(0, 0x49)
    ..setUint8(1, 0x49)
    ..setUint16(2, 42, Endian.little)
    ..setUint32(4, 8, Endian.little);
  void dir(int at, List<TiffEntry> entries, List<int> dataAt) {
    bd.setUint16(at, entries.length, Endian.little);
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final o = at + 2 + i * 12;
      bd
        ..setUint16(o, e.tag, Endian.little)
        ..setUint16(o + 2, e.type, Endian.little)
        ..setUint32(o + 4, e.count, Endian.little);
      if (e.bytes.length <= 4) {
        out.setRange(o + 8, o + 8 + e.bytes.length, e.bytes);
      } else {
        bd.setUint32(o + 8, dataAt[i], Endian.little);
        out.setRange(dataAt[i], dataAt[i] + e.bytes.length, e.bytes);
      }
    }
    bd.setUint32(at + 2 + entries.length * 12, 0, Endian.little);
  }

  dir(8, main, mainAt);
  if (exif.isNotEmpty) dir(exifAt, exif, exifData);
  return (bytes: out, exifAt: exifAt, end: end);
}

/// The bytes of 16-bit samples as stored in a little-endian TIFF: a view,
/// no copy (every platform Lumen runs on is little-endian).
Uint8List tiff16PixelBytes(Uint16List samples) {
  if (Endian.host != Endian.little) {
    throw UnsupportedError('big-endian hosts are not supported');
  }
  return samples.buffer.asUint8List(
    samples.offsetInBytes,
    samples.lengthInBytes,
  );
}
