import 'model_spec.dart';
import 'tensor_sampling.dart';

export 'model_spec.dart';

const _mp = 'https://storage.googleapis.com/mediapipe-models';
const _taskUrl =
    '$_mp/face_landmarker/face_landmarker/float16/latest/face_landmarker.task';
const _google = 'Google-collected data (model card)';
const _m11 = [1, 1];
const _m1111 = [1, 1, 1, 1];

/// Tensor roles the vision pipeline binds by.
abstract final class TensorRoles {
  static const image = 'image';
  static const regressors = 'regressors';
  static const scores = 'scores';
  static const landmarks = 'landmarks';
  static const presence = 'presence';
  static const segmentation = 'segmentation';
}

/// The Phase 2 on-device models (research 07 §7.2). SHA-256s and tensor
/// contracts verified by the lead on 2026-10-03 (classic Interpreter, CPU).
/// Every row must also be in docs/MODEL_LICENSES.md before shipping.
abstract final class ModelManifest {
  /// Source bundle of [blazeFaceShortRange] and [faceLandmarksDetector]; the
  /// app ships the extracted entries, so this row is provenance only.
  static const faceLandmarkerTask = ModelSpec(
    id: 'face_landmarker_task',
    version: '1',
    fileName: 'face_landmarker.task',
    url: _taskUrl,
    sha256: '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff',
    bytes: 3758596,
    license: 'Apache-2.0',
    trainingDataNote: '$_google, 17 geographic regions',
    disabledReason: 'source bundle; the app ships its extracted entries',
  );

  /// BlazeFace short-range (selfie distance), from [faceLandmarkerTask].
  static const blazeFaceShortRange = ModelSpec(
    id: 'blaze_face_short_range',
    version: '1',
    fileName: 'blaze_face_short_range.tflite',
    url: _taskUrl,
    sha256: 'b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f',
    bytes: 229746,
    license: 'Apache-2.0',
    trainingDataNote: _google,
    bundled: true,
    inputs: [
      ModelTensorSpec(
        name: 'input',
        shape: [1, 128, 128, 3],
        role: TensorRoles.image,
        range: TensorRange.minusOneToOne,
      ),
    ],
    outputs: [
      ModelTensorSpec(
        name: 'regressors',
        shape: [1, 896, 16],
        role: TensorRoles.regressors,
      ),
      ModelTensorSpec(
        name: 'classificators',
        shape: [1, 896, 1],
        role: TensorRoles.scores,
      ),
    ],
  );

  /// BlazeFace full-range (group and wide shots): 192², one stride-4 layer.
  static const blazeFaceFullRange = ModelSpec(
    id: 'blaze_face_full_range',
    version: '1',
    fileName: 'blaze_face_full_range.tflite',
    url:
        '$_mp/face_detector/blaze_face_full_range/float16/latest/'
        'blaze_face_full_range.tflite',
    sha256: '3698b18f063835bc609069ef052228fbe86d9c9a6dc8dcb7c7c2d69aed2b181b',
    bytes: 1083786,
    license: 'Apache-2.0 (family card; full-range card unverified)',
    trainingDataNote: _google,
    bundled: true,
    inputs: [
      ModelTensorSpec(
        name: 'input',
        shape: [1, 192, 192, 3],
        role: TensorRoles.image,
        range: TensorRange.minusOneToOne,
      ),
    ],
    outputs: [
      ModelTensorSpec(
        name: 'reshaped_regressor_face_4',
        shape: [1, 2304, 16],
        role: TensorRoles.regressors,
      ),
      ModelTensorSpec(
        name: 'reshaped_classifier_face_4',
        shape: [1, 2304, 1],
        role: TensorRoles.scores,
      ),
    ],
  );

  /// FaceMesh V2 with iris (478 points), from [faceLandmarkerTask].
  static const faceLandmarksDetector = ModelSpec(
    id: 'face_landmarks_detector',
    version: '1',
    fileName: 'face_landmarks_detector.tflite',
    url: _taskUrl,
    sha256: 'c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5',
    bytes: 2553590,
    license: 'Apache-2.0',
    trainingDataNote: '$_google, 17 geographic regions',
    bundled: true,
    inputs: [
      ModelTensorSpec(
        name: 'input_12',
        shape: [1, 256, 256, 3],
        role: TensorRoles.image,
        range: TensorRange.zeroToOne,
      ),
    ],
    outputs: [
      // 478 × (x, y, z) in 256-px crop coordinates.
      ModelTensorSpec(
        name: 'Identity',
        shape: [1, 1, 1, 1434],
        role: TensorRoles.landmarks,
      ),
      // Face-presence logit (sigmoid → probability).
      ModelTensorSpec(
        name: 'Identity_1',
        shape: _m1111,
        role: TensorRoles.presence,
      ),
      ModelTensorSpec(name: 'Identity_2', shape: _m11),
    ],
  );

  /// Classes: 0 background, 1 hair, 2 body skin, 3 face skin, 4 clothes,
  /// 5 others/accessories. 144 ms CPU.
  static const selfieMulticlass = ModelSpec(
    id: 'selfie_multiclass_256',
    version: '1',
    fileName: 'selfie_multiclass_256x256.tflite',
    url:
        '$_mp/image_segmenter/selfie_multiclass_256x256/float32/latest/'
        'selfie_multiclass_256x256.tflite',
    sha256: 'c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0',
    bytes: 16371837,
    license: 'Apache-2.0',
    trainingDataNote: '$_google; fairness-evaluated (Monk 1-10, gender)',
    inputs: [
      // TFLite metadata: mean 127.5, std 127.5 → [−1, 1].
      ModelTensorSpec(
        name: 'input_29',
        shape: [1, 256, 256, 3],
        role: TensorRoles.image,
        range: TensorRange.minusOneToOne,
      ),
    ],
    outputs: [
      ModelTensorSpec(
        name: 'Identity',
        shape: [1, 256, 256, 6],
        role: TensorRoles.segmentation,
      ),
    ],
  );

  /// Needs custom ops flutter_litert does not ship.
  static const hairSegmenter = ModelSpec(
    id: 'hair_segmenter',
    version: '1',
    fileName: 'hair_segmenter.tflite',
    url:
        '$_mp/image_segmenter/hair_segmenter/float32/latest/'
        'hair_segmenter.tflite',
    sha256: '2628cf3ce5f695f604cbea2841e00befcaa3624bf80caf3664bef2656d59bf84',
    bytes: 781618,
    license: 'Apache-2.0',
    trainingDataNote: _google,
    disabledReason:
        'needs custom ops MaxPoolingWithArgmax2D/MaxUnpooling2D, which '
        'flutter_litert does not ship',
  );

  /// Object removal. NCHW: channel 0 = mask − 0.5 (mask 1 = keep), channels
  /// 1-3 = rgb·mask in [−1, 1]; output rgb ≈ [−1, 1] (clamp). Runs only via
  /// `CompiledModel` (the classic Interpreter rejects it), 794 ms CPU.
  static const miGan = ModelSpec(
    id: 'migan_512_places2',
    version: '1',
    fileName: 'migan_fp16.tflite',
    url:
        'https://huggingface.co/litert-community/MI-GAN-512-Places2-LiteRT/'
        'resolve/main/migan_fp16.tflite',
    sha256: 'ef53f8dca69e5ce29629441128322c4d9a0a527b2a043703e0ab497f2463c25f',
    bytes: 16312640,
    license: 'MIT',
    trainingDataNote: 'Places2 (legal note: dataset terms)',
    inputs: [
      ModelTensorSpec(
        shape: [1, 4, 512, 512],
        role: TensorRoles.image,
        range: TensorRange.minusOneToOne,
        layout: TensorLayout.nchw,
      ),
    ],
    outputs: [
      ModelTensorSpec(
        shape: [1, 3, 512, 512],
        role: TensorRoles.image,
        layout: TensorLayout.nchw,
      ),
    ],
  );

  static const all = [
    faceLandmarkerTask,
    blazeFaceShortRange,
    blazeFaceFullRange,
    faceLandmarksDetector,
    selfieMulticlass,
    hairSegmenter,
    miGan,
  ];

  static ModelSpec? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }
}
