import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

/// Writes the raw regressor values that decode to [box] at anchor [k].
void encodeBox(
  Float32List reg,
  List<SsdAnchor> anchors,
  int k,
  ({double cx, double cy, double w, double h}) box,
  List<double> keypoints, {
  double scale = 128,
  int numCoords = 16,
}) {
  final a = anchors[k];
  final b = k * numCoords;
  reg[b] = (box.cx - a.centerX) * scale / a.width;
  reg[b + 1] = (box.cy - a.centerY) * scale / a.height;
  reg[b + 2] = box.w * scale / a.width;
  reg[b + 3] = box.h * scale / a.height;
  for (var i = 0; i < keypoints.length; i += 2) {
    reg[b + 4 + i] = (keypoints[i] - a.centerX) * scale / a.width;
    reg[b + 5 + i] = (keypoints[i + 1] - a.centerY) * scale / a.height;
  }
}

void main() {
  final anchors = SsdAnchorConfig.shortRange.generate();
  final options = BlazeFaceDecodeOptions.forInput(
    inputWidth: 128,
    inputHeight: 128,
  );

  Float32List lowScores() =>
      Float32List(anchors.length)..fillRange(0, anchors.length, -10);

  test('a synthetic regressor tensor round-trips a known box', () {
    final reg = Float32List(anchors.length * 16);
    final scores = lowScores();
    const box = (cx: 0.42, cy: 0.37, w: 0.25, h: 0.3);
    final kps = [0.36, 0.3, 0.48, 0.3, 0.42, 0.38, 0.42, 0.45, 0.3, 0.33];
    kps.addAll([0.54, 0.33]);
    encodeBox(reg, anchors, 700, box, kps);
    scores[700] = 3;

    final dets = decodeBlazeFace(
      regressors: reg,
      scores: scores,
      anchors: anchors,
      options: options,
    );

    expect(dets, hasLength(1));
    final d = dets.single;
    expect(d.centerX, closeTo(box.cx, 1e-5));
    expect(d.centerY, closeTo(box.cy, 1e-5));
    expect(d.width, closeTo(box.w, 1e-5));
    expect(d.height, closeTo(box.h, 1e-5));
    expect(d.keypointCount, 6);
    for (var i = 0; i < kps.length; i++) {
      expect(d.keypoints[i], closeTo(kps[i], 1e-5), reason: 'kp $i');
    }
    expect(d.score, closeTo(logistic(3), 1e-6));
  });

  test('scores below the threshold are dropped, huge logits are clipped', () {
    final reg = Float32List(anchors.length * 16);
    final scores = lowScores();
    encodeBox(reg, anchors, 10, (cx: 0.1, cy: 0.1, w: 0.1, h: 0.1), const []);
    encodeBox(reg, anchors, 20, (cx: 0.2, cy: 0.1, w: 0.1, h: 0.1), const []);
    scores[10] = 1e6; // clipped to 100 → sigmoid ≈ 1, no overflow
    scores[20] = -0.1; // sigmoid < 0.5 → dropped
    final dets = decodeBlazeFace(
      regressors: reg,
      scores: scores,
      anchors: anchors,
      options: options,
    );
    expect(dets, hasLength(1));
    expect(dets.single.score, closeTo(1, 1e-9));
    expect(dets.single.score.isFinite, isTrue);
  });

  test('shape mismatches are programming errors', () {
    expect(
      () => decodeBlazeFace(
        regressors: Float32List(10),
        scores: Float32List(anchors.length),
        anchors: anchors,
        options: options,
      ),
      throwsArgumentError,
    );
    expect(
      () => decodeBlazeFace(
        regressors: Float32List(anchors.length * 16),
        scores: Float32List(3),
        anchors: anchors,
        options: options,
      ),
      throwsArgumentError,
    );
  });

  test('forInput derives the keypoint count from numCoords', () {
    final o = BlazeFaceDecodeOptions.forInput(
      inputWidth: 192,
      inputHeight: 192,
      numCoords: 16,
    );
    expect(o.numKeypoints, 6);
    expect(o.xScale, 192);
  });

  test('letterbox removal maps tensor space back to the image', () {
    final d = FaceDetection(
      xMin: 0.4,
      yMin: 0.25,
      width: 0.2,
      height: 0.25,
      keypoints: const [0.5, 0.5],
      score: 0.9,
    );
    // 2:1 image in a square tensor → 25 % pad top and bottom.
    const lb = Letterbox(top: 0.25, bottom: 0.25);
    final m = lb.remove(d);
    expect(m.xMin, closeTo(0.4, 1e-12));
    expect(m.yMin, closeTo(0, 1e-12));
    expect(m.height, closeTo(0.5, 1e-12));
    expect(m.keypoints[1], closeTo(0.5, 1e-12));
  });
}
