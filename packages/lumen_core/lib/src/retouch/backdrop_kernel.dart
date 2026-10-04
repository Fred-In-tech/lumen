/// CPU twin of `backdropRetouch()` in `retouch.frag` (image scope): Clean
/// backdrop, stray hairs, Unify lighting, Luminance, clothing wrinkles and
/// lint (see `backdrop_maps.dart` for the atlas and the formulas).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'backdrop_maps.dart';
import 'backdrop_params.dart';
import 'clothes_maps.dart';
import 'lab_planes.dart';
import 'retouch_maps.dart' show decodeSigned;

class BackdropKernel {
  BackdropKernel(this.maps, this.params)
    : backdropOn = maps.isReady && !params.backdropIdentity,
      clothesOn = maps.clothesReady && !params.clothesIdentity;

  final BackdropMaps maps;
  final BackdropParams params;

  /// Backdrop / clothes effects run (maps ready and a value set).
  final bool backdropOn;
  final bool clothesOn;

  /// False when neither part runs.
  bool get active => backdropOn || clothesOn;

  final Float64List _t = Float64List(3);
  final Float64List _e = Float64List(3);
  final Float64List _g = Float64List(3);
  final Float64List _u = Float64List(3);
  final Float64List _fold = Float64List(3);
  final Float64List _lint = Float64List(3);
  double _mix = 0;
  double _matte = 0;
  bool _unify = false;
  bool _clothes = false;

  /// Samples the weights at source uv; true when a backdrop effect
  /// touches the pixel (then call [apply]).
  bool weights(double u, double v) {
    _mix = 0;
    _unify = false;
    _clothes = false;
    if (backdropOn) {
      maps.sampleTile(1, 1, u, v, _t, 0);
      final wc = params.clean * _t[0] / 255;
      final ws = params.strays * _t[2] / 255;
      _mix = math.max(wc, ws);
      _matte = _t[1] / 255;
      _unify = _matte > 0 && (params.unify > 0 || params.luminance != 0);
    }
    if (clothesOn) {
      maps.sampleTile(2, 0, u, v, _t, 0);
      for (var c = 0; c < 3; c++) {
        _fold[c] = decodeSigned(_t[c], kClothesFoldRange[c]);
      }
      maps.sampleTile(2, 1, u, v, _t, 0);
      for (var c = 0; c < 3; c++) {
        _lint[c] = decodeSigned(_t[c], kLintRange[c]);
      }
      _clothes =
          (params.clothesWrinkles > 0 && _nonZero(_fold)) ||
          (params.clothesLint > 0 && _nonZero(_lint));
    }
    return _mix > 0 || _unify || _clothes;
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
    if (_clothes) {
      for (var c = 0; c < 3; c++) {
        o[c] +=
            params.clothesLint * _lint[c] - params.clothesWrinkles * _fold[c];
      }
    }
  }

  /// Bilinear taps of four neutral (128) texels leave rounding residue;
  /// below [kClothesZero] a field counts as untouched (as on the GPU).
  static bool _nonZero(Float64List d) =>
      d[0].abs() > kClothesZero ||
      d[1].abs() > kClothesZero ||
      d[2].abs() > kClothesZero;

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
