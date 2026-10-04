import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/inference_backend.dart';

/// Computes a fake model's outputs from its inputs.
typedef FakeRunHandler = Map<String, Float32List> Function(
  Map<String, Float32List> inputs,
);

/// A scripted model for [FakeInferenceBackend].
class FakeModel {
  const FakeModel({
    required this.inputs,
    required this.outputs,
    required this.onRun,
  });

  /// Mirrors a manifest row's declared contract.
  factory FakeModel.fromSpec(ModelSpec spec, FakeRunHandler onRun) => FakeModel(
    inputs: [
      for (final (i, t) in spec.inputs.indexed)
        (name: t.name ?? 'input_$i', shape: t.shape),
    ],
    outputs: [
      for (final (i, t) in spec.outputs.indexed)
        (name: t.name ?? 'output_$i', shape: t.shape),
    ],
    onRun: onRun,
  );

  final List<TensorSignature> inputs;
  final List<TensorSignature> outputs;
  final FakeRunHandler onRun;
}

/// In-memory backend for tests: models are looked up by
/// [ModelSource.debugName] (the file name).
class FakeInferenceBackend implements InferenceBackend {
  FakeInferenceBackend(this.models);

  final Map<String, FakeModel> models;
  final List<FakeInferenceSession> sessions = [];

  @override
  String get name => 'fake';

  @override
  Future<InferenceSession> load(
    ModelSource source, {
    ModelSpec? contract,
  }) async {
    final model = models[source.debugName];
    if (model == null) {
      throw ModelLoadFailed('fake backend has no model ${source.debugName}');
    }
    final session = FakeInferenceSession(source.debugName, model);
    sessions.add(session);
    return session;
  }
}

class FakeInferenceSession implements InferenceSession {
  FakeInferenceSession(this.name, this._model);

  final String name;
  final FakeModel _model;
  int runCount = 0;
  bool disposed = false;

  @override
  List<TensorSignature> get inputs => _model.inputs;

  @override
  List<TensorSignature> get outputs => _model.outputs;

  @override
  Future<Map<String, Float32List>> run(Map<String, Float32List> inputs) async {
    if (disposed) throw const InferenceRunFailed('session disposed');
    for (final t in _model.inputs) {
      final data = inputs[t.name];
      if (data == null || data.length != elementCount(t.shape)) {
        throw InferenceRunFailed(
          '$name: input ${t.name} needs ${elementCount(t.shape)} values, '
          'got ${data?.length}',
        );
      }
    }
    runCount++;
    final out = _model.onRun(inputs);
    return {
      for (final t in _model.outputs)
        t.name: out[t.name] ?? Float32List(elementCount(t.shape)),
    };
  }

  @override
  Future<void> dispose() async => disposed = true;
}
