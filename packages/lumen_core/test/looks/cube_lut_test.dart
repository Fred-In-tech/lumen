import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

String _cube(int n, {String header = '', double Function(double)? f}) {
  final sb = StringBuffer(header)..writeln('LUT_3D_SIZE $n');
  final fn = f ?? (double x) => x;
  for (var b = 0; b < n; b++) {
    for (var g = 0; g < n; g++) {
      for (var r = 0; r < n; r++) {
        sb.writeln('${fn(r / (n - 1))} ${fn(g / (n - 1))} ${fn(b / (n - 1))}');
      }
    }
  }
  return sb.toString();
}

void main() {
  final out = Float64List(3);

  group('parse', () {
    test('identity cube with title, comments and domain', () {
      final lut = CubeLut.parse(
        _cube(
          5,
          header:
              '# made by a test\nTITLE "Kodak 2383"\n'
              'DOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n\n',
        ),
      );
      expect(lut.size, 5);
      expect(lut.title, 'Kodak 2383');
      lut.sample(0.3, 0.6, 0.9, out);
      expect(out[0], closeTo(0.3, 1e-4));
      expect(out[1], closeTo(0.6, 1e-4));
      expect(out[2], closeTo(0.9, 1e-4));
    });

    test('red index runs fastest', () {
      // Output red = 1 only where the red index is the last one.
      final n = 3;
      final sb = StringBuffer('LUT_3D_SIZE $n\n');
      for (var b = 0; b < n; b++) {
        for (var g = 0; g < n; g++) {
          for (var r = 0; r < n; r++) {
            sb.writeln('${r == n - 1 ? 1 : 0} 0 0');
          }
        }
      }
      final lut = CubeLut.parse(sb.toString());
      lut.sample(1, 0, 0, out);
      expect(out[0], 1);
      lut.sample(0, 1, 1, out);
      expect(out[0], 0);
    });

    test('fallback title when TITLE is missing', () {
      final lut = CubeLut.parse(_cube(2), fallbackTitle: 'teal.cube');
      expect(lut.title, 'teal.cube');
    });

    test('a non-unit domain is resampled onto 0..1', () {
      // Table over 0..2: output = input / 2 maps 0..1 → 0..0.5 of the
      // domain, so sampling at x gives (x * 2 - 0) / 2... = x * 1 → x/2*2.
      final lut = CubeLut.parse(
        _cube(9, header: 'DOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n', f: (x) => x),
      );
      // Input 0.5 lies at normalized 0.25 of the 0..2 domain → output 0.25.
      lut.sample(0.5, 0.5, 0.5, out);
      expect(out[0], closeTo(0.25, 2e-3));
    });

    test('a 1D-only LUT is baked into a 33³ cube', () {
      final sb = StringBuffer('LUT_1D_SIZE 4\n');
      for (var i = 0; i < 4; i++) {
        final v = 1 - i / 3;
        sb.writeln('$v $v $v');
      }
      final lut = CubeLut.parse(sb.toString());
      expect(lut.size, 33);
      lut.sample(0, 0.5, 1, out);
      expect(out[0], closeTo(1, 1e-4));
      expect(out[1], closeTo(0.5, 1e-3));
      expect(out[2], closeTo(0, 1e-4));
    });

    test('a 1D shaper in front of a 3D table is baked in', () {
      final sb = StringBuffer('LUT_1D_SIZE 2\nLUT_3D_SIZE 2\n')
        ..writeln('0 0 0')
        ..writeln('0.5 0.5 0.5'); // shaper halves the input
      for (var b = 0; b < 2; b++) {
        for (var g = 0; g < 2; g++) {
          for (var r = 0; r < 2; r++) {
            sb.writeln('$r $g $b');
          }
        }
      }
      final lut = CubeLut.parse(sb.toString());
      lut.sample(1, 1, 1, out);
      expect(out[0], closeTo(0.5, 2e-3));
    });

    test('Resolve input ranges are accepted', () {
      final lut = CubeLut.parse(
        _cube(3, header: 'LUT_3D_INPUT_RANGE 0.0 1.0\n'),
      );
      expect(lut.size, 3);
    });

    test('values outside 0..1 are clamped', () {
      final lut = CubeLut.parse(_cube(2, f: (x) => x * 2 - 0.5));
      lut.sample(0, 0, 0, out);
      expect(out[0], 0);
      lut.sample(1, 1, 1, out);
      expect(out[0], 1);
    });

    test('rejects broken files with a readable message', () {
      void bad(String text, String fragment) => expect(
        () => CubeLut.parse(text),
        throwsA(
          isA<CubeFormatException>().having(
            (e) => e.message,
            'message',
            contains(fragment),
          ),
        ),
      );
      bad('TITLE "x"\n0 0 0\n', 'no LUT_3D_SIZE');
      bad('LUT_3D_SIZE 2\n0 0 0\n', 'expected 8 data lines');
      bad('LUT_3D_SIZE 99\n', 'size 99');
      bad('LUT_3D_SIZE 1\n', 'size 1');
      bad('LUT_3D_SIZE 2\n0 0\n', 'fewer than 3');
      bad('LUT_3D_SIZE 2\n0 x 0\n', 'not a number');
      bad('LUT_3D_SIZE two\n', 'whole number');
      bad('LUT_3D_SIZE 2\nDOMAIN_MIN 0 0\n', 'three numbers');
      bad('${_cube(2)}0 0 0\n', 'more data lines');
      bad('LUT_3D_SIZE 2\n0 0 0\nTITLE "late"\n', 'after the data');
      bad('LUT_1D_SIZE 1\n', '1D LUT size');
      bad('LUT_3D_INPUT_RANGE 0\n', 'two numbers');
      bad('\u0000\u0001binary', 'Not a .cube');
    });

    test('rejects an oversized file before parsing', () {
      final huge = 'x' * (CubeLut.maxFileBytes + 1);
      expect(() => CubeLut.parse(huge), throwsA(isA<CubeFormatException>()));
    });
  });

  group('sampling', () {
    test('trilinear between grid points', () {
      final lut = CubeLut.fromFunction(2, (r, g, b) => (r * r, g, 1 - b));
      lut.sample(0.5, 0.25, 0.5, out);
      expect(out[0], closeTo(0.5, 1e-4)); // linear between 0 and 1
      expect(out[1], closeTo(0.25, 1e-4));
      expect(out[2], closeTo(0.5, 1e-4));
    });

    test('inputs are clamped (NaN → 0)', () {
      final lut = CubeLut.identity(5);
      lut.sample(-1, 2, double.nan, out);
      expect(out, [0, 1, 0]);
    });
  });

  group('storage and hash', () {
    test('encode / decode round-trips values and title', () {
      final lut = CubeLut.fromFunction(
        7,
        (r, g, b) => (g, b, r),
        title: 'Rotate · ünïcode',
      );
      final back = CubeLut.decode(lut.encode());
      expect(back.size, 7);
      expect(back.title, 'Rotate · ünïcode');
      expect(back.values, lut.values);
      expect(back.contentHash, lut.contentHash);
    });

    test('decode rejects other bytes', () {
      expect(
        () => CubeLut.decode(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<CubeFormatException>()),
      );
      final ok = CubeLut.identity(2).encode();
      expect(
        () => CubeLut.decode(ok.sublist(0, ok.length - 1)),
        throwsA(isA<CubeFormatException>()),
      );
    });

    test('hash depends on the table only', () {
      final a = CubeLut.parse(_cube(5, header: 'TITLE "A"\n# x\n'));
      final b = CubeLut.parse(_cube(5, header: 'TITLE "B"\n'));
      final c = CubeLut.parse(_cube(5, f: (x) => x * 0.9));
      expect(a.contentHash, b.contentHash);
      expect(a.contentHash, isNot(c.contentHash));
      expect(LutRef.isValidHash(a.contentHash), isTrue);
      expect(a.renamed('Z').contentHash, a.contentHash);
    });

    test('toCubeText parses back to the same table', () {
      final lut = CubeLut.fromFunction(
        9,
        (r, g, b) => (r * 0.8 + 0.1, g, b * b),
        title: 'Warm "teal"',
      );
      final back = CubeLut.parse(lut.toCubeText());
      expect(back.contentHash, lut.contentHash);
      expect(back.title, "Warm 'teal'");
    });
  });

  test('atlas layout: hi bytes left, lo bytes right, opaque', () {
    final lut = CubeLut.fromFunction(3, (r, g, b) => (r, g * 0.5, 0.3));
    final a = lut.toAtlasRgba();
    expect(lut.atlasWidth, 6);
    expect(lut.atlasHeight, 9);
    expect(a.length, 6 * 9 * 4);
    // Entry (r=2, g=1, b=2): row g + b·N = 7.
    final hi = (7 * 6 + 2) * 4, lo = (7 * 6 + 2 + 3) * 4;
    for (var c = 0; c < 3; c++) {
      final v = (a[hi + c] << 8) | a[lo + c];
      expect(v / 65535, closeTo(lut.entry(2, 1, 2, c), 1e-9));
    }
    expect(a[hi + 3], 255);
    expect(a[lo + 3], 255);
    expect(lut.entry(2, 1, 2, 1), closeTo(0.25, 1e-4));
  });
}
