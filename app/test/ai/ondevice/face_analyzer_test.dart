import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/face_analyzer.dart';
import 'package:lumen/ai/ondevice/fake_inference_backend.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen_core/lumen_core.dart';

import 'face_fakes.dart';

const _w = 400, _h = 300;

RgbaBuffer _image() => RgbaBuffer.filled(_w, _h, 120, 100, 90);

FakeInferenceSession _session(FakeInferenceBackend b, String file) =>
    b.sessions.firstWhere((s) => s.name == file);

void main() {
  test('crafted tensors produce the expected FaceAnalysis', () async {
    final backend = fakeFaceBackend(
      faces: [(cx: 0.5, cy: 0.5, size: 0.25)],
      w: _w,
      h: _h,
    );
    final analyzer = await fakeAnalyzer(backend);

    final result = await analyzer.analyze(_image());

    final a = result.analysis;
    expect(result.rejected, isEmpty);
    expect(a.imageWidth, _w);
    expect(a.modelVersion, 'blaze_face_full_range@1+face_landmarks_detector@1');
    expect(a.faces, hasLength(1));
    final f = a.faces.single;
    // Box: 100 px square centred in the image.
    expect(f.box.centerX, closeTo(0.5, 1e-4));
    expect(f.box.centerY, closeTo(0.5, 1e-4));
    expect(f.box.width * _w, closeTo(100, 0.05));
    expect(f.box.height * _h, closeTo(100, 0.05));
    expect(f.id, faceKey(f.box));
    expect(f.confidence, closeTo(logistic(4), 1e-6));
    // Landmarks went back through the crop: iris midpoint = box centre,
    // IOD = 80 crop px × (1.5 × 100 px) / 256.
    expect(f.landmarkCount, 478);
    final g = FaceGeometry.fromLandmarks(
      f.landmarks,
      imageWidth: _w,
      imageHeight: _h,
    );
    expect(g.iod, closeTo(80 * 150 / 256, 0.05));
    expect(g.roll, closeTo(0, 1e-3));
    expect(g.yawDegrees, closeTo(0, 1e-3));
    const r = MeshKeypoints.rightIrisCenter, l = MeshKeypoints.leftIrisCenter;
    final midX = (f.landmarks[2 * r] + f.landmarks[2 * l]) / 2;
    expect(midX, closeTo(0.5, 1e-4));
    expect(_session(backend, meshSpec.fileName).runCount, 1);
  });

  test('runs through the real background isolate runner', () async {
    final backend = fakeFaceBackend(
      faces: [(cx: 0.3, cy: 0.4, size: 0.2)],
      w: _w,
      h: _h,
    );
    final analyzer = await fakeAnalyzer(backend, runner: null);
    final result = await analyzer.analyze(_image());
    expect(result.analysis.faces, hasLength(1));
  });

  test('low face flag → rejected, not in the analysis', () async {
    final backend = fakeFaceBackend(
      faces: [(cx: 0.5, cy: 0.5, size: 0.25)],
      w: _w,
      h: _h,
      presenceLogit: -3,
    );
    final result = await (await fakeAnalyzer(backend)).analyze(_image());
    expect(result.analysis.faces, isEmpty);
    expect(result.rejected.single.reason, FaceRejectReason.lowPresence);
  });

  test('no detections → empty analysis, mesh never runs', () async {
    final backend = fakeFaceBackend(faces: const [], w: _w, h: _h);
    final result = await (await fakeAnalyzer(backend)).analyze(_image());
    expect(result.analysis.faces, isEmpty);
    expect(_session(backend, meshSpec.fileName).runCount, 0);
  });

  test(
    'source size scales reject lengths, refine runs a second pass',
    () async {
      final backend = fakeFaceBackend(
        faces: [(cx: 0.5, cy: 0.5, size: 0.25)],
        w: _w,
        h: _h,
      );
      final analyzer = await fakeAnalyzer(
        backend,
        config: const FaceAnalyzerConfig(refine: RefineMode.always),
      );
      final result = await analyzer.analyze(
        _image(),
        sourceWidth: 2 * _w,
        sourceHeight: 2 * _h,
      );
      expect(result.analysis.imageWidth, 2 * _w);
      expect(_session(backend, meshSpec.fileName).runCount, 2);
      expect(result.analysis.faces, hasLength(1));
    },
  );

  test('a crowd triggers the 2×2 tiled pass', () async {
    final faces = [
      for (var i = 0; i < 5; i++) (cx: 0.1 + i * 0.2, cy: 0.5, size: 0.08),
    ];
    final backend = fakeFaceBackend(faces: faces, w: _w, h: _h);
    final analyzer = await fakeAnalyzer(
      backend,
      config: const FaceAnalyzerConfig(maxFaces: 6),
    );
    final result = await analyzer.analyze(_image());
    expect(_session(backend, detSpec.fileName).runCount, 5);
    expect(
      result.analysis.faces.length + result.rejected.length,
      lessThanOrEqualTo(6),
    );
  });

  group('contracts', () {
    test('a session that breaks the pinned contract is refused', () async {
      final backend = FakeInferenceBackend({
        detSpec.fileName: FakeModel(
          inputs: const [
            (name: 'input', shape: [1, 128, 128, 3]),
          ],
          outputs: const [
            (name: 'regressors', shape: [1, 896, 16]),
            (name: 'classificators', shape: [1, 896, 1]),
          ],
          onRun: (_) => const {},
        ),
      });
      await expectLater(
        loadVerifiedSession(
          backend,
          detSpec,
          ModelFileSource('/m/${detSpec.fileName}'),
        ),
        throwsA(
          isA<ModelContractMismatch>().having(
            (e) => e.violations,
            'violations',
            isNotEmpty,
          ),
        ),
      );
      expect(backend.sessions.single.disposed, isTrue);
    });

    test('a mesh without a presence output cannot bind', () async {
      final backend = FakeInferenceBackend({
        'mesh': FakeModel(
          inputs: const [
            (name: 'img', shape: [1, 256, 256, 3]),
          ],
          outputs: const [
            (name: 'lm', shape: [1, 1434]),
          ],
          onRun: (_) => const {},
        ),
        'det': FakeModel.fromSpec(detSpec, (_) => const {}),
      });
      const bare = ModelSpec(
        id: 'mesh',
        version: '1',
        fileName: 'mesh',
        url: 'https://example.invalid',
        bytes: 1,
        license: '-',
        trainingDataNote: '-',
      );
      final det = await backend.load(const ModelFileSource('det'));
      final mesh = await backend.load(const ModelFileSource('mesh'));
      expect(
        () => FaceAnalyzer(
          detector: det,
          detectorSpec: detSpec,
          mesh: mesh,
          meshSpec: bare,
        ),
        throwsA(isA<ModelContractMismatch>()),
      );
    });

    test('fake sessions validate input sizes', () async {
      final backend = fakeFaceBackend(faces: const [], w: _w, h: _h);
      final s = await backend.load(ModelFileSource('/x/${detSpec.fileName}'));
      await expectLater(
        s.run({'input': Float32List(3)}),
        throwsA(isA<InferenceRunFailed>()),
      );
      await expectLater(
        const UnavailableInferenceBackend().load(const ModelFileSource('x')),
        throwsA(isA<InferenceUnavailable>()),
      );
    });
  });
}
