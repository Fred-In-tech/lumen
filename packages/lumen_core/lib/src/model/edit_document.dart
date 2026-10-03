import 'develop_settings.dart';
import 'history.dart';
import 'migrations.dart';
import 'param_registry.dart';

/// One AI-made change, kept for the "Explain this edit" list and AI Amount.
class AiChange {
  const AiChange({
    required this.param,
    required this.from,
    required this.to,
    required this.reason,
  });

  factory AiChange.fromJson(Map<String, Object?> json) => AiChange(
    param: json['param'] as String? ?? '',
    from: ((json['from'] as num?) ?? 0).toDouble(),
    to: ((json['to'] as num?) ?? 0).toDouble(),
    reason: json['reason'] as String? ?? '',
  );

  final ParamId param;
  final double from;
  final double to;
  final String reason;

  Map<String, Object?> toJson() => {
    'param': param,
    'from': from,
    'to': to,
    'reason': reason,
  };
}

/// The last AI edit applied to a photo.
class AiRecord {
  const AiRecord({
    required this.engine,
    required this.style,
    this.model,
    this.promptVersion,
    this.intent,
    this.instruction,
    required this.preAi,
    this.postAi,
    this.changes = const [],
    this.degradedReason,
  });

  factory AiRecord.fromJson(Map<String, Object?> json) => AiRecord(
    engine: json['engine'] as String? ?? 'local',
    style: json['style'] as String? ?? 'natural',
    model: json['model'] as String?,
    promptVersion: json['promptVersion'] as String?,
    intent: json['intent'] as String?,
    instruction: json['instruction'] as String?,
    preAi: DevelopSettings.fromJson(json['preAi']),
    postAi: json['postAi'] == null
        ? null
        : DevelopSettings.fromJson(json['postAi']),
    changes: List.unmodifiable(
      ((json['changes'] as List?) ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((m) => AiChange.fromJson(m.cast())),
    ),
    degradedReason: json['degradedReason'] as String?,
  );

  final String engine;
  final String style;
  final String? model;
  final String? promptVersion;
  final String? intent;
  final String? instruction;

  /// Settings right before the AI edit (AI Amount interpolates from here).
  final DevelopSettings preAi;

  /// Settings the AI produced at 100 %.
  final DevelopSettings? postAi;
  final List<AiChange> changes;
  final String? degradedReason;

  Map<String, Object?> toJson() => {
    'engine': engine,
    'style': style,
    'model': model,
    'promptVersion': promptVersion,
    'intent': intent,
    'instruction': instruction,
    'preAi': preAi.toJson(),
    'postAi': postAi?.toJson(),
    'changes': [for (final c in changes) c.toJson()],
    'degradedReason': degradedReason,
  };
}

class Snapshot {
  const Snapshot({
    required this.name,
    required this.settings,
    required this.at,
  });

  factory Snapshot.fromJson(Map<String, Object?> json) => Snapshot(
    name: json['name'] as String? ?? 'Snapshot',
    settings: DevelopSettings.fromJson(json['settings']),
    at:
        DateTime.tryParse(json['at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  final String name;
  final DevelopSettings settings;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'name': name,
    'settings': settings.toJson(),
    'at': at.toIso8601String(),
  };
}

/// Everything persisted per photo (`assets/<id>/edit.json`).
class EditDocument {
  const EditDocument({
    required this.assetId,
    this.schemaVersion = currentSchemaVersion,
    this.engineVersion = currentEngineVersion,
    this.settings = DevelopSettings.defaults,
    this.history = HistoryStack.empty,
    this.snapshots = const [],
    this.ai,
    required this.createdAt,
    required this.updatedAt,
    this.readOnly = false,
  });

  factory EditDocument.create(String assetId, {DateTime? now}) {
    final t = now ?? DateTime.now().toUtc();
    return EditDocument(assetId: assetId, createdAt: t, updatedAt: t);
  }

  factory EditDocument.fromJson(Map<String, Object?> raw) {
    final version =
        (raw['schemaVersion'] as num?)?.toInt() ?? currentSchemaVersion;
    final readOnly = version > currentSchemaVersion;
    final json = readOnly ? raw : migrateEditJson(raw);
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final ai = json['ai'];
    final snaps = json['snapshots'];
    return EditDocument(
      assetId: json['assetId'] as String? ?? '',
      schemaVersion: readOnly ? version : currentSchemaVersion,
      engineVersion: json['engineVersion'] as String? ?? currentEngineVersion,
      settings: DevelopSettings.fromJson(json['settings']),
      history: HistoryStack.fromJson(json['history']),
      snapshots: snaps is List
          ? List.unmodifiable(
              snaps.whereType<Map<Object?, Object?>>().map(
                (m) => Snapshot.fromJson(m.cast()),
              ),
            )
          : const [],
      ai: ai is Map ? AiRecord.fromJson(ai.cast()) : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? epoch,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? epoch,
      readOnly: readOnly,
    );
  }

  static const int currentSchemaVersion = 1;
  static const String currentEngineVersion = 'lumen-1';

  final String assetId;
  final int schemaVersion;
  final String engineVersion;
  final DevelopSettings settings;
  final HistoryStack history;
  final List<Snapshot> snapshots;
  final AiRecord? ai;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True for documents written by a newer app version.
  final bool readOnly;

  bool get hasEdits => !settings.isDefault;

  EditDocument copyWith({
    DevelopSettings? settings,
    HistoryStack? history,
    List<Snapshot>? snapshots,
    AiRecord? ai,
    bool clearAi = false,
    DateTime? updatedAt,
  }) => EditDocument(
    assetId: assetId,
    schemaVersion: schemaVersion,
    engineVersion: engineVersion,
    settings: settings ?? this.settings,
    history: history ?? this.history,
    snapshots: snapshots ?? this.snapshots,
    ai: clearAi ? null : (ai ?? this.ai),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    readOnly: readOnly,
  );

  Map<String, Object?> toJson() => {
    'schema': 'lumen.edit',
    'schemaVersion': schemaVersion,
    'engineVersion': engineVersion,
    'assetId': assetId,
    'settings': settings.toJson(),
    'history': history.toJson(),
    'snapshots': [for (final s in snapshots) s.toJson()],
    'ai': ai?.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
