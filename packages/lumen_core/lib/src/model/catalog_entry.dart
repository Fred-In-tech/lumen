import 'develop_settings.dart';
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
    this.bitDepth,
    this.projectId,
    this.exportedAt,
    this.retouched = false,
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
      bitDepth: (json['bitDepth'] as num?)?.toInt(),
      projectId: switch (json['project']) {
        final String id when id.isNotEmpty => id,
        _ => null,
      },
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? ''),
      retouched: json['retouched'] == true,
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

  /// Bits per channel the file stores (8, 10, 12, 14, 16), read at import;
  /// null when unknown (older catalogs, RAW formats that do not declare
  /// it). Sources above 8 bits are edited on the float path where the
  /// device supports it (docs/HIGH_BIT_DEPTH.md).
  final int? bitDepth;

  /// The project (shoot) this photo belongs to; null: "Unsorted".
  final String? projectId;

  /// When the photo was last exported (single or batch); null: never.
  final DateTime? exportedAt;

  /// True when the edit holds face retouch (portrait face-scope values).
  final bool retouched;

  DateTime get sortDate => exif.capturedAt ?? importedAt;

  /// Exported, and not edited again since.
  bool get exportIsCurrent {
    final out = exportedAt;
    if (out == null) return false;
    final edited = editedAt;
    return edited == null || !edited.isAfter(out);
  }

  /// The entry after saving [settings] at [at]: edit flags follow the
  /// settings (any change, face retouch).
  CatalogEntry withEditState(DevelopSettings settings, DateTime at) => copyWith(
    hasEdits: !settings.isDefault,
    retouched: settings.portrait.hasFaceEdits,
    editedAt: at,
  );

  /// The same photo in project [id] (null: Unsorted).
  CatalogEntry withProject(String? id) => _copy(projectId: id);

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
    DateTime? exportedAt,
    bool? retouched,
  }) => _copy(
    hasEdits: hasEdits ?? this.hasEdits,
    editedAt: editedAt ?? this.editedAt,
    aiEngine: aiEngine ?? this.aiEngine,
    aiStyle: aiStyle ?? this.aiStyle,
    thumbVersion: thumbVersion ?? this.thumbVersion,
    rating: rating ?? this.rating,
    flag: flag ?? this.flag,
    width: width ?? this.width,
    height: height ?? this.height,
    exportedAt: exportedAt ?? this.exportedAt,
    retouched: retouched ?? this.retouched,
    projectId: projectId,
  );

  CatalogEntry _copy({
    required String? projectId,
    bool? hasEdits,
    DateTime? editedAt,
    String? aiEngine,
    String? aiStyle,
    int? thumbVersion,
    int? rating,
    String? flag,
    int? width,
    int? height,
    DateTime? exportedAt,
    bool? retouched,
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
    bitDepth: bitDepth,
    projectId: projectId,
    exportedAt: exportedAt ?? this.exportedAt,
    retouched: retouched ?? this.retouched,
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
    if (bitDepth != null) 'bitDepth': bitDepth,
    if (projectId != null) 'project': projectId,
    if (exportedAt != null) 'exportedAt': exportedAt!.toIso8601String(),
    if (retouched) 'retouched': true,
  };
}
