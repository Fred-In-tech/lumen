import 'package:collection/collection.dart';

import 'geometry.dart';
import 'mask.dart';
import 'param_registry.dart';
import 'tone_curve.dart';
import 'treatment.dart';

/// The full, immutable develop state of one photo.
///
/// Scalar values are sparse: only non-default values are stored.
class DevelopSettings {
  const DevelopSettings({
    this._values = const {},
    this.curves = CurveSet.identity,
    this.treatment = Treatment.color,
    this.geometry = Geometry.none,
    this.masks = const [],
  });

  factory DevelopSettings.fromJson(Object? json) {
    if (json is! Map) return defaults;
    final raw = json['values'];
    final values = <ParamId, double>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final spec = e.key is String
            ? ParamRegistry.tryById(e.key as String)
            : null;
        if (spec == null || e.value is! num) continue;
        final v = spec.clamp((e.value as num).toDouble());
        if (!spec.isDefault(v)) values[spec.id] = v;
      }
    }
    final masksJson = json['masks'];
    return DevelopSettings(
      values: Map.unmodifiable(values),
      curves: CurveSet.fromJson(json['curves']),
      treatment: Treatment.fromJson(json['treatment']),
      geometry: Geometry.fromJson(json['geometry']),
      masks: masksJson is List
          ? List.unmodifiable(
              masksJson.whereType<Map<Object?, Object?>>().map(
                (m) => LocalMask.fromJson(m.cast()),
              ),
            )
          : const [],
    );
  }

  static const defaults = DevelopSettings();

  final Map<ParamId, double> _values;
  final CurveSet curves;
  final Treatment treatment;
  final Geometry geometry;
  final List<LocalMask> masks;

  /// Non-default scalar values (read-only view).
  Map<ParamId, double> get nonDefaultValues => Map.unmodifiable(_values);

  /// Current value of [id], or the registry default.
  double value(ParamId id) =>
      _values[id] ?? ParamRegistry.byId(id).defaultValue;

  /// Returns a copy with [id] set (clamped). Setting the default removes the key.
  DevelopSettings withValue(ParamId id, double v) => withValues({id: v});

  DevelopSettings withValues(Map<ParamId, double> changes) {
    if (changes.isEmpty) return this;
    final next = Map<ParamId, double>.of(_values);
    for (final e in changes.entries) {
      final spec = ParamRegistry.byId(e.key);
      final v = spec.clamp(e.value);
      if (spec.isDefault(v)) {
        next.remove(spec.id);
      } else {
        next[spec.id] = v;
      }
    }
    return DevelopSettings(
      values: Map.unmodifiable(next),
      curves: curves,
      treatment: treatment,
      geometry: geometry,
      masks: masks,
    );
  }

  DevelopSettings copyWith({
    CurveSet? curves,
    Treatment? treatment,
    Geometry? geometry,
    List<LocalMask>? masks,
  }) => DevelopSettings(
    values: _values,
    curves: curves ?? this.curves,
    treatment: treatment ?? this.treatment,
    geometry: geometry ?? this.geometry,
    masks: masks == null ? this.masks : List.unmodifiable(masks),
  );

  /// Returns a copy with every scalar in [ids] reset to its default.
  DevelopSettings resetParams(Iterable<ParamId> ids) => withValues({
    for (final id in ids) id: ParamRegistry.byId(id).defaultValue,
  });

  bool get isDefault =>
      _values.isEmpty &&
      curves.isIdentity &&
      treatment == Treatment.color &&
      geometry.isIdentity &&
      masks.isEmpty;

  /// Scalar params whose values differ between this and [other].
  Set<ParamId> changedParams(DevelopSettings other) => {
    for (final id in {..._values.keys, ...other._values.keys})
      if ((value(id) - other.value(id)).abs() > 1e-9) id,
  };

  Map<String, Object?> toJson() => {
    'values': Map<String, double>.of(_values),
    'curves': curves.toJson(),
    'treatment': treatment.name,
    'geometry': geometry.toJson(),
    'masks': [for (final m in masks) m.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is DevelopSettings &&
      const MapEquality<ParamId, double>().equals(other._values, _values) &&
      other.curves == curves &&
      other.treatment == treatment &&
      other.geometry == geometry &&
      const ListEquality<LocalMask>().equals(other.masks, masks);

  @override
  int get hashCode => Object.hash(
    const MapEquality<ParamId, double>().hash(_values),
    curves,
    treatment,
    geometry,
    const ListEquality<LocalMask>().hash(masks),
  );

  @override
  String toString() =>
      'DevelopSettings($_values, treatment: ${treatment.name})';
}
