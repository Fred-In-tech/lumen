/// Creative 3D LUTs: the Adobe / Resolve `.cube` format.
///
/// A [CubeLut] is an N×N×N grid of RGB outputs over the display-referred
/// (sRGB-encoded) cube 0..1, red index fastest. Values are stored as 16-bit
/// integers: the GPU atlas, the CPU twin, the stored file and the content
/// hash all use these same numbers, so they cannot disagree.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Thrown for a file that is not a usable `.cube` LUT. [message] is shown
/// to the user as is.
class CubeFormatException implements Exception {
  const CubeFormatException(this.message);
  final String message;

  @override
  String toString() => 'CubeFormatException: $message';
}

/// RGB → RGB function used to bake LUTs (tests, conversions).
typedef RgbFn = (double, double, double) Function(double r, double g, double b);

class CubeLut {
  CubeLut._(this.size, this.title, this.values)
    : assert(values.length == size * size * size * 3);

  /// Builds a LUT of [size] by evaluating [fn] at every grid point.
  factory CubeLut.fromFunction(int size, RgbFn fn, {String title = 'LUT'}) {
    _checkSize(size);
    final v = Uint16List(size * size * size * 3);
    final k = size - 1;
    var o = 0;
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        for (var r = 0; r < size; r++) {
          final (x, y, z) = fn(r / k, g / k, b / k);
          v[o++] = _q(x);
          v[o++] = _q(y);
          v[o++] = _q(z);
        }
      }
    }
    return CubeLut._(size, title, v);
  }

  /// The identity LUT (output = input).
  factory CubeLut.identity(int size) =>
      CubeLut.fromFunction(size, (r, g, b) => (r, g, b), title: 'Identity');

  /// Parses `.cube` text. [fallbackTitle] names a LUT without `TITLE`.
  ///
  /// Accepts `LUT_3D_SIZE` 2–[maxSize], `DOMAIN_MIN` / `DOMAIN_MAX`,
  /// Resolve's `LUT_3D_INPUT_RANGE` / `LUT_1D_INPUT_RANGE`, `#` comments,
  /// and `LUT_1D_SIZE` (a 1D-only LUT is baked into a 33³ cube; a 1D
  /// shaper in front of a 3D table is baked into the 3D table). Rejects
  /// anything else with a [CubeFormatException].
  factory CubeLut.parse(String text, {String fallbackTitle = 'LUT'}) =>
      _CubeParser(text, fallbackTitle).parse();

  /// Largest supported grid (Resolve exports 65; most looks use 33).
  static const int maxSize = 65;

  /// Largest `.cube` file read (a 65³ table is about 8 MB of text).
  static const int maxFileBytes = 24 * 1024 * 1024;

  /// Grid size N (N³ entries).
  final int size;

  /// `TITLE` of the file (or the fallback name).
  final String title;

  /// N³ × RGB, red fastest, then green, then blue; 0..65535 = 0..1.
  final Uint16List values;

  static void _checkSize(int n) {
    if (n < 2 || n > maxSize) {
      throw CubeFormatException(
        'LUT size $n is not supported (2 to $maxSize).',
      );
    }
  }

  static int _q(double v) {
    if (v.isNaN || v <= 0) return 0;
    if (v >= 1) return 65535;
    return (v * 65535).round();
  }

  /// Content hash of the grid (not of the file): 16 lowercase hex digits.
  /// Two files holding the same table (other comments, title or number
  /// formatting) get the same hash, so the library stores them once.
  late final String contentHash = _hash();

  String _hash() {
    // Two 32-bit FNV-1a lanes with different offsets; multiplications are
    // split so they stay exact where integers are doubles (web).
    var a = 0x811c9dc5, b = 0x01000193 ^ 0x5bd1e995;
    void eat(int byte) {
      a = _mul32(a ^ byte, 0x01000193);
      b = _mul32(b ^ byte, 0x01000193);
      b = (b ^ (b >>> 13)) & 0xffffffff;
    }

    eat(size);
    for (final v in values) {
      eat(v & 0xff);
      eat(v >> 8);
    }
    String hex(int x) => x.toRadixString(16).padLeft(8, '0');
    return '${hex(a)}${hex(b)}';
  }

  static int _mul32(int a, int b) {
    final lo = a * (b & 0xffff);
    final hi = ((a * (b >>> 16)) & 0xffff) * 65536;
    return (lo + hi) & 0xffffffff;
  }

  /// Output at grid point (r, g, b) as 0..1.
  double entry(int r, int g, int b, int channel) =>
      values[((b * size + g) * size + r) * 3 + channel] / 65535;

  /// Trilinear lookup of encoded [r], [g], [b] (clamped to 0..1) into
  /// [out]; the exact arithmetic of `lutSample` in `develop.frag`.
  void sample(double r, double g, double b, Float64List out) {
    final k = (size - 1).toDouble();
    double pos(double v) => (v.isNaN ? 0.0 : v.clamp(0.0, 1.0)) * k;
    final pr = pos(r), pg = pos(g), pb = pos(b);
    final r0 = pr.floor(), g0 = pg.floor(), b0 = pb.floor();
    final fr = pr - r0, fg = pg - g0, fb = pb - b0;
    final r1 = math.min(r0 + 1, size - 1);
    final g1 = math.min(g0 + 1, size - 1);
    final b1 = math.min(b0 + 1, size - 1);
    for (var c = 0; c < 3; c++) {
      double mix(double x, double y, double t) => x + (y - x) * t;
      final c00 = mix(entry(r0, g0, b0, c), entry(r1, g0, b0, c), fr);
      final c10 = mix(entry(r0, g1, b0, c), entry(r1, g1, b0, c), fr);
      final c01 = mix(entry(r0, g0, b1, c), entry(r1, g0, b1, c), fr);
      final c11 = mix(entry(r0, g1, b1, c), entry(r1, g1, b1, c), fr);
      out[c] = mix(mix(c00, c10, fg), mix(c01, c11, fg), fb);
    }
  }

  /// Width of the GPU atlas: two N-wide halves (high bytes | low bytes).
  int get atlasWidth => 2 * size;

  /// Height of the GPU atlas: N² rows (green + blue × N).
  int get atlasHeight => size * size;

  /// The GPU atlas as RGBA8888: texel (r, g + b·N) holds the high bytes of
  /// the entry's R, G, B; texel (r + N, g + b·N) the low bytes. Opaque, so
  /// premultiplication cannot touch it; sampled with `FilterQuality.none`.
  Uint8List toAtlasRgba() {
    final w = atlasWidth;
    final out = Uint8List(w * atlasHeight * 4);
    for (var b = 0; b < size; b++) {
      for (var g = 0; g < size; g++) {
        final row = g + b * size;
        for (var r = 0; r < size; r++) {
          final src = ((b * size + g) * size + r) * 3;
          final hi = (row * w + r) * 4;
          final lo = (row * w + r + size) * 4;
          for (var c = 0; c < 3; c++) {
            final v = values[src + c];
            out[hi + c] = v >> 8;
            out[lo + c] = v & 0xff;
          }
          out[hi + 3] = 255;
          out[lo + 3] = 255;
        }
      }
    }
    return out;
  }

  /// Compact storage form: `LLUT`, version, N, title, N³ × RGB uint16 LE.
  Uint8List encode() {
    final t = utf8.encode(title);
    final titleLen = math.min(t.length, 1024);
    final out = ByteData(10 + titleLen + values.length * 2);
    const magic = [0x4c, 0x4c, 0x55, 0x54];
    for (var i = 0; i < 4; i++) {
      out.setUint8(i, magic[i]);
    }
    out
      ..setUint8(4, 1)
      ..setUint8(5, size)
      ..setUint16(6, titleLen, Endian.little);
    for (var i = 0; i < titleLen; i++) {
      out.setUint8(8 + i, t[i]);
    }
    var o = 8 + titleLen;
    out.setUint16(o, 0, Endian.little);
    o += 2;
    for (final v in values) {
      out.setUint16(o, v, Endian.little);
      o += 2;
    }
    return out.buffer.asUint8List();
  }

  /// Reads [encode]'s output; throws [CubeFormatException] on anything else.
  static CubeLut decode(Uint8List bytes) {
    if (bytes.length < 10 ||
        bytes[0] != 0x4c ||
        bytes[1] != 0x4c ||
        bytes[2] != 0x55 ||
        bytes[3] != 0x54 ||
        bytes[4] != 1) {
      throw const CubeFormatException('Not a stored LUT.');
    }
    final d = ByteData.sublistView(bytes);
    final n = bytes[5];
    _checkSize(n);
    final titleLen = d.getUint16(6, Endian.little);
    final start = 10 + titleLen;
    final count = n * n * n * 3;
    if (bytes.length != start + count * 2) {
      throw const CubeFormatException('Stored LUT is truncated.');
    }
    final title = utf8.decode(
      bytes.sublist(8, 8 + titleLen),
      allowMalformed: true,
    );
    final v = Uint16List(count);
    for (var i = 0; i < count; i++) {
      v[i] = d.getUint16(start + i * 2, Endian.little);
    }
    return CubeLut._(n, title, v);
  }

  /// Writes this LUT as `.cube` text (tests, export of generated LUTs).
  String toCubeText() {
    final sb = StringBuffer()
      ..writeln('TITLE "${title.replaceAll('"', "'")}"')
      ..writeln('LUT_3D_SIZE $size')
      ..writeln('DOMAIN_MIN 0.0 0.0 0.0')
      ..writeln('DOMAIN_MAX 1.0 1.0 1.0');
    for (var i = 0; i < values.length; i += 3) {
      sb.writeln(
        '${(values[i] / 65535).toStringAsFixed(6)} '
        '${(values[i + 1] / 65535).toStringAsFixed(6)} '
        '${(values[i + 2] / 65535).toStringAsFixed(6)}',
      );
    }
    return sb.toString();
  }

  /// Copy with another display name.
  CubeLut renamed(String name) => CubeLut._(size, name, values);
}

/// A raw table of a `.cube` file before baking.
class _Table {
  _Table(this.size, this.data, this.min, this.max);
  final int size;
  final List<double> data;
  final List<double> min;
  final List<double> max;

  double norm(double v, int c) {
    final span = max[c] - min[c];
    return span <= 0 ? 0 : ((v - min[c]) / span).clamp(0.0, 1.0);
  }

  bool get unitDomain => min.every((v) => v == 0) && max.every((v) => v == 1);
}

class _CubeParser {
  _CubeParser(this.text, this.fallbackTitle);

  final String text;
  final String fallbackTitle;

  String? _title;
  int? _size3;
  int? _size1;
  List<double>? _min3, _max3, _min1, _max1;
  final List<double> _data = [];

  CubeLut parse() {
    if (text.length > CubeLut.maxFileBytes) {
      throw const CubeFormatException('The LUT file is too large.');
    }
    if (text.contains('\u0000')) {
      throw const CubeFormatException('Not a .cube text file.');
    }
    var lineNo = 0;
    for (final raw in const LineSplitter().convert(text)) {
      lineNo++;
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      _line(line, lineNo);
    }
    return _bake();
  }

  void _line(String line, int lineNo) {
    final c0 = line.codeUnitAt(0);
    final numeric =
        (c0 >= 0x30 && c0 <= 0x39) || c0 == 0x2d || c0 == 0x2b || c0 == 0x2e;
    if (numeric) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 3) _bad('line $lineNo has fewer than 3 numbers');
      for (var i = 0; i < 3; i++) {
        final v = double.tryParse(parts[i]);
        if (v == null || !v.isFinite) _bad('line $lineNo is not a number');
        _data.add(v);
      }
      final cap = _expected();
      if (cap != null && _data.length > cap * 3) {
        _bad('more data lines than the LUT size declares');
      }
      return;
    }
    final sp = line.indexOf(RegExp(r'\s'));
    final key = (sp < 0 ? line : line.substring(0, sp)).toUpperCase();
    final rest = sp < 0 ? '' : line.substring(sp).trim();
    if (_data.isNotEmpty) _bad('unexpected "$key" after the data');
    switch (key) {
      case 'TITLE':
        _title = rest.replaceAll('"', '').trim();
      case 'LUT_3D_SIZE':
        _size3 = _int(rest, key);
        CubeLut._checkSize(_size3!);
      case 'LUT_1D_SIZE':
        final n = _int(rest, key);
        if (n < 2 || n > 65536) _bad('1D LUT size $n is not supported');
        _size1 = n;
      case 'DOMAIN_MIN':
        _min3 = _min1 = _three(rest, key);
      case 'DOMAIN_MAX':
        _max3 = _max1 = _three(rest, key);
      case 'LUT_3D_INPUT_RANGE':
        final r = _two(rest, key);
        _min3 = [r.$1, r.$1, r.$1];
        _max3 = [r.$2, r.$2, r.$2];
      case 'LUT_1D_INPUT_RANGE':
        final r = _two(rest, key);
        _min1 = [r.$1, r.$1, r.$1];
        _max1 = [r.$2, r.$2, r.$2];
      default:
        // Unknown keywords (e.g. LUT_IN_VIDEO_RANGE) are ignored, as
        // Resolve does.
        break;
    }
  }

  int? _expected() {
    final n3 = _size3, n1 = _size1;
    if (n3 == null && n1 == null) return null;
    return (n1 ?? 0) + (n3 == null ? 0 : n3 * n3 * n3);
  }

  int _int(String s, String key) =>
      int.tryParse(s.split(RegExp(r'\s+')).first) ??
      _bad('$key is not a whole number');

  List<double> _three(String s, String key) {
    final p = s.split(RegExp(r'\s+'));
    final v = [for (final x in p.take(3)) double.tryParse(x)];
    if (v.length < 3 || v.any((x) => x == null || !x.isFinite)) {
      _bad('$key needs three numbers');
    }
    return [for (final x in v) x!];
  }

  (double, double) _two(String s, String key) {
    final p = s.split(RegExp(r'\s+'));
    final a = p.isNotEmpty ? double.tryParse(p[0]) : null;
    final b = p.length > 1 ? double.tryParse(p[1]) : null;
    if (a == null || b == null) _bad('$key needs two numbers');
    return (a, b);
  }

  Never _bad(String why) =>
      throw CubeFormatException('Not a valid .cube LUT: $why.');

  CubeLut _bake() {
    final n3 = _size3, n1 = _size1;
    final title = (_title == null || _title!.isEmpty) ? fallbackTitle : _title!;
    if (n3 == null && n1 == null) {
      _bad('no LUT_3D_SIZE');
    }
    final expected = _expected()!;
    if (_data.length != expected * 3) {
      _bad('expected $expected data lines, found ${_data.length ~/ 3}');
    }
    const unitMin = [0.0, 0.0, 0.0], unitMax = [1.0, 1.0, 1.0];
    final shaper = n1 == null
        ? null
        : _Table(
            n1,
            _data.sublist(0, n1 * 3),
            _min1 ?? unitMin,
            _max1 ?? unitMax,
          );
    final cube = n3 == null
        ? null
        : _Table(
            n3,
            _data.sublist((n1 ?? 0) * 3),
            _min3 ?? unitMin,
            _max3 ?? unitMax,
          );
    if (cube != null && shaper == null && cube.unitDomain) {
      final v = Uint16List(cube.data.length);
      for (var i = 0; i < v.length; i++) {
        v[i] = CubeLut._q(cube.data[i]);
      }
      return CubeLut._(n3!, title, v);
    }
    return CubeLut.fromFunction(n3 ?? 33, (r, g, b) {
      var x = [r, g, b];
      if (shaper != null) {
        x = [for (var c = 0; c < 3; c++) _sample1(shaper, x[c], c)];
      }
      if (cube == null) return (x[0], x[1], x[2]);
      final o = _sample3(cube, [
        for (var c = 0; c < 3; c++) cube.norm(x[c], c),
      ]);
      return (o[0], o[1], o[2]);
    }, title: title);
  }

  static double _sample1(_Table t, double v, int c) {
    final p = t.norm(v, c) * (t.size - 1);
    final i0 = p.floor();
    final i1 = math.min(i0 + 1, t.size - 1);
    final f = p - i0;
    final a = t.data[i0 * 3 + c], b = t.data[i1 * 3 + c];
    return a + (b - a) * f;
  }

  static List<double> _sample3(_Table t, List<double> x) {
    final n = t.size;
    final p = [for (final v in x) v * (n - 1)];
    final i0 = [for (final v in p) v.floor()];
    final f = [for (var c = 0; c < 3; c++) p[c] - i0[c]];
    final i1 = [for (final v in i0) math.min(v + 1, n - 1)];
    double at(int r, int g, int b, int c) =>
        t.data[((b * n + g) * n + r) * 3 + c];
    return [
      for (var c = 0; c < 3; c++)
        () {
          double mix(double a, double b, double s) => a + (b - a) * s;
          final c00 = mix(
            at(i0[0], i0[1], i0[2], c),
            at(i1[0], i0[1], i0[2], c),
            f[0],
          );
          final c10 = mix(
            at(i0[0], i1[1], i0[2], c),
            at(i1[0], i1[1], i0[2], c),
            f[0],
          );
          final c01 = mix(
            at(i0[0], i0[1], i1[2], c),
            at(i1[0], i0[1], i1[2], c),
            f[0],
          );
          final c11 = mix(
            at(i0[0], i1[1], i1[2], c),
            at(i1[0], i1[1], i1[2], c),
            f[0],
          );
          return mix(mix(c00, c10, f[1]), mix(c01, c11, f[1]), f[2]);
        }(),
    ];
  }
}
