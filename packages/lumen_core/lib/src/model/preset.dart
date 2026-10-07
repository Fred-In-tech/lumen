import 'package:collection/collection.dart';

import 'creative_lut.dart';
import 'develop_settings.dart';
import 'param_registry.dart';
import 'portrait.dart';
import 'settings_subset.dart';
import 'tone_curve.dart';
import 'treatment.dart';

/// Where a preset came from (badges and the Looks manage view).
enum PresetSource {
  /// Saved from the editor ("Save current as preset").
  user,

  /// Ships with the app ([builtIn]).
  builtIn,

  /// Converted from a Lightroom / Camera Raw preset (.xmp, .lrtemplate).
  lightroom,

  /// A .cube LUT used on its own as a look.
  lut;

  static PresetSource fromJson(Object? v, {required bool builtIn}) =>
      PresetSource.values.firstWhere(
        (s) => s.name == v,
        orElse: () => builtIn ? PresetSource.builtIn : PresetSource.user,
      );
}

/// What an import kept from the original file, in plain language.
class PresetImportReport {
  const PresetImportReport({
    required this.fileName,
    this.applied = const [],
    this.approximated = const [],
    this.skipped = const [],
  });

  factory PresetImportReport.fromJson(Object? json) {
    if (json is! Map) return const PresetImportReport(fileName: '');
    List<String> list(Object? v) =>
        v is List ? List.unmodifiable(v.whereType<String>()) : const <String>[];
    return PresetImportReport(
      fileName: json['fileName'] as String? ?? '',
      applied: list(json['applied']),
      approximated: list(json['approximated']),
      skipped: list(json['skipped']),
    );
  }

  /// The file (inside a zip: its path there) the preset was read from.
  final String fileName;

  /// Settings applied as they are (labels such as "Exposure").
  final List<String> applied;

  /// Settings converted with an approximation (see the mapping table).
  final List<String> approximated;

  /// Settings Lumen has no equivalent for (never applied).
  final List<String> skipped;

  Map<String, Object?> toJson() => {
    'fileName': fileName,
    'applied': applied,
    'approximated': approximated,
    'skipped': skipped,
  };

  @override
  bool operator ==(Object other) =>
      other is PresetImportReport &&
      other.fileName == fileName &&
      const ListEquality<String>().equals(other.applied, applied) &&
      const ListEquality<String>().equals(other.approximated, approximated) &&
      const ListEquality<String>().equals(other.skipped, skipped);

  @override
  int get hashCode => Object.hash(
    fileName,
    const ListEquality<String>().hash(applied),
    const ListEquality<String>().hash(skipped),
  );
}

/// A sparse look. Omitted keys keep current values; explicit values (even 0) apply.
/// Geometry is never part of a preset.
///
/// Partial presets (a Lightroom preset only sets what it contains): scalar
/// [values] are sparse, [curves] apply only to [curveChannels] (all four
/// when null), [treatment] and [lut] only when set.
class Preset {
  Preset({
    required this.id,
    required this.name,
    this.group = 'User',
    this.builtIn = false,
    required Map<ParamId, double> values,
    this.curves,
    Set<CurveChannel>? curveChannels,
    this.treatment,
    this.portrait,
    this.lut,
    PresetSource? source,
    this.importReport,
    this.createdAt,
  }) : source = source ?? (builtIn ? PresetSource.builtIn : PresetSource.user),
       curveChannels = curveChannels == null
           ? null
           : Set.unmodifiable(curveChannels),
       values = Map.unmodifiable({
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
              !settings.portrait.transferable.isDefault
          ? settings.portrait.transferable
          : null,
      lut: groups.contains(SettingsGroup.lut) ? settings.lut : null,
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );
  }

  factory Preset.fromJson(Map<String, Object?> json) => Preset(
    id: json['id'] as String? ?? 'preset',
    name: json['name'] as String? ?? 'Preset',
    group: json['group'] as String? ?? 'User',
    builtIn: json['builtIn'] == true,
    source: PresetSource.fromJson(
      json['source'],
      builtIn: json['builtIn'] == true,
    ),
    values: {
      for (final e in ((json['values'] as Map?) ?? const {}).entries)
        if (e.key is String && e.value is num)
          e.key as String: (e.value as num).toDouble(),
    },
    curves: json['curves'] == null ? null : CurveSet.fromJson(json['curves']),
    curveChannels: switch (json['curveChannels']) {
      final List<Object?> l => {
        for (final c in CurveChannel.values)
          if (l.contains(c.name)) c,
      },
      _ => null,
    },
    treatment: json['treatment'] == null
        ? null
        : Treatment.fromJson(json['treatment']),
    portrait: json['portrait'] == null
        ? null
        : PortraitSettings.fromJson(json['portrait']).transferable,
    lut: LutRef.fromJson(json['lut']),
    importReport: json['import'] == null
        ? null
        : PresetImportReport.fromJson(json['import']),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );

  final String id;
  final String name;
  final String group;
  final bool builtIn;
  final Map<ParamId, double> values;
  final CurveSet? curves;

  /// Channels of [curves] this preset sets; null = all four.
  final Set<CurveChannel>? curveChannels;
  final Treatment? treatment;

  /// Creative LUT this preset applies (by reference), or null.
  final LutRef? lut;

  /// Origin: built in, saved in the editor, or imported.
  final PresetSource source;

  /// For imported presets: what was applied and skipped.
  final PresetImportReport? importReport;

  /// A look that is only a LUT (the "LUT: Kodak 2383" cards).
  bool get isLutOnly =>
      lut != null &&
      values.isEmpty &&
      curves == null &&
      treatment == null &&
      portrait == null;

  /// Number of things this preset changes (cards: "12 adjustments").
  int get adjustmentCount =>
      values.length +
      (curves == null ? 0 : 1) +
      (treatment == null ? 0 : 1) +
      (lut == null ? 0 : 1);

  /// Group and backdrop retouch values (never per-person).
  final PortraitSettings? portrait;
  final DateTime? createdAt;

  /// Applies this preset at [amount] (0..1), interpolating numeric values from current.
  /// Portrait values interpolate too. Curves and treatment apply when amount ≥ 0.5.
  /// A LUT applies at its own amount × [amount].
  DevelopSettings apply(DevelopSettings current, {double amount = 1}) {
    final a = amount.clamp(0, 1).toDouble();
    final p = portrait;
    final l = lut;
    final withLut = l == null || a == 0
        ? current
        : current.withLut(l.copyWith(amount: l.amount * a));
    final next = withLut
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
    return next.copyWith(curves: _curvesOn(next.curves), treatment: treatment);
  }

  CurveSet? _curvesOn(CurveSet current) {
    final c = curves;
    final only = curveChannels;
    if (c == null || only == null) return c;
    var out = current;
    for (final ch in only) {
      out = out.withChannel(ch, c.channel(ch));
    }
    return out;
  }

  Preset copyWith({String? name, String? group}) => Preset(
    id: id,
    name: name ?? this.name,
    group: group ?? this.group,
    builtIn: builtIn,
    values: values,
    curves: curves,
    curveChannels: curveChannels,
    treatment: treatment,
    portrait: portrait,
    lut: lut,
    source: source,
    importReport: importReport,
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
    if (curveChannels case final ch?)
      'curveChannels': [
        for (final c in CurveChannel.values)
          if (ch.contains(c)) c.name,
      ],
    'treatment': treatment?.name,
    if (portrait != null) 'portrait': portrait!.toJson(),
    if (lut case final l?) 'lut': l.toJson(),
    'source': source.name,
    if (importReport case final r?) 'import': r.toJson(),
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
      other.portrait == portrait &&
      other.lut == lut &&
      other.group == group &&
      other.source == source &&
      const SetEquality<CurveChannel>().equals(
        other.curveChannels,
        curveChannels,
      );

  @override
  int get hashCode =>
      Object.hash(id, name, const MapEquality<ParamId, double>().hash(values));
}
