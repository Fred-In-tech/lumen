// Real-model test: the retouch face parser (Selfie Multiclass through
// LiteRtBackend) on the face tiles of a drawn two-face portrait, then the
// retouch maps with that parsing. Needs the bundled face models, the dev
// copy of the segmenter (repo-root .dev_models/) and the LiteRT host
// libraries (tool/verify.sh); skips cleanly without them.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ai/ondevice/face_parser.dart';
import 'package:lumen/ai/ondevice/inference_backend.dart';
import 'package:lumen/ai/ondevice/litert_backend_io.dart';
import 'package:lumen_core/lumen_core.dart';

import 'litert_ai_mask_test.dart' as masks;
import 'synthetic_portrait.dart';

void main() {
  test(
    'parses each face tile into class planes over its source rect',
    () async {
      final models = await masks.openRealModels();
      addTearDown(models.faces.dispose);
      addTearDown(models.segmenter.dispose);
      final parser = FaceParser(
        session: await loadVerifiedSession(
          const LiteRtBackend(),
          ModelManifest.selfieMulticlass,
          const ModelFileSource(
            '../.dev_models/selfie_multiclass_256x256.tflite',
          ),
        ),
        spec: ModelManifest.selfieMulticlass,
      );
      addTearDown(parser.dispose);
      final (img, layouts) = syntheticGroupPortrait(
        width: 2560,
        height: 1707,
        faces: masks.kGroupFaces,
      );
      final analysis = (await models.faces.analyze(img)).analysis;
      expect(analysis.faces, isNotEmpty);
      final tiles = [
        for (final t in planFaceTiles(analysis, img.width, img.height))
          FaceTileImage(t, resampleTile(img, t)),
      ];
      final planes = await parser.parse(tiles);
      expect(planes, hasLength(tiles.length));
      // The planes cover each tile's source rect, and every cell is a
      // probability split over the six classes. (On this cartoon the model
      // reads the zoomed faces as backdrop, as the AI-mask test notes, so
      // the class semantics are checked on the real photo instead:
      // integration_test/retouch_real_photo_test.dart.)
      for (var k = 0; k < planes.length; k++) {
        final pl = planes[k], t = tiles[k].plan;
        expect(pl.faceId, t.faceId);
        expect(pl.cropX, closeTo(t.u0, 1e-9));
        expect(pl.cropHeight, closeTo(t.v1 - t.v0, 1e-9));
        expect(pl.width, lessThanOrEqualTo(256));
        for (var i = 0; i < pl.width * pl.height; i += 97) {
          final sum = pl.planes.fold(0, (a, q) => a + q[i]);
          expect(sum, inInclusiveRange(250, 260));
        }
      }
      final maps = computeRetouchMaps(
        img,
        analysis,
        tiles: tiles,
        parsing: planes,
      );
      expect(maps.faces, hasLength(analysis.faces.length));
    },
    skip: masks.skipReason,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
