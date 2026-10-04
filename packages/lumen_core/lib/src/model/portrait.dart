import 'package:collection/collection.dart';

/// Retouch profile a detected face uses (Evoto-style groups). These are
/// user-chosen retouch profiles, not identity claims; [all] is the base
/// every face inherits from.
enum FaceGroup {
  all,
  female,
  male,
  child,
  senior;

  static FaceGroup fromName(Object? v) =>
      FaceGroup.values.firstWhere((g) => g.name == v, orElse: () => all);

  String get label => switch (this) {
    all => 'All',
    female => 'Female',
    male => 'Male',
    child => 'Child',
    senior => 'Senior',
  };
}

/// Where a retouch parameter applies: per face, or once per image.
enum PortraitScope { face, image }

enum PortraitSection { skin, blemish, eyes, teeth, shape, background, hair }

class PortraitParamSpec {
  const PortraitParamSpec(
    this.id,
    this.label,
    this.section, {
    this.min = 0,
    this.max = 100,
    this.defaultValue = 0,
    this.scope = PortraitScope.face,
  });

  final String id;
  final String label;
  final PortraitSection section;
  final double min;
  final double max;
  final double defaultValue;
  final PortraitScope scope;

  bool get bipolar => min < 0;

  double clamp(double v) =>
      v.isNaN ? defaultValue : v.clamp(min, max).toDouble();

  bool isDefault(double v) => (v - defaultValue).abs() < 1e-9;
}

/// Retouch parameter ids.
abstract final class PortraitIds {
  static const skinSoftening = 'skin.softening';
  static const skinEven = 'skin.even';
  static const skinTexture = 'skin.texture';
  static const skinShine = 'skin.shine';
  static const acne = 'blemish.acne';
  static const freckle = 'blemish.freckle';
  static const mole = 'blemish.mole';
  static const darkCircles = 'eyes.darkCircles';
  static const eyeBags = 'eyes.bags';
  static const lidProtect = 'eyes.lidProtect';
  static const eyeWhites = 'eyes.whites';
  static const iris = 'eyes.iris';
  static const redVein = 'eyes.redVein';
  static const glare = 'eyes.glare';
  static const teethBrightness = 'teeth.brightness';
  static const teethDesaturate = 'teeth.desaturate';
  static const faceWidth = 'shape.faceWidth';
  static const vShape = 'shape.vShape';
  static const chin = 'shape.chin';
  static const eyeSize = 'shape.eyeSize';
  static const noseWidth = 'shape.noseWidth';
  static const mouthSize = 'shape.mouthSize';
  static const bgClean = 'bg.clean';
  static const bgUnify = 'bg.unify';
  static const bgUnifyLuminance = 'bg.unifyLuminance';
  static const strayHairs = 'hair.strayBeyond';
}

typedef _P = PortraitParamSpec;
typedef _S = PortraitSection;
const _image = PortraitScope.image;

abstract final class PortraitRegistry {
  static const List<PortraitParamSpec> all = [
    _P(PortraitIds.skinSoftening, 'Skin softening', _S.skin),
    _P(PortraitIds.skinEven, 'Even skin tone', _S.skin),
    _P(PortraitIds.skinTexture, 'Texture', _S.skin, min: -100),
    _P(PortraitIds.skinShine, 'Reduce shine', _S.skin),
    _P(PortraitIds.acne, 'Acne & blemishes', _S.blemish),
    _P(PortraitIds.freckle, 'Freckles', _S.blemish),
    _P(PortraitIds.mole, 'Moles', _S.blemish),
    _P(PortraitIds.darkCircles, 'Dark circles', _S.eyes),
    _P(PortraitIds.eyeBags, 'Eye bags', _S.eyes),
    _P(
      PortraitIds.lidProtect,
      'Lower-lid protection',
      _S.eyes,
      defaultValue: 100,
    ),
    _P(PortraitIds.eyeWhites, 'Eye whites', _S.eyes),
    _P(PortraitIds.iris, 'Iris brightness', _S.eyes),
    _P(PortraitIds.redVein, 'Red veins', _S.eyes),
    _P(PortraitIds.glare, 'Glasses glare', _S.eyes),
    _P(PortraitIds.teethBrightness, 'Teeth brightness', _S.teeth),
    _P(PortraitIds.teethDesaturate, 'Teeth whitening', _S.teeth),
    _P(PortraitIds.faceWidth, 'Face width', _S.shape, min: -100),
    _P(PortraitIds.vShape, 'V-shape', _S.shape, min: -100),
    _P(PortraitIds.chin, 'Chin', _S.shape, min: -100),
    _P(PortraitIds.eyeSize, 'Eye size', _S.shape, min: -100),
    _P(PortraitIds.noseWidth, 'Nose width', _S.shape, min: -100),
    _P(PortraitIds.mouthSize, 'Mouth size', _S.shape, min: -100),
    _P(PortraitIds.bgClean, 'Clean backdrop', _S.background, scope: _image),
    _P(
      PortraitIds.bgUnify,
      'Unify backdrop light',
      _S.background,
      scope: _image,
    ),
    _P(
      PortraitIds.bgUnifyLuminance,
      'Backdrop luminance',
      _S.background,
      min: -100,
      scope: _image,
    ),
    _P(PortraitIds.strayHairs, 'Stray hairs', _S.hair, scope: _image),
  ];

  static final Map<String, PortraitParamSpec> _byId = {
    for (final p in all) p.id: p,
  };

  static PortraitParamSpec byId(String id) =>
      _byId[id] ??
      (throw ArgumentError.value(id, 'id', 'Unknown portrait parameter'));

  static PortraitParamSpec? tryById(String id) => _byId[id];

  static List<PortraitParamSpec> inSection(PortraitSection s) =>
      all.where((p) => p.section == s).toList(growable: false);
}

/// Clamps known ids and drops unknown ones. With [dropDefaults], values equal
/// to the registry default are removed (used where "absent" means default).
Map<String, double> _clean(
  Map<String, double> raw, {
  required bool dropDefaults,
}) {
  final out = <String, double>{};
  for (final e in raw.entries) {
    final spec = PortraitRegistry.tryById(e.key);
    if (spec == null) continue;
    final v = spec.clamp(e.value);
    if (dropDefaults && spec.isDefault(v)) continue;
    out[e.key] = v;
  }
  return Map.unmodifiable(out);
}

Map<String, double> _readValues(Object? json, {required bool dropDefaults}) {
  if (json is! Map) return const {};
  return _clean({
    for (final e in json.entries)
      if (e.key is String && e.value is num)
        e.key as String: (e.value as num).toDouble(),
  }, dropDefaults: dropDefaults);
}

/// Portrait retouch settings, stored sparsely.
///
/// Face-scope values live per [FaceGroup] and per person; a face resolves a
/// value as individual → its group → [FaceGroup.all] → registry default.
/// An explicit value on a non-All group or a person is an override even when
/// it equals the default (e.g. "no smoothing on children"). Image-scope values
/// (backdrop, stray hairs) live in [image].
class PortraitSettings {
  const PortraitSettings({
    this.groups = const {},
    this.individuals = const {},
    this.image = const {},
  });

  factory PortraitSettings.fromJson(Object? json) {
    if (json is! Map) return empty;
    final g = json['groups'];
    final ind = json['individuals'];
    final groups = <FaceGroup, Map<String, double>>{};
    if (g is Map) {
      for (final e in g.entries) {
        final group = FaceGroup.values.firstWhereOrNull((x) => x.name == e.key);
        if (group == null) continue;
        final v = _readValues(e.value, dropDefaults: group == FaceGroup.all);
        if (v.isNotEmpty) groups[group] = v;
      }
    }
    final individuals = <String, Map<String, double>>{};
    if (ind is Map) {
      for (final e in ind.entries) {
        if (e.key is! String) continue;
        final v = _readValues(e.value, dropDefaults: false);
        if (v.isNotEmpty) individuals[e.key as String] = v;
      }
    }
    return PortraitSettings(
      groups: Map.unmodifiable(groups),
      individuals: Map.unmodifiable(individuals),
      image: _readValues(json['image'], dropDefaults: true),
    );
  }

  static const empty = PortraitSettings();

  final Map<FaceGroup, Map<String, double>> groups;
  final Map<String, Map<String, double>> individuals;
  final Map<String, double> image;

  bool get isDefault => groups.isEmpty && individuals.isEmpty && image.isEmpty;

  /// True when any face-scope value is set (face retouch must run).
  bool get hasFaceEdits => groups.isNotEmpty || individuals.isNotEmpty;

  /// Effective face-scope value for a face in [group], optionally a person.
  double valueFor(String id, {required FaceGroup group, String? personId}) {
    final spec = PortraitRegistry.byId(id);
    return individuals[personId]?[id] ??
        groups[group]?[id] ??
        groups[FaceGroup.all]?[id] ??
        spec.defaultValue;
  }

  /// Value shown on [group]'s slider (inherits All when not overridden).
  double groupValue(FaceGroup group, String id) => valueFor(id, group: group);

  double imageValue(String id) =>
      image[id] ?? PortraitRegistry.byId(id).defaultValue;

  /// True when non-All [group] explicitly overrides [id].
  bool groupOverrides(FaceGroup group, String id) =>
      group != FaceGroup.all && (groups[group]?.containsKey(id) ?? false);

  bool hasIndividual(String personId) => individuals.containsKey(personId);

  PortraitSettings withGroupValue(FaceGroup group, String id, double v) {
    _requireScope(id, PortraitScope.face);
    final values = _clean({
      ...?groups[group],
      id: v,
    }, dropDefaults: group == FaceGroup.all);
    return _copy(groups: _put(groups, group, values));
  }

  PortraitSettings withIndividualValue(String personId, String id, double v) {
    _requireScope(id, PortraitScope.face);
    final values = _clean({
      ...?individuals[personId],
      id: v,
    }, dropDefaults: false);
    return _copy(individuals: _put(individuals, personId, values));
  }

  /// Removes every per-person override for [personId] (re-attach to group).
  PortraitSettings clearIndividual(String personId) =>
      _copy(individuals: _put(individuals, personId, const {}));

  /// Removes [group]'s override of [id] so it inherits All again.
  PortraitSettings clearGroupOverride(FaceGroup group, String id) {
    final values = Map.of(groups[group] ?? const <String, double>{})
      ..remove(id);
    return _copy(groups: _put(groups, group, values));
  }

  PortraitSettings withImageValue(String id, double v) {
    _requireScope(id, PortraitScope.image);
    return _copy(image: _clean({...image, id: v}, dropDefaults: true));
  }

  /// Without per-person values (presets are not tied to people).
  PortraitSettings get withoutIndividuals =>
      individuals.isEmpty ? this : _copy(individuals: const {});

  /// Interpolates from [from] toward [to] by [t] (0..1) for preset Amount.
  /// Per-person values come from [from]; group overrides present on either
  /// side stay explicit.
  static PortraitSettings lerp(
    PortraitSettings from,
    PortraitSettings to,
    double t,
  ) {
    double mix(double a, double b) => a + (b - a) * t;
    final groups = <FaceGroup, Map<String, double>>{};
    for (final g in {...from.groups.keys, ...to.groups.keys}) {
      final ids = {...?from.groups[g]?.keys, ...?to.groups[g]?.keys};
      final values = _clean({
        for (final id in ids)
          id: mix(from.groupValue(g, id), to.groupValue(g, id)),
      }, dropDefaults: g == FaceGroup.all);
      if (values.isNotEmpty) groups[g] = values;
    }
    return PortraitSettings(
      groups: Map.unmodifiable(groups),
      individuals: from.individuals,
      image: _clean({
        for (final id in {...from.image.keys, ...to.image.keys})
          id: mix(from.imageValue(id), to.imageValue(id)),
      }, dropDefaults: true),
    );
  }

  PortraitSettings _copy({
    Map<FaceGroup, Map<String, double>>? groups,
    Map<String, Map<String, double>>? individuals,
    Map<String, double>? image,
  }) => PortraitSettings(
    groups: groups ?? this.groups,
    individuals: individuals ?? this.individuals,
    image: image ?? this.image,
  );

  static Map<K, Map<String, double>> _put<K>(
    Map<K, Map<String, double>> m,
    K key,
    Map<String, double> values,
  ) {
    final next = Map.of(m);
    if (values.isEmpty) {
      next.remove(key);
    } else {
      next[key] = values;
    }
    return Map.unmodifiable(next);
  }

  static void _requireScope(String id, PortraitScope scope) {
    final actual = PortraitRegistry.byId(id).scope;
    if (actual != scope) {
      throw ArgumentError.value(id, 'id', 'is ${actual.name}-scoped');
    }
  }

  Map<String, Object?> toJson() => {
    'groups': {for (final e in groups.entries) e.key.name: Map.of(e.value)},
    'individuals': {
      for (final e in individuals.entries) e.key: Map.of(e.value),
    },
    'image': Map.of(image),
  };

  static const _eq = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      other is PortraitSettings &&
      _eq.equals(other.groups, groups) &&
      _eq.equals(other.individuals, individuals) &&
      _eq.equals(other.image, image);

  @override
  int get hashCode =>
      Object.hash(_eq.hash(groups), _eq.hash(individuals), _eq.hash(image));
}
