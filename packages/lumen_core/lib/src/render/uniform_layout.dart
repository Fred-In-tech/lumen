import 'dart:math' as math;
import 'dart:typed_data';

import '../color/rgb.dart';
import '../color/white_balance.dart';
import '../model/develop_settings.dart';
import '../model/mask.dart';
import '../model/param_registry.dart';
import '../model/treatment.dart';
import 'engine_constants.dart';

/// Per-render context for [DevelopUniforms.pack] (sizes and analysis data).
class DevelopContext {
  const DevelopContext({
    required this.outWidth,
    required this.outHeight,
    this.tileX = 0,
    this.tileY = 0,
    this._fullWidth,
    this._fullHeight,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.auxWidth,
    required this.auxHeight,
    this.airlight = const Rgb(1, 1, 1),
    this.showClipping = false,
    this.maskWidth = 1,
    this.maskHeight = 1,
    this.warpWidth = 1,
    this.warpHeight = 1,
    this.warpRange = 0,
  });

  /// Size of the image this pass renders (a tile during export).
  final int outWidth;
  final int outHeight;

  /// Offset of this tile inside the full output (0, 0 for preview).
  final double tileX;
  final double tileY;
  final double? _fullWidth;
  final double? _fullHeight;

  /// Size of the full output frame (defaults to the pass size).
  double get fullWidth => _fullWidth ?? outWidth.toDouble();
  double get fullHeight => _fullHeight ?? outHeight.toDouble();

  final int sourceWidth;
  final int sourceHeight;
  final int auxWidth;
  final int auxHeight;

  /// Dehaze airlight in linear sRGB (from the aux maps).
  final Rgb airlight;

  /// Paint clipped highlights red and crushed shadows blue.
  final bool showClipping;

  /// Mask grid size (one atlas tile, see `MaskAtlases`).
  final int maskWidth;
  final int maskHeight;

  /// Warp field grid and packing range; range 0 = no warp (skipped).
  final int warpWidth;
  final int warpHeight;
  final double warpRange;
}

/// One uniform of `develop.frag`, in declaration order.
typedef UniformSlot = ({String name, int index, int length});

/// Float offsets into the packed develop uniforms (PLAN.md §1.6).
abstract final class DevelopIndex {
  static const outSize = 0;
  static const tile = 2;
  static const crop = 6;
  static const geom = 10;
  static const src = 14;
  static const wbExp = 18;
  static const local = 22;
  static const haze = 26;
  static const color = 30;
  static const hslHue = 34;
  static const hslSat = 42;
  static const hslLum = 50;
  static const gradeShadows = 58;
  static const gradeMidtones = 62;
  static const gradeHighlights = 66;
  static const gradeGlobal = 70;
  static const gradeParams = 74;
  static const bwMix = 78;
  static const vignette = 86;
  static const vignette2 = 90;

  /// `vec4 uMaskGrid`: mask grid w, h, active mask count, 0.
  static const maskGrid = 94;

  /// First of the 8 × 3 `vec4 uMask{i}A/B/C` (12 floats per mask, in
  /// [kLocalParams] order).
  static const masks = 98;

  static int mask(int i) => masks + 12 * i;

  /// `vec4 uWarpInfo`: warp grid w, h, range (uv), enabled (0/1).
  static const warpInfo = 194;
}

/// Packs [DevelopSettings] into the `develop.frag` float uniforms.
///
/// The CPU reference pipeline consumes the same packed floats, so every
/// slider → shader-unit mapping lives in exactly one place.
abstract final class DevelopUniforms {
  static final List<UniformSlot> table = List.unmodifiable(<UniformSlot>[
    (name: 'uOutSize', index: 0, length: 2),
    (name: 'uTile', index: 2, length: 4),
    (name: 'uCrop', index: 6, length: 4),
    (name: 'uGeom', index: 10, length: 4),
    (name: 'uSrc', index: 14, length: 4),
    (name: 'uWbExp', index: 18, length: 4),
    (name: 'uLocal', index: 22, length: 4),
    (name: 'uHaze', index: 26, length: 4),
    (name: 'uColor', index: 30, length: 4),
    (name: 'uHslHue0', index: 34, length: 4),
    (name: 'uHslHue1', index: 38, length: 4),
    (name: 'uHslSat0', index: 42, length: 4),
    (name: 'uHslSat1', index: 46, length: 4),
    (name: 'uHslLum0', index: 50, length: 4),
    (name: 'uHslLum1', index: 54, length: 4),
    (name: 'uGradeShadows', index: 58, length: 4),
    (name: 'uGradeMidtones', index: 62, length: 4),
    (name: 'uGradeHighlights', index: 66, length: 4),
    (name: 'uGradeGlobal', index: 70, length: 4),
    (name: 'uGradeParams', index: 74, length: 4),
    (name: 'uBwMix0', index: 78, length: 4),
    (name: 'uBwMix1', index: 82, length: 4),
    (name: 'uVignette', index: 86, length: 4),
    (name: 'uVignette2', index: 90, length: 4),
    (name: 'uMaskGrid', index: 94, length: 4),
    for (var i = 0; i < 8; i++) ...[
      (name: 'uMask${i}A', index: 98 + 12 * i, length: 4),
      (name: 'uMask${i}B', index: 102 + 12 * i, length: 4),
      (name: 'uMask${i}C', index: 106 + 12 * i, length: 4),
    ],
    (name: 'uWarpInfo', index: 194, length: 4),
  ]);

  static Float32List pack(DevelopSettings s, DevelopContext ctx) {
    final f = Float32List(kDevelopFloatCount);
    double v(ParamId id) => s.value(id);
    double n(ParamId id) => s.value(id) / 100;
    void put(int at, List<double> values) {
      for (var i = 0; i < values.length; i++) {
        f[at + i] = values[i];
      }
    }

    final g = s.geometry;
    put(DevelopIndex.outSize, [
      ctx.outWidth.toDouble(),
      ctx.outHeight.toDouble(),
    ]);
    put(DevelopIndex.tile, [
      ctx.tileX,
      ctx.tileY,
      ctx.fullWidth,
      ctx.fullHeight,
    ]);
    put(DevelopIndex.crop, [
      g.crop.left,
      g.crop.top,
      g.crop.right,
      g.crop.bottom,
    ]);
    put(DevelopIndex.geom, [
      g.angle * math.pi / 180,
      g.rotate90.toDouble(),
      g.flipH ? 1 : 0,
      g.flipV ? 1 : 0,
    ]);
    put(DevelopIndex.src, [
      ctx.sourceWidth.toDouble(),
      ctx.sourceHeight.toDouble(),
      ctx.auxWidth.toDouble(),
      ctx.auxHeight.toDouble(),
    ]);
    final wb = whiteBalanceGains(v(P.temp), v(P.tint));
    put(DevelopIndex.wbExp, [
      wb.r,
      wb.g,
      wb.b,
      math.pow(2, v(P.exposure)).toDouble(),
    ]);
    put(DevelopIndex.local, [
      n(P.highlights),
      n(P.shadows),
      n(P.clarity),
      n(P.texture),
    ]);
    put(DevelopIndex.haze, [
      n(P.dehaze),
      ctx.airlight.r,
      ctx.airlight.g,
      ctx.airlight.b,
    ]);
    final c = s.curves;
    final curvesActive =
        !(c.red.isIdentity && c.green.isIdentity && c.blue.isIdentity);
    put(DevelopIndex.color, [
      n(P.vibrance),
      n(P.saturation),
      s.treatment == Treatment.bw ? 1 : 0,
      curvesActive ? 1 : 0,
    ]);
    for (final band in HslBand.values) {
      f[DevelopIndex.hslHue + band.index] = n(P.hsl(band, HslChannel.hue));
      f[DevelopIndex.hslSat + band.index] = n(P.hsl(band, HslChannel.sat));
      f[DevelopIndex.hslLum + band.index] = n(P.hsl(band, HslChannel.lum));
      f[DevelopIndex.bwMix + band.index] = n(P.bw(band));
    }
    const zones = {
      GradeZone.shadows: DevelopIndex.gradeShadows,
      GradeZone.midtones: DevelopIndex.gradeMidtones,
      GradeZone.highlights: DevelopIndex.gradeHighlights,
      GradeZone.global: DevelopIndex.gradeGlobal,
    };
    for (final e in zones.entries) {
      final hue = v(P.grade(e.key, 'hue')) * math.pi / 180;
      final chroma = n(P.grade(e.key, 'sat')) * kGradeMaxChroma;
      put(e.value, [
        chroma * math.cos(hue),
        chroma * math.sin(hue),
        n(P.grade(e.key, 'lum')),
        0,
      ]);
    }
    put(DevelopIndex.gradeParams, [
      n(P.gradeBlending),
      n(P.gradeBalance),
      0,
      0,
    ]);
    put(DevelopIndex.vignette, [
      n(P.vignetteAmount),
      n(P.vignetteMidpoint),
      n(P.vignetteRoundness),
      n(P.vignetteFeather),
    ]);
    put(DevelopIndex.vignette2, [
      n(P.vignetteHighlights),
      ctx.fullWidth / ctx.fullHeight,
      ctx.showClipping ? 1 : 0,
      0,
    ]);
    _packMasks(f, s.masks, ctx);
    f
      ..[DevelopIndex.warpInfo] = ctx.warpWidth.toDouble()
      ..[DevelopIndex.warpInfo + 1] = ctx.warpHeight.toDouble()
      ..[DevelopIndex.warpInfo + 2] = ctx.warpRange
      ..[DevelopIndex.warpInfo + 3] = ctx.warpRange > 0 ? 1 : 0;
    return f;
  }

  /// Local adjustments in shader units: exposure in EV, the rest / 100.
  static void _packMasks(
    Float32List f,
    List<LocalMask> masks,
    DevelopContext ctx,
  ) {
    var active = false;
    final n = masks.length < kMaxRenderedMasks
        ? masks.length
        : kMaxRenderedMasks;
    for (var i = 0; i < n; i++) {
      final adj = masks[i].localAdjustments;
      if (adj.isEmpty) continue;
      active = true;
      for (var k = 0; k < kLocalParams.length; k++) {
        final id = kLocalParams[k];
        final v = adj[id] ?? 0;
        f[DevelopIndex.mask(i) + k] = id == P.exposure ? v : v / 100;
      }
    }
    f[DevelopIndex.maskGrid] = ctx.maskWidth.toDouble();
    f[DevelopIndex.maskGrid + 1] = ctx.maskHeight.toDouble();
    f[DevelopIndex.maskGrid + 2] = active ? n.toDouble() : 0;
  }
}
