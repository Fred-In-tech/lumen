/// Face ownership and the face-id channel of the region atlases, shared by
/// the map builder and the Manual Tuning Pen (`skin_pen.dart`), so both
/// assign texels identically.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'kernel_constants.dart';
import 'map_rect.dart';
import 'retouch_maps.dart';

/// Per grid pixel, the slot of the face that owns it (−1 = none): among
/// the faces whose work rect contains the pixel, the one whose
/// size-normalized centre is nearest; ties go to the larger face. With
/// [within], only texels inside it are resolved (the rest stay −1).
Int8List faceOwners(
  List<RetouchFaceInfo> faces,
  int w,
  int h, {
  MapRect? within,
}) {
  final owner = Int8List(w * h)..fillRange(0, w * h, -1);
  final dist = Float32List(w * h)..fillRange(0, w * h, double.infinity);
  final bySize = [...faces]..sort((a, b) => b.iod.compareTo(a.iod));
  for (final f in bySize) {
    final r = within == null ? f.rect : f.rect.intersect(within);
    for (var y = r.y0; y < r.y1; y++) {
      final dy = y + 0.5 - f.centerY;
      for (var x = r.x0; x < r.x1; x++) {
        final dx = x + 0.5 - f.centerX;
        final i = y * w + x;
        final d = math.sqrt(dx * dx + dy * dy) / f.iod;
        if (d < dist[i]) {
          dist[i] = d;
          owner[i] = f.slot;
        }
      }
    }
  }
  return owner;
}

/// Sets the face id (`slot + 1`) on the texels of [f]'s rect that it owns
/// and where an effect can apply (any region byte, a spot code, a heal
/// delta or a red-eye disc), grown by one texel so bilinear fringes keep
/// their face; clears it on its other owned texels. With [within], only
/// texels inside it are reassigned ([owner] must cover it plus a texel).
void assignFaceIds(
  RetouchFaceInfo f,
  int w,
  Int8List owner,
  Uint8List bh,
  Uint8List ra,
  Uint8List rb, {
  MapRect? within,
}) {
  final slot = f.slot;
  final target = within == null ? f.rect : f.rect.intersect(within);
  if (target.isEmpty) return;
  // Active texels are needed one texel around the target (growth).
  final rect = within == null
      ? f.rect
      : f.rect.intersect(
          MapRect(target.x0 - 1, target.y0 - 1, target.w + 2, target.h + 2),
        );
  final active = Uint8List(rect.area);
  final eyeR = kRedEyeRadiusIod * f.iod, eyeR2 = eyeR * eyeR;
  for (var y = rect.y0; y < rect.y1; y++) {
    var i = (y - rect.y0) * rect.w;
    for (var x = rect.x0; x < rect.x1; x++, i++) {
      if (owner[y * w + x] != slot) continue;
      final left = (y * 2 * w + x) * 4, right = left + w * 4;
      final any =
          ra[left] |
          ra[left + 1] |
          ra[right] |
          ra[right + 1] |
          ra[right + 2] |
          rb[left] |
          rb[left + 1] |
          rb[left + 2] |
          rb[right + 1];
      if (any != 0 || _healed(bh, left)) {
        active[i] = 1;
        continue;
      }
      final px = x + 0.5, py = y + 0.5;
      final rx = px - f.eyeRightX, ry = py - f.eyeRightY;
      final lx = px - f.eyeLeftX, ly = py - f.eyeLeftY;
      if (rx * rx + ry * ry <= eyeR2 || lx * lx + ly * ly <= eyeR2) {
        active[i] = 1;
      }
    }
  }
  final grown = _grow(active, rect.w, rect.h);
  final id = slot + 1;
  for (var y = target.y0; y < target.y1; y++) {
    for (var x = target.x0; x < target.x1; x++) {
      if (owner[y * w + x] != slot) continue;
      rb[(y * 2 * w + w + x) * 4] = grown[rect.index(x, y)] != 0 ? id : 0;
    }
  }
}

bool _healed(Uint8List bh, int o) =>
    bh[o] != 128 || bh[o + 1] != 128 || bh[o + 2] != 128;

/// 3×3 binary dilation (separable max of radius 1).
Uint8List _grow(Uint8List m, int w, int h) {
  final row = Uint8List(m.length), out = Uint8List(m.length);
  for (var y = 0; y < h; y++) {
    final base = y * w;
    for (var x = 0; x < w; x++) {
      if (m[base + x] != 0 ||
          (x > 0 && m[base + x - 1] != 0) ||
          (x < w - 1 && m[base + x + 1] != 0)) {
        row[base + x] = 1;
      }
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (row[i] != 0 ||
          (y > 0 && row[i - w] != 0) ||
          (y < h - 1 && row[i + w] != 0)) {
        out[i] = 1;
      }
    }
  }
  return out;
}
