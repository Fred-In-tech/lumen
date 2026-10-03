/// Normalized crop rectangle in oriented-source space (0..1).
class CropRect {
  const CropRect(this.left, this.top, this.right, this.bottom);

  factory CropRect.normalized(double l, double t, double r, double b) {
    double c(double v) => v.clamp(0, 1).toDouble();
    var (x0, x1) = l <= r ? (c(l), c(r)) : (c(r), c(l));
    var (y0, y1) = t <= b ? (c(t), c(b)) : (c(b), c(t));
    const minSize = 0.01;
    if (x1 - x0 < minSize) x1 = (x0 + minSize).clamp(0, 1).toDouble();
    if (y1 - y0 < minSize) y1 = (y0 + minSize).clamp(0, 1).toDouble();
    return CropRect(x0, y0, x1, y1);
  }

  static const full = CropRect(0, 0, 1, 1);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  bool get isFull => left == 0 && top == 0 && right == 1 && bottom == 1;

  List<double> toJson() => [left, top, right, bottom];

  @override
  bool operator ==(Object other) =>
      other is CropRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// Crop, straighten, rotate and flip. Never part of presets.
class Geometry {
  const Geometry({
    this.crop = CropRect.full,
    this.angle = 0,
    this.rotate90 = 0,
    this.flipH = false,
    this.flipV = false,
    this.aspect = 'original',
    this.baseOrientation = 1,
  });

  factory Geometry.fromJson(Object? json) {
    if (json is! Map) return none;
    final c = json['crop'];
    final crop = c is List && c.length == 4 && c.every((e) => e is num)
        ? CropRect.normalized(
            (c[0] as num).toDouble(),
            (c[1] as num).toDouble(),
            (c[2] as num).toDouble(),
            (c[3] as num).toDouble(),
          )
        : CropRect.full;
    return none.copyWith(
      crop: crop,
      angle: (json['angle'] as num?)?.toDouble() ?? 0,
      rotate90: (json['rotate90'] as num?)?.toInt() ?? 0,
      flipH: json['flipH'] == true,
      flipV: json['flipV'] == true,
      aspect: json['aspect'] is String ? json['aspect'] as String : 'original',
      baseOrientation: (json['baseOrientation'] as num?)?.toInt() ?? 1,
    );
  }

  static const none = Geometry();
  static const double maxAngle = 45;

  final CropRect crop;

  /// Straighten angle in degrees, −45..45.
  final double angle;

  /// Quarter turns clockwise, 0..3.
  final int rotate90;
  final bool flipH;
  final bool flipV;

  /// Aspect preset id: original, free, 1:1, 4:5, 3:2, 16:9, ...
  final String aspect;

  /// EXIF orientation of the source (1 = upright). Used only if the decoder doesn't apply it.
  final int baseOrientation;

  bool get isIdentity =>
      crop.isFull && angle == 0 && rotate90 == 0 && !flipH && !flipV;

  /// True when the oriented image is rotated by an odd number of quarter turns.
  bool get swapsAxes => rotate90.isOdd;

  Geometry copyWith({
    CropRect? crop,
    double? angle,
    int? rotate90,
    bool? flipH,
    bool? flipV,
    String? aspect,
    int? baseOrientation,
  }) => Geometry(
    crop: crop ?? this.crop,
    angle: (angle ?? this.angle).clamp(-maxAngle, maxAngle).toDouble(),
    rotate90: (rotate90 ?? this.rotate90) % 4,
    flipH: flipH ?? this.flipH,
    flipV: flipV ?? this.flipV,
    aspect: aspect ?? this.aspect,
    baseOrientation: (baseOrientation ?? this.baseOrientation).clamp(1, 8),
  );

  Map<String, Object?> toJson() => {
    'crop': crop.toJson(),
    'angle': angle,
    'rotate90': rotate90,
    'flipH': flipH,
    'flipV': flipV,
    'aspect': aspect,
    'baseOrientation': baseOrientation,
  };

  @override
  bool operator ==(Object other) =>
      other is Geometry &&
      other.crop == crop &&
      other.angle == angle &&
      other.rotate90 == rotate90 &&
      other.flipH == flipH &&
      other.flipV == flipV &&
      other.aspect == aspect &&
      other.baseOrientation == baseOrientation;

  @override
  int get hashCode =>
      Object.hash(crop, angle, rotate90, flipH, flipV, aspect, baseOrientation);
}
