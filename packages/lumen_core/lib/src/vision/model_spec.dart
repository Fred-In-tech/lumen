import 'package:collection/collection.dart';

import 'tensor_sampling.dart';

/// Inference runtime a model file targets.
enum ModelRuntime { litert, onnx }

/// Memory layout of an image tensor.
enum TensorLayout { nhwc, nchw }

/// One tensor of a model's verified I/O contract.
class ModelTensorSpec {
  const ModelTensorSpec({
    required this.shape,
    this.name,
    this.role,
    this.range,
    this.layout = TensorLayout.nhwc,
  });

  /// Tensor name as the runtime reports it; null when the runtime path does
  /// not expose names (e.g. `CompiledModel`), so only the shape is checked.
  final String? name;
  final List<int> shape;

  /// What the pipeline uses it for (`landmarks`, `presence`, …); lets code
  /// bind tensors by meaning instead of position.
  final String? role;
  final TensorRange? range;
  final TensorLayout layout;

  int get elementCount => shape.fold(1, (a, b) => a * b);
}

/// A tensor as a loaded session reports it.
typedef TensorSignature = ({String name, List<int> shape});

/// Base of the typed load refusals for a [ModelSpec].
sealed class ModelSpecException implements Exception {
  const ModelSpecException(this.modelId);
  final String modelId;
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The model has no pinned SHA-256. A pinned hash is what stops a
/// compromised CDN from swapping a model (research 07 §6.2), so unpinned
/// specs are never downloaded, extracted or run.
final class UnpinnedModelException extends ModelSpecException {
  const UnpinnedModelException(super.modelId);

  @override
  String get message =>
      '$modelId has no pinned SHA-256; refusing to load it. Pin the hash of '
      'the mirrored file in model_manifest.dart.';
}

/// The model is in the manifest for provenance but cannot run yet.
final class DisabledModelException extends ModelSpecException {
  const DisabledModelException(super.modelId, this.reason);
  final String reason;

  @override
  String get message => '$modelId is disabled: $reason';
}

final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

/// One on-device model file.
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.version,
    required this.fileName,
    required this.url,
    required this.bytes,
    required this.license,
    required this.trainingDataNote,
    this.sha256,
    this.runtime = ModelRuntime.litert,
    this.bundled = false,
    this.inputs = const [],
    this.outputs = const [],
    this.disabledReason,
  });

  final String id;
  final String version;
  final String fileName;

  /// Upstream URL (bundled models: where the file was extracted from). To be
  /// replaced by the own-CDN mirror before launch.
  final String url;

  /// Lower-case hex SHA-256 of the exact file; null until pinned.
  final String? sha256;

  /// Exact file size; downloads stop if the server sends more.
  final int bytes;
  final String license;
  final String trainingDataNote;
  final ModelRuntime runtime;

  /// Ships in the app's `assets/models/` (resolved, never downloaded).
  final bool bundled;
  final List<ModelTensorSpec> inputs;
  final List<ModelTensorSpec> outputs;

  /// Non-null keeps the row for provenance but refuses to load it.
  final String? disabledReason;

  bool get enabled => disabledReason == null;

  /// `id@version`: the cache and analysis version key.
  String get key => '$id@$version';

  /// Asset key for [bundled] models.
  String get bundledAssetKey => 'assets/models/$fileName';

  bool get isPinned {
    final h = sha256;
    return h != null && _sha256Hex.hasMatch(h);
  }

  /// Throws a [ModelSpecException] unless the model may be loaded.
  void requireLoadable() {
    final reason = disabledReason;
    if (reason != null) throw DisabledModelException(id, reason);
    if (!isPinned) throw UnpinnedModelException(id);
  }

  /// The output tensor declared with [role], if any.
  ModelTensorSpec? outputWithRole(String role) =>
      outputs.firstWhereOrNull((t) => t.role == role);

  ModelTensorSpec? inputWithRole(String role) =>
      inputs.firstWhereOrNull((t) => t.role == role);

  /// Differences between the declared contract and what a loaded session
  /// reports (names, order and shapes). Empty when they match or when the
  /// spec declares no tensors for that side.
  List<String> contractViolations({
    required List<TensorSignature> inputs,
    required List<TensorSignature> outputs,
  }) => [
    ..._diff('input', this.inputs, inputs),
    ..._diff('output', this.outputs, outputs),
  ];

  static List<String> _diff(
    String side,
    List<ModelTensorSpec> expected,
    List<TensorSignature> actual,
  ) {
    if (expected.isEmpty) return const [];
    if (expected.length != actual.length) {
      return ['$side count ${actual.length} != ${expected.length}'];
    }
    const eq = ListEquality<int>();
    return [
      for (var i = 0; i < expected.length; i++)
        if ((expected[i].name != null && expected[i].name != actual[i].name) ||
            !eq.equals(expected[i].shape, actual[i].shape))
          '$side $i: got ${actual[i].name} ${actual[i].shape}, expected '
              '${expected[i].name} ${expected[i].shape}',
    ];
  }
}
