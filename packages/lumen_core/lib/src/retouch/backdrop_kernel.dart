/// CPU twin of `backdropRetouch()` in `retouch.frag` (image scope): Clean
/// backdrop, stray hairs, Unify lighting and Luminance (see
/// `backdrop_maps.dart` for the atlas and the formulas).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'backdrop_maps.dart';
import 'backdrop_params.dart';
import 'lab_planes.dart';

class BackdropKernel {
  BackdropKernel(this.maps, this.params)
    : active = maps.isReady && !params.isIdentity;

  final BackdropMaps maps;
  final BackdropParams params;

  /// False when the maps are not ready or every value is at its default.
  final bool active;

  final Float64List _t = Float64List(3);
  final Float64List _e = Float64List(3);
  final Float64List _g = Float64List(3);
  final Float64List _u = Float64List(3);
  double _mix = 0;
  double _matte = 0;
  bool _unify = false;

  /// Samples the weights at source uv; true when a backdrop effect
  /// touches the pixel (then call [apply]).
  bool weights(double u, double v) {
    if (!active) return false;
    maps.sampleTile(1, 1, u, v, _t, 0);
    final wc = params.clean * _t[0] / 255;
    final ws = params.strays * _t[2] / 255;
    _mix = math.max(wc, ws);
    _matte = _t[1] / 255;
    _unify = _matte > 0 && (params.unify > 0 || params.luminance != 0);
    return _mix > 0 || _unify;
  }

  /// Adds the backdrop change at uv for a pixel with source OkLab [li] to
  /// [o] (OkLab, the face result or [li] itself).
  void apply(double u, double v, Float64List li, Float64List o) {
    if (_mix > 0) {
      _tileLab(0, 0, u, v, _e);
      _tileLab(1, 0, u, v, _g);
      for (var c = 0; c < 3; c++) {
        final r = li[c] - _g[c];
        final tau = c == 0 ? maps.tauL : maps.tauC;
        final target = _e[c] + r / (1 + r.abs() / tau);
        o[c] += _mix * (target - li[c]);
      }
    }
    if (_unify) {
      _tileLab(0, 1, u, v, _u);
      o[0] +=
          _matte * (params.unify * (maps.medianL - _u[0]) + params.luminance);
      o[1] += _matte * params.unify * (maps.medianA - _u[1]);
      o[2] += _matte * params.unify * (maps.medianB - _u[2]);
    }
  }

  void _tileLab(int tx, int ty, double u, double v, Float64List out) {
    maps.sampleTile(tx, ty, u, v, _t, 0);
    linearToOklab(
      bandByteToLinear(_t[0]),
      bandByteToLinear(_t[1]),
      bandByteToLinear(_t[2]),
      out,
      0,
    );
  }
}
