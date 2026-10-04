/// Mask coverage rasterization (pure Dart, deterministic).
///
/// Every mask is rendered to an 8-bit coverage grid in source-uv space
/// (≤ [kMaskLongEdge] px, same aspect as the source): shape (linear, radial,
/// AI raster; none for brush) → brush strokes add/erase → invert → ×
/// opacity. Up to 8 masks are packed into two RGBA atlases (see
/// [MaskAtlases.atlasRgba]); CPU and GPU sample the same bytes.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/mask.dart';
import 'engine_constants.dart';

/// A decoded 8-bit AI mask (row-major coverage, 0 = none, 255 = full).
class MaskRaster {
  MaskRaster(this.width, this.height, this.data) {
    if (data.length != width * height) {
      throw ArgumentError('raster ${data.length} != $width x $height');
    }
  }

  final int width;
  final int height;
  final Uint8List data;
}

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Coverage of every rendered mask, plus atlas packing and sampling.
class MaskAtlases {
  MaskAtlases._(this.width, this.height, this.coverage);

  /// No masks: a 1×1 grid (the engine binds 1×1 empty atlases).
  factory MaskAtlases.empty() => MaskAtlases._(1, 1, const []);

  /// Mask grid size (one atlas tile).
  final int width;
  final int height;

  /// Per-mask coverage, `width * height` bytes each, at most 8.
  final List<Uint8List> coverage;

  int get count => coverage.length;

  /// Atlas [k] (0 or 1) as RGBA8888 of size `(2 * width) × height`: the left
  /// tile holds masks `4k..4k+2` in R, G, B; the right tile holds mask
  /// `4k+3` in R. Alpha is always 255 (never packed, so premultiplication
  /// cannot corrupt it).
  Uint8List atlasRgba(int k) {
    final out = Uint8List(2 * width * height * 4);
    for (var i = 3; i < out.length; i += 4) {
      out[i] = 255;
    }
    for (var slot = 0; slot < 4; slot++) {
      final m = 4 * k + slot;
      if (m >= count) break;
      final c = coverage[m];
      final xOff = slot < 3 ? 0 : width;
      final ch = slot < 3 ? slot : 0;
      for (var y = 0; y < height; y++) {
        var o = ((y * 2 * width) + xOff) * 4 + ch;
        var s = y * width;
        for (var x = 0; x < width; x++, o += 4, s++) {
          out[o] = c[s];
        }
      }
    }
    return out;
  }

  /// Bilinear coverage (0..1) of [mask] at uv over texel centers, exactly
  /// like `sampleMasks()` in `develop.frag`.
  double sample(int mask, double u, double v) {
    if (mask >= count) return 0;
    final px = u * width - 0.5, py = v * height - 0.5;
    final fx0 = px.floorToDouble(), fy0 = py.floorToDouble();
    final fx = px - fx0, fy = py - fy0;
    final x0 = fx0.toInt().clamp(0, width - 1);
    final x1 = (fx0.toInt() + 1).clamp(0, width - 1);
    final y0 = fy0.toInt().clamp(0, height - 1);
    final y1 = (fy0.toInt() + 1).clamp(0, height - 1);
    final c = coverage[mask];
    final top =
        c[y0 * width + x0] + (c[y0 * width + x1] - c[y0 * width + x0]) * fx;
    final bot =
        c[y1 * width + x0] + (c[y1 * width + x1] - c[y1 * width + x0]) * fx;
    return (top + (bot - top) * fy) / 255;
  }

  /// Samples every mask into [out] (length ≥ 8; unused slots get 0).
  void sampleAll(double u, double v, Float64List out) {
    for (var m = 0; m < kMaxRenderedMasks; m++) {
      out[m] = m < count ? sample(m, u, v) : 0;
    }
  }
}

abstract final class MaskRasterizer {
  /// Mask grid size for a source: long edge ≤ [longEdge], never upscaled.
  static ({int width, int height}) gridSize(
    int srcWidth,
    int srcHeight, {
    int longEdge = kMaskLongEdge,
  }) {
    final le = math.max(srcWidth, srcHeight);
    if (le <= longEdge) return (width: srcWidth, height: srcHeight);
    final s = longEdge / le;
    return (
      width: math.max(1, (srcWidth * s).round()),
      height: math.max(1, (srcHeight * s).round()),
    );
  }

  /// Rasterizes the first 8 [masks] for a [srcWidth]×[srcHeight] source.
  /// AI masks read their raster from [rasters] by `ai.maskRef` (missing
  /// rasters cover nothing).
  static MaskAtlases build(
    List<LocalMask> masks,
    int srcWidth,
    int srcHeight, {
    Map<String, MaskRaster> rasters = const {},
    int longEdge = kMaskLongEdge,
  }) {
    if (masks.isEmpty) return MaskAtlases.empty();
    final g = gridSize(srcWidth, srcHeight, longEdge: longEdge);
    return MaskAtlases._(
      g.width,
      g.height,
      List.unmodifiable([
        for (final m in masks.take(kMaxRenderedMasks))
          rasterize(
            m,
            g.width,
            g.height,
            raster: m.kind.isAi ? rasters[m.ai.maskRef] : null,
          ),
      ]),
    );
  }

  /// Coverage of one mask on a [w]×[h] grid (bytes 0..255).
  static Uint8List rasterize(LocalMask m, int w, int h, {MaskRaster? raster}) {
    // Unsupported (newer-version) masks are inert: no coverage at all.
    if (!m.isSupported) return Uint8List(w * h);
    final c = Float32List(w * h);
    switch (m.kind) {
      case MaskKind.linear:
        _linear(m.linear, c, w, h);
      case MaskKind.radial:
        _radial(m.radial, c, w, h);
      case MaskKind.brush || MaskKind.unsupported:
        break;
      case MaskKind.subject ||
          MaskKind.sky ||
          MaskKind.background ||
          MaskKind.person ||
          MaskKind.faceSkin:
        if (raster != null) _resample(raster, c, w, h);
    }
    for (final s in m.strokes) {
      _stroke(s, c, w, h);
    }
    final out = Uint8List(w * h);
    for (var i = 0; i < c.length; i++) {
      final v = m.invert ? 1 - c[i] : c[i];
      out[i] = (v.clamp(0.0, 1.0) * m.opacity * 255).round();
    }
    return out;
  }

  static void _linear(LinearShape s, Float32List c, int w, int h) {
    final le = math.max(w, h).toDouble();
    final ax = w / le, ay = h / le;
    final dx = (s.x1 - s.x0) * ax, dy = (s.y1 - s.y0) * ay;
    final len2 = dx * dx + dy * dy;
    for (var y = 0; y < h; y++) {
      final py = ((y + 0.5) / h - s.y0) * ay;
      for (var x = 0; x < w; x++) {
        final px = ((x + 0.5) / w - s.x0) * ax;
        final t = len2 < 1e-12 ? 0.0 : (px * dx + py * dy) / len2;
        c[y * w + x] = 1 - t.clamp(0.0, 1.0);
      }
    }
  }

  static void _radial(RadialShape s, Float32List c, int w, int h) {
    final rx = math.max(s.rx * w, 1e-6), ry = math.max(s.ry * h, 1e-6);
    final a = s.angle * math.pi / 180;
    final ca = math.cos(a), sa = math.sin(a);
    final f = s.feather;
    for (var y = 0; y < h; y++) {
      final py = y + 0.5 - s.cy * h;
      for (var x = 0; x < w; x++) {
        final px = x + 0.5 - s.cx * w;
        final qx = (px * ca + py * sa) / rx;
        final qy = (-px * sa + py * ca) / ry;
        final e = math.sqrt(qx * qx + qy * qy);
        final v = f > 0 ? 1 - _smoothstep(1 - f, 1, e) : (e <= 1 ? 1.0 : 0.0);
        c[y * w + x] = s.inverted ? 1 - v : v;
      }
    }
  }

  static void _resample(MaskRaster r, Float32List c, int w, int h) {
    for (var y = 0; y < h; y++) {
      final py = (y + 0.5) / h * r.height - 0.5;
      final y0f = py.floorToDouble();
      final fy = py - y0f;
      final y0 = y0f.toInt().clamp(0, r.height - 1);
      final y1 = (y0f.toInt() + 1).clamp(0, r.height - 1);
      for (var x = 0; x < w; x++) {
        final px = (x + 0.5) / w * r.width - 0.5;
        final x0f = px.floorToDouble();
        final fx = px - x0f;
        final x0 = x0f.toInt().clamp(0, r.width - 1);
        final x1 = (x0f.toInt() + 1).clamp(0, r.width - 1);
        final d = r.data;
        final top =
            d[y0 * r.width + x0] +
            (d[y0 * r.width + x1] - d[y0 * r.width + x0]) * fx;
        final bot =
            d[y1 * r.width + x0] +
            (d[y1 * r.width + x1] - d[y1 * r.width + x0]) * fx;
        c[y * w + x] = (top + (bot - top) * fy) / 255;
      }
    }
  }

  /// Paints one stroke: S = flow × max over segments of the brush falloff;
  /// add: c += (1 − c)·S, erase: c *= 1 − S.
  static void _stroke(BrushStroke s, Float32List c, int w, int h) {
    if (s.points.isEmpty || s.flow <= 0) return;
    final le = math.max(w, h).toDouble();
    final r = s.radius * le; // pixels
    final strength = Float32List(w * h);
    final pts = [for (final p in s.points) (p.$1 * w, p.$2 * h)];
    final segs = pts.length == 1
        ? [(pts[0], pts[0])]
        : [for (var i = 0; i + 1 < pts.length; i++) (pts[i], pts[i + 1])];
    for (final ((ax, ay), (bx, by)) in segs) {
      final x0 = math.max(0, (math.min(ax, bx) - r).floor());
      final x1 = math.min(w - 1, (math.max(ax, bx) + r).ceil());
      final y0 = math.max(0, (math.min(ay, by) - r).floor());
      final y1 = math.min(h - 1, (math.max(ay, by) + r).ceil());
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          final px = x + 0.5 - ax, py = y + 0.5 - ay;
          final t = len2 == 0
              ? 0.0
              : ((px * dx + py * dy) / len2).clamp(0.0, 1.0);
          final ex = px - t * dx, ey = py - t * dy;
          final v = _falloff(math.sqrt(ex * ex + ey * ey) / r, s.hardness);
          final i = y * w + x;
          if (v > strength[i]) strength[i] = v;
        }
      }
    }
    for (var i = 0; i < c.length; i++) {
      final k = strength[i] * s.flow;
      if (k == 0) continue;
      c[i] = s.erase ? c[i] * (1 - k) : c[i] + (1 - c[i]) * k;
    }
  }

  static double _falloff(double t, double hardness) {
    if (t >= 1) return 0;
    if (t <= hardness) return 1;
    return 1 - _smoothstep(hardness, 1, t);
  }
}
