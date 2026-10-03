import 'package:collection/collection.dart';

enum MaskKind { linear, radial, subject, sky, brush }

/// A local adjustment mask. Serialized in schema v1; rendered from Phase 2.
class LocalMask {
  const LocalMask({
    required this.id,
    required this.name,
    required this.kind,
    this.invert = false,
    this.opacity = 1,
    this.shape = const {},
    this.adjustments = const {},
  });

  factory LocalMask.fromJson(Map<String, Object?> json) => LocalMask(
    id: json['id'] as String? ?? 'mask',
    name: json['name'] as String? ?? 'Mask',
    kind: MaskKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => MaskKind.radial,
    ),
    invert: json['invert'] == true,
    opacity: ((json['opacity'] as num?) ?? 1).toDouble().clamp(0, 1).toDouble(),
    shape: Map<String, Object?>.unmodifiable(
      (json['shape'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
    adjustments: Map<String, double>.unmodifiable({
      for (final e in ((json['adjustments'] as Map?) ?? const {}).entries)
        if (e.key is String && e.value is num)
          e.key as String: (e.value as num).toDouble(),
    }),
  );

  static const int maxMasks = 8;

  final String id;
  final String name;
  final MaskKind kind;
  final bool invert;
  final double opacity;
  final Map<String, Object?> shape;
  final Map<String, double> adjustments;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'invert': invert,
    'opacity': opacity,
    'shape': shape,
    'adjustments': adjustments,
  };

  @override
  bool operator ==(Object other) =>
      other is LocalMask &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.invert == invert &&
      other.opacity == opacity &&
      const DeepCollectionEquality().equals(other.shape, shape) &&
      const MapEquality<String, double>().equals(
        other.adjustments,
        adjustments,
      );

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    invert,
    opacity,
    const MapEquality<String, double>().hash(adjustments),
  );
}
