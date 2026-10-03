import 'dart:math' as math;
import 'dart:typed_data';

import '../color/srgb.dart';
import '../render/engine_constants.dart';
import '../render/rgba_buffer.dart';

/// Long edge of the proxy the auto-tone solver renders (PLAN.md P1.14).
const int kSolverLongEdge = 256;

/// Area-filter downscale of [source] so its long edge is [longEdge],
/// averaging in linear light. Never upscales: smaller inputs are copied.
RgbaBuffer makeProxy(RgbaBuffer source, {int longEdge = kAnalysisLongEdge}) {
  final sw = source.width, sh = source.height;
  if (math.max(sw, sh) <= longEdge) return source.copy();
  final scale = longEdge / math.max(sw, sh);
  final dw = math.max(1, (sw * scale).round());
  final dh = math.max(1, (sh * scale).round());
  final xTaps = _taps(sw, dw);
  final yTaps = _taps(sh, dh);

  // Horizontal pass: sh rows × dw columns, linear RGB.
  final tmp = Float64List(sh * dw * 3);
  final src = source.data;
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < dw; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (final t in xTaps[x]) {
        final o = (y * sw + t.index) * 4;
        r += kSrgbByteToLinear[src[o]] * t.weight;
        g += kSrgbByteToLinear[src[o + 1]] * t.weight;
        b += kSrgbByteToLinear[src[o + 2]] * t.weight;
      }
      final o = (y * dw + x) * 3;
      tmp[o] = r;
      tmp[o + 1] = g;
      tmp[o + 2] = b;
    }
  }

  // Vertical pass and encode.
  final out = RgbaBuffer(dw, dh);
  int enc(double v) => (linearToSrgb(v) * 255).round().clamp(0, 255);
  for (var y = 0; y < dh; y++) {
    for (var x = 0; x < dw; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (final t in yTaps[y]) {
        final o = (t.index * dw + x) * 3;
        r += tmp[o] * t.weight;
        g += tmp[o + 1] * t.weight;
        b += tmp[o + 2] * t.weight;
      }
      out.setPixel(x, y, enc(r), enc(g), enc(b));
    }
  }
  return out;
}

class _Tap {
  const _Tap(this.index, this.weight);
  final int index;
  final double weight;
}

/// Exact box-filter coverage weights mapping [src] samples onto [dst].
List<List<_Tap>> _taps(int src, int dst) {
  final ratio = src / dst;
  return List.generate(dst, (i) {
    final start = i * ratio, end = (i + 1) * ratio;
    final taps = <_Tap>[];
    for (var s = start.floor(); s < end.ceil() && s < src; s++) {
      final cover = math.min(end, s + 1.0) - math.max(start, s.toDouble());
      if (cover > 1e-12) taps.add(_Tap(s, cover / ratio));
    }
    return taps;
  }, growable: false);
}
