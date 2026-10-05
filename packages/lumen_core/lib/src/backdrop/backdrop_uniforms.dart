/// Uniforms of the backdrop composite pass `B` (`app/shaders/backdrop.frag`
/// and [applyBackdrop]), 46 floats:
///
/// | floats | uniform | contents |
/// |---|---|---|
/// | 0–1 | `uSize` | pass size (px) |
/// | 2–5 | `uTile` | pass offset in the source, full source w, h |
/// | 6–9 | `uMatte` | matte w, h, mode (1 blur, 2 colour, 3 gradient, 4 image), letterbox |
/// | 10–13 | `uFill` | fill w, h, plate A w, h |
/// | 14–17 | `uPlateB` | plate B w, h, source is the pass window (0/1), 0 |
/// | 18–21 | `uColorA` | colour (sRGB-encoded 0..1), 0 |
/// | 22–25 | `uColorB` | colour 2 |
/// | 26–29 | `uGrad` | direction x, y, frame aspect, extent |
/// | 30–33 | `uFit` | plate uv scale x, y, 0, 0 |
/// | 34–37 | `uSpill` | amount 0..1, old-backdrop chroma direction (linear) |
/// | 38–41 | `uSpill2` | new-background chroma direction, 0 |
/// | 42–45 | `uMatch` | amount 0..1, brightness gain, 0, 0 |
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../color/rgb.dart';
import '../color/srgb.dart';
import '../model/backdrop_change.dart';
import 'backdrop_assets.dart';

const int kBackdropFloatCount = 46;

abstract final class BackdropUniforms {
  static int modeIndex(BackdropMode m) => switch (m) {
    BackdropMode.none => 0,
    BackdropMode.blur => 1,
    BackdropMode.color => 2,
    BackdropMode.gradient => 3,
    BackdropMode.image => 4,
  };

  static Float32List pack(
    BackdropAssets a,
    BackdropChange b, {
    required int width,
    required int height,
    double tileX = 0,
    double tileY = 0,
    double? fullWidth,
    double? fullHeight,
    bool sourceIsWindow = false,
  }) {
    final fw = fullWidth ?? width.toDouble(),
        fh = fullHeight ?? height.toDouble();
    final f = Float32List(kBackdropFloatCount);
    void put(int at, List<double> v) => f.setRange(at, at + v.length, v);
    put(0, [width.toDouble(), height.toDouble(), tileX, tileY, fw, fh]);
    final image = b.mode == BackdropMode.image;
    put(6, [
      a.matte.width.toDouble(),
      a.matte.height.toDouble(),
      modeIndex(b.isNone ? BackdropMode.none : b.mode).toDouble(),
      image && b.fit == BackdropFit.fit ? 1 : 0,
    ]);
    put(10, [
      a.fill.width.toDouble(),
      a.fill.height.toDouble(),
      a.plateA.width.toDouble(),
      a.plateA.height.toDouble(),
    ]);
    // z: the source texture holds exactly the pass rectangle (a window of
    // the full source, float export) instead of the whole source.
    put(14, [
      a.plateB.width.toDouble(),
      a.plateB.height.toDouble(),
      sourceIsWindow ? 1 : 0,
    ]);
    put(18, _encoded(b.color));
    put(22, _encoded(b.color2));
    final t = b.angle * math.pi / 180, aspect = fw / fh;
    final dx = math.cos(t), dy = math.sin(t);
    put(26, [dx, dy, aspect, 0.5 * (dx.abs() * aspect + dy.abs())]);
    put(30, _fit(b.fit, a.plateA.width / a.plateA.height, aspect));
    final old = a.base.oldBackgroundMean, now = newBackgroundMean(a, b);
    put(34, [b.spill / 100, ..._chromaDir(old)]);
    put(38, _chromaDir(now));
    final yOld = _luma(old), yNew = _luma(now);
    put(42, [
      b.match / 100,
      math.sqrt(yNew / math.max(yOld, 1e-4)).clamp(0.7, 1.4),
    ]);
    return f;
  }

  /// Mean new background colour (linear): spill target, brightness match.
  static Rgb newBackgroundMean(BackdropAssets a, BackdropChange b) {
    switch (b.mode) {
      case BackdropMode.color:
        return _linear(b.color);
      case BackdropMode.gradient:
        final c1 = _linear(b.color), c2 = _linear(b.color2);
        return Rgb((c1.r + c2.r) / 2, (c1.g + c2.g) / 2, (c1.b + c2.b) / 2);
      case BackdropMode.image:
      case BackdropMode.blur:
      case BackdropMode.none:
        return a.plateMean;
    }
  }

  static Rgb _linear(int c) => Rgb(
    srgbToLinear(((c >> 16) & 0xff) / 255),
    srgbToLinear(((c >> 8) & 0xff) / 255),
    srgbToLinear((c & 0xff) / 255),
  );

  static List<double> _encoded(int c) => [
    ((c >> 16) & 0xff) / 255,
    ((c >> 8) & 0xff) / 255,
    (c & 0xff) / 255,
  ];

  /// Plate-uv scale about the centre: fill covers, fit contains, stretch.
  static List<double> _fit(
    BackdropFit fit,
    double plate,
    double frame,
  ) => switch (fit) {
    BackdropFit.stretch => [1, 1],
    BackdropFit.fill => plate > frame ? [frame / plate, 1] : [1, plate / frame],
    BackdropFit.fit => plate > frame ? [1, plate / frame] : [frame / plate, 1],
  };

  static double _luma(Rgb c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

  /// Unit chroma direction (colour minus its luminance); 0 for greys.
  static List<double> _chromaDir(Rgb c) {
    final y = _luma(c);
    final x = c.r - y, yy = c.g - y, z = c.b - y;
    final n = math.sqrt(x * x + yy * yy + z * z);
    return n < 1e-4 ? [0, 0, 0] : [x / n, yy / n, z / n];
  }
}
