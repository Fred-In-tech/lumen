import 'face_detection.dart';

/// MediaPipe's `WEIGHTED` non-max suppression (BlazeFace's choice).
///
/// Detections are visited by descending score. Every remaining detection
/// whose IoU with the current best exceeds [iouThreshold] joins its cluster;
/// the cluster is replaced by one detection whose box and keypoints are the
/// score-weighted mean of its members and whose score is the best member's.
/// Unlike hard NMS this smooths the jitter between neighbouring anchors.
List<FaceDetection> weightedNonMaxSuppression(
  List<FaceDetection> detections, {
  double iouThreshold = 0.3,
  int? maxDetections,
}) {
  var remaining = [...detections]..sort((a, b) => b.score.compareTo(a.score));
  final out = <FaceDetection>[];
  while (remaining.isNotEmpty) {
    if (maxDetections != null && out.length >= maxDetections) break;
    final best = remaining.first;
    final cluster = <FaceDetection>[];
    final rest = <FaceDetection>[];
    for (final d in remaining) {
      (identical(d, best) || best.iou(d) > iouThreshold ? cluster : rest).add(
        d,
      );
    }
    out.add(_weightedMean(best, cluster));
    remaining = rest;
  }
  return List.unmodifiable(out);
}

FaceDetection _weightedMean(FaceDetection best, List<FaceDetection> cluster) {
  if (cluster.length == 1) return best;
  var total = 0.0;
  var x0 = 0.0, y0 = 0.0, x1 = 0.0, y1 = 0.0;
  final kp = List<double>.filled(best.keypoints.length, 0);
  for (final d in cluster) {
    final s = d.score;
    total += s;
    x0 += d.xMin * s;
    y0 += d.yMin * s;
    x1 += d.xMax * s;
    y1 += d.yMax * s;
    final n = d.keypoints.length < kp.length ? d.keypoints.length : kp.length;
    for (var i = 0; i < n; i++) {
      kp[i] += d.keypoints[i] * s;
    }
  }
  if (total <= 0) return best;
  return FaceDetection(
    xMin: x0 / total,
    yMin: y0 / total,
    width: (x1 - x0) / total,
    height: (y1 - y0) / total,
    keypoints: [for (final v in kp) v / total],
    score: best.score,
  );
}
