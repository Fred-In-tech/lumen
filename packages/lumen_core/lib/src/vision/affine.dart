import 'dart:math' as math;

/// A 2×3 affine transform, row-major:
///
///     | a  b  tx |      x' = a·x + b·y + tx
///     | c  d  ty |      y' = c·x + d·y + ty
class Affine2x3 {
  const Affine2x3(this.a, this.b, this.tx, this.c, this.d, this.ty);

  static const identity = Affine2x3(1, 0, 0, 0, 1, 0);

  /// Rotation by [rotation] radians (image coordinates: y down, so positive
  /// turns +x toward +y), uniform [scale], then translation.
  factory Affine2x3.similarity({
    double scale = 1,
    double rotation = 0,
    double tx = 0,
    double ty = 0,
  }) {
    final cs = math.cos(rotation) * scale;
    final sn = math.sin(rotation) * scale;
    return Affine2x3(cs, -sn, tx, sn, cs, ty);
  }

  final double a;
  final double b;
  final double tx;
  final double c;
  final double d;
  final double ty;

  double get determinant => a * d - b * c;

  (double, double) apply(double x, double y) =>
      (a * x + b * y + tx, c * x + d * y + ty);

  /// The inverse transform. Throws [StateError] when singular.
  Affine2x3 inverse() {
    final det = determinant;
    if (det.abs() < 1e-15) throw StateError('Affine2x3 is singular');
    final ia = d / det;
    final ib = -b / det;
    final ic = -c / det;
    final id = a / det;
    return Affine2x3(
      ia,
      ib,
      -(ia * tx + ib * ty),
      ic,
      id,
      -(ic * tx + id * ty),
    );
  }

  /// `this` followed by [next]: x ↦ next(this(x)).
  Affine2x3 then(Affine2x3 next) => Affine2x3(
    next.a * a + next.b * c,
    next.a * b + next.b * d,
    next.a * tx + next.b * ty + next.tx,
    next.c * a + next.d * c,
    next.c * b + next.d * d,
    next.c * tx + next.d * ty + next.ty,
  );

  /// Row-major `[a, b, tx, c, d, ty]` (OpenCV / shader layout).
  List<double> toList() => List.unmodifiable([a, b, tx, c, d, ty]);

  @override
  bool operator ==(Object other) =>
      other is Affine2x3 &&
      other.a == a &&
      other.b == b &&
      other.tx == tx &&
      other.c == c &&
      other.d == d &&
      other.ty == ty;

  @override
  int get hashCode => Object.hash(a, b, tx, c, d, ty);

  @override
  String toString() => 'Affine2x3([$a, $b, $tx], [$c, $d, $ty])';
}
