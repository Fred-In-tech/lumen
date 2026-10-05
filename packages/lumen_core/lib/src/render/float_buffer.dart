import 'dart:typed_data';

import 'rgba_buffer.dart';

/// A high-bit-depth image: 32-bit float RGBA, row-major, straight alpha,
/// holding **sRGB-encoded values with extended range**. 0..1 means the same
/// as a byte / 255 in an [RgbaBuffer]; values above 1.0 are highlights
/// brighter than display white (RAW headroom) and are not clamped.
///
/// This is the CPU twin of the float32 source texture of the float editing
/// path (docs/HIGH_BIT_DEPTH.md).
class FloatBuffer {
  FloatBuffer(this.width, this.height, [Float32List? data])
    : data = data ?? Float32List(width * height * 4) {
    if (this.data.length != width * height * 4) {
      throw ArgumentError(
        'data length ${this.data.length} != ${width * height * 4}',
      );
    }
  }

  /// The exact float equivalent of an 8-bit buffer (byte / 255).
  factory FloatBuffer.fromRgba(RgbaBuffer b) {
    final out = FloatBuffer(b.width, b.height);
    for (var i = 0; i < b.data.length; i++) {
      out.data[i] = b.data[i] / 255;
    }
    return out;
  }

  final int width;
  final int height;
  final Float32List data;

  int get pixelCount => width * height;

  int offset(int x, int y) => (y * width + x) * 4;

  void setPixel(int x, int y, double r, double g, double b, [double a = 1]) {
    final o = offset(x, y);
    data[o] = r;
    data[o + 1] = g;
    data[o + 2] = b;
    data[o + 3] = a;
  }

  /// The 8-bit rendition: every channel clamped to 0..1 and rounded (what
  /// an 8-bit render target stores).
  RgbaBuffer toRgba() {
    final out = RgbaBuffer(width, height);
    for (var i = 0; i < data.length; i++) {
      out.data[i] = (data[i].clamp(0.0, 1.0) * 255).round();
    }
    return out;
  }

  /// A copy of the [w]×[h] rectangle at ([x], [y]).
  FloatBuffer crop(int x, int y, int w, int h) {
    if (x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > width || y + h > height) {
      throw RangeError('crop $x,$y ${w}x$h outside ${width}x$height');
    }
    final out = FloatBuffer(w, h);
    for (var row = 0; row < h; row++) {
      final from = offset(x, y + row);
      out.data.setRange(row * w * 4, (row + 1) * w * 4, data, from);
    }
    return out;
  }
}

/// How develop treats a float source beyond plain decoding. Both values are
/// 0 for sources without highlight headroom (16-bit PNG, 10-bit HEIC), which
/// then render exactly like their 8-bit equivalent, only more precisely.
class HbdProfile {
  const HbdProfile({this.shoulderKnee = 0, this.highlightGain = 0});

  /// No shoulder, no extra highlight range.
  static const none = HbdProfile();

  /// Apple's extended-range RAW rendering (`CIRAWFilter` with
  /// `extendedDynamicRangeAmount = 2`): identical to the default rendering
  /// below the knee, without its highlight roll-off above. Develop applies
  /// that roll-off itself ([highlightShoulder]) so the unedited photo looks
  /// like the default rendering, and Highlights gets [highlightGain] more
  /// EV per stop above white. Measured on Canon CR3 (HIGH_BIT_DEPTH.md).
  static const rawExtended = HbdProfile(shoulderKnee: 0.86, highlightGain: 0.5);

  /// Encoded value where the base highlight shoulder starts (0 = off).
  final double shoulderKnee;

  /// Extra Highlights strength in EV per stop the guided base sits above
  /// display white (0 = off), up to two stops.
  final double highlightGain;

  bool get isNone => shoulderKnee == 0 && highlightGain == 0;

  @override
  bool operator ==(Object other) =>
      other is HbdProfile &&
      other.shoulderKnee == shoulderKnee &&
      other.highlightGain == highlightGain;

  @override
  int get hashCode => Object.hash(shoulderKnee, highlightGain);

  @override
  String toString() => 'HbdProfile(knee $shoulderKnee, gain $highlightGain)';
}

/// Where a source buffer or texture sits inside the full (virtual) source:
/// export renders develop each output tile from a window instead of the
/// whole photo. The window's own size is the buffer's.
class SourceWindow {
  const SourceWindow({
    required this.x,
    required this.y,
    required this.fullWidth,
    required this.fullHeight,
  });

  /// Top-left pixel of the window in the full source.
  final int x;
  final int y;

  /// Size of the full source the window was cut from.
  final int fullWidth;
  final int fullHeight;
}

/// The base highlight shoulder of [HbdProfile.shoulderKnee], on an encoded
/// value: identity up to [knee], a quadratic roll-off that reaches 1.0 at
/// `2 − knee` with matching slope at the knee, 1.0 beyond. With `knee <= 0`
/// it is the plain clamp of the 8-bit path. `develop.frag shoulder()`.
double highlightShoulder(double e, double knee) {
  if (knee <= 0 || knee >= 1) return e < 0 ? 0 : (e > 1 ? 1 : e);
  if (e <= knee) return e < 0 ? 0 : e;
  final t = (e - knee) / (2 * (1 - knee));
  if (t >= 1) return 1;
  return knee + (1 - knee) * (2 * t - t * t);
}
