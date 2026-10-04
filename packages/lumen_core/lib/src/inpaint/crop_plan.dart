/// Context crops around holes (§5.2.2 and §5.2.5).
library;

import 'dart:math' as math;

import '../render/rgba_buffer.dart';
import 'pixel_box.dart';

/// Context-crop sizing: side = clamp(factor × max hole side, min, max),
/// and never less than the hole plus [minMargin] on each side.
class CropPolicy {
  const CropPolicy({
    this.contextFactor = 2.5,
    this.minSide = 512,
    this.maxSide = 2048,
    this.minMargin = 32,
  });

  final double contextFactor;
  final int minSide;
  final int maxSide;

  /// Context kept around holes too large for [maxSide].
  final int minMargin;
}

/// One crop job: the square [crop] (source px; may extend past the source,
/// those pixels are mirror-padded) and the bbox of the [holes] it covers.
typedef CropJob = ({PixelBox crop, PixelBox holes});

/// The square context crop for a hole bbox: centred on the hole, then
/// shifted to stay inside the source. When the source is smaller than the
/// side, the crop covers it entirely and is mirror-padded.
PixelBox planContextCrop(
  PixelBox hole,
  int srcWidth,
  int srcHeight, {
  CropPolicy policy = const CropPolicy(),
}) {
  final want = (policy.contextFactor * hole.maxSide).round();
  final side = math.max(
    want.clamp(policy.minSide, policy.maxSide),
    hole.maxSide + 2 * policy.minMargin,
  );
  int place(int start, int len, int size) {
    final x = start + len ~/ 2 - side ~/ 2;
    return side <= size ? x.clamp(0, size - side) : x.clamp(size - side, 0);
  }

  return PixelBox(
    place(hole.x, hole.width, srcWidth),
    place(hole.y, hole.height, srcHeight),
    side,
    side,
  );
}

/// One crop per hole bbox; holes whose crops overlap are merged (their
/// union is re-planned) until all crops are disjoint. Deterministic order.
List<CropJob> planCrops(
  List<PixelBox> holes,
  int srcWidth,
  int srcHeight, {
  CropPolicy policy = const CropPolicy(),
}) {
  var groups = [
    for (final h in holes)
      if (!h.isEmpty) h,
  ];
  PixelBox crop(PixelBox h) =>
      planContextCrop(h, srcWidth, srcHeight, policy: policy);
  var merged = true;
  while (merged) {
    merged = false;
    outer:
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        if (crop(groups[i]).overlaps(crop(groups[j]))) {
          groups = [
            for (var k = 0; k < groups.length; k++)
              if (k != i && k != j) groups[k],
          ]..insert(i, groups[i].union(groups[j]));
          merged = true;
          break outer;
        }
      }
    }
  }
  return [for (final g in groups) (crop: crop(g), holes: g)];
}

/// Copies [crop] out of [src]; pixels past the source edges mirror
/// (reflect-101).
RgbaBuffer extractCrop(RgbaBuffer src, PixelBox crop) {
  final out = RgbaBuffer(crop.width, crop.height);
  final inside =
      crop.x >= 0 &&
      crop.y >= 0 &&
      crop.right <= src.width &&
      crop.bottom <= src.height;
  for (var y = 0; y < crop.height; y++) {
    final sy = inside ? crop.y + y : mirrorIndex(crop.y + y, src.height);
    if (inside) {
      final s = src.offset(crop.x, sy);
      out.data.setRange(
        y * crop.width * 4,
        (y + 1) * crop.width * 4,
        src.data,
        s,
      );
      continue;
    }
    for (var x = 0; x < crop.width; x++) {
      final s = src.offset(mirrorIndex(crop.x + x, src.width), sy);
      final o = (y * crop.width + x) * 4;
      out.data.setRange(o, o + 4, src.data, s);
    }
  }
  return out;
}
