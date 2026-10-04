import 'dart:math' as math;

import 'package:meta/meta.dart';

/// An integer pixel rectangle: origin ([x], [y]) and size. [right] and
/// [bottom] are exclusive. Empty when either side is ≤ 0.
@immutable
class PixelBox {
  const PixelBox(this.x, this.y, this.width, this.height);

  /// From exclusive edges; inverted edges give an empty rect.
  factory PixelBox.fromLTRB(int left, int top, int right, int bottom) =>
      PixelBox(left, top, math.max(0, right - left), math.max(0, bottom - top));

  /// Lenient: `[x, y, w, h]` of numbers, else null.
  static PixelBox? tryFromJson(Object? json) {
    if (json is! List || json.length < 4) return null;
    if (json.take(4).any((v) => v is! num)) return null;
    final v = [for (final n in json.take(4)) (n as num).round()];
    return PixelBox(v[0], v[1], math.max(0, v[2]), math.max(0, v[3]));
  }

  static const zero = PixelBox(0, 0, 0, 0);

  final int x;
  final int y;
  final int width;
  final int height;

  int get right => x + width;
  int get bottom => y + height;
  bool get isEmpty => width <= 0 || height <= 0;
  int get area => isEmpty ? 0 : width * height;
  int get maxSide => math.max(width, height);

  bool contains(int px, int py) =>
      px >= x && py >= y && px < right && py < bottom;

  bool overlaps(PixelBox o) =>
      !isEmpty &&
      !o.isEmpty &&
      x < o.right &&
      o.x < right &&
      y < o.bottom &&
      o.y < bottom;

  PixelBox inflate(int d) =>
      PixelBox.fromLTRB(x - d, y - d, right + d, bottom + d);

  PixelBox translate(int dx, int dy) => PixelBox(x + dx, y + dy, width, height);

  /// Overlap of both; empty (zero) when they do not overlap.
  PixelBox intersect(PixelBox o) {
    if (!overlaps(o)) return zero;
    return PixelBox.fromLTRB(
      math.max(x, o.x),
      math.max(y, o.y),
      math.min(right, o.right),
      math.min(bottom, o.bottom),
    );
  }

  /// Smallest rect containing both (an empty side is ignored).
  PixelBox union(PixelBox o) {
    if (isEmpty) return o;
    if (o.isEmpty) return this;
    return PixelBox.fromLTRB(
      math.min(x, o.x),
      math.min(y, o.y),
      math.max(right, o.right),
      math.max(bottom, o.bottom),
    );
  }

  List<int> toJson() => [x, y, width, height];

  @override
  bool operator ==(Object other) =>
      other is PixelBox &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'PixelBox($x, $y, $width x $height)';
}

/// Reflect-101 index (no edge repeat), periodic for any [i]: maps
/// out-of-range indices into `0..n-1` like a mirrored, tiled image.
int mirrorIndex(int i, int n) {
  if (n <= 1) return 0;
  final period = 2 * (n - 1);
  final m = i % period; // Dart's % is non-negative for a positive divisor.
  return m < n ? m : period - m;
}
