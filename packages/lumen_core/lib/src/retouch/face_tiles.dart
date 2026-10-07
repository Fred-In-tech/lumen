/// Per-face analysis tiles: each face's retouch maps are built from its own
/// crop of the pixel source, sampled so the face gets about
/// [kTileTargetIod] pixels between the eyes (never more than the source
/// has), instead of from one downscaled frame where a small face in a
/// 45 MP photo got ~60 px.
///
/// A tile is a window of a *virtual grid*: the whole source scaled by the
/// tile's scale (`gridW × gridH`). Every per-face computation runs in that
/// grid's pixel coordinates, so normalized uv (`x / gridW`) stays source
/// uv: blemish anchors, the parsing planes and the Manual Tuning Pen need
/// no special case. The finished tiles are packed into one atlas
/// (`retouch_maps_builder.dart`); each face carries the affine transform
/// from source uv to atlas pixels ([RetouchFaceInfo.mapScaleX] …).
library;

import 'dart:math' as math;

import '../model/face_analysis.dart';
import '../render/rgba_buffer.dart';
import 'face_frame.dart';
import 'map_rect.dart';
import 'retouch_maps.dart' show kMaxRetouchFaces;

/// IOD (tile pixels) each face is analysed at, when the source has it.
const double kTileTargetIod = 224;

/// The tile reaches this far (IOD) beyond the work rect along the face
/// axis, toward the chin: the neck below the jaw (skin found there by the
/// parsing model gets the capped off-face treatment).
const double kTileNeckIod = 0.6;

/// All tiles of a photo together hold at most this many pixels; above it
/// every tile is scaled down by the same factor (group shots). Each atlas
/// pixel costs 44 bytes (one RGBA texture plus five double-width ones).
const int kTileBudgetPx = 3 * 1024 * 1024;

/// Width of an atlas shelf (the double-width textures are twice this).
const int kAtlasShelfPx = 4096;

/// Empty texels between atlas tiles (bilinear taps never cross faces).
const int kAtlasGutterPx = 2;

/// Where one face is analysed: [window] of a `gridW × gridH` virtual grid
/// (the source scaled by `gridW / sourceWidth`).
class FaceTilePlan {
  const FaceTilePlan({
    required this.slot,
    required this.faceId,
    required this.gridW,
    required this.gridH,
    required this.window,
  });

  final int slot;
  final String faceId;
  final int gridW;
  final int gridH;
  final MapRect window;

  int get width => window.w;
  int get height => window.h;

  /// Source uv of the window edges.
  double get u0 => window.x0 / gridW;
  double get v0 => window.y0 / gridH;
  double get u1 => window.x1 / gridW;
  double get v1 => window.y1 / gridH;

  @override
  String toString() =>
      'FaceTilePlan($slot $faceId grid ${gridW}x$gridH $window)';
}

/// Pixels of one planned tile (`plan.width × plan.height`), e.g. a crop of
/// the full-resolution original.
class FaceTileImage {
  FaceTileImage(this.plan, this.pixels) {
    if (pixels.width != plan.width || pixels.height != plan.height) {
      throw ArgumentError(
        'tile ${pixels.width}x${pixels.height} != '
        '${plan.width}x${plan.height}',
      );
    }
  }

  final FaceTilePlan plan;
  final RgbaBuffer pixels;
}

/// Tile plans for the first [kMaxRetouchFaces] faces of [analysis] on a
/// `sourceWidth × sourceHeight` pixel source, in slot order (faces without
/// a usable mesh are skipped). Each face gets `min(1, targetIod / IOD)` of
/// the source's resolution; when the tiles together exceed [budgetPx]
/// they are all scaled down by the same factor.
List<FaceTilePlan> planFaceTiles(
  FaceAnalysis analysis,
  int sourceWidth,
  int sourceHeight, {
  double targetIod = kTileTargetIod,
  int budgetPx = kTileBudgetPx,
}) {
  final slots = math.min(kMaxRetouchFaces, analysis.faces.length);
  final rects = <({int slot, String id, double iod, _Box box})>[];
  for (var k = 0; k < slots; k++) {
    final f = FaceFrame.tryCreate(
      analysis.faces[k],
      k,
      sourceWidth,
      sourceHeight,
    );
    if (f == null || f.rect.isEmpty) continue;
    rects.add((slot: k, id: f.faceId, iod: f.iod, box: _tileBox(f)));
  }
  if (rects.isEmpty) return const [];
  final scales = [for (final r in rects) math.min(1.0, targetIod / r.iod)];
  var area = 0.0;
  for (var i = 0; i < rects.length; i++) {
    area += rects[i].box.w * rects[i].box.h * scales[i] * scales[i];
  }
  final fit = area > budgetPx ? math.sqrt(budgetPx / area) : 1.0;
  return [
    for (var i = 0; i < rects.length; i++)
      _plan(rects[i], scales[i] * fit, sourceWidth, sourceHeight),
  ];
}

typedef _Box = ({double x0, double y0, double x1, double y1});

extension on _Box {
  double get w => x1 - x0;
  double get h => y1 - y0;
}

/// The work rect, grown along the face axis by [kTileNeckIod] (source px).
_Box _tileBox(FaceFrame f) {
  final r = f.rect;
  final dx = f.axis.x * kTileNeckIod * f.iod;
  final dy = f.axis.y * kTileNeckIod * f.iod;
  return (
    x0: math.min(r.x0.toDouble(), r.x0 + dx),
    y0: math.min(r.y0.toDouble(), r.y0 + dy),
    x1: math.max(r.x1.toDouble(), r.x1 + dx),
    y1: math.max(r.y1.toDouble(), r.y1 + dy),
  );
}

FaceTilePlan _plan(
  ({int slot, String id, double iod, _Box box}) r,
  double scale,
  int sw,
  int sh,
) {
  final gw = math.max(1, (sw * scale).round());
  final gh = math.max(1, (sh * scale).round());
  final kx = gw / sw, ky = gh / sh;
  final x0 = math.max(0, (r.box.x0 * kx).floor());
  final y0 = math.max(0, (r.box.y0 * ky).floor());
  final x1 = math.min(gw, (r.box.x1 * kx).ceil());
  final y1 = math.min(gh, (r.box.y1 * ky).ceil());
  return FaceTilePlan(
    slot: r.slot,
    faceId: r.id,
    gridW: gw,
    gridH: gh,
    window: MapRect(x0, y0, math.max(1, x1 - x0), math.max(1, y1 - y0)),
  );
}

/// [plan]'s window resampled from [src] (any size of the same photo): an
/// area average when the tile is smaller than the source footprint, else
/// bilinear.
RgbaBuffer resampleTile(RgbaBuffer src, FaceTilePlan plan) {
  final w = plan.width, h = plan.height, out = RgbaBuffer(w, h);
  if (plan.gridW == src.width && plan.gridH == src.height) {
    // Native size: the window itself.
    for (var y = 0; y < h; y++) {
      final o = src.offset(plan.window.x0, plan.window.y0 + y);
      out.data.setRange(y * w * 4, (y + 1) * w * 4, src.data, o);
    }
    return out;
  }
  final kx = src.width / plan.gridW, ky = src.height / plan.gridH;
  final nx = math.max(1, kx.ceil()), ny = math.max(1, ky.ceil());
  final acc = List<double>.filled(3, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      acc[0] = acc[1] = acc[2] = 0;
      // Footprint of the tile pixel in source px, sampled nx × ny times.
      final fx0 = (plan.window.x0 + x) * kx, fy0 = (plan.window.y0 + y) * ky;
      for (var j = 0; j < ny; j++) {
        final sy = fy0 + (j + 0.5) * ky / ny;
        for (var i = 0; i < nx; i++) {
          _bilinear(src, fx0 + (i + 0.5) * kx / nx, sy, acc);
        }
      }
      final c = nx * ny;
      out.setPixel(
        x,
        y,
        (acc[0] / c).round(),
        (acc[1] / c).round(),
        (acc[2] / c).round(),
      );
    }
  }
  return out;
}

/// Adds the bilinear RGB of [src] at continuous pixel `(px, py)` to [acc].
void _bilinear(RgbaBuffer src, double px, double py, List<double> acc) {
  final x = px - 0.5, y = py - 0.5;
  final xf = x.floorToDouble(), yf = y.floorToDouble();
  final fx = x - xf, fy = y - yf;
  int cx(int v) => v < 0 ? 0 : (v >= src.width ? src.width - 1 : v);
  int cy(int v) => v < 0 ? 0 : (v >= src.height ? src.height - 1 : v);
  final xa = cx(xf.toInt()), xb = cx(xf.toInt() + 1);
  final ya = cy(yf.toInt()), yb = cy(yf.toInt() + 1);
  final d = src.data;
  final o00 = src.offset(xa, ya), o10 = src.offset(xb, ya);
  final o01 = src.offset(xa, yb), o11 = src.offset(xb, yb);
  for (var c = 0; c < 3; c++) {
    acc[c] +=
        (d[o00 + c] * (1 - fx) + d[o10 + c] * fx) * (1 - fy) +
        (d[o01 + c] * (1 - fx) + d[o11 + c] * fx) * fy;
  }
}

/// Shelf packing of tiles of the given sizes into one atlas, with
/// [kAtlasGutterPx] between tiles and around the edge: the origin of each
/// tile (same order) and the atlas size.
({List<({int x, int y})> origins, int width, int height}) packAtlas(
  List<({int w, int h})> sizes,
) {
  const g = kAtlasGutterPx;
  final order = List.generate(sizes.length, (i) => i)
    ..sort((a, b) => sizes[b].h.compareTo(sizes[a].h));
  final origins = List<({int x, int y})>.filled(sizes.length, (x: 0, y: 0));
  var x = g, y = g, shelfH = 0, width = 1;
  for (final i in order) {
    final s = sizes[i];
    if (x > g && x + s.w + g > kAtlasShelfPx) {
      y += shelfH + g;
      x = g;
      shelfH = 0;
    }
    origins[i] = (x: x, y: y);
    x += s.w + g;
    shelfH = math.max(shelfH, s.h);
    width = math.max(width, x);
  }
  return (origins: origins, width: width, height: y + shelfH + g);
}
