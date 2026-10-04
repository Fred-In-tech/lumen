import 'package:collection/collection.dart';

import 'develop_settings.dart';
import 'param_registry.dart';
import 'portrait.dart';
import 'settings_subset.dart';
import 'tone_curve.dart';
import 'treatment.dart';

/// A sparse look. Omitted keys keep current values; explicit values (even 0) apply.
/// Geometry is never part of a preset.
class Preset {
  Preset({
    required this.id,
    required this.name,
    this.group = 'User',
    this.builtIn = false,
    required Map<ParamId, double> values,
    this.curves,
    this.treatment,
    this.portrait,
    this.createdAt,
  }) : values = Map.unmodifiable({
         for (final e in values.entries)
           if (ParamRegistry.contains(e.key))
             e.key: ParamRegistry.byId(e.key).clamp(e.value),
       });

  factory Preset.fromSettings({
    required String id,
    required String name,
    required DevelopSettings settings,
    Set<SettingsGroup> groups = SettingsGroup.defaultCopy,
    String group = 'User',
    DateTime? createdAt,
  }) {
    return Preset(
      id: id,
      name: name,
      group: group,
      values: {
        for (final e in settings.nonDefaultValues.entries)
          if (groups.contains(SettingsGroup.forParam(e.key))) e.key: e.value,
      },
      curves:
          groups.contains(SettingsGroup.curve) && !settings.curves.isIdentity
          ? settings.curves
          : null,
      treatment:
          groups.contains(SettingsGroup.bw) &&
              settings.treatment != Treatment.color
          ? settings.treatment
          : null,
      portrait:
          groups.contains(SettingsGroup.portrait) &&
              !settings.portrait.withoutIndividuals.isDefault
          ? settings.portrait.withoutIndividuals
          : null,
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );
  }

  factory Preset.fromJson(Map<String, Object?> json) => Preset(
    id: json['id'] as String? ?? 'preset',
    name: json['name'] as String? ?? 'Preset',
    group: json['group'] as String? ?? 'User',
    builtIn: json['builtIn'] == true,
    values: {
      for (final e in ((json['values'] as Map?) ?? const {}).entries)
        if (e.key is String && e.value is num)
          e.key as String: (e.value as num).toDouble(),
    },
    curves: json['curves'] == null ? null : CurveSet.fromJson(json['curves']),
    treatment: json['treatment'] == null
        ? null
        : Treatment.fromJson(json['treatment']),
    portrait: json['portrait'] == null
        ? null
        : PortraitSettings.fromJson(json['portrait']).withoutIndividuals,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );

  final String id;
  final String name;
  final String group;
  final bool builtIn;
  final Map<ParamId, double> values;
  final CurveSet? curves;
  final Treatment? treatment;

  /// Group and backdrop retouch values (never per-person).
  final PortraitSettings? portrait;
  final DateTime? createdAt;

  /// Applies this preset at [amount] (0..1), interpolating numeric values from current.
  /// Portrait values interpolate too. Curves and treatment apply when amount ≥ 0.5.
  DevelopSettings apply(DevelopSettings current, {double amount = 1}) {
    final a = amount.clamp(0, 1).toDouble();
    final p = portrait;
    final next = current
        .withValues({
          for (final e in values.entries)
            e.key: current.value(e.key) + (e.value - current.value(e.key)) * a,
        })
        .copyWith(
          portrait: p == null
              ? null
              : PortraitSettings.lerp(current.portrait, p, a),
        );
    if (a < 0.5) return next;
    return next.copyWith(curves: curves, treatment: treatment);
  }

  Preset copyWith({String? name, String? group}) => Preset(
    id: id,
    name: name ?? this.name,
    group: group ?? this.group,
    builtIn: builtIn,
    values: values,
    curves: curves,
    treatment: treatment,
    portrait: portrait,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'schema': 'lumen.preset',
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'group': group,
    'builtIn': builtIn,
    'values': Map<String, double>.of(values),
    'curves': curves?.toJson(),
    'treatment': treatment?.name,
    if (portrait != null) 'portrait': portrait!.toJson(),
    'createdAt': createdAt?.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is Preset &&
      other.id == id &&
      other.name == name &&
      const MapEquality<ParamId, double>().equals(other.values, values) &&
      other.curves == curves &&
      other.treatment == treatment &&
      other.portrait == portrait;

  @override
  int get hashCode =>
      Object.hash(id, name, const MapEquality<ParamId, double>().hash(values));
}
