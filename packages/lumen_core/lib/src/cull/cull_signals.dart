import 'package:collection/collection.dart';

double _num(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;

/// Quality signals of one face (source-pixel measurements).
class FaceCullSignal {
  const FaceCullSignal({
    required this.faceId,
    required this.area,
    required this.sharpness,
    this.earRight,
    this.earLeft,
  });

  factory FaceCullSignal.fromJson(Map<String, Object?> j) => FaceCullSignal(
    faceId: j['id'] as String? ?? '',
    area: _num(j['area']),
    sharpness: _num(j['sharp']),
    earRight: (j['earR'] as num?)?.toDouble(),
    earLeft: (j['earL'] as num?)?.toDouble(),
  );

  final String faceId;

  /// Box area as a fraction of the image.
  final double area;

  /// Contrast-normalized Laplacian energy ([sharpnessScore]).
  final double sharpness;

  /// Eye aspect ratios (null without landmarks, e.g. a rejected face).
  final double? earRight;
  final double? earLeft;

  bool get hasEyes => earRight != null && earLeft != null;

  /// Mean EAR of both eyes, or null.
  double? get ear {
    final r = earRight, l = earLeft;
    return r == null || l == null ? null : (r + l) / 2;
  }

  Map<String, Object?> toJson() => {
    'id': faceId,
    'area': area,
    'sharp': sharpness,
    if (earRight != null) 'earR': earRight,
    if (earLeft != null) 'earL': earLeft,
  };

  @override
  bool operator ==(Object other) =>
      other is FaceCullSignal &&
      other.faceId == faceId &&
      other.area == area &&
      other.sharpness == sharpness &&
      other.earRight == earRight &&
      other.earLeft == earLeft;

  @override
  int get hashCode => Object.hash(faceId, area, sharpness, earRight, earLeft);
}

/// Per-photo culling measurements; the cull cache stores these and the
/// suggestions are re-derived from them with any [CullConfig].
class CullSignals {
  CullSignals({
    required this.sharpness,
    required this.highlightClip,
    required this.shadowClip,
    required this.meanLuma,
    required this.dHash,
    List<FaceCullSignal> faces = const [],
    this.faceHighlightClip = 0,
    this.capturedAt,
  }) : faces = List.unmodifiable(faces);

  static CullSignals? tryFromJson(Object? json) {
    if (json is! Map || json['v'] != version) return null;
    final faces = json['faces'];
    final hash = json['dhash'];
    if (hash is! String) return null;
    return CullSignals(
      sharpness: _num(json['sharp']),
      highlightClip: _num(json['hiClip']),
      shadowClip: _num(json['loClip']),
      meanLuma: _num(json['meanLuma'], 0.5),
      faceHighlightClip: _num(json['faceHiClip']),
      dHash: hash,
      capturedAt: DateTime.tryParse(json['captured'] as String? ?? ''),
      faces: [
        if (faces is List)
          for (final f in faces.whereType<Map<Object?, Object?>>())
            FaceCullSignal.fromJson(f.cast()),
      ],
    );
  }

  /// Bump when a measurement changes meaning (cached signals recompute).
  static const version = 1;

  /// Centre sharpness (used when there is no face).
  final double sharpness;

  /// Share of pixels with a channel ≥ 250 / luma ≤ 4 (of 255).
  final double highlightClip;
  final double shadowClip;
  final double meanLuma;

  /// Highlight clip share inside the face boxes.
  final double faceHighlightClip;

  /// 64-bit difference hash, 16 hex digits ([differenceHash]).
  final String dHash;
  final List<FaceCullSignal> faces;
  final DateTime? capturedAt;

  /// The largest face (the main subject), if any.
  FaceCullSignal? get mainFace =>
      faces.isEmpty ? null : faces.reduce((a, b) => a.area >= b.area ? a : b);

  Map<String, Object?> toJson() => {
    'v': version,
    'sharp': sharpness,
    'hiClip': highlightClip,
    'loClip': shadowClip,
    'meanLuma': meanLuma,
    'faceHiClip': faceHighlightClip,
    'dhash': dHash,
    'captured': capturedAt?.toIso8601String(),
    'faces': [for (final f in faces) f.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is CullSignals &&
      other.sharpness == sharpness &&
      other.highlightClip == highlightClip &&
      other.shadowClip == shadowClip &&
      other.meanLuma == meanLuma &&
      other.faceHighlightClip == faceHighlightClip &&
      other.dHash == dHash &&
      other.capturedAt == capturedAt &&
      const ListEquality<FaceCullSignal>().equals(other.faces, faces);

  @override
  int get hashCode => Object.hash(sharpness, dHash, capturedAt, faces.length);
}
