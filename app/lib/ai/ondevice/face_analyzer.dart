import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/face_model_bindings.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/platform/background.dart';

/// Runs CPU work off the UI isolate (`runInBackground`; inline in tests).
typedef BackgroundRunner = Future<T> Function<T>(FutureOr<T> Function() fn);

/// When to run the second, landmark-aligned mesh pass (research 07 §1.2.4).
enum RefineMode { never, largeFaces, always }

class FaceAnalyzerConfig {
  const FaceAnalyzerConfig({
    this.minDetectionScore = 0.5,
    this.nmsIouThreshold = 0.3,
    this.cropScale = 1.5,
    this.refine = RefineMode.largeFaces,
    this.largeFaceFraction = 0.25,
    this.maxFaces = 20,
    this.tiling = const TilingPolicy(),
    this.rejectRules = const FaceRejectRules(),
  });

  final double minDetectionScore;
  final double nmsIouThreshold;
  final double cropScale;
  final RefineMode refine;

  /// Face long side / image long edge above which [RefineMode.largeFaces]
  /// refines.
  final double largeFaceFraction;
  final int maxFaces;
  final TilingPolicy tiling;
  final FaceRejectRules rejectRules;
}

/// Detect → (tile) → align → mesh → (refine) → reject, on decoded pixels.
///
/// Pixel work (resampling into tensors) runs through [BackgroundRunner];
/// inference runs in the sessions' own isolates; decoding, NMS and geometry
/// are cheap and stay on the caller.
class FaceAnalyzer {
  FaceAnalyzer({
    required InferenceSession detector,
    required this.detectorSpec,
    required InferenceSession mesh,
    required this.meshSpec,
    this.config = const FaceAnalyzerConfig(),
    BackgroundRunner? runner,
  }) : _detector = detector,
       _mesh = mesh,
       _run = runner ?? runInBackground,
       _det = DetectorBinding.resolve(
         detector,
         detectorSpec,
         minScore: config.minDetectionScore,
       ),
       _meshBinding = MeshBinding.resolve(mesh, meshSpec);

  final ModelSpec detectorSpec;
  final ModelSpec meshSpec;
  final FaceAnalyzerConfig config;
  final InferenceSession _detector;
  final InferenceSession _mesh;
  final BackgroundRunner _run;
  final DetectorBinding _det;
  final MeshBinding _meshBinding;

  /// Model keys the result depends on (the face cache's version key).
  Map<String, String> get models => {
    'detector': detectorSpec.key,
    'mesh': meshSpec.key,
  };

  String get modelVersion => '${detectorSpec.key}+${meshSpec.key}';

  /// Analyzes [pixels]. [sourceWidth]/[sourceHeight] are the original
  /// (oriented) size when [pixels] is a downscaled copy; reject lengths are
  /// measured there. Throws [InferenceException] on runtime failures.
  Future<FaceAnalysisResult> analyze(
    RgbaBuffer pixels, {
    int? sourceWidth,
    int? sourceHeight,
  }) async {
    final dets = await _detect(pixels);
    final candidates = await _landmarks(pixels, dets);
    return buildFaceAnalysis(
      imageWidth: sourceWidth ?? pixels.width,
      imageHeight: sourceHeight ?? pixels.height,
      modelVersion: modelVersion,
      candidates: candidates,
      rules: config.rejectRules,
    );
  }

  Future<void> dispose() async {
    await _detector.dispose();
    await _mesh.dispose();
  }

  Future<List<FaceDetection>> _detect(RgbaBuffer img) async {
    final i = _det.input;
    final full = await _letterbox(
      _run,
      img,
      [null],
      i.width,
      i.height,
      i.range,
    );
    var dets = weightedNonMaxSuppression(
      await _decode(full.single),
      iouThreshold: config.nmsIouThreshold,
    );
    final tiles = planDetectionTiles(
      imageWidth: img.width,
      imageHeight: img.height,
      detections: dets,
      policy: config.tiling,
    );
    if (tiles.isNotEmpty) {
      final regions = [
        for (final t in tiles) t.pixelBounds(img.width, img.height),
      ];
      final tensors = await _letterbox(
        _run,
        img,
        regions,
        i.width,
        i.height,
        i.range,
      );
      dets = mergeTileDetections(
        fullFrame: dets,
        tiles: [
          for (var k = 0; k < regions.length; k++)
            (
              DetectionTile(
                regions[k].left / img.width,
                regions[k].top / img.height,
                regions[k].width / img.width,
                regions[k].height / img.height,
              ),
              await _decode(tensors[k]),
            ),
        ],
        iouThreshold: config.nmsIouThreshold,
      );
    }
    final sorted = [...dets]..sort((a, b) => b.score.compareTo(a.score));
    return sorted.take(config.maxFaces).toList();
  }

  /// Runs the detector on one tensor; detections normalized to its region.
  Future<List<FaceDetection>> _decode(LetterboxedTensor t) async {
    final out = await _detector.run({_det.input.name: t.data});
    final reg = out[_det.regressors];
    final scores = out[_det.scores];
    if (reg == null || scores == null) {
      throw const InferenceRunFailed('detector returned no boxes/scores');
    }
    return [
      for (final d in decodeBlazeFace(
        regressors: reg,
        scores: scores,
        anchors: _det.anchors,
        options: _det.options,
      ))
        t.letterbox.remove(d),
    ];
  }

  Future<List<FaceCandidate>> _landmarks(
    RgbaBuffer img,
    List<FaceDetection> dets,
  ) async {
    final w = img.width, h = img.height;
    final size = _meshBinding.size;
    final crops = [
      for (final d in dets)
        AlignedCrop.fromDetection(
          d,
          imageWidth: w,
          imageHeight: h,
          scale: config.cropScale,
          outputSize: size,
        ),
    ];
    final first = await _meshPass(img, crops);
    final refineIdx = [
      for (var k = 0; k < dets.length; k++)
        if (_shouldRefine(dets[k], w, h) && first[k].presence >= 0.5) k,
    ];
    final refined = await _meshPass(img, [
      for (final k in refineIdx)
        AlignedCrop.fromLandmarks(
          first[k].landmarks,
          imageWidth: w,
          imageHeight: h,
          scale: config.cropScale,
          outputSize: size,
        ),
    ]);
    final result = [...first];
    for (var j = 0; j < refineIdx.length; j++) {
      result[refineIdx[j]] = refined[j];
    }
    return [
      for (var k = 0; k < dets.length; k++)
        FaceCandidate(
          detection: dets[k],
          landmarks: result[k].landmarks,
          presence: result[k].presence,
        ),
    ];
  }

  bool _shouldRefine(FaceDetection d, int w, int h) => switch (config.refine) {
    RefineMode.never => false,
    RefineMode.always => true,
    RefineMode.largeFaces =>
      math.max(d.width * w, d.height * h) / math.max(w, h) >
          config.largeFaceFraction,
  };

  Future<List<({List<double> landmarks, double presence})>> _meshPass(
    RgbaBuffer img,
    List<AlignedCrop> crops,
  ) async {
    if (crops.isEmpty) return const [];
    final b = _meshBinding;
    final tensors = await _warp(_run, img, crops, b.size, b.input.range);
    final out = <({List<double> landmarks, double presence})>[];
    for (var k = 0; k < crops.length; k++) {
      final r = await _mesh.run({b.input.name: tensors[k]});
      final raw = r[b.landmarks];
      final flag = r[b.presence];
      if (raw == null || flag == null || flag.isEmpty) {
        throw const InferenceRunFailed('mesh returned no landmarks/flag');
      }
      out.add((
        landmarks: landmarksToSource(
          raw,
          crops[k],
          imageWidth: img.width,
          imageHeight: img.height,
          valuesPerPoint: b.valuesPerPoint,
          inputSize: b.size,
        ),
        presence: logistic(flag[0]),
      ));
    }
    return out;
  }
}

// Top-level so the isolate closure captures only its arguments (see
// `_autoEditInIsolate` in auto_edit_service.dart).
Future<List<LetterboxedTensor>> _letterbox(
  BackgroundRunner run,
  RgbaBuffer img,
  List<PixelRegion?> regions,
  int w,
  int h,
  TensorRange range,
) => run(
  () => [
    for (final r in regions)
      letterboxToTensor(img, width: w, height: h, region: r, range: range),
  ],
);

Future<List<Float32List>> _warp(
  BackgroundRunner run,
  RgbaBuffer img,
  List<AlignedCrop> crops,
  int size,
  TensorRange range,
) => run(
  () => [
    for (final c in crops)
      warpToTensor(img, c.cropToSource, size: size, range: range),
  ],
);
