/// Backdrop analysis texture (image scope), CPU-built by
/// `computeBackdropMaps` and sampled in source uv by `applyRetouch` and
/// `retouch.frag` (sampler `uBackdropMap`).
///
/// One 3W×2H RGBA atlas (A = 255), manual 4-tap bilinear at texel centres
/// like the face maps; each tile clamps to its own W×H:
///
/// | tile (x, y) | R | G | B |
/// |---|---|---|---|
/// | (0, 0) | E: clean backdrop estimate, sRGB (dithered) | | |
/// | (1, 0) | G: image low-pass (σ = 1 texel), sRGB (dithered) | | |
/// | (0, 1) | U: illumination field, sRGB (dithered) | | |
/// | (1, 1) | clean weight (matte − guard band) | Unify matte (contrast-shaped) | stray-hair weight |
/// | (2, 0) | clothes fold field D, signed L | a | b (`kClothesFoldRange`) |
/// | (2, 1) | lint fill Δ, signed L | a | b (`kLintRange`) |
///
/// Clean target `T = E + r / (1 + |r| / τ)` with `r = I − G` (OkLab), so
/// coarse defects and banding go and grain below τ stays. Unify adds
/// `matte · (unify · (median − U) + (luminance, 0, 0))`. Clothes add
/// `−wrinkles · D + lint · Δ` (`clothes_maps.dart`). Signed tiles decode
/// like the heal deltas: `(byte − 128) / 127 · range`, 128 = 0.
library;

import 'dart:typed_data';

/// Why backdrop effects are (not) available, for the UI.
enum BackdropState {
  ready,
  notRequested,
  noMatte,
  tooLittleBackdrop,
  notSolid;

  /// A message for disabled backdrop sliders, or null when [ready].
  String? get reason => switch (this) {
    ready => null,
    notRequested => null,
    noMatte => 'Backdrop cleanup needs the on-device person mask.',
    tooLittleBackdrop => 'Too little backdrop is visible to clean.',
    notSolid =>
      'Backdrop cleanup works on plain studio backdrops; this one is '
          'textured or patterned.',
  };
}

/// Why clothes effects are (not) available, for the UI.
enum ClothesState {
  ready,
  notRequested,
  noMatte,
  noClothes;

  /// A message for disabled clothes sliders, or null when [ready].
  String? get reason => switch (this) {
    ready => null,
    notRequested => null,
    noMatte => 'Clothing cleanup needs the on-device clothes mask.',
    noClothes => 'No clothing was found in this photo.',
  };
}

/// Floats of [BackdropMaps.packInfo].
const int kBackdropInfoFloats = 8;

/// Atlas tiles per row / column.
const int kImageAtlasColumns = 3;
const int kImageAtlasRows = 2;

class BackdropMaps {
  BackdropMaps({
    required this.width,
    required this.height,
    required this.atlas,
    required this.state,
    this.clothesState = ClothesState.notRequested,
    this.medianL = 0,
    this.medianA = 0,
    this.medianB = 0,
    this.tauL = 0.01,
    this.tauC = 0.005,
    this.textureMad = 0,
  }) {
    final n = 4 * kImageAtlasColumns * kImageAtlasRows * width * height;
    if (atlas.length != n) {
      throw ArgumentError('atlas ${atlas.length} != $n');
    }
  }

  /// 1×1 neutral tiles (zero weights and deltas) with [state].
  factory BackdropMaps.none(
    BackdropState state, {
    ClothesState clothes = ClothesState.notRequested,
  }) => BackdropMaps(
    width: 1,
    height: 1,
    atlas: Uint8List.fromList([
      ...[0, 0, 0, 255, 0, 0, 0, 255, 128, 128, 128, 255], // row 0
      ...[0, 0, 0, 255, 0, 0, 0, 255, 128, 128, 128, 255], // row 1
    ]),
    state: state,
    clothesState: clothes,
  );

  /// Size of one tile.
  final int width;
  final int height;

  /// 3W×2H RGBA.
  final Uint8List atlas;
  final BackdropState state;
  final ClothesState clothesState;

  /// Median backdrop OkLab colour (the Unify target).
  final double medianL;
  final double medianA;
  final double medianB;

  /// Grain soft-clip levels (OkLab L and a/b).
  final double tauL;
  final double tauC;

  /// Robust texture level that decided [state] (diagnostics).
  final double textureMad;

  bool get isReady => state == BackdropState.ready;

  /// Clothes effects can run.
  bool get clothesReady => clothesState == ClothesState.ready;

  /// Bilinear RGB of tile ([tx], [ty]) at uv, in byte units, into
  /// `out[o..o+2]`. Mirrors the shader's taps.
  void sampleTile(int tx, int ty, double u, double v, List<double> out, int o) {
    final w = width, h = height, stride = kImageAtlasColumns * w;
    final px = u * w - 0.5, py = v * h - 0.5;
    final fx0 = px.floorToDouble(), fy0 = py.floorToDouble();
    final fx = px - fx0, fy = py - fy0;
    final ix = fx0.toInt(), iy = fy0.toInt();
    final xa = _ci(ix, w) + tx * w, xb = _ci(ix + 1, w) + tx * w;
    final ya = _ci(iy, h) + ty * h, yb = _ci(iy + 1, h) + ty * h;
    final o00 = (ya * stride + xa) * 4, o10 = (ya * stride + xb) * 4;
    final o01 = (yb * stride + xa) * 4, o11 = (yb * stride + xb) * 4;
    final w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy);
    final w01 = (1 - fx) * fy, w11 = fx * fy;
    final t = atlas;
    for (var c = 0; c < 3; c++) {
      out[o + c] =
          t[o00 + c] * w00 +
          t[o10 + c] * w10 +
          t[o01 + c] * w01 +
          t[o11 + c] * w11;
    }
  }

  static int _ci(int i, int size) => i < 0 ? 0 : (i >= size ? size - 1 : i);

  /// `uBackdropInfo0` = (W, H, ready 0/1, τL),
  /// `uBackdropInfo1` = (median L, a, b, τC).
  Float32List packInfo() => Float32List.fromList([
    width.toDouble(),
    height.toDouble(),
    isReady ? 1 : 0,
    tauL,
    medianL,
    medianA,
    medianB,
    tauC,
  ]);
}
