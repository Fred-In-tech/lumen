// Runs the GPU engine suites on a real backend (Metal on macOS/iOS, Vulkan/GLES
// on Android) instead of the headless tester, plus the full-size export checks
// from PLAN.md §9 item 15.
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen/features/export/export_encoder.dart';
import 'package:lumen_core/lumen_core.dart';

import '../test/engine/develop_behavior_test.dart' as behavior;
import '../test/engine/develop_parity_test.dart' as parity;
import '../test/engine/engine_harness.dart';
import '../test/engine/finish_denoise_test.dart' as finish;
import '../test/support/test_images.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('parity on device', parity.main);
  group('behavior on device', behavior.main);
  group('finish/denoise on device', finish.main);

  group('full-size export (DoD 15)', () {
    final settings = DevelopSettings.defaults.withValues({
      P.exposure: 0.4,
      P.contrast: 20,
      P.clarity: 15,
      P.vignetteAmount: -20,
    });

    test('6000x4000 exports to JPEG q90 at full size; long edge 2048 gives 2048x1365; PNG is lossless', () async {
      final shaders = await ShaderLibrary.load();
      final scene = TestScenes.portrait(6000, 4000);
      final source = await imageFromBuffer(scene);
      final aux = await AuxTextures.fromMaps(
        AuxMaps.compute(AuxMaps.proxy(scene)),
      );
      final renderer = ExportRenderer(shaders);

      final full = await renderer.render(
        source: source,
        aux: aux,
        settings: settings,
        assetId: 'big',
      );
      expect([full.width, full.height], [6000, 4000]);
      final jpeg = await encodeExport(
        RgbaBuffer(full.width, full.height, full.rgba),
        format: ExportFormat.jpeg,
        quality: 90,
      );
      final decoded = img.decodeJpg(jpeg)!;
      expect([decoded.width, decoded.height], [6000, 4000]);

      final small = await renderer.render(
        source: source,
        aux: aux,
        settings: settings,
        assetId: 'big',
        longEdge: 2048,
      );
      expect([small.width, small.height], [2048, 1365]);

      final pngBytes = await encodeExport(
        RgbaBuffer(small.width, small.height, small.rgba),
        format: ExportFormat.png,
      );
      final png = img.decodePng(pngBytes)!;
      var maxDiff = 0;
      for (var y = 0; y < small.height; y += 7) {
        for (var x = 0; x < small.width; x += 7) {
          final p = png.getPixel(x, y);
          final o = (y * small.width + x) * 4;
          for (final (a, b) in [
            (p.r.toInt(), small.rgba[o]),
            (p.g.toInt(), small.rgba[o + 1]),
            (p.b.toInt(), small.rgba[o + 2]),
          ]) {
            if ((a - b).abs() > maxDiff) maxDiff = (a - b).abs();
          }
        }
      }
      expect(maxDiff, 0, reason: 'PNG export is lossless');

      // The scaled export matches a preview-size render of the same settings (mean |Δ| ≤ 3/255).
      final big = img.Image.fromBytes(
        width: 6000,
        height: 4000,
        bytes: scene.data.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      final down = img.copyResize(
        big,
        width: 2048,
        height: 1365,
        interpolation: img.Interpolation.average,
      );
      final previewBuf = RgbaBuffer(
        2048,
        1365,
        down.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba),
      );
      final preview = await gpuRender(
        previewBuf,
        settings,
        aux: AuxMaps.compute(AuxMaps.proxy(scene)),
        assetId: 'big',
      );
      final d = diffStats(
        RgbaBuffer(small.width, small.height, small.rgba),
        preview,
      );
      expect(d.mean, lessThanOrEqualTo(3));

      aux.dispose();
      EngineImages.dispose(source);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
