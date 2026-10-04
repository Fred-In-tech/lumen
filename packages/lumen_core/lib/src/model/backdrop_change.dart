/// Backdrop changer and background blur (Evoto's Backdrop Changer + AI
/// Lens Blur, on device). Stored in `DevelopSettings.backdrop`; paste group
/// "Background swap"; never part of presets.
library;

/// none = off; blur = the original background blurred around the subject;
/// color / gradient / image = a new background behind the subject.
enum BackdropMode { none, blur, color, gradient, image }

/// How a backdrop image covers the frame: fill (cover, centre-cropped),
/// fit (contain; the rest is [BackdropChange.color]), stretch.
enum BackdropFit { fill, fit, stretch }

class BackdropChange {
  const BackdropChange({
    this.mode = BackdropMode.none,
    this.blur = 50,
    this.color = 0xFFFFFFFF,
    this.color2 = 0xFF808080,
    this.angle = 90,
    this.imageRef = '',
    this.fit = BackdropFit.fill,
    this.edgeShift = 0,
    this.feather = 50,
    this.spill = 50,
    this.match = 0,
  });

  /// Lenient: unknown enums fall back, numbers are clamped, junk is [none].
  factory BackdropChange.fromJson(Object? json) {
    if (json is! Map) return none;
    double n(String k, double d, double lo, double hi) =>
        json[k] is num ? (json[k] as num).toDouble().clamp(lo, hi) : d;
    int c(String k, int d) =>
        json[k] is int ? (json[k] as int) & 0xFFFFFFFF : d;
    T e<T extends Enum>(List<T> values, String k, T d) =>
        values.where((v) => v.name == json[k]).firstOrNull ?? d;
    const d = none;
    return BackdropChange(
      mode: e(BackdropMode.values, 'mode', d.mode),
      blur: n('blur', d.blur, 0, 100),
      color: c('color', d.color),
      color2: c('color2', d.color2),
      angle: n('angle', d.angle, -360, 360),
      imageRef: json['imageRef'] is String ? json['imageRef'] as String : '',
      fit: e(BackdropFit.values, 'fit', d.fit),
      edgeShift: n('edgeShift', d.edgeShift, -100, 100),
      feather: n('feather', d.feather, 0, 100),
      spill: n('spill', d.spill, 0, 100),
      match: n('match', d.match, 0, 100),
    );
  }

  static const none = BackdropChange();

  final BackdropMode mode;

  /// Background blur strength 0–100 (blur mode).
  final double blur;

  /// ARGB colours: [color] (solid / gradient start / fit letterbox) and
  /// [color2] (gradient end).
  final int color;
  final int color2;

  /// Gradient direction in degrees (0 = left → right, 90 = top → bottom).
  final double angle;

  /// Backdrop image, `retouch/<name>.png` under `assets/<id>/` (PatchStore).
  final String imageRef;
  final BackdropFit fit;

  /// Edge adjustments: shift −100 (choke) … +100 (spread); feather 0–100.
  final double edgeShift;
  final double feather;

  /// Remove spill 0–100 (old-backdrop colour cast at the subject edge).
  final double spill;

  /// Subject brightness match toward the new background, 0–100.
  final double match;

  /// True when nothing is drawn (off, or an image mode without an image).
  bool get isNone =>
      mode == BackdropMode.none ||
      (mode == BackdropMode.image && imageRef.isEmpty);

  BackdropChange copyWith({
    BackdropMode? mode,
    double? blur,
    int? color,
    int? color2,
    double? angle,
    String? imageRef,
    BackdropFit? fit,
    double? edgeShift,
    double? feather,
    double? spill,
    double? match,
  }) => BackdropChange(
    mode: mode ?? this.mode,
    blur: (blur ?? this.blur).clamp(0, 100),
    color: color ?? this.color,
    color2: color2 ?? this.color2,
    angle: angle ?? this.angle,
    imageRef: imageRef ?? this.imageRef,
    fit: fit ?? this.fit,
    edgeShift: (edgeShift ?? this.edgeShift).clamp(-100, 100),
    feather: (feather ?? this.feather).clamp(0, 100),
    spill: (spill ?? this.spill).clamp(0, 100),
    match: (match ?? this.match).clamp(0, 100),
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'blur': blur,
    'color': color,
    'color2': color2,
    'angle': angle,
    if (imageRef.isNotEmpty) 'imageRef': imageRef,
    'fit': fit.name,
    'edgeShift': edgeShift,
    'feather': feather,
    'spill': spill,
    'match': match,
  };

  List<Object> get _props => [
    mode,
    blur,
    color,
    color2,
    angle,
    imageRef,
    fit,
    edgeShift,
    feather,
    spill,
    match,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! BackdropChange) return false;
    final a = _props, b = other._props;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_props);
}
