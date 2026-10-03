import 'exif_summary.dart';

/// One photo in the library index (`catalog.json`).
class CatalogEntry {
  const CatalogEntry({
    required this.assetId,
    required this.fileName,
    required this.originalPath,
    required this.format,
    required this.width,
    required this.height,
    required this.bytes,
    required this.importedAt,
    this.exif = const ExifSummary(),
    this.hasEdits = false,
    this.editedAt,
    this.aiEngine,
    this.aiStyle,
    this.thumbVersion = 0,
    this.rating = 0,
    this.flag = 'none',
  });

  factory CatalogEntry.fromJson(Map<String, Object?> json) {
    final ai = json['ai'];
    return CatalogEntry(
      assetId: json['assetId'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      originalPath: json['original'] as String? ?? '',
      format: json['format'] as String? ?? 'jpeg',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      importedAt:
          DateTime.tryParse(json['importedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      exif: ExifSummary.fromJson(json['exif']),
      hasEdits: json['hasEdits'] == true,
      editedAt: DateTime.tryParse(json['editedAt'] as String? ?? ''),
      aiEngine: ai is Map ? ai['engine'] as String? : null,
      aiStyle: ai is Map ? ai['style'] as String? : null,
      thumbVersion: (json['thumbVersion'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      flag: json['flag'] as String? ?? 'none',
    );
  }

  final String assetId;
  final String fileName;

  /// Path relative to the catalog root, e.g. `originals/<id>.jpg`.
  final String originalPath;
  final String format;
  final int width;
  final int height;
  final int bytes;
  final DateTime importedAt;
  final ExifSummary exif;
  final bool hasEdits;
  final DateTime? editedAt;
  final String? aiEngine;
  final String? aiStyle;
  final int thumbVersion;
  final int rating;
  final String flag;

  DateTime get sortDate => exif.capturedAt ?? importedAt;

  CatalogEntry copyWith({
    bool? hasEdits,
    DateTime? editedAt,
    String? aiEngine,
    String? aiStyle,
    int? thumbVersion,
    int? rating,
    String? flag,
    int? width,
    int? height,
  }) => CatalogEntry(
    assetId: assetId,
    fileName: fileName,
    originalPath: originalPath,
    format: format,
    width: width ?? this.width,
    height: height ?? this.height,
    bytes: bytes,
    importedAt: importedAt,
    exif: exif,
    hasEdits: hasEdits ?? this.hasEdits,
    editedAt: editedAt ?? this.editedAt,
    aiEngine: aiEngine ?? this.aiEngine,
    aiStyle: aiStyle ?? this.aiStyle,
    thumbVersion: thumbVersion ?? this.thumbVersion,
    rating: rating ?? this.rating,
    flag: flag ?? this.flag,
  );

  Map<String, Object?> toJson() => {
    'assetId': assetId,
    'fileName': fileName,
    'original': originalPath,
    'format': format,
    'width': width,
    'height': height,
    'bytes': bytes,
    'importedAt': importedAt.toIso8601String(),
    'exif': exif.toJson(),
    'hasEdits': hasEdits,
    'editedAt': editedAt?.toIso8601String(),
    'ai': aiEngine == null ? null : {'engine': aiEngine, 'style': aiStyle},
    'thumbVersion': thumbVersion,
    'rating': rating,
    'flag': flag,
  };
}
