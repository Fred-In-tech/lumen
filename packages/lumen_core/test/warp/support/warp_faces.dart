import 'package:lumen_core/lumen_core.dart';

import '../../retouch/support/synthetic_landmarks.dart';

/// A symmetric synthetic face (MediaPipe 478 landmarks) in pixels.
typedef FacePlace = ({
  String id,
  double cx,
  double cy,
  double iod,
  FaceGroup group,
  String? personId,
});

FacePlace face(
  String id,
  double cx,
  double cy,
  double iod, {
  FaceGroup group = FaceGroup.all,
  String? personId,
}) => (id: id, cx: cx, cy: cy, iod: iod, group: group, personId: personId);

/// Face analysis of [faces] on a [w]×[h] image (no pixels rendered).
FaceAnalysis synthAnalysis(int w, int h, List<FacePlace> faces) {
  final lms = synthLandmarksLocal();
  return FaceAnalysis(
    imageWidth: w,
    imageHeight: h,
    modelVersion: 'synthetic',
    faces: [
      for (final f in faces)
        DetectedFace(
          id: f.id,
          box: FaceBox(
            (f.cx - 1.3 * f.iod) / w,
            (f.cy - 1.5 * f.iod) / h,
            2.6 * f.iod / w,
            3.4 * f.iod / h,
          ),
          landmarks: [
            for (var i = 0; i < FaceMesh.landmarkCount; i++) ...[
              (f.cx + lms[i]!.x * f.iod) / w,
              (f.cy + lms[i]!.y * f.iod) / h,
            ],
          ],
          group: f.group,
          personId: f.personId,
        ),
    ],
  );
}

/// Portrait settings with [values] on the All group.
PortraitSettings shapes(Map<String, double> values) {
  var s = PortraitSettings.empty;
  for (final e in values.entries) {
    s = s.withGroupValue(FaceGroup.all, e.key, e.value);
  }
  return s;
}
