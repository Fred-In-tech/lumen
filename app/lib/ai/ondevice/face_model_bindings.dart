import 'package:collection/collection.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/inference_backend.dart';

/// Image input of an NHWC model.
typedef ImageInput = ({String name, int width, int height, TensorRange range});

ImageInput _imageInput(InferenceSession s, ModelSpec spec, TensorRange dflt) {
  final declared = spec.inputWithRole(TensorRoles.image);
  final t = declared?.name == null
      ? s.inputs.firstOrNull
      : s.inputs.firstWhereOrNull((t) => t.name == declared!.name);
  if (t == null || t.shape.length != 4 || t.shape[3] != 3) {
    throw ModelContractMismatch(
      '${spec.key}: no [1, H, W, 3] image input (inputs: ${s.inputs})',
    );
  }
  return (
    name: t.name,
    width: t.shape[2],
    height: t.shape[1],
    range: declared?.range ?? dflt,
  );
}

/// Binds an output by its declared role, else by [fallback] on the shapes.
TensorSignature _output(
  InferenceSession s,
  ModelSpec spec,
  String role,
  bool Function(TensorSignature t) fallback,
) {
  final name = spec.outputWithRole(role)?.name;
  final t = name == null
      ? s.outputs.firstWhereOrNull(fallback)
      : s.outputs.firstWhereOrNull((t) => t.name == name);
  if (t == null) {
    throw ModelContractMismatch(
      '${spec.key}: no $role output (outputs: ${s.outputs})',
    );
  }
  return t;
}

/// BlazeFace tensors, anchors and decode options, all read from the loaded
/// session's shapes (never assumed).
class DetectorBinding {
  DetectorBinding._(
    this.input,
    this.regressors,
    this.scores,
    this.anchors,
    this.options,
  );

  factory DetectorBinding.resolve(
    InferenceSession s,
    ModelSpec spec, {
    double minScore = 0.5,
  }) {
    final input = _imageInput(s, spec, TensorRange.minusOneToOne);
    final reg = _output(
      s,
      spec,
      TensorRoles.regressors,
      (t) => t.shape.length == 3 && t.shape[2] >= 4 && t.shape[2] != 1,
    );
    final scores = _output(
      s,
      spec,
      TensorRoles.scores,
      (t) => t.shape.length == 3 && t.shape[2] == 1,
    );
    if (reg.shape.length != 3 ||
        scores.shape.length != 3 ||
        reg.shape[1] != scores.shape[1]) {
      throw ModelContractMismatch(
        '${spec.key}: regressors ${reg.shape} and scores ${scores.shape} '
        'disagree on the anchor count',
      );
    }
    final SsdAnchorConfig layout;
    try {
      layout = SsdAnchorConfig.resolve(
        inputWidth: input.width,
        inputHeight: input.height,
        anchorCount: reg.shape[1],
      );
    } on AnchorLayoutException catch (e) {
      throw ModelContractMismatch('${spec.key}: ${e.message}');
    }
    return DetectorBinding._(
      input,
      reg.name,
      scores.name,
      layout.generate(),
      BlazeFaceDecodeOptions.forInput(
        inputWidth: input.width,
        inputHeight: input.height,
        numCoords: reg.shape[2],
        minScore: minScore,
      ),
    );
  }

  final ImageInput input;
  final String regressors;
  final String scores;
  final List<SsdAnchor> anchors;
  final BlazeFaceDecodeOptions options;
}

/// Face mesh tensors: square image input, landmarks and face-flag outputs.
class MeshBinding {
  MeshBinding._(this.input, this.landmarks, this.presence, this.valuesPerPoint);

  factory MeshBinding.resolve(InferenceSession s, ModelSpec spec) {
    final input = _imageInput(s, spec, TensorRange.zeroToOne);
    if (input.width != input.height) {
      throw ModelContractMismatch('${spec.key}: mesh input must be square');
    }
    final lm = _output(
      s,
      spec,
      TensorRoles.landmarks,
      (t) => elementCount(t.shape) % MeshKeypoints.pointCount == 0,
    );
    final presence = _output(
      s,
      spec,
      TensorRoles.presence,
      (t) => elementCount(t.shape) == 1,
    );
    final count = elementCount(lm.shape);
    final vpp = count ~/ MeshKeypoints.pointCount;
    if (count % MeshKeypoints.pointCount != 0 || vpp < 2) {
      throw ModelContractMismatch(
        '${spec.key}: landmarks ${lm.shape} is not '
        '${MeshKeypoints.pointCount} points',
      );
    }
    return MeshBinding._(input, lm.name, presence.name, vpp);
  }

  final ImageInput input;
  final String landmarks;
  final String presence;
  final int valuesPerPoint;

  int get size => input.width;
}
