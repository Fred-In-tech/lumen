import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/import/bit_depth.dart';
import 'package:lumen/import/import_file.dart';

Uint8List _png(int depth) => Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, // IHDR
  0, 0, 0x10, 0, 0, 0, 0, 0x10, // 4096 x 16
  depth, 6, 0, 0, 0,
]);

List<int> _box(String type, List<int> payload) => [
  0,
  0,
  0,
  8 + payload.length,
  ...type.codeUnits,
  ...payload,
];

Uint8List _heif(List<List<int>> boxes) => Uint8List.fromList([
  ..._box('ftyp', 'heic'.codeUnits + [0, 0, 0, 0]),
  for (final b in boxes) ...b,
  ...List.filled(32, 0),
]);

/// A little- or big-endian TIFF: IFD0 is an 8-bit preview that points to a
/// SubIFD holding the sensor data ([photometric], [bits] per sample).
Uint8List _tiff({
  required bool little,
  int bits = 14,
  int photometric = 32803,
}) {
  final d = ByteData(128);
  final e = little ? Endian.little : Endian.big;
  d
    ..setUint8(0, little ? 0x49 : 0x4D)
    ..setUint8(1, little ? 0x49 : 0x4D)
    ..setUint16(2, 42, e)
    ..setUint32(4, 8, e);
  void entry(int at, int tag, int type, int count, int value) {
    d
      ..setUint16(at, tag, e)
      ..setUint16(at + 2, type, e)
      ..setUint32(at + 4, count, e);
    if (type == 3) {
      d.setUint16(at + 8, value, e);
    } else {
      d.setUint32(at + 8, value, e);
    }
  }

  // IFD0 at 8: three entries.
  d.setUint16(8, 3, e);
  entry(10, 258, 3, 1, 8);
  entry(22, 262, 3, 1, 2); // RGB preview
  entry(34, 330, 4, 1, 64); // SubIFD
  d.setUint32(46, 0, e);
  // SubIFD at 64: two entries.
  d.setUint16(64, 2, e);
  entry(66, 258, 3, 1, bits);
  entry(78, 262, 3, 1, photometric);
  d.setUint32(90, 0, e);
  return d.buffer.asUint8List();
}

void main() {
  test('JPEG and WebP are 8-bit, unknown formats are unknown', () {
    final any = Uint8List(64);
    expect(sniffBitDepth(any, PhotoFormat.jpeg), 8);
    expect(sniffBitDepth(any, PhotoFormat.webp), 8);
    expect(sniffBitDepth(any, PhotoFormat.unknown), isNull);
  });

  test('PNG depth comes from IHDR', () {
    expect(sniffBitDepth(_png(8), PhotoFormat.png), 8);
    expect(sniffBitDepth(_png(16), PhotoFormat.png), 16);
    expect(sniffBitDepth(Uint8List(10), PhotoFormat.png), isNull);
    expect(sniffBitDepth(_png(0), PhotoFormat.png), isNull);
  });

  test('HEIC depth comes from pixi, else from the codec configuration', () {
    final pixi10 = _box('pixi', [0, 0, 0, 0, 3, 10, 10, 10]);
    final pixi8 = _box('pixi', [0, 0, 0, 0, 3, 8, 8, 8]);
    final hvcC10 = _box('hvcC', [...List.filled(17, 0), 0xFA, 0xFA, 0, 0, 0]);
    final av1C12 = _box('av1C', [0x81, 0, 0x60, 0, 0, 0, 0, 0]);
    final av1C10 = _box('av1C', [0x81, 0, 0x40, 0, 0, 0, 0, 0]);
    final av1C8 = _box('av1C', [0x81, 0, 0x00, 0, 0, 0, 0, 0]);
    expect(sniffBitDepth(_heif([pixi8, pixi10]), PhotoFormat.heic), 10);
    expect(sniffBitDepth(_heif([pixi8]), PhotoFormat.heic), 8);
    expect(sniffBitDepth(_heif([hvcC10]), PhotoFormat.heic), 10);
    expect(sniffBitDepth(_heif([av1C12]), PhotoFormat.heic), 12);
    expect(sniffBitDepth(_heif([av1C10]), PhotoFormat.heic), 10);
    expect(sniffBitDepth(_heif([av1C8]), PhotoFormat.heic), 8);
    expect(sniffBitDepth(_heif([]), PhotoFormat.heic), isNull);
  });

  test('TIFF-based RAW: BitsPerSample of the sensor directory', () {
    expect(sniffBitDepth(_tiff(little: true), PhotoFormat.dng), 14);
    expect(sniffBitDepth(_tiff(little: false, bits: 12), PhotoFormat.nef), 12);
    expect(
      sniffBitDepth(
        _tiff(little: true, bits: 16, photometric: 34892),
        PhotoFormat.dng,
      ),
      16,
    );
    // No sensor directory (only RGB previews): not declared.
    expect(
      sniffBitDepth(_tiff(little: true, photometric: 2), PhotoFormat.dng),
      isNull,
    );
  });

  test('non-TIFF RAW and damaged files never invent a number', () {
    final cr3 = Uint8List.fromList([
      ..._box('ftyp', 'crx '.codeUnits + [0, 0, 0, 1]),
      ...List.filled(64, 0),
    ]);
    expect(sniffBitDepth(cr3, PhotoFormat.cr3), isNull);
    expect(sniffBitDepth(Uint8List(4), PhotoFormat.dng), isNull);
    final truncated = _tiff(little: true).sublist(0, 40);
    expect(sniffBitDepth(truncated, PhotoFormat.dng), isNull);
    final bad = _tiff(little: true)..[2] = 7; // wrong magic
    expect(sniffBitDepth(bad, PhotoFormat.dng), isNull);
  });

  test('isHighBitDepth: every RAW, PNG and HEIC above 8 bits', () {
    expect(isHighBitDepth('cr3', null), isTrue);
    expect(isHighBitDepth('dng', 12), isTrue);
    expect(isHighBitDepth('png', 16), isTrue);
    expect(isHighBitDepth('png', 8), isFalse);
    expect(isHighBitDepth('png', null), isFalse);
    expect(isHighBitDepth('heic', 10), isTrue);
    expect(isHighBitDepth('heic', 8), isFalse);
    expect(isHighBitDepth('jpeg', 8), isFalse);
    expect(isHighBitDepth('webp', 16), isFalse);
  });
}
