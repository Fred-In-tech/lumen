/// Per-photo backdrop analysis: the subject matte (person ∪ hair raster,
/// refined against the photo) and the old background with the subject
/// filled in. Pure data, isolate-safe; rebuild only when the photo or its
/// rasters change.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../color/rgb.dart';
import '../render/aux_maps.dart';
import '../render/mask_rasterizer.dart';
import '../render/rgba_buffer.dart';
import '../vision/guided_filter.dart';
import 'backdrop_filters.dart';

/// Matte grid long edge (hair needs resolution).
const int kBackdropMatteLongEdge = 1536;

/// Low-resolution plates (fill, blur) long edge.
const int kBackdropPlateLongEdge = 640;

class BackdropBase {
  BackdropBase._({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.matteWidth,
    required this.matteHeight,
    required this.raw,
    required this.alpha,
    required this.plateWidth,
    required this.plateHeight,
    required this.fillR,
    required this.fillG,
    required this.fillB,
    required this.oldBackgroundMean,
    required this.analysisProxy,
  }) : fill = (
         width: plateWidth,
         height: plateHeight,
         rgba: encodePlanes(fillR, fillG, fillB),
       );

  /// Builds the matte from [people] ∪ [hair] (any resolution; null = none)
  /// refined with a guided filter against [src]'s luma, and the subject
  /// filled with the surrounding background (push-pull).
  factory BackdropBase.build(
    RgbaBuffer src, {
    MaskRaster? people,
    MaskRaster? hair,
  }) {
    final m = MaskRasterizer.gridSize(
      src.width,
      src.height,
      longEdge: kBackdropMatteLongEdge,
    );
    final mw = m.width, mh = m.height, n = mw * mh;
    final raw = Float32List(n);
    if (people != null || hair != null) {
      for (var y = 0; y < mh; y++) {
        for (var x = 0; x < mw; x++) {
          final u = (x + 0.5) / mw, v = (y + 0.5) / mh;
          raw[y * mw + x] = math.max(
            _raster(people, u, v),
            _raster(hair, u, v),
          );
        }
      }
    }
    final alpha = people == null && hair == null
        ? Float32List(n)
        : _refine(src, raw, mw, mh);
    // Plates: the photo downscaled, background weights, push-pull fill.
    final proxy = AuxMaps.proxy(src, longEdge: kBackdropPlateLongEdge);
    final pw = proxy.width, ph = proxy.height;
    final (r, g, b) = linearPlanes(proxy);
    final w = Float32List(pw * ph);
    var sw = 0.0, sr = 0.0, sg = 0.0, sb = 0.0;
    for (var y = 0; y < ph; y++) {
      for (var x = 0; x < pw; x++) {
        // Any subject coverage in the plate cell excludes it (no bleed).
        final a = _cellMax(alpha, mw, mh, x, y, pw, ph);
        final q = 1 - _smoothstep(0, 0.1, a), i = y * pw + x;
        w[i] = q;
        sw += q;
        sr += r[i] * q;
        sg += g[i] * q;
        sb += b[i] * q;
      }
    }
    final (fr, fg, fb) = pushPullFill(r, g, b, w, pw, ph);
    return BackdropBase._(
      sourceWidth: src.width,
      sourceHeight: src.height,
      matteWidth: mw,
      matteHeight: mh,
      raw: raw,
      alpha: alpha,
      plateWidth: pw,
      plateHeight: ph,
      fillR: fr,
      fillG: fg,
      fillB: fb,
      oldBackgroundMean: sw > 0
          ? Rgb(sr / sw, sg / sw, sb / sw)
          : const Rgb(0.5, 0.5, 0.5),
      analysisProxy: AuxMaps.proxy(src),
    );
  }

  final int sourceWidth;
  final int sourceHeight;
  final int matteWidth;
  final int matteHeight;

  /// Union of the rasters on the matte grid, before refinement.
  final Float32List raw;

  /// Refined coverage 0..1 on the matte grid.
  final Float32List alpha;
  final int plateWidth;
  final int plateHeight;

  /// Old background (linear) with the subject filled in, on the plate grid.
  final Float32List fillR;
  final Float32List fillG;
  final Float32List fillB;

  /// [fillR]/[fillG]/[fillB] as an sRGB texture (`fill` of the assets).
  final ByteTexture fill;

  /// Mean old background colour (linear), for spill removal.
  final Rgb oldBackgroundMean;

  /// The photo at the develop analysis size (`AuxMaps.proxy`), for the aux
  /// maps of the composite ([backdropAuxMaps]).
  final RgbaBuffer analysisProxy;

  /// Refined coverage at source pixel ([x], [y]) (bilinear).
  double alphaAt(int x, int y) => _at(alpha, x, y);

  /// Raster union at source pixel ([x], [y]) (bilinear), for diagnostics.
  double rawAlphaAt(int x, int y) => _at(raw, x, y);

  double _at(Float32List p, int x, int y) {
    final u = (x + 0.5) / sourceWidth, v = (y + 0.5) / sourceHeight;
    final px = (u * matteWidth - 0.5).clamp(0.0, matteWidth - 1.0);
    final py = (v * matteHeight - 0.5).clamp(0.0, matteHeight - 1.0);
    final x0 = px.floor(), y0 = py.floor();
    final x1 = math.min(x0 + 1, matteWidth - 1);
    final y1 = math.min(y0 + 1, matteHeight - 1);
    final fx = px - x0, fy = py - y0;
    final top =
        p[y0 * matteWidth + x0] * (1 - fx) + p[y0 * matteWidth + x1] * fx;
    final bot =
        p[y1 * matteWidth + x0] * (1 - fx) + p[y1 * matteWidth + x1] * fx;
    return top * (1 - fy) + bot * fy;
  }

  static double _raster(MaskRaster? r, double u, double v) {
    if (r == null) return 0;
    final px = (u * r.width - 0.5).clamp(0.0, r.width - 1.0);
    final py = (v * r.height - 0.5).clamp(0.0, r.height - 1.0);
    final x0 = px.floor(), y0 = py.floor();
    final x1 = math.min(x0 + 1, r.width - 1),
        y1 = math.min(y0 + 1, r.height - 1);
    final fx = px - x0, fy = py - y0, d = r.data;
    final top = d[y0 * r.width + x0] * (1 - fx) + d[y0 * r.width + x1] * fx;
    final bot = d[y1 * r.width + x0] * (1 - fx) + d[y1 * r.width + x1] * fx;
    return (top * (1 - fy) + bot * fy) / 255;
  }

  /// Guided filter against the photo's luma, then a contrast cleanup that
  /// removes the filter's low-amplitude tails (keeps soft hair edges).
  static Float32List _refine(RgbaBuffer src, Float32List raw, int w, int h) {
    final guide = lumaPlane(src, width: w, height: h);
    final r = math.max(2, (math.max(w, h) / 256).round());
    final q = guidedFilterPlanes(guide, [raw], w, h, radius: r, eps: 1e-3)[0];
    for (var i = 0; i < q.length; i++) {
      q[i] = _smoothstep(0.08, 0.92, q[i]);
    }
    return q;
  }

  static double _cellMax(
    Float32List a,
    int mw,
    int mh,
    int x,
    int y,
    int pw,
    int ph,
  ) {
    final x0 = x * mw ~/ pw, x1 = math.max(x0 + 1, (x + 1) * mw ~/ pw);
    final y0 = y * mh ~/ ph, y1 = math.max(y0 + 1, (y + 1) * mh ~/ ph);
    var m = 0.0;
    for (var yy = y0; yy < math.min(y1, mh); yy++) {
      for (var xx = x0; xx < math.min(x1, mw); xx++) {
        m = math.max(m, a[yy * mw + xx]);
      }
    }
    return m;
  }
}

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}
