import 'dart:math' as math;

import '../analysis/proxy.dart';
import '../model/face_analysis.dart';
import '../render/rgba_buffer.dart';
import '../vision/face_analysis_builder.dart';
import '../vision/face_geometry.dart';
import '../vision/mesh_keypoints.dart';
import 'cull_signals.dart';
import 'quality_measures.dart';

/// Measures [pixels] (the shared analysis decode) for culling.
///
/// [faces] are the accepted faces (with landmarks: sharpness + eyes);
/// [rejected] faces rejected only for size or yaw still get a sharpness.
/// Pure and isolate-safe; call it through `runInBackground`.
CullSignals computeCullSignals(
  RgbaBuffer pixels, {
  List<DetectedFace> faces = const [],
  List<RejectedFace> rejected = const [],
  DateTime? capturedAt,
}) {
  final w = pixels.width, h = pixels.height;
  final measured = <FaceCullSignal>[
    for (final f in faces) _face(pixels, f.id, f.box, f.landmarks),
    for (final r in rejected)
      if (r.reason != FaceRejectReason.lowPresence)
        _face(pixels, r.id, r.box, const []),
  ];
  final proxy = makeProxy(pixels);
  final exposure = measureExposure(
    proxy,
    faces: [for (final f in faces) f.box],
  );
  final cw = math.max(1, w ~/ 2), ch = math.max(1, h ~/ 2);
  return CullSignals(
    sharpness: sharpnessScore(
      pixels,
      region: (left: (w - cw) ~/ 2, top: (h - ch) ~/ 2, width: cw, height: ch),
    ),
    highlightClip: exposure.highlightClip,
    shadowClip: exposure.shadowClip,
    meanLuma: exposure.meanLuma,
    faceHighlightClip: exposure.faceHighlightClip,
    dHash: differenceHash(proxy),
    faces: measured,
    capturedAt: capturedAt,
  );
}

FaceCullSignal _face(
  RgbaBuffer img,
  String id,
  FaceBox box,
  List<double> landmarks,
) {
  final w = img.width, h = img.height;
  final hasMesh = landmarks.length >= MeshKeypoints.pointCount * 2;
  double ear(List<int> eye) =>
      eyeAspectRatio(landmarks, eye, imageWidth: w, imageHeight: h);
  return FaceCullSignal(
    faceId: id,
    area: box.width * box.height,
    sharpness: sharpnessScore(
      img,
      region: faceBoxRegion(box, w, h, scale: 1.1),
    ),
    earRight: hasMesh ? ear(MeshKeypoints.rightEyeEar) : null,
    earLeft: hasMesh ? ear(MeshKeypoints.leftEyeEar) : null,
  );
}
