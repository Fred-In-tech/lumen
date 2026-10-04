import 'package:lumen_core/lumen_core.dart';
import 'package:test/test.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

ModelSpec spec({String? sha, String? disabled}) => ModelSpec(
  id: 'x',
  version: '2',
  fileName: 'x.tflite',
  url: 'https://example.invalid/x.tflite',
  bytes: 10,
  license: 'MIT',
  trainingDataNote: 'n/a',
  sha256: sha,
  disabledReason: disabled,
  inputs: const [
    ModelTensorSpec(name: 'in', shape: [1, 4]),
  ],
  outputs: const [
    ModelTensorSpec(name: 'out', shape: [1, 2], role: 'scores'),
    ModelTensorSpec(shape: [1, 1]),
  ],
);

void main() {
  test('a spec without a pinned hash is refused at load time', () {
    expect(spec().isPinned, isFalse);
    expect(spec().requireLoadable, throwsA(isA<UnpinnedModelException>()));
    // Malformed hashes are refused too.
    for (final bad in ['', 'abc', _hash.toUpperCase(), '${_hash}00']) {
      expect(
        spec(sha: bad).requireLoadable,
        throwsA(isA<UnpinnedModelException>()),
        reason: bad,
      );
    }
    expect(spec(sha: _hash).requireLoadable, returnsNormally);
  });

  test('a disabled spec is refused even when pinned', () {
    expect(
      spec(sha: _hash, disabled: 'custom ops').requireLoadable,
      throwsA(
        isA<DisabledModelException>().having(
          (e) => e.reason,
          'reason',
          'custom ops',
        ),
      ),
    );
  });

  test('manifest rows: unique ids, all pinned, bundled set', () {
    final ids = ModelManifest.all.map((s) => s.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final s in ModelManifest.all) {
      expect(s.isPinned, isTrue, reason: s.id);
      expect(s.bytes, greaterThan(0));
      expect(s.url, startsWith('https://'));
      expect(ModelManifest.byId(s.id), same(s));
    }
    expect(ModelManifest.all.where((s) => s.bundled).map((s) => s.id).toSet(), {
      'blaze_face_short_range',
      'blaze_face_full_range',
      'face_landmarks_detector',
    });
    expect(ModelManifest.hairSegmenter.enabled, isFalse);
    expect(ModelManifest.faceLandmarkerTask.enabled, isFalse);
    expect(ModelManifest.miGan.enabled, isTrue);
    expect(ModelManifest.byId('nope'), isNull);
    expect(ModelManifest.blazeFaceFullRange.key, 'blaze_face_full_range@1');
    expect(
      ModelManifest.faceLandmarksDetector.bundledAssetKey,
      'assets/models/face_landmarks_detector.tflite',
    );
  });

  test('declared contracts match the verified shapes', () {
    final full = ModelManifest.blazeFaceFullRange;
    expect(full.inputs.single.shape, [1, 192, 192, 3]);
    expect(full.outputWithRole(TensorRoles.regressors)!.shape, [1, 2304, 16]);
    final mesh = ModelManifest.faceLandmarksDetector;
    expect(mesh.outputWithRole(TensorRoles.landmarks)!.elementCount, 478 * 3);
    expect(mesh.outputWithRole(TensorRoles.presence)!.name, 'Identity_1');
  });

  test('contractViolations compares names (when declared) and shapes', () {
    final s = spec(sha: _hash);
    expect(
      s.contractViolations(
        inputs: [
          (name: 'in', shape: [1, 4]),
        ],
        outputs: [
          (name: 'out', shape: [1, 2]),
          (name: 'anything', shape: [1, 1]),
        ],
      ),
      isEmpty,
    );
    final bad = s.contractViolations(
      inputs: [
        (name: 'input', shape: [1, 4]),
      ],
      outputs: [
        (name: 'out', shape: [1, 3]),
      ],
    );
    expect(bad, hasLength(2));
    expect(bad.first, contains('input 0'));
    expect(bad.last, contains('output count'));
  });
}
