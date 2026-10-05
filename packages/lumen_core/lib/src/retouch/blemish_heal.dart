/// Push-pull spot healing (research 07 §3.3, 09 §4.5).
///
/// The spot is filled from its ring by push-pull on a pore-scale-smoothed
/// copy, so pores (finer than [kHealPoreSigmaIod]) continue through the
/// healed spot: the delta is band-limited and the original fine band is
/// kept. The retouch pass adds `selection · Δ` (`deltaB` left tile); the
/// skin bands are computed from the healed image, so a healed spot is
/// never smoothed twice and an unselected one stays exactly as it was.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'blemish_types.dart';
import 'face_frame.dart';
import 'filters.dart';
import 'lab_planes.dart';
import 'map_rect.dart';
import 'push_pull.dart';
import 'region_parts.dart';

/// Hole = disc of radius × 1.3 with a 30 % feather (§3.3 healing step 1).
const double kHealHoleScale = 1.3;
const double kHealHoleFeather = 0.3;

/// Pore-scale smoothing before the fill (detail below this survives), in
/// IOD units, but never below [kHealPoreSigmaMinPx] pixels.
const double kHealPoreSigmaIod = 0.0035;
const double kHealPoreSigmaMinPx = 0.7;

/// Spot codes cover the hole plus [kSpotCodeSpillSigmas] of this (IOD),
/// so bilinear fringes of the delta keep their code.
const double kHealSpillIod = 0.012;
const double kSpotCodeSpillSigmas = 2.5;

/// Heal deltas of one face over its work rect.
class HealPlanes {
  const HealPlanes({
    required this.rect,
    required this.dl,
    required this.da,
    required this.db,
    required this.spotCode,
    required this.healed,
  });

  final MapRect rect;

  /// OkLab change that heals every spot (and core, glare) completely.
  final Float32List dl;
  final Float32List da;
  final Float32List db;

  /// Nearest spot's code per pixel (0 = none), see [encodeSpotCode].
  final Uint8List spotCode;

  /// [lab] with every non-kept spot healed (input of the skin bands).
  final LabPlanes healed;
}

/// Computes the heal deltas for [spots] of face [f] from [lab].
HealPlanes healBlemishes(
  FaceFrame f,
  LabPlanes lab,
  List<BlemishCandidate> spots, {
  required int gridW,
  required int gridH,
  BlemishOverrides overrides = BlemishOverrides.none,
  Float32List? core,
}) {
  final rect = lab.rect, n = rect.area;
  final active = [
    for (final s in spots)
      if (!overrides.keep.contains(s.id)) s,
  ];
  final sigma1 = kHealSpillIod * f.iod;
  final alpha = Float32List(n);
  final best = Float32List(n)..fillRange(0, n, double.infinity);
  final codes = Uint8List(n);
  var x0 = rect.x1, y0 = rect.y1, x1 = rect.x0, y1 = rect.y0;
  var margin = 0.0;
  for (final s in active) {
    final cx = s.u * gridW, cy = s.v * gridH;
    final rh = s.radiusIod * f.iod * kHealHoleScale;
    final reach = rh + kSpotCodeSpillSigmas * sigma1;
    margin = math.max(margin, 3 * rh + 3 * sigma1);

    final code = encodeSpotCode(
      s.kind,
      s.threshold,
      forced: overrides.remove.contains(s.id),
    );
    final box = MapRect.around(cx, cy, reach + 1, reach + 1, gridW, gridH);
    final ys = math.max(box.y0, rect.y0), ye = math.min(box.y1, rect.y1);
    final xs = math.max(box.x0, rect.x0), xe = math.min(box.x1, rect.x1);
    x0 = math.min(x0, xs);
    y0 = math.min(y0, ys);
    x1 = math.max(x1, xe);
    y1 = math.max(y1, ye);
    for (var y = ys; y < ye; y++) {
      for (var x = xs; x < xe; x++) {
        final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d > reach) continue;
        final i = rect.index(x, y);
        final a = 1 - smoothstep((1 - kHealHoleFeather) * rh, rh, d);
        if (a > alpha[i]) alpha[i] = a;
        if (d < best[i]) {
          best[i] = d;
          codes[i] = code;
        }
      }
    }
  }
  if (core != null) {
    final box = _coreBox(core, rect, (kSpotCodeSpillSigmas * sigma1).ceil());
    if (box != null) {
      final spill = cropPlane(core, rect, box);
      final reach = rankFilter(
        spill,
        box.w,
        box.h,
        (kSpotCodeSpillSigmas * sigma1).ceil(),
        true,
      );
      for (var y = box.y0; y < box.y1; y++) {
        var i = rect.index(box.x0, y);
        var j = (y - box.y0) * box.w;
        for (var x = box.x0; x < box.x1; x++, i++, j++) {
          final a = core[i];
          if (reach[j] <= 0.01) continue;
          if (codes[i] == 0 || a > alpha[i]) codes[i] = kShineCoreCode;
          if (a > alpha[i]) alpha[i] = a;
        }
      }
      x0 = math.min(x0, box.x0);
      y0 = math.min(y0, box.y0);
      x1 = math.max(x1, box.x1);
      y1 = math.max(y1, box.y1);
      margin = math.max(margin, 0.1 * f.iod + 3 * sigma1);
    }
  }
  final zero = Float32List(n);
  if (x1 <= x0 || y1 <= y0) {
    return HealPlanes(
      rect: rect,
      dl: zero,
      da: zero,
      db: zero,
      spotCode: codes,
      healed: lab,
    );
  }
  // Fill only around the holes (plus a ring margin), not the whole rect.
  final m = margin.ceil();
  final work = MapRect(
    math.max(rect.x0, x0 - m),
    math.max(rect.y0, y0 - m),
    math.min(rect.x1, x1 + m) - math.max(rect.x0, x0 - m),
    math.min(rect.y1, y1 + m) - math.max(rect.y0, y0 - m),
  );
  final ww = work.w, wh = work.h;
  final trust = cropPlane(alpha, rect, work);
  for (var i = 0; i < trust.length; i++) {
    trust[i] = 1 - trust[i];
  }
  final poreSigma = math.max(kHealPoreSigmaMinPx, kHealPoreSigmaIod * f.iod);
  final full = <Float32List>[];
  for (final c in lab.channels) {
    final sub = cropPlane(c, rect, work);
    final smooth = gaussianBlur(sub, ww, wh, poreSigma);
    full.add(subtractPlanes(pushPull(smooth, trust, ww, wh), smooth));
  }
  final healed = [
    for (var k = 0; k < 3; k++) _pasteAdd(lab.channels[k], rect, full[k], work),
  ];
  return HealPlanes(
    rect: rect,
    dl: _pasteAdd(zero, rect, full[0], work),
    da: _pasteAdd(zero, rect, full[1], work),
    db: _pasteAdd(zero, rect, full[2], work),
    spotCode: codes,
    healed: LabPlanes(rect, healed[0], healed[1], healed[2]),
  );
}

/// A copy of [base] (covering [rect]) with [delta] (covering [sub]) added.
Float32List _pasteAdd(
  Float32List base,
  MapRect rect,
  Float32List delta,
  MapRect sub,
) {
  final out = Float32List.fromList(base);
  for (var y = sub.y0; y < sub.y1; y++) {
    var i = rect.index(sub.x0, y);
    var j = (y - sub.y0) * sub.w;
    for (var x = 0; x < sub.w; x++, i++, j++) {
      out[i] += delta[j];
    }
  }
  return out;
}

/// Bounding rect of `core > 0` grown by [pad], clipped to [rect], or null.
MapRect? _coreBox(Float32List core, MapRect rect, int pad) {
  var x0 = rect.x1, y0 = rect.y1, x1 = rect.x0, y1 = rect.y0;
  for (var y = rect.y0; y < rect.y1; y++) {
    var i = (y - rect.y0) * rect.w;
    for (var x = rect.x0; x < rect.x1; x++, i++) {
      if (core[i] <= 0) continue;
      x0 = math.min(x0, x);
      y0 = math.min(y0, y);
      x1 = math.max(x1, x + 1);
      y1 = math.max(y1, y + 1);
    }
  }
  if (x1 <= x0) return null;
  final a = math.max(rect.x0, x0 - pad), b = math.max(rect.y0, y0 - pad);
  return MapRect(
    a,
    b,
    math.min(rect.x1, x1 + pad) - a,
    math.min(rect.y1, y1 + pad) - b,
  );
}
