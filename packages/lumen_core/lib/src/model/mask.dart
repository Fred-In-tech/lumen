import 'package:collection/collection.dart';

import 'mask_shapes.dart';
import 'param_registry.dart';

export 'mask_shapes.dart';

enum MaskKind {
  linear,
  radial,
  subject,
  sky,
  brush,
  background,
  person,
  faceSkin,
  hair,
  clothes,

  /// A kind written by a newer app version. Kept verbatim for round-trips
  /// (see [LocalMask.rawJson]) and rendered as off (inert).
  unsupported;

  /// AI kinds are rasters (see [AiShape]).
  bool get isAi => switch (this) {
    subject ||
    sky ||
    background ||
    person ||
    faceSkin ||
    hair ||
    clothes => true,
    linear || radial || brush || unsupported => false,
  };

  /// Parses a stored kind; unknown or missing → [unsupported] (never a
  /// guess such as radial).
  static MaskKind parse(Object? name) => MaskKind.values.firstWhere(
    (k) => k != unsupported && k.name == name,
    orElse: () => unsupported,
  );
}

/// The 12 params a mask may adjust, in `develop.frag` uniform order
/// (`uMask*A`: exposure, temp, tint, saturation; `uMask*B`: highlights,
/// shadows, clarity, texture; `uMask*C`: dehaze, contrast, whites, blacks).
const List<ParamId> kLocalParams = [
  P.exposure,
  P.temp,
  P.tint,
  P.saturation,
  P.highlights,
  P.shadows,
  P.clarity,
  P.texture,
  P.dehaze,
  P.contrast,
  P.whites,
  P.blacks,
];

Map<ParamId, double> _sanitize(Map<Object?, Object?> raw) {
  final out = <ParamId, double>{};
  for (final e in raw.entries) {
    final spec = e.key is String
        ? ParamRegistry.tryById(e.key as String)
        : null;
    if (spec == null || !spec.localAllowed || e.value is! num) continue;
    final v = spec.clamp((e.value as num).toDouble());
    if (v != 0) out[spec.id] = v;
  }
  return Map.unmodifiable(out);
}

/// A local adjustment mask (Lightroom-style). Coverage = shape (linear,
/// radial or AI raster; none for brush) → brush strokes add/erase →
/// [invert] → × [opacity]. [adjustments] are sparse deltas on top of the
/// global values, limited to `localAllowed` params. At most [maxMasks].
class LocalMask {
  const LocalMask({
    required this.id,
    required this.name,
    required this.kind,
    this.invert = false,
    this.opacity = 1,
    this.shape = const {},
    this.strokes = const [],
    this.adjustments = const {},
    this.rawJson,
  });

  factory LocalMask.fromJson(Map<String, Object?> json) {
    final strokes = json['strokes'];
    final kind = MaskKind.parse(json['kind']);
    return LocalMask(
      id: json['id'] as String? ?? 'mask',
      name: json['name'] as String? ?? 'Mask',
      kind: kind,
      rawJson: kind == MaskKind.unsupported
          ? Map<String, Object?>.unmodifiable(json)
          : null,
      invert: json['invert'] == true,
      opacity: ((json['opacity'] as num?) ?? 1)
          .toDouble()
          .clamp(0, 1)
          .toDouble(),
      shape: Map<String, Object?>.unmodifiable(
        (json['shape'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      strokes: strokes is List
          ? List.unmodifiable(
              strokes.whereType<Map<Object?, Object?>>().map(
                (s) => BrushStroke.fromJson(s.cast()),
              ),
            )
          : const [],
      adjustments: _sanitize((json['adjustments'] as Map?) ?? const {}),
    );
  }

  static const int maxMasks = 8;

  final String id;
  final String name;
  final MaskKind kind;
  final bool invert;
  final double opacity;

  /// Raw shape parameters; read them through [linear], [radial] or [ai].
  final Map<String, Object?> shape;
  final List<BrushStroke> strokes;
  final Map<ParamId, double> adjustments;

  /// The original JSON of an [MaskKind.unsupported] mask (null otherwise).
  /// [toJson] writes it back, so newer data survives an older app.
  final Map<String, Object?>? rawJson;

  bool get isSupported => kind != MaskKind.unsupported;

  /// The stored kind string (the newer kind's name when unsupported).
  String get rawKind =>
      rawJson?['kind'] is String ? rawJson!['kind'] as String : kind.name;

  LinearShape get linear => LinearShape.fromJson(shape);
  RadialShape get radial => RadialShape.fromJson(shape);
  AiShape get ai => AiShape.fromJson(shape);

  /// Validated adjustments (local-allowed, clamped, non-zero); always empty
  /// for unsupported masks (they are inert).
  Map<ParamId, double> get localAdjustments =>
      isSupported ? _sanitize(adjustments) : const {};

  bool get hasAdjustments => localAdjustments.isNotEmpty;

  /// Changes only when the coverage changes (not with name/adjustments).
  int get coverageKey => Object.hash(
    kind,
    invert,
    opacity,
    const DeepCollectionEquality().hash(shape),
    const ListEquality<BrushStroke>().hash(strokes),
  );

  LocalMask copyWith({
    String? name,
    MaskKind? kind,
    bool? invert,
    double? opacity,
    Map<String, Object?>? shape,
    List<BrushStroke>? strokes,
    Map<ParamId, double>? adjustments,
  }) => LocalMask(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    invert: invert ?? this.invert,
    opacity: (opacity ?? this.opacity).clamp(0.0, 1.0),
    shape: shape == null ? this.shape : Map.unmodifiable(shape),
    strokes: strokes == null ? this.strokes : List.unmodifiable(strokes),
    adjustments: adjustments == null
        ? this.adjustments
        : _sanitize(adjustments),
    rawJson: rawJson,
  );

  /// Returns a copy with [param] set (clamped; 0 removes it). Throws for
  /// params that are not `localAllowed`.
  LocalMask withAdjustment(ParamId param, double value) {
    final spec = ParamRegistry.byId(param);
    if (!spec.localAllowed) {
      throw ArgumentError.value(param, 'param', 'not allowed in a mask');
    }
    return copyWith(adjustments: {...adjustments, param: value});
  }

  Map<String, Object?> toJson() {
    final raw = rawJson;
    if (raw != null) return {...raw, 'id': id, 'name': name};
    return _supportedJson();
  }

  Map<String, Object?> _supportedJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'invert': invert,
    'opacity': opacity,
    'shape': shape,
    if (strokes.isNotEmpty) 'strokes': [for (final s in strokes) s.toJson()],
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
      const ListEquality<BrushStroke>().equals(other.strokes, strokes) &&
      const MapEquality<String, double>().equals(
        other.adjustments,
        adjustments,
      ) &&
      const DeepCollectionEquality().equals(other.rawJson, rawJson);

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    invert,
    opacity,
    const ListEquality<BrushStroke>().hash(strokes),
    const MapEquality<String, double>().hash(adjustments),
  );
}
