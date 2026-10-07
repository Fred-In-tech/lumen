// Real-model test: Selfie Multiclass through LiteRtBackend on a drawn
// two-face portrait at 2560 px (no real person, no download), with the
// real face pipeline supplying the per-face crops.
//
// Needs the bundled face models (app/assets/models), the dev copy of the
// download-on-first-use segmenter (repo-root .dev_models/) and the LiteRT
// host libraries (TFLITE_LIB_PATH, LITERT_LIB_PATH; tool/verify.sh).
// Skips cleanly without them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/face_analyzer.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/litert_backend_io.dart';
import 'package:lumen/ai/ondevice/mask_segmenter.dart';
import 'package:lumen_core/lumen_core.dart';

import 'synthetic_portrait.dart';

const _det = ModelManifest.blazeFaceFullRange;
const _mesh = ModelManifest.faceLandmarksDetector;
const _seg = ModelManifest.selfieMulticlass;

String _asset(ModelSpec s) => 'assets/models/${s.fileName}';
String _dev(ModelSpec s) => '../.dev_models/${s.fileName}';

/// Why the real-model tests skip here (false: they run).
final Object skipReason =
    Platform.environment['TFLITE_LIB_PATH'] == null ||
        Platform.environment['LITERT_LIB_PATH'] == null
    ? 'LiteRT host libraries not configured (run tool/verify.sh)'
    : ![
        _asset(_det),
        _asset(_mesh),
        _dev(_seg),
      ].every((f) => File(f).existsSync())
    ? 'models missing'
    : false;

/// Two drawn people in a 2560×1707 frame.
const kGroupFaces = [(820.0, 760.0, 560.0), (1760.0, 800.0, 500.0)];

Future<({FaceAnalyzer faces, MaskSegmenter segmenter})> openRealModels() async {
  const backend = LiteRtBackend();
  final faces = FaceAnalyzer(
    detector: await loadVerifiedSession(
      backend,
      _det,
      ModelFileSource(_asset(_det)),
    ),
    detectorSpec: _det,
    mesh: await loadVerifiedSession(
      backend,
      _mesh,
      ModelFileSource(_asset(_mesh)),
    ),
    meshSpec: _mesh,
  );
  final segmenter = MaskSegmenter(
    session: await loadVerifiedSession(
      backend,
      _seg,
      ModelFileSource(_dev(_seg)),
    ),
    spec: _seg,
  );
  return (faces: faces, segmenter: segmenter);
}

double _cover(MaskRaster r, double sx, double sy, int w, int h) =>
    r.data[(sy / h * r.height).floor() * r.width + (sx / w * r.width).floor()] /
    255;

void main() {
  test(
    'two faces at 2560 px: people and face-skin rasters land on the people',
    () async {
      final models = await openRealModels();
      addTearDown(models.faces.dispose);
      addTearDown(models.segmenter.dispose);
      final (img, layouts) = syntheticGroupPortrait(
        width: 2560,
        height: 1707,
        faces: kGroupFaces,
      );
      final analysis = await models.faces.analyze(img);
      final boxes = [
        for (final f in analysis.analysis.faces) f.box,
        for (final r in analysis.rejected) r.box,
      ];
      expect(boxes, hasLength(2));

      final result = await models.segmenter.segment(img, faces: boxes);

      final planes = result.planes;
      expect(planes.width, 1024);
      expect(result.timings.faceCrops, 2);
      // On this cartoon the zoomed crops read as backdrop, so the agreement
      // check drops them and the whole pass is used (verified 2026-10-03;
      // crop gains need a licensed real portrait to measure).
      expect(planes.faceCropsUsed, lessThanOrEqualTo(2));
      final people = planes.raster(AiRaster.people);
      final skin = planes.raster(AiRaster.faceSkin);
      final bg = planes.raster(AiRaster.background);
      for (final l in layouts) {
        final cheekY = l.cy + 0.1 * l.scale;
        expect(_cover(people, l.cx, cheekY, 2560, 1707), greaterThan(0.5));
        expect(_cover(skin, l.cx, cheekY, 2560, 1707), greaterThan(0.5));
        expect(_cover(bg, l.cx, cheekY, 2560, 1707), lessThan(0.5));
      }
      // Empty backdrop: top-left corner and the gap between the two people.
      expect(_cover(people, 60, 60, 2560, 1707), lessThan(0.5));
      expect(_cover(people, 1290, 200, 2560, 1707), lessThan(0.5));
      expect(_cover(skin, 60, 60, 2560, 1707), lessThan(0.5));
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
