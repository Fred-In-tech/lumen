/// Stray hairs beyond the figure (research 07 §3.12, research 06 §1.4).
///
/// Strays are thin lines (ridge detector, either polarity against the
/// backdrop estimate) in a band just outside the person matte and near the
/// hair raster. The person itself and its silhouette edge are never part
/// of the band; the two-sided ridge test rejects the silhouette edge.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'filters.dart';
import 'map_rect.dart';
import 'region_parts.dart';
import 'wrinkle_map.dart';

/// Band width outside the person (fraction of the long edge).
const double kStrayBandFrac = 0.04;

/// Person coverage below this counts as outside the figure.
const double kStrayCoreP = 0.2;

/// Ridge scales (backdrop grid px) and strength ramp (OkLab L).
const List<double> kStraySigmasPx = [0.8, 1.3];
const double kStrayLo = 0.006;
const double kStrayHi = 0.016;

/// Stray weight (0..1) per pixel of a `width × height` grid. [l] is OkLab
/// L, [backdropL] the clean backdrop estimate, [person] the matte and
/// [hair] the hair raster (null: the band alone limits the search).
Float32List strayHairWeights({
  required Float32List l,
  required Float32List backdropL,
  required Float32List person,
  required Float32List? hair,
  required int width,
  required int height,
}) {
  final w = width, h = height, n = w * h;
  final band = (kStrayBandFrac * math.max(w, h)).round();
  final inside = Float32List(n);
  for (var i = 0; i < n; i++) {
    inside[i] = person[i] >= 0.5 ? 1 : 0;
  }
  final near = gaussianBlur(dilate(inside, w, h, band), w, h, band / 6);
  final hairNear = hair == null
      ? null
      : gaussianBlur(
          dilate(
            Float32List.fromList([for (final v in hair) v >= 0.35 ? 1 : 0]),
            w,
            h,
            band,
          ),
          w,
          h,
          band / 6,
        );
  final zone = Float32List(n), d = Float32List(n), neg = Float32List(n);
  var any = false;
  for (var i = 0; i < n; i++) {
    final outside = 1 - smoothstep(0.5 * kStrayCoreP, kStrayCoreP, person[i]);
    final z =
        clamp01(near[i]) *
        outside *
        (hairNear == null ? 1 : clamp01(hairNear[i]));
    zone[i] = z;
    if (z > 0) any = true;
    d[i] = l[i] - backdropL[i];
    neg[i] = -d[i];
  }
  if (!any) return Float32List(n);
  // Ridges only on the bounding box of the zone (plus the filter reach).
  var x0 = w, y0 = h, x1 = 0, y1 = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (zone[y * w + x] <= 0) continue;
      x0 = math.min(x0, x);
      y0 = math.min(y0, y);
      x1 = math.max(x1, x + 1);
      y1 = math.max(y1, y + 1);
    }
  }
  final pad = (4 * kStraySigmasPx.last).ceil() + 2;
  final sub = MapRect(
    math.max(0, x0 - pad),
    math.max(0, y0 - pad),
    math.min(w, x1 + pad) - math.max(0, x0 - pad),
    math.min(h, y1 + pad) - math.max(0, y0 - pad),
  );
  final full = MapRect(0, 0, w, h);
  final zs = cropPlane(zone, full, sub);
  final dark = ridgeStrengthAt(
    cropPlane(d, full, sub),
    sub.w,
    sub.h,
    kStraySigmasPx,
    only: zs,
  );
  final light = ridgeStrengthAt(
    cropPlane(neg, full, sub),
    sub.w,
    sub.h,
    kStraySigmasPx,
    only: zs,
  );
  final raw = Float32List(n);
  for (var y = sub.y0; y < sub.y1; y++) {
    for (var x = sub.x0; x < sub.x1; x++) {
      final i = y * w + x, j = (y - sub.y0) * sub.w + (x - sub.x0);
      if (zone[i] <= 0) continue;
      raw[i] =
          smoothstep(kStrayLo, kStrayHi, math.max(dark[j], light[j])) * zone[i];
    }
  }
  final out = gaussianBlur(rankFilter(raw, w, h, 1, true), w, h, 0.7);
  for (var i = 0; i < n; i++) {
    out[i] =
        clamp01(out[i]) *
        (1 - smoothstep(0.5 * kStrayCoreP, kStrayCoreP, person[i]));
  }
  return out;
}
