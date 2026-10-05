import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'retouch_harness.dart';

/// Regression: a photo that opens already retouched showed no retouch on
/// its first settled frame. The frame render waits for the retouch map
/// upload; style-preview thumbnails rendered meanwhile (other tone
/// settings) replaced and disposed the graph's single-slot LUT, so the
/// frame's develop pass threw "Image has been disposed" and the frame was
/// dropped. Renders of one graph must not interleave.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overlapping renders with other tone settings all complete and the '
      'retouched frame equals a solo render', () async {
    final one = onePortrait();
    final shaders = await ShaderLibrary.load();
    final src = await imageFromBuffer(one.p.image);
    final aux = await AuxTextures.fromMaps(AuxMaps.neutral());
    final graph = RenderGraph(shaders: shaders, source: src, aux: aux)
      ..retouchMaps = one.maps
      ..faceAnalysis = one.p.analysis;
    final base = DevelopSettings.defaults.copyWith(
      portrait: portraitOf({
        PortraitIds.skinSoftening: 80,
        PortraitIds.skinShine: 80,
      }),
    );
    try {
      // The frame (uploads the retouch maps) and three "style previews".
      final pending = [
        graph.render(base),
        graph.render(base.withValue(P.contrast, 40)),
        graph.render(base.withValue(P.exposure, 0.8), scale: 0.25),
        graph.render(
          DevelopSettings.defaults.withValue(P.shadows, 30),
          scale: 0.25,
        ),
      ];
      final images = await Future.wait(pending);
      final frame = await bufferFromImage(images.first);
      images.forEach(EngineImages.dispose);
      final soloImage = await graph.render(base);
      final solo = await bufferFromImage(soloImage);
      EngineImages.dispose(soloImage);
      expect(frame.data, solo.data);
      final plainImage = await graph.render(
        base.copyWith(portrait: PortraitSettings.empty),
      );
      final plain = await bufferFromImage(plainImage);
      EngineImages.dispose(plainImage);
      expect(diffStats(frame, plain).max, greaterThan(3), reason: 'retouched');
    } finally {
      graph.dispose();
      aux.dispose();
      EngineImages.dispose(src);
    }
    expect(EngineImages.live, 0);
  });
}
