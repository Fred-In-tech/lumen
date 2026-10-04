import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

/// Where a model's bytes come from.
sealed class ModelSource {
  const ModelSource();

  /// Name used in logs and by fakes to pick a model (file basename).
  String get debugName;
}

/// A verified model file on disk (from `ModelStore`).
final class ModelFileSource extends ModelSource {
  const ModelFileSource(this.path);
  final String path;

  @override
  String get debugName => path.split(RegExp(r'[/\\]')).last;
}

/// Verified model bytes already in memory.
final class ModelBytesSource extends ModelSource {
  const ModelBytesSource(this.bytes, {required this.name});
  final Uint8List bytes;
  final String name;

  @override
  String get debugName => name;
}

/// Typed inference failures (the UI degrades instead of crashing).
sealed class InferenceException implements Exception {
  const InferenceException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No on-device runtime on this platform/build.
final class InferenceUnavailable extends InferenceException {
  const InferenceUnavailable(super.message);
}

/// The runtime could not load or compile the model.
final class ModelLoadFailed extends InferenceException {
  const ModelLoadFailed(super.message);
}

/// A run failed (bad input, runtime error, session closed).
final class InferenceRunFailed extends InferenceException {
  const InferenceRunFailed(super.message);
}

/// The loaded model's tensors do not match the pinned contract.
final class ModelContractMismatch extends InferenceException {
  const ModelContractMismatch(super.message, {this.violations = const []});
  final List<String> violations;
}

/// One loaded model. Implementations run off the UI isolate (LiteRT's
/// `CompiledModel.runAsync` / `IsolateInterpreter`).
abstract interface class InferenceSession {
  /// Input tensors in runtime order, with names and shapes.
  List<TensorSignature> get inputs;

  /// Output tensors in runtime order, with names and shapes.
  List<TensorSignature> get outputs;

  /// Runs once. [inputs] is keyed by input name; the result by output name.
  /// Throws [InferenceRunFailed].
  Future<Map<String, Float32List>> run(Map<String, Float32List> inputs);

  Future<void> dispose();
}

/// A runtime that turns model bytes into sessions (`LiteRtBackend` now,
/// an ORT backend later).
abstract interface class InferenceBackend {
  String get name;

  /// Throws [ModelLoadFailed] or [InferenceUnavailable]. [contract] lets a
  /// runtime that cannot report tensor names/shapes (LiteRT `CompiledModel`
  /// only exposes byte sizes) adopt the declared ones after checking sizes.
  Future<InferenceSession> load(ModelSource source, {ModelSpec? contract});
}

/// Used where no runtime exists (web, tests that never infer).
class UnavailableInferenceBackend implements InferenceBackend {
  const UnavailableInferenceBackend([this.reason = 'no on-device runtime']);
  final String reason;

  @override
  String get name => 'unavailable';

  @override
  Future<InferenceSession> load(ModelSource source, {ModelSpec? contract}) =>
      Future.error(InferenceUnavailable(reason));
}

/// Element count of a tensor shape.
int elementCount(List<int> shape) => shape.fold(1, (a, b) => a * b);

/// Loads [source] and asserts [spec]'s tensor contract (names, order,
/// shapes). Disposes the session and throws [ModelContractMismatch] when it
/// does not match.
Future<InferenceSession> loadVerifiedSession(
  InferenceBackend backend,
  ModelSpec spec,
  ModelSource source,
) async {
  final session = await backend.load(source, contract: spec);
  final violations = spec.contractViolations(
    inputs: session.inputs,
    outputs: session.outputs,
  );
  if (violations.isEmpty) return session;
  await session.dispose();
  throw ModelContractMismatch(
    '${spec.key} does not match its pinned contract',
    violations: violations,
  );
}
