import 'dart:math' as math;
import 'dart:typed_data';

/// Name stored in the profile's `desc` tag.
const String srgbIccDescription = 'sRGB IEC61966-2.1 (Lumen)';

Uint8List? _cached;

/// A compact ICC v2 display profile for sRGB (IEC 61966-2.1): D50
/// Bradford-adapted primaries and a 1024-entry tone curve. Generated, not
/// copied from any vendor profile. Embedded in 16-bit TIFF and PNG
/// exports so colour-managed apps read the pixels as sRGB.
Uint8List srgbIccProfile() => _cached ??= _build();

class _Writer {
  final BytesBuilder b = BytesBuilder();

  void u8(int v) => b.addByte(v & 0xFF);

  void u16(int v) {
    u8(v >> 8);
    u8(v);
  }

  void u32(int v) {
    u16(v >> 16);
    u16(v);
  }

  void sig(String s) => s.codeUnits.forEach(u8);

  void s15(double v) => u32((v * 65536).round() & 0xFFFFFFFF);

  void pad4() {
    while (b.length % 4 != 0) {
      u8(0);
    }
  }
}

Uint8List _desc() {
  final w = _Writer()
    ..sig('desc')
    ..u32(0)
    ..u32(srgbIccDescription.length + 1);
  srgbIccDescription.codeUnits.forEach(w.u8);
  w
    ..u8(0)
    ..u32(0) // Unicode language
    ..u32(0) // Unicode count
    ..u16(0) // ScriptCode code
    ..u8(0); // ScriptCode count
  for (var i = 0; i < 67; i++) {
    w.u8(0);
  }
  return w.b.takeBytes();
}

Uint8List _text(String s) {
  final w = _Writer()
    ..sig('text')
    ..u32(0);
  s.codeUnits.forEach(w.u8);
  w.u8(0);
  return w.b.takeBytes();
}

Uint8List _xyz(double x, double y, double z) {
  final w = _Writer()
    ..sig('XYZ ')
    ..u32(0)
    ..s15(x)
    ..s15(y)
    ..s15(z);
  return w.b.takeBytes();
}

Uint8List _curve() {
  const n = 1024;
  final w = _Writer()
    ..sig('curv')
    ..u32(0)
    ..u32(n);
  for (var i = 0; i < n; i++) {
    final v = i / (n - 1);
    final lin = v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    w.u16((lin * 65535).round());
  }
  return w.b.takeBytes();
}

Uint8List _build() {
  final trc = _curve();
  final tags = <(String, Uint8List)>[
    ('desc', _desc()),
    ('cprt', _text('No copyright, use freely')),
    ('wtpt', _xyz(0.9642, 1.0, 0.8249)),
    ('rXYZ', _xyz(0.4360747, 0.2225045, 0.0139322)),
    ('gXYZ', _xyz(0.3850649, 0.7168786, 0.0971045)),
    ('bXYZ', _xyz(0.1430804, 0.0606169, 0.7141733)),
    ('rTRC', trc),
  ];
  // Offsets: header 128 + count 4 + 9 entries (g/bTRC share rTRC's data).
  const entries = 9;
  var pos = 128 + 4 + entries * 12;
  final offsets = <int>[];
  for (final (_, data) in tags) {
    offsets.add(pos);
    pos += (data.length + 3) & ~3;
  }
  final size = pos;
  final w = _Writer()
    ..u32(size)
    ..u32(0) // CMM
    ..u32(0x02100000) // version 2.1
    ..sig('mntr')
    ..sig('RGB ')
    ..sig('XYZ ')
    ..u16(2026)
    ..u16(1)
    ..u16(1)
    ..u16(0)
    ..u16(0)
    ..u16(0)
    ..sig('acsp')
    ..u32(0) // platform
    ..u32(0) // flags
    ..u32(0) // manufacturer
    ..u32(0) // model
    ..u32(0)
    ..u32(0) // attributes
    ..u32(0) // perceptual
    ..s15(0.9642)
    ..s15(1.0)
    ..s15(0.8249)
    ..u32(0); // creator
  while (w.b.length < 128) {
    w.u8(0);
  }
  w.u32(entries);
  for (var i = 0; i < tags.length; i++) {
    w
      ..sig(tags[i].$1)
      ..u32(offsets[i])
      ..u32(tags[i].$2.length);
  }
  final trcAt = offsets.last;
  for (final s in const ['gTRC', 'bTRC']) {
    w
      ..sig(s)
      ..u32(trcAt)
      ..u32(trc.length);
  }
  for (final (_, data) in tags) {
    w.b.add(data);
    w.pad4();
  }
  return w.b.takeBytes();
}
