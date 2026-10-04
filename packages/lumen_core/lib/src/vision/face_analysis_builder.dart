import '../model/face_analysis.dart';
import 'face_detection.dart';
import 'face_geometry.dart';
import 'face_key.dart';
import 'mesh_keypoints.dart';

/// One face after detection and landmarking, before the reject rules.
class FaceCandidate {
  const FaceCandidate({
    required this.detection,
    required this.landmarks,
    required this.presence,
  });

  /// Detector output normalized to the image (letterbox removed).
  final FaceDetection detection;

  /// Flat normalized (x, y) mesh points; empty when the mesh did not run.
  final List<double> landmarks;

  /// Sigmoid of the landmark model's face flag.
  final double presence;
}

/// A face that gets no automatic retouch, with the reason.
class RejectedFace {
  const RejectedFace({
    required this.id,
    required this.box,
    required this.reason,
    this.confidence = 1,
  });

  factory RejectedFace.fromJson(Map<String, Object?> json) => RejectedFace(
    id: json['id'] as String? ?? '',
    box: FaceBox.fromJson(json['box']),
    reason:
        FaceRejectReason.fromName(json['reason']) ??
        FaceRejectReason.lowPresence,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
  );

  final String id;
  final FaceBox box;
  final FaceRejectReason reason;
  final double confidence;

  Map<String, Object?> toJson() => {
    'id': id,
    'box': box.toJson(),
    'reason': reason.name,
    'confidence': confidence,
  };

  @override
  bool operator ==(Object other) =>
      other is RejectedFace &&
      other.id == id &&
      other.box == box &&
      other.reason == reason &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(id, box, reason, confidence);
}

/// Accepted faces (as the shared [FaceAnalysis]) plus the rejected ones.
class FaceAnalysisResult {
  const FaceAnalysisResult({required this.analysis, this.rejected = const []});

  final FaceAnalysis analysis;
  final List<RejectedFace> rejected;
}

/// Applies the reject rules and assembles [FaceAnalysis].
///
/// [imageWidth]/[imageHeight] are the oriented source size (lengths for the
/// reject rules are measured there). Faces are ordered left → right, then top
/// → bottom; ids are [faceKey]s, with `-2`, `-3`… on the rare collision.
FaceAnalysisResult buildFaceAnalysis({
  required int imageWidth,
  required int imageHeight,
  required String modelVersion,
  required List<FaceCandidate> candidates,
  FaceRejectRules rules = const FaceRejectRules(),
}) {
  final ordered = [...candidates]
    ..sort((a, b) {
      final c = a.detection.centerX.compareTo(b.detection.centerX);
      return c != 0 ? c : a.detection.centerY.compareTo(b.detection.centerY);
    });
  final used = <String, int>{};
  final accepted = <DetectedFace>[];
  final rejected = <RejectedFace>[];
  for (final c in ordered) {
    final box = c.detection.toFaceBox();
    final base = faceKey(box);
    final n = (used[base] ?? 0) + 1;
    used[base] = n;
    final id = n == 1 ? base : '$base-$n';
    final reason = c.landmarks.length < MeshKeypoints.pointCount * 2
        ? FaceRejectReason.lowPresence
        : rules.evaluate(
            presence: c.presence,
            geometry: FaceGeometry.fromLandmarks(
              c.landmarks,
              imageWidth: imageWidth,
              imageHeight: imageHeight,
            ),
          );
    if (reason != null) {
      rejected.add(
        RejectedFace(
          id: id,
          box: box,
          reason: reason,
          confidence: c.detection.score,
        ),
      );
      continue;
    }
    accepted.add(
      DetectedFace(
        id: id,
        box: box,
        landmarks: List.unmodifiable(c.landmarks),
        confidence: c.detection.score,
      ),
    );
  }
  return FaceAnalysisResult(
    analysis: FaceAnalysis(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      modelVersion: modelVersion,
      faces: List.unmodifiable(accepted),
    ),
    rejected: List.unmodifiable(rejected),
  );
}

/// Copies manual group/person tags from [previous] onto faces of [next] with
/// the same id, so a re-analysis (new model version) keeps the user's tags.
FaceAnalysis carryOverManualTags(FaceAnalysis previous, FaceAnalysis next) {
  final manual = {
    for (final f in previous.faces)
      if (f.tagSource == TagSource.manual) f.id: f,
  };
  if (manual.isEmpty) return next;
  return FaceAnalysis(
    imageWidth: next.imageWidth,
    imageHeight: next.imageHeight,
    modelVersion: next.modelVersion,
    faces: List.unmodifiable([
      for (final f in next.faces)
        switch (manual[f.id]) {
          final old? => f.copyWith(
            group: old.group,
            personId: old.personId,
            tagSource: TagSource.manual,
          ),
          null => f,
        },
    ]),
  );
}
