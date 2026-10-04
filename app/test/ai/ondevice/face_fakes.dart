import 'dart:async';
import 'dart:typed_data';

import 'package:lumen/ai/ondevice/face_analyzer.dart';
import 'package:lumen/ai/ondevice/fake_inference_backend.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen_core/lumen_core.dart';

/// Runs inline (no isolate) for most tests.
Future<T> inlineRunner<T>(FutureOr<T> Function() fn) async => fn();

const detSpec = ModelManifest.blazeFaceFullRange;
const meshSpec = ModelManifest.faceLandmarksDetector;

/// A face as the detector should report it, in image-normalized coords.
typedef FakeFace = ({double cx, double cy, double size});

/// Raw BlazeFace full-range tensors for [faces] on a [w]×[h] image
/// (letterboxed into the 192² input, like the analyzer does).
Map<String, Float32List> detectorTensors(
  List<FakeFace> faces, {
  required int w,
  required int h,
}) {
  final anchors = SsdAnchorConfig.fullRange.generate();
  final reg = Float32List(anchors.length * 16);
  final scores = Float32List(anchors.length)..fillRange(0, anchors.length, -10);
  final scale = 192 / (w > h ? w : h);
  final padX = (192 - w * scale) / 2 / 192;
  final padY = (192 - h * scale) / 2 / 192;
  double tx(double x) => padX + x * (1 - 2 * padX);
  double ty(double y) => padY + y * (1 - 2 * padY);
  for (final f in faces) {
    final cx = tx(f.cx), cy = ty(f.cy);
    final k = _nearest(anchors, cx, cy);
    final a = anchors[k];
    final sz = f.size * w * scale / 192; // square in pixels
    final b = k * 16;
    reg[b] = (cx - a.centerX) * 192;
    reg[b + 1] = (cy - a.centerY) * 192;
    reg[b + 2] = sz * 192;
    reg[b + 3] = sz * 192;
    // Eyes level, a quarter of the box either side of the centre.
    final eyes = [cx - sz / 4, cy - sz / 8, cx + sz / 4, cy - sz / 8];
    for (var i = 0; i < 4; i += 2) {
      reg[b + 4 + i] = (eyes[i] - a.centerX) * 192;
      reg[b + 5 + i] = (eyes[i + 1] - a.centerY) * 192;
    }
    scores[k] = 4;
  }
  return {
    'reshaped_regressor_face_4': reg,
    'reshaped_classifier_face_4': scores,
  };
}

int _nearest(List<SsdAnchor> anchors, double x, double y) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < anchors.length; i++) {
    final d =
        (anchors[i].centerX - x) * (anchors[i].centerX - x) +
        (anchors[i].centerY - y) * (anchors[i].centerY - y);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// Iris centres in the 256² crop: 80 px apart, centred on the crop centre.
const irisHalfSpan = 40.0;

/// A frontal face in mesh crop space (x, y, z per point).
Float32List meshLandmarks() {
  final pts = List<(double, double)>.filled(MeshKeypoints.pointCount, (
    128,
    128,
  ));
  pts[MeshKeypoints.rightIrisCenter] = (128 - irisHalfSpan, 128);
  pts[MeshKeypoints.leftIrisCenter] = (128 + irisHalfSpan, 128);
  pts[MeshKeypoints.rightEyeOuter] = (128 - 58, 128);
  pts[MeshKeypoints.leftEyeOuter] = (128 + 58, 128);
  pts[MeshKeypoints.noseTip] = (128, 160);
  pts[MeshKeypoints.chin] = (128, 220);
  for (final (c, ring) in [
    (MeshKeypoints.rightIrisCenter, MeshKeypoints.rightIrisRing),
    (MeshKeypoints.leftIrisCenter, MeshKeypoints.leftIrisRing),
  ]) {
    final (x, y) = pts[c];
    pts[ring[0]] = (x + 5, y);
    pts[ring[1]] = (x, y - 5);
    pts[ring[2]] = (x - 5, y);
    pts[ring[3]] = (x, y + 5);
  }
  final out = Float32List(MeshKeypoints.pointCount * 3);
  for (var i = 0; i < pts.length; i++) {
    out[3 * i] = pts[i].$1;
    out[3 * i + 1] = pts[i].$2;
  }
  return out;
}

/// Backend with the full-range detector and mesh contracts.
FakeInferenceBackend fakeFaceBackend({
  required List<FakeFace> faces,
  required int w,
  required int h,
  double presenceLogit = 3,
}) => FakeInferenceBackend({
  detSpec.fileName: FakeModel.fromSpec(
    detSpec,
    (_) => detectorTensors(faces, w: w, h: h),
  ),
  meshSpec.fileName: FakeModel.fromSpec(
    meshSpec,
    (_) => {
      'Identity': meshLandmarks(),
      'Identity_1': Float32List.fromList([presenceLogit]),
    },
  ),
});

Future<FaceAnalyzer> fakeAnalyzer(
  FakeInferenceBackend backend, {
  FaceAnalyzerConfig config = const FaceAnalyzerConfig(),
  BackgroundRunner? runner = inlineRunner,
}) async => FaceAnalyzer(
  detector: await loadVerifiedSession(
    backend,
    detSpec,
    ModelFileSource('/m/${detSpec.fileName}'),
  ),
  detectorSpec: detSpec,
  mesh: await loadVerifiedSession(
    backend,
    meshSpec,
    ModelFileSource('/m/${meshSpec.fileName}'),
  ),
  meshSpec: meshSpec,
  config: config,
  runner: runner,
);
