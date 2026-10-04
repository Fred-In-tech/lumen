import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/face_analyzer.dart';
import 'package:lumen/ai/ondevice/face_model_bindings.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/platform/background.dart';

/// Wall-clock cost of one segmentation, in milliseconds.
class MaskSegmentationTimings {
  const MaskSegmentationTimings({
    required this.prepareMs,
    required this.wholeMs,
    required this.facesMs,
    required this.composeMs,
    required this.totalMs,
    required this.faceCrops,
    required this.faceCropsUsed,
  });

  /// Resampling the image into the whole-image and per-face tensors.
  final int prepareMs;

  /// Whole-image inference.
  final int wholeMs;

  /// All per-face inferences.
  final int facesMs;

  /// Luma guide + compositing + guided filter + quantization.
  final int composeMs;
  final int totalMs;

  /// Crops run, and crops that agreed with the whole pass and were used.
  final int faceCrops;
  final int faceCropsUsed;

  @override
  String toString() =>
      'prepare $prepareMs ms, whole $wholeMs ms, faces '
      '($faceCropsUsed/$faceCrops used) $facesMs ms, compose+guided '
      '$composeMs ms, total $totalMs ms';
}

class MaskSegmentation {
  const MaskSegmentation(this.planes, this.timings);
  final AiMaskPlanes planes;
  final MaskSegmentationTimings timings;
}

/// Selfie Multiclass on the whole image (letterboxed) and on each face crop
/// (bbox × 2.2, squared), composited and edge-refined into 8-bit planes on
/// the renderer's mask grid (research 07 §2.2, §4).
class MaskSegmenter {
  MaskSegmenter({
    required InferenceSession session,
    required this.spec,
    this.gridLongEdge = kMaskLongEdge,
    this.refine = const GuidedFilterParams(),
    this.maxFaceCrops = 6,
    BackgroundRunner? runner,
  }) : _session = session,
       _run = runner ?? runInBackground,
       _input = resolveImageInput(session, spec, TensorRange.minusOneToOne),
       _output = _resolveOutput(session, spec);

  final ModelSpec spec;
  final int gridLongEdge;
  final GuidedFilterParams refine;

  /// The largest faces get their own crop; the rest use the whole pass.
  final int maxFaceCrops;
  final InferenceSession _session;
  final BackgroundRunner _run;
  final ImageInput _input;
  final ({String name, int channels}) _output;

  static ({String name, int channels}) _resolveOutput(
    InferenceSession s,
    ModelSpec spec,
  ) {
    final name = spec.outputWithRole(TensorRoles.segmentation)?.name;
    final t = name == null
        ? s.outputs.firstOrNull
        : s.outputs.firstWhereOrNull((t) => t.name == name);
    if (t == null || t.shape.length != 4 || t.shape[3] <= SelfieClass.clothes) {
      throw ModelContractMismatch(
        '${spec.key}: no [1, H, W, ≥5] segmentation output (${s.outputs})',
      );
    }
    return (name: t.name, channels: t.shape[3]);
  }

  /// Segments [pixels]; [faces] (normalized boxes) get per-face crops.
  Future<MaskSegmentation> segment(
    RgbaBuffer pixels, {
    List<FaceBox> faces = const [],
  }) async {
    final total = Stopwatch()..start();
    final w = pixels.width, h = pixels.height;
    final crops = _crops(faces, w, h);
    final i = _input;
    var lap = Stopwatch()..start();
    final tensors = await _prepare(
      _run,
      pixels,
      [null, ...crops],
      i.width,
      i.height,
      i.range,
    );
    final prepareMs = lap.elapsedMilliseconds;
    lap = Stopwatch()..start();
    final whole = await _infer(tensors.first);
    final wholeMs = lap.elapsedMilliseconds;
    lap = Stopwatch()..start();
    final faceOut = [for (final t in tensors.skip(1)) await _infer(t)];
    final facesMs = lap.elapsedMilliseconds;
    lap = Stopwatch()..start();
    final grid = MaskRasterizer.gridSize(w, h, longEdge: gridLongEdge);
    final planes = await _compose(
      _run,
      pixels,
      grid,
      (raw: whole, tensor: tensors.first, region: null),
      [
        for (var k = 0; k < crops.length; k++)
          (raw: faceOut[k], tensor: tensors[k + 1], region: crops[k]),
      ],
      _output.channels,
      refine,
    );
    return MaskSegmentation(
      planes,
      MaskSegmentationTimings(
        prepareMs: prepareMs,
        wholeMs: wholeMs,
        facesMs: facesMs,
        composeMs: lap.elapsedMilliseconds,
        totalMs: total.elapsedMilliseconds,
        faceCrops: crops.length,
        faceCropsUsed: planes.faceCropsUsed,
      ),
    );
  }

  List<PixelRegion> _crops(List<FaceBox> faces, int w, int h) {
    final sorted = [...faces]
      ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    return [
      for (final f in sorted.take(maxFaceCrops))
        if (segmentationCropFor(f, imageWidth: w, imageHeight: h) case final c
            when c.width >= 8 && c.height >= 8)
          (left: c.left, top: c.top, width: c.width, height: c.height),
    ];
  }

  Future<Float32List> _infer(LetterboxedTensor t) async {
    final out = await _session.run({_input.name: t.data});
    final raw = out[_output.name];
    if (raw == null) {
      throw InferenceRunFailed('${spec.key} returned no segmentation');
    }
    return raw;
  }

  Future<void> dispose() => _session.dispose();
}

typedef _Pass = ({
  Float32List raw,
  LetterboxedTensor tensor,
  PixelRegion? region,
});

// Top-level so the isolate closures capture only their arguments.
Future<List<LetterboxedTensor>> _prepare(
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

Future<AiMaskPlanes> _compose(
  BackgroundRunner run,
  RgbaBuffer img,
  ({int width, int height}) grid,
  _Pass whole,
  List<_Pass> faces,
  int channels,
  GuidedFilterParams refine,
) => run(() {
  SegmentationView view(_Pass p) => SegmentationView(
    probabilities: multiclassProbabilities(p.raw, channels),
    width: p.tensor.width,
    height: p.tensor.height,
    channels: channels,
    region: p.region ?? (left: 0, top: 0, width: img.width, height: img.height),
    letterbox: p.tensor.letterbox,
  );
  return composeAiMasks(
    gridWidth: grid.width,
    gridHeight: grid.height,
    sourceWidth: img.width,
    sourceHeight: img.height,
    whole: view(whole),
    faces: [for (final f in faces) view(f)],
    guide: lumaPlane(img, width: grid.width, height: grid.height),
    refine: refine,
  );
});
