import 'dart:math' as math;

/// File formats an export can write.
enum ExportFileFormat {
  jpeg('jpg', 'JPEG', sixteenBit: false, hasQuality: true),
  png('png', 'PNG', sixteenBit: false, hasQuality: false),
  png16('png', 'PNG 16-bit', sixteenBit: true, hasQuality: false),
  tiff16('tif', 'TIFF 16-bit', sixteenBit: true, hasQuality: false);

  const ExportFileFormat(
    this.extension,
    this.label, {
    required this.sixteenBit,
    required this.hasQuality,
  });

  final String extension;
  final String label;

  /// 16 bits per channel (65 536 levels) instead of 8.
  final bool sixteenBit;

  /// Takes a quality setting (JPEG).
  final bool hasQuality;

  /// The format named [name], JPEG for anything unknown.
  static ExportFileFormat byName(Object? name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return jpeg;
  }
}

/// Unsharp mask applied to the finished output, by destination.
enum OutputSharpen {
  none('None'),
  screen('Screen'),
  printLow('Print, low'),
  printStandard('Print, standard');

  const OutputSharpen(this.label);
  final String label;

  static OutputSharpen byName(Object? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return none;
  }
}

enum WatermarkPosition {
  topLeft('Top left'),
  topRight('Top right'),
  center('Center'),
  bottomLeft('Bottom left'),
  bottomRight('Bottom right');

  const WatermarkPosition(this.label);
  final String label;

  static WatermarkPosition byName(Object? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return bottomRight;
  }
}

/// Smallest and largest watermark text height, as a fraction of the
/// output's short edge.
const double kWatermarkMinSize = 0.01;
const double kWatermarkMaxSize = 0.2;

/// A text watermark drawn in white over the finished output.
class Watermark {
  const Watermark({
    required this.text,
    this.position = WatermarkPosition.bottomRight,
    this.opacity = 0.6,
    this.size = 0.04,
  });

  /// Null for anything that is not a watermark with text.
  static Watermark? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = (json['text'] as String? ?? '').trim();
    if (text.isEmpty) return null;
    return Watermark(
      text: text,
      position: WatermarkPosition.byName(json['position']),
      opacity: ((json['opacity'] as num?) ?? 0.6).toDouble().clamp(0.0, 1.0),
      size: ((json['size'] as num?) ?? 0.04).toDouble().clamp(
        kWatermarkMinSize,
        kWatermarkMaxSize,
      ),
    );
  }

  final String text;
  final WatermarkPosition position;

  /// 0 (invisible) … 1 (solid).
  final double opacity;

  /// Text height as a fraction of the output's short edge.
  final double size;

  Map<String, Object?> toJson() => {
    'text': text,
    'position': position.name,
    'opacity': opacity,
    'size': size,
  };

  @override
  bool operator ==(Object other) =>
      other is Watermark &&
      other.text == text &&
      other.position == position &&
      other.opacity == opacity &&
      other.size == size;

  @override
  int get hashCode => Object.hash(text, position, opacity, size);
}

enum _SizeKind { none, longEdge, megapixels, box }

/// How large an export may be. Never upscales.
class ExportSizeLimit {
  const ExportSizeLimit.none() : _kind = _SizeKind.none, _a = 0, _b = 0;

  /// Long edge at most [pixels].
  const ExportSizeLimit.longEdge(int pixels)
    : _kind = _SizeKind.longEdge,
      _a = pixels,
      _b = 0;

  /// At most [megapixels] million pixels, aspect kept.
  const ExportSizeLimit.megapixels(int megapixels)
    : _kind = _SizeKind.megapixels,
      _a = megapixels,
      _b = 0;

  /// Width at most [width] and height at most [height] (Instagram:
  /// 1080 × 1350 fits 4:5 portraits at 1350 and landscapes at 1080 wide).
  const ExportSizeLimit.box(int width, int height)
    : _kind = _SizeKind.box,
      _a = width,
      _b = height;

  factory ExportSizeLimit.fromJson(Object? json) {
    if (json is! Map) return const ExportSizeLimit.none();
    final a = (json['value'] as num?)?.toInt() ?? 0;
    final b = (json['height'] as num?)?.toInt() ?? 0;
    if (a <= 0) return const ExportSizeLimit.none();
    return switch (json['kind']) {
      'longEdge' => ExportSizeLimit.longEdge(a),
      'megapixels' => ExportSizeLimit.megapixels(a),
      'box' when b > 0 => ExportSizeLimit.box(a, b),
      _ => const ExportSizeLimit.none(),
    };
  }

  final _SizeKind _kind;
  final int _a;
  final int _b;

  bool get isNone => _kind == _SizeKind.none;

  /// The long edge for [longEdge] limits, else null.
  int? get longEdgePixels => _kind == _SizeKind.longEdge ? _a : null;

  /// The megapixels for [megapixels] limits, else null.
  int? get megapixelLimit => _kind == _SizeKind.megapixels ? _a : null;

  String get label => switch (_kind) {
    _SizeKind.none => 'Full size',
    _SizeKind.longEdge => 'Long edge $_a px',
    _SizeKind.megapixels => '$_a MP',
    _SizeKind.box => 'Fit $_a × $_b px',
  };

  /// Scale (≤ 1) for a [w]×[h] output.
  double _scale(int w, int h) => switch (_kind) {
    _ when _a <= 0 || (_kind == _SizeKind.box && _b <= 0) => 1.0,
    _SizeKind.none => 1.0,
    _SizeKind.longEdge => _a / math.max(w, h),
    _SizeKind.megapixels => math.sqrt(_a * 1e6 / (w * h)),
    _SizeKind.box => math.min(_a / w, _b / h),
  };

  /// The output size for a [w]×[h] photo (after crop).
  (int, int) fit(int w, int h) {
    final s = _scale(w, h);
    if (s >= 1) return (w, h);
    if (_kind == _SizeKind.megapixels) {
      return (math.max(1, (w * s).floor()), math.max(1, (h * s).floor()));
    }
    var ow = math.max(1, (w * s).round()), oh = math.max(1, (h * s).round());
    if (_kind == _SizeKind.box) {
      ow = math.min(ow, _a);
      oh = math.min(oh, _b);
    }
    return (ow, oh);
  }

  /// The long edge to render a [w]×[h] photo at, null for full size.
  int? longEdgeFor(int w, int h) {
    final (ow, oh) = fit(w, h);
    if (ow == w && oh == h) return null;
    return math.max(ow, oh);
  }

  Map<String, Object?> toJson() => {
    'kind': _kind.name,
    'value': _a,
    if (_kind == _SizeKind.box) 'height': _b,
  };

  @override
  bool operator ==(Object other) =>
      other is ExportSizeLimit &&
      other._kind == _kind &&
      other._a == _a &&
      other._b == _b;

  @override
  int get hashCode => Object.hash(_kind, _a, _b);
}

/// The naming template of exports made before presets existed.
const String kDefaultNaming = '{name}_edit';

/// A named set of export settings.
class ExportPreset {
  const ExportPreset({
    required this.id,
    required this.name,
    this.builtin = false,
    this.format = ExportFileFormat.jpeg,
    this.quality = 90,
    this.size = const ExportSizeLimit.none(),
    this.sharpen = OutputSharpen.none,
    this.naming = kDefaultNaming,
    this.folder,
    this.keepMetadata = true,
    this.watermark,
  });

  factory ExportPreset.fromJson(Map<String, Object?> json) {
    final name = (json['name'] as String? ?? '').trim();
    final naming = (json['naming'] as String? ?? '').trim();
    final folder = json['folder'] as String?;
    return ExportPreset(
      id: json['id'] as String? ?? '',
      name: name.isEmpty ? 'Untitled' : name,
      format: ExportFileFormat.byName(json['format']),
      quality: ((json['quality'] as num?) ?? 90).toInt().clamp(1, 100),
      size: ExportSizeLimit.fromJson(json['size']),
      sharpen: OutputSharpen.byName(json['sharpen']),
      naming: naming.isEmpty ? kDefaultNaming : naming,
      folder: folder == null || folder.isEmpty ? null : folder,
      keepMetadata: json['keepMetadata'] != false,
      watermark: Watermark.fromJson(json['watermark']),
    );
  }

  final String id;
  final String name;

  /// Shipped with the app (cannot be deleted or overwritten).
  final bool builtin;
  final ExportFileFormat format;

  /// JPEG quality 1–100.
  final int quality;
  final ExportSizeLimit size;
  final OutputSharpen sharpen;

  /// File name template: `{name}` `{date}` `{seq}` `{preset}`.
  final String naming;

  /// Default destination folder (null: ask).
  final String? folder;

  /// Keep camera EXIF (never location or serial numbers).
  final bool keepMetadata;
  final Watermark? watermark;

  ExportPreset copyWith({
    String? id,
    String? name,
    bool? builtin,
    ExportFileFormat? format,
    int? quality,
    ExportSizeLimit? size,
    OutputSharpen? sharpen,
    String? naming,
    String? folder,
    bool clearFolder = false,
    bool? keepMetadata,
    Watermark? watermark,
    bool clearWatermark = false,
  }) => ExportPreset(
    id: id ?? this.id,
    name: name ?? this.name,
    builtin: builtin ?? this.builtin,
    format: format ?? this.format,
    quality: quality ?? this.quality,
    size: size ?? this.size,
    sharpen: sharpen ?? this.sharpen,
    naming: naming ?? this.naming,
    folder: clearFolder ? null : (folder ?? this.folder),
    keepMetadata: keepMetadata ?? this.keepMetadata,
    watermark: clearWatermark ? null : (watermark ?? this.watermark),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'format': format.name,
    'quality': quality,
    'size': size.toJson(),
    'sharpen': sharpen.name,
    'naming': naming,
    'folder': folder,
    'keepMetadata': keepMetadata,
    'watermark': watermark?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ExportPreset &&
      other.id == id &&
      other.name == name &&
      other.builtin == builtin &&
      other.format == format &&
      other.quality == quality &&
      other.size == size &&
      other.sharpen == sharpen &&
      other.naming == naming &&
      other.folder == folder &&
      other.keepMetadata == keepMetadata &&
      other.watermark == watermark;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    builtin,
    format,
    quality,
    size,
    sharpen,
    naming,
    folder,
    keepMetadata,
    watermark,
  );
}

/// Presets shipped with the app.
const List<ExportPreset> kBuiltinExportPresets = [
  ExportPreset(
    id: 'builtin-web',
    name: 'Web (2048 px JPEG 85)',
    builtin: true,
    quality: 85,
    size: ExportSizeLimit.longEdge(2048),
    sharpen: OutputSharpen.screen,
  ),
  ExportPreset(
    id: 'builtin-full-jpeg',
    name: 'Full size JPEG',
    builtin: true,
    quality: 92,
  ),
  ExportPreset(
    id: 'builtin-print-tiff16',
    name: 'Print TIFF 16-bit full size',
    builtin: true,
    format: ExportFileFormat.tiff16,
    sharpen: OutputSharpen.printStandard,
  ),
  ExportPreset(
    id: 'builtin-instagram',
    name: 'Instagram 1080 px (4:5 aware, long edge 1350)',
    builtin: true,
    size: ExportSizeLimit.box(1080, 1350),
    sharpen: OutputSharpen.screen,
  ),
];
