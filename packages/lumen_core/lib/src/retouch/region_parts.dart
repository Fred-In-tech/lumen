/// Building blocks of [buildFaceRegions]: sub-rect rasterization so small
/// features (eyes, mouth) never cost a full-rect plane, plus the eye and
/// mouth maps of research 07 §2.3.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'face_frame.dart';
import 'face_mesh.dart';
import 'filters.dart';
import 'lab_planes.dart';
import 'map_rect.dart';
import 'polygon_raster.dart';

const double kEyeRegionFeatherIod = 0.006;
const double kScleraErodeIod = 0.005;
const double kIrisDiscScale = 1.05;
const double kPupilScale = 0.35;
const double kMouthErodeIod = 0.01;

/// Lips need a* above the skin mean by this much (soft band to 3×).
const double kLipRedness = 0.01;

/// Bounding rect of [pts] grown by [pad] pixels, clipped to [rect].
MapRect boxOf(List<MapPoint> pts, double pad, MapRect rect) {
  var x0 = double.infinity, y0 = double.infinity;
  var x1 = -double.infinity, y1 = -double.infinity;
  for (final p in pts) {
    x0 = math.min(x0, p.x);
    y0 = math.min(y0, p.y);
    x1 = math.max(x1, p.x);
    y1 = math.max(y1, p.y);
  }
  final a = math.max(rect.x0, (x0 - pad).floor());
  final b = math.max(rect.y0, (y0 - pad).floor());
  final c = math.min(rect.x1, (x1 + pad).ceil());
  final d = math.min(rect.y1, (y1 + pad).ceil());
  return MapRect(a, b, math.max(0, c - a), math.max(0, d - b));
}

/// Writes `max(dst, src)` for the [sub] plane [src] into [dst] (covering
/// [rect]).
void paintMax(Float32List dst, MapRect rect, Float32List src, MapRect sub) {
  for (var y = sub.y0; y < sub.y1; y++) {
    var i = rect.index(sub.x0, y);
    var j = (y - sub.y0) * sub.w;
    for (var x = 0; x < sub.w; x++, i++, j++) {
      if (src[j] > dst[i]) dst[i] = src[j];
    }
  }
}

/// A [rect]-sized plane holding the [sub] plane [src] (zeros elsewhere).
Float32List pasted(MapRect rect, Float32List src, MapRect sub) {
  final out = Float32List(rect.area);
  paintMax(out, rect, src, sub);
  return out;
}

/// Copies the [sub] part of a plane covering [rect].
Float32List cropPlane(Float32List p, MapRect rect, MapRect sub) {
  final out = Float32List(sub.area);
  for (var y = sub.y0; y < sub.y1; y++) {
    final from = rect.index(sub.x0, y);
    out.setRange((y - sub.y0) * sub.w, (y - sub.y0 + 1) * sub.w, p, from);
  }
  return out;
}

/// Union of closed polygons, each rasterized on its own bounding box.
Float32List unionOfPolygons(List<List<MapPoint>> polys, MapRect rect) {
  final out = Float32List(rect.area);
  for (final poly in polys) {
    final sub = boxOf(poly, 1, rect);
    if (sub.isEmpty) continue;
    paintMax(out, rect, rasterizePolygon(poly, sub), sub);
  }
  return out;
}

/// Ellipse through ring points (centroid + principal axes) on [sub].
Float32List fitEllipse(List<MapPoint> pts, MapRect sub) {
  final n = pts.length;
  final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / n;
  final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / n;
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (final p in pts) {
    sxx += (p.x - cx) * (p.x - cx) / n;
    sxy += (p.x - cx) * (p.y - cy) / n;
    syy += (p.y - cy) * (p.y - cy) / n;
  }
  final tr = sxx + syy, det = sxx * syy - sxy * sxy;
  final disc = math.sqrt(math.max(0.0, tr * tr / 4 - det));
  final l1 = tr / 2 + disc, l2 = math.max(0.0, tr / 2 - disc);
  return rasterizeEllipse(
    cx,
    cy,
    math.max(1.0, math.sqrt(2 * l1)),
    math.max(1.0, math.sqrt(2 * l2)),
    0.5 * math.atan2(2 * sxy, sxx - syy),
    sub,
  );
}

/// Eye-open ramp on the lid gap / eye width ratio: a closed or squinting
/// eye has no sclera or iris to work on (the polygon then covers lid skin
/// and lashes).
const double kEyeOpenLo = 0.10;
const double kEyeOpenHi = 0.18;

/// Sclera: near-neutral pixels only (lid skin is chromatic), weighted by
/// proximity to the iris (full within [kScleraFullIod] of its edge, then
/// `exp(−d / kScleraNearIod)`), so the corners stay
/// (research 09 §4.9).
const double kScleraChromaLo = 0.045;
const double kScleraChromaHi = 0.075;
const double kScleraChromaBlurIod = 0.012;
const double kScleraNearIod = 0.05;
const double kScleraFullIod = 0.04;

/// How open one eye is, 0 (closed) .. 1, from its lid landmarks
/// ([loop] is `FaceMesh.rightEye` / `leftEye`).
double eyeOpenness(FaceFrame f, List<int> loop) {
  double d(int a, int b) => math.sqrt(
    math.pow(f.xs[a] - f.xs[b], 2) + math.pow(f.ys[a] - f.ys[b], 2),
  );
  final width = d(loop[0], loop[8]);
  if (width < 1e-6) return 0;
  return smoothstep(kEyeOpenLo, kEyeOpenHi, d(loop[4], loop[12]) / width);
}

/// Sclera and iris maps (§2.3) on the eye sub-rect, plus the teeth cap
/// (sclera P90 L, null when no sclera is visible).
({MapRect sub, Float32List sclera, Float32List iris, double? capL}) eyeMaps(
  FaceFrame f,
  LabPlanes lab,
) {
  final iod = f.iod;
  final sub = boxOf(
    [...f.pts(FaceMesh.rightEye), ...f.pts(FaceMesh.leftEye)],
    0.15 * iod,
    f.rect,
  );
  final w = sub.w, h = sub.h;
  final erodePx = math.max(1, (kScleraErodeIod * iod).round());
  final feather = kEyeRegionFeatherIod * iod;
  final l = cropPlane(lab.l, lab.rect, sub);
  // Chroma is judged below vein scale: a thin red vein is still sclera.
  final soft = math.max(1.0, kScleraChromaBlurIod * iod);
  final a = gaussianBlur(cropPlane(lab.a, lab.rect, sub), w, h, soft);
  final b = gaussianBlur(cropPlane(lab.b, lab.rect, sub), w, h, soft);
  final sclera = Float32List(sub.area), iris = Float32List(sub.area);
  for (final (loop, centre, radius) in [
    (FaceMesh.rightEye, FaceMesh.rightIrisCenter, f.irisRadiusRight),
    (FaceMesh.leftEye, FaceMesh.leftIrisCenter, f.irisRadiusLeft),
  ]) {
    final open = eyeOpenness(f, loop);
    if (open <= 0) continue;
    final cx = f.xs[centre], cy = f.ys[centre];
    final eye = rasterizePolygon(f.pts(loop), sub);
    final white = gaussianBlur(
      erode(
        subtractMask(eye, rasterizeDisc(cx, cy, radius * kIrisDiscScale, sub)),
        w,
        h,
        erodePx,
      ),
      w,
      h,
      feather,
    );
    final ring = gaussianBlur(
      subtractMask(
        productOf([rasterizeDisc(cx, cy, radius, sub), eye]),
        rasterizeDisc(cx, cy, radius * kPupilScale, sub),
      ),
      w,
      h,
      feather,
    );
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (ring[i] > 0) iris[i] = math.max(iris[i], open * ring[i]);
        if (white[i] <= 0) continue;
        final dx = sub.x0 + x + 0.5 - cx, dy = sub.y0 + y + 0.5 - cy;
        final d = math.max(
          0.0,
          math.sqrt(dx * dx + dy * dy) - radius - kScleraFullIod * iod,
        );
        final neutral =
            1 -
            smoothstep(
              kScleraChromaLo,
              kScleraChromaHi,
              math.sqrt(a[i] * a[i] + b[i] * b[i]),
            );
        final v =
            open * white[i] * neutral * math.exp(-d / (kScleraNearIod * iod));
        if (v > sclera[i]) sclera[i] = v;
      }
    }
  }
  final picked = <double>[
    for (var i = 0; i < l.length; i++)
      if (sclera[i] > 0.35) l[i],
  ]..sort();
  return (
    sub: sub,
    sclera: sclera,
    iris: iris,
    capL: picked.length < 4
        ? null
        : picked[((picked.length - 1) * 0.9).round()],
  );
}

/// Mouth opening (teeth candidate) and lips (outer − inner ∩ redness).
({MapRect sub, Float32List mouth, Float32List lips}) mouthMaps(
  FaceFrame f,
  LabPlanes lab,
  double skinMeanA,
) {
  final iod = f.iod;
  final sub = boxOf(f.pts(FaceMesh.lipsOuter), 0.1 * iod, f.rect);
  final w = sub.w, h = sub.h;
  final outer = rasterizePolygon(f.pts(FaceMesh.lipsOuter), sub);
  final inner = rasterizePolygon(f.pts(FaceMesh.lipsInner), sub);
  final a = cropPlane(lab.a, lab.rect, sub);
  final e0 = skinMeanA + kLipRedness, e1 = skinMeanA + 3 * kLipRedness;
  for (var i = 0; i < a.length; i++) {
    a[i] = smoothstep(e0, e1, a[i]);
  }
  final feather = kEyeRegionFeatherIod * iod;
  return (
    sub: sub,
    mouth: gaussianBlur(
      erode(inner, w, h, math.max(1, (kMouthErodeIod * iod).round())),
      w,
      h,
      feather,
    ),
    lips: gaussianBlur(
      productOf([subtractMask(outer, inner), a]),
      w,
      h,
      feather,
    ),
  );
}
