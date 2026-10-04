/// Wrinkle zones (research 07 §3.4) and the per-texel zone code that lets
/// each zone have its own slider while drags stay uniform-only.
///
/// Zone code byte (`regionB` right tile, B; sampled nearest):
///
/// | code | zone | slider weight |
/// |---|---|---|
/// | 0 | none | 0 |
/// | 1..64 | forehead ↔ frown | `mix(forehead, frown, (c − 1)/63)` |
/// | 65..128 | smile ↔ marionette | `mix(smile, marionette, (c − 65)/63)` |
/// | 129 | crow's feet | crowsFeet |
///
/// Adjacent zones blend over their soft overlap, so a line that crosses
/// from the forehead into the glabella never shows a seam when the two
/// sliders differ.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'face_frame.dart';
import 'face_mesh.dart';
import 'filters.dart';
import 'map_rect.dart';
import 'polygon_raster.dart';
import 'region_parts.dart';

const int kZoneCodeForehead = 1;
const int kZoneCodeSmile = 65;
const int kZoneCodeCrowsFeet = 129;
const int kZoneBlendSteps = 63;

// Zone geometry (IOD units).
const double kForeheadGapIod = 0.03;
const double kForeheadHeightIod = 0.95;
const double kForeheadWidenIod = 0.12;
const double kZoneFeatherIod = 0.03;
const double kFrownRiseIod = 0.22;
const double kFrownRadiusIod = 0.15;

/// The frown capsule is full out to this (IOD), then fades to its radius,
/// so the forehead ↔ frown blend spans ≈ 0.09 IOD (no visible seam).
const double kFrownCoreIod = 0.06;
const double kCrowsFeetGrowIod = 0.04;
const double kFoldRadiusIod = 0.07;

/// Coverage below this gets no zone code.
const double kMinZoneCover = 0.02;

/// Wrinkle slider weight of a texel with zone code [code]. Mirrors
/// `wrinkleZone()` in `retouch.frag`.
double wrinkleZoneWeight(
  int code, {
  required double forehead,
  required double frown,
  required double crowsFeet,
  required double smile,
  required double marionette,
}) {
  if (code <= 0) return 0;
  if (code < kZoneCodeSmile) {
    final t = (code - kZoneCodeForehead) / kZoneBlendSteps;
    return forehead + (frown - forehead) * t;
  }
  if (code < kZoneCodeCrowsFeet) {
    final t = (code - kZoneCodeSmile) / kZoneBlendSteps;
    return smile + (marionette - smile) * t;
  }
  return code == kZoneCodeCrowsFeet ? crowsFeet : 0;
}

/// One zone group on its own sub-rect: soft coverage and zone codes.
class ZoneGroup {
  const ZoneGroup(this.sub, this.cover, this.code);
  final MapRect sub;
  final Float32List cover;
  final Uint8List code;
}

/// The five zone groups of face [f] (forehead + frown, both crow's feet,
/// both fold pairs), each on a sub-rect padded by [margin] pixels.
List<ZoneGroup> wrinkleZoneGroups(FaceFrame f, double margin) {
  final iod = f.iod;
  final ex = (x: f.axis.y, y: -f.axis.x); // toward the image right
  MapPoint shift(MapPoint p, double up, double side) => (
    x: p.x - f.axis.x * up * iod + ex.x * side * iod,
    y: p.y - f.axis.y * up * iod + ex.y * side * iod,
  );
  double soft(double d, double r, [double? core]) =>
      1 - smoothstep(core ?? 0.55 * r, r, d);
  final pad = margin + 3 * kZoneFeatherIod * iod;
  final groups = <ZoneGroup>[];

  // Forehead band above the brows, with the frown capsule blended in.
  final browR = f.pts(FaceMesh.rightBrowUpper); // outer → inner
  final browL = f
      .pts(FaceMesh.leftBrowUpper)
      .reversed
      .toList(); // inner → outer
  final bottom = [
    for (var i = 0; i < browR.length; i++)
      shift(browR[i], kForeheadGapIod, i == 0 ? -kForeheadWidenIod : 0),
    for (var i = 0; i < browL.length; i++)
      shift(
        browL[i],
        kForeheadGapIod,
        i == browL.length - 1 ? kForeheadWidenIod : 0,
      ),
  ];
  final band = [
    ...bottom,
    for (final p in bottom.reversed) shift(p, kForeheadHeightIod, 0),
  ];
  final frownLine = [
    f.p(8),
    shift(f.p(FaceMesh.glabellaTop), kFrownRiseIod, 0),
  ];
  final frownR = kFrownRadiusIod * iod;
  {
    final sub = boxOf([...band, ...frownLine], pad + frownR, f.rect);
    if (!sub.isEmpty) {
      final fh = gaussianBlur(
        rasterizePolygon(band, sub),
        sub.w,
        sub.h,
        kZoneFeatherIod * iod,
      );
      final gd = polylineDistance(frownLine, sub, frownR + 1);
      final cover = Float32List(sub.area), code = Uint8List(sub.area);
      for (var i = 0; i < cover.length; i++) {
        final fo = clamp01(fh[i]);
        final g = soft(gd[i], frownR, kFrownCoreIod * iod);
        final c = math.max(fo, g);
        if (c < kMinZoneCover) continue;
        cover[i] = c;
        final t = g / math.max(1e-6, fo * (1 - g) + g);
        code[i] = kZoneCodeForehead + (t * kZoneBlendSteps).round();
      }
      groups.add(ZoneGroup(sub, cover, code));
    }
  }

  // Crow's feet: convex hull of the §1.3 points, grown and softened.
  for (final idx in [FaceMesh.rightCrowsFeet, FaceMesh.leftCrowsFeet]) {
    final hull = convexHull(f.pts(idx));
    final grow = kCrowsFeetGrowIod * iod;
    final sub = boxOf(hull, pad + 2 * grow, f.rect);
    if (sub.isEmpty || hull.length < 3) continue;
    final blurred = gaussianBlur(
      rasterizePolygon(hull, sub),
      sub.w,
      sub.h,
      grow,
    );
    final cover = Float32List(sub.area), code = Uint8List(sub.area);
    for (var i = 0; i < cover.length; i++) {
      final c = smoothstep(0.1, 0.5, blurred[i]);
      if (c < kMinZoneCover) continue;
      cover[i] = c;
      code[i] = kZoneCodeCrowsFeet;
    }
    groups.add(ZoneGroup(sub, cover, code));
  }

  // Folds: nasolabial (smile) and marionette strokes, blended at the
  // mouth corner where they meet.
  final r = kFoldRadiusIod * iod;
  for (final (smileIdx, marIdx) in [
    (FaceMesh.rightNasolabial, FaceMesh.rightMarionette),
    (FaceMesh.leftNasolabial, FaceMesh.leftMarionette),
  ]) {
    final sp = f.pts(smileIdx), mp = f.pts(marIdx);
    final sub = boxOf([...sp, ...mp], pad + r, f.rect);
    if (sub.isEmpty) continue;
    final ds = polylineDistance(sp, sub, r + 1);
    final dm = polylineDistance(mp, sub, r + 1);
    final cover = Float32List(sub.area), code = Uint8List(sub.area);
    for (var i = 0; i < cover.length; i++) {
      final s = soft(ds[i], r), m = soft(dm[i], r);
      final c = math.max(s, m);
      if (c < kMinZoneCover) continue;
      cover[i] = c;
      code[i] = kZoneCodeSmile + (m / (s + m) * kZoneBlendSteps).round();
    }
    groups.add(ZoneGroup(sub, cover, code));
  }
  return groups;
}

/// Convex hull (Andrew's monotone chain), counter-clockwise.
List<MapPoint> convexHull(List<MapPoint> pts) {
  if (pts.length < 3) return List.of(pts);
  final p = [...pts]
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  double cross(MapPoint o, MapPoint a, MapPoint b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <MapPoint>[], upper = <MapPoint>[];
  for (final q in p) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  for (final q in p.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [
    ...lower.sublist(0, lower.length - 1),
    ...upper.sublist(0, upper.length - 1),
  ];
}
