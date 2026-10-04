import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_litert/native.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/inference_backend.dart';

final _log = Logger('LiteRtBackend');

typedef _Signature = ({
  List<TensorSignature> inputs,
  List<TensorSignature> outputs,
});

/// LiteRT (`flutter_litert`) backend.
///
/// Primary path: `CompiledModel` (LiteRT Next; GPU/Metal via [config], and
/// the only path MI-GAN runs on), run with `runAsync` so inference happens
/// on a helper isolate. Fallback: the classic `Interpreter` behind an
/// `IsolateInterpreter`. Tensor names and shapes come from the classic
/// interpreter when it can read the model, else from the manifest contract
/// after a byte-size check, so callers can always assert the contract.
///
/// flutter_litert reports failures as `StateError`/`ArgumentError`/
/// `UnsupportedError`; they are caught here, at the runtime boundary, and
/// turned into typed [InferenceException]s.
class LiteRtBackend implements InferenceBackend {
  const LiteRtBackend({this.config = const CompiledModelConfig.cpu()});

  final CompiledModelConfig config;

  @override
  String get name => 'litert';

  @override
  Future<InferenceSession> load(
    ModelSource source, {
    ModelSpec? contract,
  }) async {
    final signature = _readSignature(source);
    final compiled = _compile(source);
    if (compiled != null) {
      final sig = signature ?? _fromContract(contract) ?? _flat(compiled);
      final problem = _sizeMismatch(compiled, sig);
      if (problem == null) return _CompiledSession(compiled, sig);
      compiled.close();
      throw ModelLoadFailed('${source.debugName}: $problem');
    }
    if (signature == null) {
      throw ModelLoadFailed(
        '${source.debugName}: neither CompiledModel nor Interpreter loads it',
      );
    }
    return _InterpreterSession.open(source, signature);
  }

  CompiledModel? _compile(ModelSource source) {
    try {
      return switch (source) {
        ModelFileSource(:final path) => CompiledModel.fromFileWithConfig(
          path,
          config: config,
        ),
        ModelBytesSource(:final bytes) => CompiledModel.fromBufferWithConfig(
          bytes,
          config: config,
        ),
      };
    } on StateError catch (e) {
      _log.warning('CompiledModel failed for ${source.debugName}: $e');
    } on UnsupportedError catch (e) {
      _log.warning('CompiledModel unsupported for ${source.debugName}: $e');
    } on ArgumentError catch (e) {
      _log.warning('CompiledModel rejected ${source.debugName}: $e');
    }
    return null;
  }

  static _Signature? _readSignature(ModelSource source) {
    final Interpreter interpreter;
    try {
      interpreter = _interpreterFor(source);
    } on ArgumentError catch (e) {
      _log.info('Interpreter cannot read ${source.debugName}: $e');
      return null;
    } on StateError catch (e) {
      _log.info('Interpreter cannot read ${source.debugName}: $e');
      return null;
    }
    try {
      return (
        inputs: [
          for (final t in interpreter.getInputTensors())
            (name: t.name, shape: List<int>.unmodifiable(t.shape)),
        ],
        outputs: [
          for (final t in interpreter.getOutputTensors())
            (name: t.name, shape: List<int>.unmodifiable(t.shape)),
        ],
      );
    } finally {
      interpreter.close();
    }
  }

  static _Signature? _fromContract(ModelSpec? spec) {
    if (spec == null || spec.inputs.isEmpty || spec.outputs.isEmpty) {
      return null;
    }
    return (
      inputs: [
        for (final (i, t) in spec.inputs.indexed)
          (name: t.name ?? 'input_$i', shape: t.shape),
      ],
      outputs: [
        for (final (i, t) in spec.outputs.indexed)
          (name: t.name ?? 'output_$i', shape: t.shape),
      ],
    );
  }

  static _Signature _flat(CompiledModel m) => (
    inputs: [
      for (final (i, b) in m.inputByteSizes.indexed)
        (name: 'input_$i', shape: [b ~/ 4]),
    ],
    outputs: [
      for (final (i, b) in m.outputByteSizes.indexed)
        (name: 'output_$i', shape: [b ~/ 4]),
    ],
  );

  static String? _sizeMismatch(CompiledModel m, _Signature sig) {
    List<int> bytes(List<TensorSignature> t) => [
      for (final s in t) elementCount(s.shape) * 4,
    ];
    final ins = bytes(sig.inputs);
    final outs = bytes(sig.outputs);
    if (ins.length != m.inputByteSizes.length ||
        outs.length != m.outputByteSizes.length) {
      return 'tensor count differs from the compiled model';
    }
    for (var i = 0; i < ins.length; i++) {
      if (ins[i] != m.inputByteSizes[i]) {
        return 'input $i is ${m.inputByteSizes[i]} B, expected ${ins[i]} B';
      }
    }
    for (var i = 0; i < outs.length; i++) {
      if (outs[i] != m.outputByteSizes[i]) {
        return 'output $i is ${m.outputByteSizes[i]} B, expected ${outs[i]} B';
      }
    }
    return null;
  }
}

Interpreter _interpreterFor(ModelSource source) => switch (source) {
  ModelFileSource(:final path) => Interpreter.fromFile(File(path)),
  ModelBytesSource(:final bytes) => Interpreter.fromBuffer(bytes),
};

List<Float32List> _ordered(
  List<TensorSignature> inputs,
  Map<String, Float32List> data,
) => [
  for (final t in inputs)
    switch (data[t.name]) {
      final d? when d.length == elementCount(t.shape) => d,
      final d => throw InferenceRunFailed(
        'input ${t.name} needs ${elementCount(t.shape)} values, '
        'got ${d?.length}',
      ),
    },
];

class _CompiledSession implements InferenceSession {
  _CompiledSession(this._model, _Signature sig)
    : inputs = List.unmodifiable(sig.inputs),
      outputs = List.unmodifiable(sig.outputs);

  final CompiledModel _model;

  @override
  final List<TensorSignature> inputs;

  @override
  final List<TensorSignature> outputs;

  @override
  Future<Map<String, Float32List>> run(Map<String, Float32List> data) async {
    final ordered = _ordered(inputs, data);
    try {
      final out = await _model.runAsync(ordered);
      return {for (var i = 0; i < outputs.length; i++) outputs[i].name: out[i]};
    } on StateError catch (e) {
      throw InferenceRunFailed('CompiledModel run failed: $e');
    } on ArgumentError catch (e) {
      throw InferenceRunFailed('CompiledModel rejected the inputs: $e');
    }
  }

  @override
  Future<void> dispose() async => _model.close();
}

class _InterpreterSession implements InferenceSession {
  _InterpreterSession._(this._interpreter, this._isolate, _Signature sig)
    : inputs = List.unmodifiable(sig.inputs),
      outputs = List.unmodifiable(sig.outputs);

  static Future<_InterpreterSession> open(
    ModelSource source,
    _Signature sig,
  ) async {
    try {
      final interpreter = _interpreterFor(source);
      final isolate = await IsolateInterpreter.create(
        address: interpreter.address,
        debugName: 'litert-${source.debugName}',
      );
      return _InterpreterSession._(interpreter, isolate, sig);
    } on ArgumentError catch (e) {
      throw ModelLoadFailed('Interpreter failed for ${source.debugName}: $e');
    }
  }

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  @override
  final List<TensorSignature> inputs;

  @override
  final List<TensorSignature> outputs;

  @override
  Future<Map<String, Float32List>> run(Map<String, Float32List> data) async {
    final ordered = _ordered(inputs, data);
    final out = [for (final t in outputs) Float32List(elementCount(t.shape))];
    try {
      await _isolate.runForMultipleInputs(
        [for (final d in ordered) d.buffer],
        {for (var i = 0; i < out.length; i++) i: out[i].buffer},
      );
    } on StateError catch (e) {
      throw InferenceRunFailed('Interpreter run failed: $e');
    } on ArgumentError catch (e) {
      throw InferenceRunFailed('Interpreter rejected the inputs: $e');
    }
    return {for (var i = 0; i < outputs.length; i++) outputs[i].name: out[i]};
  }

  @override
  Future<void> dispose() async {
    await _isolate.close();
    _interpreter.close();
  }
}
