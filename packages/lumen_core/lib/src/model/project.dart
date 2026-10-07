/// A shoot: the photos of one session (a wedding, a family, a headshot day)
/// moving together from import to delivery. Stored in `catalog.json`.
///
/// Photos point at their project ([CatalogEntry.projectId]); a photo
/// belongs to at most one project, and photos without one are "Unsorted".
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.coverAssetId,
    this.shootDate,
    this.notes,
  });

  /// Null when [json] has no id (the entry is dropped on load).
  static Project? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final created =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final name = json['name'];
    return Project(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name : 'Untitled shoot',
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? created,
      coverAssetId: json['cover'] as String?,
      shootDate: DateTime.tryParse(json['shootDate'] as String? ?? ''),
      notes: json['notes'] as String?,
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;

  /// Last change to the project or its photo list (rename, import, move).
  final DateTime updatedAt;

  /// The photo shown on the project card; null: the newest photo.
  final String? coverAssetId;

  /// The day of the shoot (from the photos' capture date at creation);
  /// null when unknown.
  final DateTime? shootDate;
  final String? notes;

  /// The shoot date when known, else the day the project was made.
  DateTime get displayDate => shootDate ?? createdAt;

  Project copyWith({
    String? name,
    DateTime? updatedAt,
    String? coverAssetId,
    bool clearCover = false,
    DateTime? shootDate,
    String? notes,
  }) => Project(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    coverAssetId: clearCover ? null : (coverAssetId ?? this.coverAssetId),
    shootDate: shootDate ?? this.shootDate,
    notes: notes ?? this.notes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (coverAssetId != null) 'cover': coverAssetId,
    if (shootDate != null) 'shootDate': shootDate!.toIso8601String(),
    if (notes != null) 'notes': notes,
  };
}
