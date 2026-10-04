// Model contract test: loads every on-device model through LiteRT on the host
// and checks the tensor shapes the vision code is written against.
//
// Needs the downloaded models (repo-root `.dev_models/`, see
// docs/MODEL_LICENSES.md) and the LiteRT host libraries (TFLITE_LIB_PATH and
// LITERT_LIB_PATH, exported by tool/verify.sh). Skips cleanly without them.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_litert/flutter_litert.dart';
import 'package:flutter_test/flutter_test.dart';

const _searchDirs = ['assets/models', '../.dev_models'];

File? _find(String name) {
  for (final dir in _searchDirs) {
    final f = File('$dir/$name');
    if (f.existsSync()) return f;
  }
  return null;
}

final bool _hasRuntime =
    Platform.environment['TFLITE_LIB_PATH'] != null &&
    Platform.environment['LITERT_LIB_PATH'] != null;

int _count(List<int> shape) => shape.fold(1, (a, b) => a * b);

Object _skip(File? f) => !_hasRuntime
    ? 'LiteRT host libraries not configured (run tool/verify.sh)'
    : f == null
    ? 'model not downloaded'
    : false;

typedef _Contract = ({List<List<int>> inputs, List<List<int>> outputs});

const Map<String, _Contract> _interpreterModels = {
  'blaze_face_short_range.tflite': (
    inputs: [
      [1, 128, 128, 3],
    ],
    outputs: [
      [1, 896, 16],
      [1, 896, 1],
    ],
  ),
  'blaze_face_full_range.tflite': (
    inputs: [
      [1, 192, 192, 3],
    ],
    outputs: [
      [1, 2304, 16],
      [1, 2304, 1],
    ],
  ),
  'face_landmarks_detector.tflite': (
    inputs: [
      [1, 256, 256, 3],
    ],
    outputs: [
      [1, 1, 1, 1434],
      [1, 1, 1, 1],
      [1, 1],
    ],
  ),
  'selfie_multiclass_256x256.tflite': (
    inputs: [
      [1, 256, 256, 3],
    ],
    outputs: [
      [1, 256, 256, 6],
    ],
  ),
};

void main() {
  for (final MapEntry(key: name, value: contract)
      in _interpreterModels.entries) {
    final file = _find(name);
    test('$name matches its tensor contract and runs', () {
      final interpreter = Interpreter.fromFile(file!);
      addTearDown(interpreter.close);
      interpreter.allocateTensors();
      final ins = interpreter.getInputTensors();
      final outs = interpreter.getOutputTensors();
      expect([for (final t in ins) t.shape], contract.inputs);
      expect([for (final t in outs) t.shape], contract.outputs);
      final outputs = {
        for (var i = 0; i < outs.length; i++)
          i: Float32List(_count(outs[i].shape)).buffer,
      };
      interpreter.runForMultipleInputs([
        for (final t in ins)
          Float32List.fromList(
            List.generate(_count(t.shape), (i) => (i % 251) / 251.0),
          ).buffer,
      ], outputs);
      final first = Float32List.view(outputs[0]!);
      expect(first.every((v) => v.isFinite), isTrue);
    }, skip: _skip(file));
  }

  final migan = _find('migan_fp16.tflite');
  test('migan_fp16.tflite runs through CompiledModel (NCHW 4→3, 512²)', () {
    final model = CompiledModel.fromFile(migan!.path);
    addTearDown(model.close);
    const n = 512 * 512;
    expect(model.inputByteSizes, [4 * n * 4]);
    expect(model.outputByteSizes, [3 * n * 4]);
    final input = Float32List(4 * n);
    for (var i = 0; i < n; i++) {
      final keep = (i % 512) < 256 ? 1.0 : 0.0; // right half is the hole
      input[i] = keep - 0.5;
      for (var c = 1; c < 4; c++) {
        input[c * n + i] = keep * (((i ~/ 512) % 32) / 16.0 - 1.0);
      }
    }
    final out = model.run([input]).single;
    expect(out.length, 3 * n);
    expect(out.every((v) => v.isFinite), isTrue);
  }, skip: _skip(migan));

  test(
    'hair_segmenter.tflite is deferred: needs MediaPipe custom ops',
    () {},
    skip:
        'MaxPoolingWithArgmax2D / MaxUnpooling2D are not shipped by '
        'flutter_litert 3.9.3',
  );
}
