/// Privacy-safe EXIF facts. GPS, serial numbers and owner names are excluded
/// by type: there is no field to put them in.
class ExifSummary {
  const ExifSummary({
    this.camera,
    this.lens,
    this.iso,
    this.shutter,
    this.exposureSeconds,
    this.aperture,
    this.focalMm,
    this.capturedAt,
    this.flash,
    this.orientation,
  });

  factory ExifSummary.fromJson(Object? json) {
    if (json is! Map) return const ExifSummary();
    double? d(String k) => (json[k] as num?)?.toDouble();
    return ExifSummary(
      camera: json['camera'] as String?,
      lens: json['lens'] as String?,
      iso: (json['iso'] as num?)?.toInt(),
      shutter: json['shutter'] as String?,
      exposureSeconds: d('exposureSeconds'),
      aperture: d('aperture'),
      focalMm: d('focalMm'),
      capturedAt: json['capturedAt'] is String
          ? DateTime.tryParse(json['capturedAt'] as String)
          : null,
      flash: json['flash'] as bool?,
      orientation: (json['orientation'] as num?)?.toInt(),
    );
  }

  final String? camera;
  final String? lens;
  final int? iso;

  /// Display string such as "1/120".
  final String? shutter;
  final double? exposureSeconds;
  final double? aperture;
  final double? focalMm;

  /// Local capture time as written by the camera (no timezone).
  final DateTime? capturedAt;
  final bool? flash;
  final int? orientation;

  bool get isEmpty =>
      camera == null &&
      iso == null &&
      exposureSeconds == null &&
      capturedAt == null;

  Map<String, Object?> toJson() => {
    if (camera != null) 'camera': camera,
    if (lens != null) 'lens': lens,
    if (iso != null) 'iso': iso,
    if (shutter != null) 'shutter': shutter,
    if (exposureSeconds != null) 'exposureSeconds': exposureSeconds,
    if (aperture != null) 'aperture': aperture,
    if (focalMm != null) 'focalMm': focalMm,
    if (capturedAt != null) 'capturedAt': capturedAt!.toIso8601String(),
    if (flash != null) 'flash': flash,
    if (orientation != null) 'orientation': orientation,
  };
}
