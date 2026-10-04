// Real-model test: the full detector → align → mesh pipeline through
// LiteRtBackend on a drawn synthetic face (no real person, no download).
//
// Needs the bundled models in app/assets/models and the LiteRT host
// libraries (TFLITE_LIB_PATH and LITERT_LIB_PATH, exported by
// tool/verify.sh). Skips cleanly without them.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/face_analyzer.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/litert_backend_io.dart';
import 'package:lumen_core/lumen_core.dart';

import 'synthetic_portrait.dart';

const _det = ModelManifest.blazeFaceFullRange;
const _mesh = ModelManifest.faceLandmarksDetector;

String _path(ModelSpec s) => 'assets/models/${s.fileName}';

final Object _skip =
    Platform.environment['TFLITE_LIB_PATH'] == null ||
        Platform.environment['LITERT_LIB_PATH'] == null
    ? 'LiteRT host libraries not configured (run tool/verify.sh)'
    : !File(_path(_det)).existsSync() || !File(_path(_mesh)).existsSync()
    ? 'bundled models missing'
    : false;

double _dist((double, double) a, double bx, double by) =>
    math.sqrt(math.pow(a.$1 - bx, 2) + math.pow(a.$2 - by, 2));

void main() {
  test(
    'detector → mesh on a synthetic face yields one aligned 478-point face',
    () async {
      const backend = LiteRtBackend();
      final detector = await loadVerifiedSession(
        backend,
        _det,
        ModelFileSource(_path(_det)),
      );
      final mesh = await loadVerifiedSession(
        backend,
        _mesh,
        ModelFileSource(_path(_mesh)),
      );
      final analyzer = FaceAnalyzer(
        detector: detector,
        detectorSpec: _det,
        mesh: mesh,
        meshSpec: _mesh,
      );
      addTearDown(analyzer.dispose);
      final (img, layout) = syntheticPortrait();

      final result = await analyzer.analyze(img);

      final all = [
        ...result.analysis.faces.map((f) => 'accepted ${f.id} ${f.confidence}'),
        ...result.rejected.map((r) => 'rejected ${r.id} ${r.reason}'),
      ];
      expect(result.analysis.faces, hasLength(1), reason: '$all');
      final f = result.analysis.faces.single;
      expect(f.landmarkCount, MeshKeypoints.pointCount);
      double px(int i) => f.landmarks[2 * i] * img.width;
      double py(int i) => f.landmarks[2 * i + 1] * img.height;
      // Iris centres land on the drawn eyes (measured on this Mac: 2.6 %
      // and 1.3 % of the eye spacing; IOD 81 vs 83 px; yaw 1.7°).
      final eyeSpan = layout.leftEye.$1 - layout.rightEye.$1;
      const r = MeshKeypoints.rightIrisCenter, l = MeshKeypoints.leftIrisCenter;
      expect(_dist(layout.rightEye, px(r), py(r)), lessThan(0.1 * eyeSpan));
      expect(_dist(layout.leftEye, px(l), py(l)), lessThan(0.1 * eyeSpan));
      expect(f.confidence, greaterThan(0.6));
      expect(result.rejected, isEmpty);
      final g = FaceGeometry.fromLandmarks(
        f.landmarks,
        imageWidth: img.width,
        imageHeight: img.height,
      );
      expect(g.roll.abs(), lessThan(0.05));
      expect(g.yawDegrees.abs(), lessThan(10));
      expect(g.iod, closeTo(eyeSpan, 0.1 * eyeSpan));
      expect(f.box.centerX * img.width, closeTo(layout.cx, 0.2 * eyeSpan));
    },
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
