/// Clipped specular cores (research 07 §3.8).
///
/// A clipped highlight (sRGB near 255) has no detail or colour left, so
/// Reduce Shine alone turns it into a flat grey blob. Above 50 % Shine the
/// core is instead filled from the surrounding skin by the blemish heal's
/// push-pull (it is a spot of kind 3, see `blemish_types.dart`), and the
/// regular shine reduction then treats it like the sheen around it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../render/rgba_buffer.dart';
import 'face_frame.dart';
import 'filters.dart';
import 'map_rect.dart';
import 'region_parts.dart';

/// Clip ramp on the brightest sRGB channel (0 below, 1 above).
const int kClipByteLo = 238;
const int kClipByteHi = 250;

/// Skin holes up to twice this (IOD) are closed before the core is taken,
/// so a clipped plateau the colour model rejected still counts as skin.
const double kCoreCloseIod = 0.06;

/// The hole grows past the clipped plateau into its desaturated rim.
const double kCoreGrowIod = 0.035;
const double kCoreFeatherIod = 0.01;

/// Clipped pixels needed before a face gets a core map.
const int kMinCorePixels = 4;

/// Soft clip mask (0..1) of `grid` over [rect], or null when no pixel in
/// [rect] is clipped.
Float32List? clipPlane(RgbaBuffer grid, MapRect rect) {
  final out = Float32List(rect.area);
  var count = 0;
  for (var y = rect.y0; y < rect.y1; y++) {
    var o = grid.offset(rect.x0, y);
    var i = (y - rect.y0) * rect.w;
    for (var x = rect.x0; x < rect.x1; x++, o += 4, i++) {
      final d = grid.data;
      final m = math.max(d[o], math.max(d[o + 1], d[o + 2]));
      if (m <= kClipByteLo) continue;
      out[i] = smoothstep(
        kClipByteLo.toDouble(),
        kClipByteHi.toDouble(),
        m.toDouble(),
      );
      if (out[i] > 0.5) count++;
    }
  }
  return count >= kMinCorePixels ? out : null;
}

/// Soft hole over the clipped cores of face [f] on skin, from the clip
/// mask [clip] and skin weight [skin] (both over `f.rect`), or null.
Float32List? shineCoreHole(FaceFrame f, Float32List clip, Float32List skin) {
  final rect = f.rect;
  var x0 = rect.x1, y0 = rect.y1, x1 = rect.x0, y1 = rect.y0;
  for (var y = rect.y0; y < rect.y1; y++) {
    var i = (y - rect.y0) * rect.w;
    for (var x = rect.x0; x < rect.x1; x++, i++) {
      if (clip[i] <= 0.5) continue;
      x0 = math.min(x0, x);
      y0 = math.min(y0, y);
      x1 = math.max(x1, x + 1);
      y1 = math.max(y1, y + 1);
    }
  }
  if (x1 <= x0) return null;
  final close = math.max(1, (kCoreCloseIod * f.iod).round());
  final grow = math.max(1, (kCoreGrowIod * f.iod).round());
  final feather = kCoreFeatherIod * f.iod;
  final m = 2 * close + grow + (3 * feather).ceil() + 2;
  final sub = MapRect(
    math.max(rect.x0, x0 - m),
    math.max(rect.y0, y0 - m),
    math.min(rect.x1, x1 + m) - math.max(rect.x0, x0 - m),
    math.min(rect.y1, y1 + m) - math.max(rect.y0, y0 - m),
  );
  final w = sub.w, h = sub.h;
  final sk = cropPlane(skin, rect, sub), cl = cropPlane(clip, rect, sub);
  final closed = rankFilter(
    rankFilter(sk, w, h, close, true),
    w,
    h,
    close,
    false,
  );
  final core = Float32List(sub.area);
  var any = false;
  for (var i = 0; i < core.length; i++) {
    core[i] = cl[i] * smoothstep(0.3, 0.7, closed[i]);
    if (core[i] > 0.5) any = true;
  }
  if (!any) return null;
  final hole = gaussianBlur(rankFilter(core, w, h, grow, true), w, h, feather);
  for (var i = 0; i < hole.length; i++) {
    hole[i] = clamp01(hole[i]) * smoothstep(0.3, 0.7, closed[i]);
  }
  return pasted(rect, hole, sub);
}
