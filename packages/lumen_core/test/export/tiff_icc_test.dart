import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

int _u16(Uint8List b, int o) => b[o] | b[o + 1] << 8;
int _u32(Uint8List b, int o) =>
    ByteData.sublistView(b).getUint32(o, Endian.little);
int _be32(Uint8List b, int o) => ByteData.sublistView(b).getUint32(o);

/// The entries of the IFD at [at]: tag → (type, count, value or offset).
Map<int, (int, int, int)> _ifd(Uint8List b, int at) => {
  for (var i = 0; i < _u16(b, at); i++)
    _u16(b, at + 2 + i * 12): (
      _u16(b, at + 4 + i * 12),
      _u32(b, at + 6 + i * 12),
      _u32(b, at + 10 + i * 12),
    ),
};

void main() {
  group('sRGB ICC', () {
    test('valid v2 display profile', () {
      final p = srgbIccProfile();
      expect(_be32(p, 0), p.length);
      expect(String.fromCharCodes(p.sublist(36, 40)), 'acsp');
      expect(String.fromCharCodes(p.sublist(12, 20)), 'mntrRGB ');
      final tags = _be32(p, 128);
      final sigs = [
        for (var i = 0; i < tags; i++)
          String.fromCharCodes(p.sublist(132 + i * 12, 136 + i * 12)),
      ];
      expect(
        sigs,
        containsAll([
          'desc',
          'cprt',
          'wtpt',
          'rXYZ',
          'gXYZ',
          'bXYZ',
          'rTRC',
          'gTRC',
          'bTRC',
        ]),
      );
      for (var i = 0; i < tags; i++) {
        final off = _be32(p, 136 + i * 12);
        expect(off % 4, 0);
        expect(off + _be32(p, 140 + i * 12), lessThanOrEqualTo(p.length));
      }
      expect(identical(srgbIccProfile(), p), isTrue, reason: 'cached');
      expect(srgbIccDescription, contains('sRGB'));
    });
  });

  group('TIFF 16', () {
    test('header layout: strips cover the pixels, ICC and EXIF linked', () {
      final icc = srgbIccProfile();
      final layout = Tiff16Layout(
        width: 3,
        height: 1000,
        icc: icc,
        ifd0: [TiffEntry.ascii(271, 'Canon'), TiffEntry.ascii(272, 'EOS R5')],
        exif: [
          TiffEntry(
            0x829A,
            5,
            1,
            Uint8List.fromList([1, 0, 0, 0, 200, 0, 0, 0]),
          ),
          TiffEntry(0x8827, 3, 1, Uint8List.fromList([100, 0])),
        ],
        rowsPerStrip: 300,
      );
      final h = layout.header;
      expect(h.length, layout.pixelOffset);
      expect(layout.pixelOffset % 2, 0);
      expect(layout.fileSize, layout.pixelOffset + 3 * 1000 * 6);
      expect(String.fromCharCodes(h.sublist(0, 2)), 'II');
      expect(_u16(h, 2), 42);
      final ifd = _ifd(h, _u32(h, 4));
      expect(ifd[256]!.$3, 3);
      expect(ifd[257]!.$3, 1000);
      expect(ifd[259]!.$3, 1); // uncompressed
      expect(ifd[262]!.$3, 2); // RGB
      expect(ifd[277]!.$3, 3);
      expect(ifd[278]!.$3, 300);
      final bps = ifd[258]!;
      expect(bps.$2, 3);
      expect(
        [_u16(h, bps.$3), _u16(h, bps.$3 + 2), _u16(h, bps.$3 + 4)],
        [16, 16, 16],
      );
      final offs = ifd[273]!, counts = ifd[279]!;
      expect(offs.$2, 4);
      var expected = layout.pixelOffset, total = 0;
      for (var i = 0; i < 4; i++) {
        expect(_u32(h, offs.$3 + i * 4), expected);
        final c = _u32(h, counts.$3 + i * 4);
        expected += c;
        total += c;
      }
      expect(total, 3 * 1000 * 6);
      final iccTag = ifd[34675]!;
      expect(iccTag.$2, icc.length);
      expect(h.sublist(iccTag.$3, iccTag.$3 + icc.length), icc);
      final make = ifd[271]!;
      expect(String.fromCharCodes(h.sublist(make.$3, make.$3 + 5)), 'Canon');
      final exif = _ifd(h, ifd[34665]!.$3);
      expect(exif[0x8827], (3, 1, 100));
      final et = exif[0x829A]!;
      expect([_u32(h, et.$3), _u32(h, et.$3 + 4)], [1, 200]);
      // Tags are sorted ascending (TIFF 6.0).
      final keys = ifd.keys.toList();
      expect(keys, [...keys]..sort());
    });

    test('without ICC and EXIF; one strip', () {
      final layout = Tiff16Layout(width: 2, height: 2);
      final ifd = _ifd(layout.header, _u32(layout.header, 4));
      expect(ifd.containsKey(34675), isFalse);
      expect(ifd.containsKey(34665), isFalse);
      expect(ifd[273]!.$2, 1);
      expect(ifd[273]!.$3, layout.pixelOffset);
      expect(() => Tiff16Layout(width: 0, height: 2), throwsArgumentError);
      expect(() => TiffEntry(1, 3, 2, Uint8List(1)), throwsArgumentError);
    });

    test('pixel bytes are the little-endian samples', () {
      final px = Uint16List.fromList([0x0102, 0xA0B0, 1, 2, 3, 4]);
      expect(tiff16PixelBytes(px).sublist(0, 4), [0x02, 0x01, 0xB0, 0xA0]);
    });
  });
}
