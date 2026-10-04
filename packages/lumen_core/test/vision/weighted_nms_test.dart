import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

FaceDetection det(double x, double y, double s, double score, {double k = 0}) =>
    FaceDetection(
      xMin: x,
      yMin: y,
      width: s,
      height: s,
      keypoints: [x + k, y + k],
      score: score,
    );

void main() {
  test('IoU of identical, disjoint and half-shifted boxes', () {
    final a = det(0, 0, 0.2, 1);
    expect(a.iou(a), closeTo(1, 1e-12));
    expect(a.iou(det(0.5, 0.5, 0.2, 1)), 0);
    // Shift by half the width: inter = 0.1·0.2, union = 2·0.04 − 0.02.
    expect(a.iou(det(0.1, 0, 0.2, 1)), closeTo(0.02 / 0.06, 1e-12));
  });

  test('weighted NMS merges duplicates into a score-weighted mean', () {
    final hi = det(0.10, 0.10, 0.20, 0.9, k: 0.05);
    final lo = det(0.12, 0.10, 0.20, 0.6, k: 0.07);
    expect(hi.iou(lo), greaterThan(0.3));

    final out = weightedNonMaxSuppression([lo, hi]);

    expect(out, hasLength(1));
    final m = out.single;
    expect(m.score, 0.9);
    expect(m.xMin, closeTo((0.10 * 0.9 + 0.12 * 0.6) / 1.5, 1e-12));
    expect(m.yMin, closeTo(0.10, 1e-12));
    expect(m.width, closeTo(0.20, 1e-12));
    expect(m.keypoints[0], closeTo((0.15 * 0.9 + 0.19 * 0.6) / 1.5, 1e-12));
  });

  test('separate faces survive, ordered by score', () {
    final a = det(0.1, 0.1, 0.2, 0.7);
    final b = det(0.6, 0.6, 0.2, 0.95);
    final out = weightedNonMaxSuppression([a, b]);
    expect(out.map((d) => d.score), [0.95, 0.7]);
  });

  test('IoU at or below the threshold does not merge', () {
    final a = det(0, 0, 0.2, 0.9);
    final b = det(0.1, 0, 0.2, 0.8); // IoU = 1/3
    expect(weightedNonMaxSuppression([a, b], iouThreshold: 0.34), hasLength(2));
    expect(weightedNonMaxSuppression([a, b], iouThreshold: 0.3), hasLength(1));
  });

  test('three-way cluster plus maxDetections cap', () {
    final cluster = [
      det(0.1, 0.1, 0.2, 0.9),
      det(0.11, 0.1, 0.2, 0.8),
      det(0.1, 0.11, 0.2, 0.7),
    ];
    final far = det(0.7, 0.7, 0.1, 0.5);
    expect(weightedNonMaxSuppression([...cluster, far]), hasLength(2));
    expect(
      weightedNonMaxSuppression([...cluster, far], maxDetections: 1),
      hasLength(1),
    );
    expect(weightedNonMaxSuppression(const []), isEmpty);
  });
}
