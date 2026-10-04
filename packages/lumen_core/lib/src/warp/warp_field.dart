/// The warp displacement field (research 07 §3.10): for every output
/// position `v` (source uv, after geometry), the develop pass samples the
/// source at `v + d(v)`: a backward map.
///
/// Packing (`packRgba`, sampled by `develop.frag` with `FilterQuality.none`
/// and a manual 4-tap bilinear like `sampleAux`): a `(2w)×h` RGBA8 atlas,
/// left tile RG = dx (hi, lo), right tile RG = dy (hi, lo), B = 0, A = 255
/// (alpha is never packed). Each 16-bit code `q` decodes to
/// `(q − 32767) / 32767 · range`, so `32767` is exactly zero: untouched
/// regions are bit-exact.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Long edge of the warp grid (texels).
const int kWarpLongEdge = 512;

const int _kZero = 32767;

class WarpField {
  /// [dx], [dy] are displacements in source uv, row-major `width × height`.
  /// [range] (≥ max |d|) defaults to the smallest that fits.
  WarpField(this.width, this.height, Float32List dx, Float32List dy)
    : range = _rangeOf(dx, dy) {
    final n = width * height;
    if (dx.length != n || dy.length != n) {
      throw ArgumentError(
        'field ${dx.length}/${dy.length} != $width x $height',
      );
    }
    _qx = _quantize(dx, range);
    _qy = _quantize(dy, range);
  }

  /// The 1×1 identity field (no warp).
  factory WarpField.identity() =>
      WarpField(1, 1, Float32List(1), Float32List(1));

  final int width;
  final int height;

  /// Packing range in uv (codes span ±range).
  final double range;
  late final Uint16List _qx;
  late final Uint16List _qy;

  /// True when every displacement is exactly zero.
  bool get isIdentity =>
      _qx.every((q) => q == _kZero) && _qy.every((q) => q == _kZero);

  /// Largest |d| component (uv) after quantization.
  double get maxDisplacement {
    var m = 0;
    for (final q in [..._qx, ..._qy]) {
      m = math.max(m, (q - _kZero).abs());
    }
    return m / _kZero * range;
  }

  double dxAt(int i) => (_qx[i] - _kZero) / _kZero * range;
  double dyAt(int i) => (_qy[i] - _kZero) / _kZero * range;

  /// Mutable float copies of the (quantized) displacements.
  (Float32List, Float32List) toFloats() {
    final n = width * height;
    return (
      Float32List.fromList([for (var i = 0; i < n; i++) dxAt(i)]),
      Float32List.fromList([for (var i = 0; i < n; i++) dyAt(i)]),
    );
  }

  static double _rangeOf(Float32List dx, Float32List dy) {
    var m = 0.0;
    for (var i = 0; i < dx.length; i++) {
      m = math.max(m, math.max(dx[i].abs(), dy[i].abs()));
    }
    // A little headroom, at least 1/1024 uv.
    return math.max(m * 1.0001, 1 / 1024);
  }

  static Uint16List _quantize(Float32List d, double range) {
    final out = Uint16List(d.length);
    for (var i = 0; i < d.length; i++) {
      final q = (d[i] / range * _kZero).round() + _kZero;
      out[i] = q.clamp(0, 2 * _kZero);
    }
    return out;
  }

  /// RGBA8 atlas `(2·width) × height` (see the library doc).
  Uint8List packRgba() {
    final w = width, h = height;
    final out = Uint8List(2 * w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final l = (y * 2 * w + x) * 4, r = (y * 2 * w + w + x) * 4;
        out[l] = _qx[i] >> 8;
        out[l + 1] = _qx[i] & 0xff;
        out[r] = _qy[i] >> 8;
        out[r + 1] = _qy[i] & 0xff;
        out[l + 3] = 255;
        out[r + 3] = 255;
      }
    }
    return out;
  }

  /// Bilinear displacement (uv) at uv over texel centres, decoding every
  /// tap before interpolating, exactly like `warpUv()` in `develop.frag`.
  (double, double) sample(double u, double v) {
    final px = u * width - 0.5, py = v * height - 0.5;
    final fx0 = px.floorToDouble(), fy0 = py.floorToDouble();
    final fx = px - fx0, fy = py - fy0;
    final x0 = _ci(fx0.toInt(), width), x1 = _ci(fx0.toInt() + 1, width);
    final y0 = _ci(fy0.toInt(), height), y1 = _ci(fy0.toInt() + 1, height);
    double lerp(Uint16List q) {
      final a = q[y0 * width + x0] - _kZero, b = q[y0 * width + x1] - _kZero;
      final c = q[y1 * width + x0] - _kZero, d = q[y1 * width + x1] - _kZero;
      final top = a + (b - a) * fx;
      return (top + (c + (d - c) * fx - top) * fy) / _kZero * range;
    }

    return (lerp(_qx), lerp(_qy));
  }

  static int _ci(int i, int n) => i < 0 ? 0 : (i >= n ? n - 1 : i);

  /// Minimum Jacobian determinant of the backward map `v ↦ v + d(v)` over
  /// the grid (forward differences). ≤ 0 means a fold-over.
  double minJacobian() {
    var m = double.infinity;
    for (var y = 0; y + 1 < height; y++) {
      for (var x = 0; x + 1 < width; x++) {
        final i = y * width + x;
        m = math.min(
          m,
          jacobianAt(
            dxAt(i + 1) - dxAt(i),
            dxAt(i + width) - dxAt(i),
            dyAt(i + 1) - dyAt(i),
            dyAt(i + width) - dyAt(i),
          ),
        );
      }
    }
    return m.isFinite ? m : 1;
  }

  /// Jacobian determinant from per-texel differences (uv units).
  double jacobianAt(double dxu, double dxv, double dyu, double dyv) =>
      (1 + dxu * width) * (1 + dyv * height) - dxv * height * dyu * width;
}
