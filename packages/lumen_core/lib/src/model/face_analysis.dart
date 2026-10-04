import 'package:collection/collection.dart';

import 'portrait.dart';

/// How a face got its [FaceGroup]: suggested automatically or set by the user.
enum TagSource { auto, manual }

/// Face bounding box, normalized to the oriented source image (0..1).
class FaceBox {
  const FaceBox(this.x, this.y, this.width, this.height);

  factory FaceBox.fromJson(Object? json) {
    if (json is! List || json.length != 4 || json.any((v) => v is! num)) {
      return const FaceBox(0, 0, 0, 0);
    }
    final v = json.cast<num>().map((n) => n.toDouble()).toList();
    return FaceBox(v[0], v[1], v[2], v[3]);
  }

  final double x;
  final double y;
  final double width;
  final double height;

  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  List<double> toJson() => [x, y, width, height];

  @override
  bool operator ==(Object other) =>
      other is FaceBox &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

class DetectedFace {
  const DetectedFace({
    required this.id,
    required this.box,
    this.landmarks = const [],
    this.confidence = 1,
    this.group = FaceGroup.all,
    this.personId,
    this.tagSource = TagSource.auto,
  });

  factory DetectedFace.fromJson(Map<String, Object?> json) => DetectedFace(
    id: json['id'] as String? ?? '',
    box: FaceBox.fromJson(json['box']),
    landmarks: List.unmodifiable(
      ((json['landmarks'] as List?) ?? const []).whereType<num>().map(
        (n) => n.toDouble(),
      ),
    ),
    confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
    group: FaceGroup.fromName(json['group']),
    personId: json['personId'] as String?,
    tagSource: json['tagSource'] == TagSource.manual.name
        ? TagSource.manual
        : TagSource.auto,
  );

  final String id;
  final FaceBox box;

  /// Flat normalized (x, y) pairs in model order (e.g. 478 MediaPipe points).
  final List<double> landmarks;
  final double confidence;
  final FaceGroup group;

  /// Stable across a shoot when faces are clustered; enables per-person edits.
  final String? personId;
  final TagSource tagSource;

  int get landmarkCount => landmarks.length ~/ 2;

  DetectedFace copyWith({
    FaceGroup? group,
    String? personId,
    TagSource? tagSource,
  }) => DetectedFace(
    id: id,
    box: box,
    landmarks: landmarks,
    confidence: confidence,
    group: group ?? this.group,
    personId: personId ?? this.personId,
    tagSource: tagSource ?? this.tagSource,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'box': box.toJson(),
    'landmarks': landmarks,
    'confidence': confidence,
    'group': group.name,
    'personId': personId,
    'tagSource': tagSource.name,
  };

  @override
  bool operator ==(Object other) =>
      other is DetectedFace &&
      other.id == id &&
      other.box == box &&
      const ListEquality<double>().equals(other.landmarks, landmarks) &&
      other.confidence == confidence &&
      other.group == group &&
      other.personId == personId &&
      other.tagSource == tagSource;

  @override
  int get hashCode => Object.hash(id, box, group, personId, tagSource);
}

/// Faces found in one photo.
///
/// Face geometry is biometric data: this lives in the local, non-synced
/// analysis cache and is never written into `edit.json` (see research 07).
class FaceAnalysis {
  const FaceAnalysis({
    required this.imageWidth,
    required this.imageHeight,
    required this.modelVersion,
    this.faces = const [],
  });

  factory FaceAnalysis.fromJson(Map<String, Object?> json) => FaceAnalysis(
    imageWidth: (json['imageWidth'] as num?)?.toInt() ?? 0,
    imageHeight: (json['imageHeight'] as num?)?.toInt() ?? 0,
    modelVersion: json['modelVersion'] as String? ?? '',
    faces: List.unmodifiable(
      ((json['faces'] as List?) ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((m) => DetectedFace.fromJson(m.cast())),
    ),
  );

  static const schemaVersion = 1;

  final int imageWidth;
  final int imageHeight;
  final String modelVersion;
  final List<DetectedFace> faces;

  DetectedFace? faceById(String id) =>
      faces.firstWhereOrNull((f) => f.id == id);

  /// Sets [faceId]'s group (and optionally person) as a manual tag.
  FaceAnalysis withTag(String faceId, FaceGroup group, {String? personId}) =>
      FaceAnalysis(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        modelVersion: modelVersion,
        faces: List.unmodifiable([
          for (final f in faces)
            f.id == faceId
                ? f.copyWith(
                    group: group,
                    personId: personId,
                    tagSource: TagSource.manual,
                  )
                : f,
        ]),
      );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'modelVersion': modelVersion,
    'faces': [for (final f in faces) f.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is FaceAnalysis &&
      other.imageWidth == imageWidth &&
      other.imageHeight == imageHeight &&
      other.modelVersion == modelVersion &&
      const ListEquality<DetectedFace>().equals(other.faces, faces);

  @override
  int get hashCode => Object.hash(
    imageWidth,
    imageHeight,
    modelVersion,
    const ListEquality<DetectedFace>().hash(faces),
  );
}
