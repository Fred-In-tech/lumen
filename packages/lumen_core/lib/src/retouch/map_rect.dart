import 'dart:math' as math;

/// An integer pixel rect inside a map grid (`x0, y0` inclusive, size `w×h`).
///
/// Map pixel `(i, j)` covers the continuous square `[i, i+1) × [j, j+1)`;
/// its centre is `(i + 0.5, j + 0.5)`. Normalized source uv `(u, v)` maps
/// to continuous map coordinates `(u·W, v·H)`.
class MapRect {
  const MapRect(this.x0, this.y0, this.w, this.h);

  /// The rect around a centre `(cx, cy)` with half-sizes, clipped to the
  /// `gridW × gridH` grid (possibly empty).
  factory MapRect.around(
    double cx,
    double cy,
    double halfW,
    double halfH,
    int gridW,
    int gridH,
  ) {
    final x0 = math.max(0, (cx - halfW).floor());
    final y0 = math.max(0, (cy - halfH).floor());
    final x1 = math.min(gridW, (cx + halfW).ceil());
    final y1 = math.min(gridH, (cy + halfH).ceil());
    return MapRect(x0, y0, math.max(0, x1 - x0), math.max(0, y1 - y0));
  }

  final int x0;
  final int y0;
  final int w;
  final int h;

  int get x1 => x0 + w;
  int get y1 => y0 + h;
  int get area => w * h;
  bool get isEmpty => w <= 0 || h <= 0;

  bool contains(int x, int y) => x >= x0 && x < x1 && y >= y0 && y < y1;

  /// Index of grid pixel `(x, y)` inside a plane covering this rect.
  int index(int x, int y) => (y - y0) * w + (x - x0);

  @override
  bool operator ==(Object other) =>
      other is MapRect &&
      other.x0 == x0 &&
      other.y0 == y0 &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x0, y0, w, h);

  @override
  String toString() => 'MapRect($x0, $y0, ${w}x$h)';
}

/// A point in continuous map pixel coordinates.
typedef MapPoint = ({double x, double y});
