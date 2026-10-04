import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/retouch_textures.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen_core/lumen_core.dart';

import '../support/test_images.dart';
import 'retouch_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a pen edit re-uploads only the region atlases, without leaks',
    () async {
      final one = onePortrait();
      final base = one.maps;
      final face = one.p.faces.single;
      final a = face.toPx(-0.2, 1.6), b = face.toPx(0.2, 1.6);
      final w = one.p.image.width, h = one.p.image.height;
      final pen = applySkinPen(base, [
        BrushStroke(
          points: [(a.x / w, a.y / h), (b.x / w, b.y / h)],
          radius: 0.03,
          erase: true,
        ),
      ]);
      expect(identical(pen, base), isFalse);

      final cache = RetouchMapsCache();
      final first = (await cache.obtain(base))!;
      final second = (await cache.obtain(pen))!;
      for (final i in [0, 1, 2, 3, 6]) {
        expect(
          identical(second.images[i], first.images[i]),
          isTrue,
          reason: 'slot $i reused',
        );
      }
      for (final i in [4, 5]) {
        expect(
          identical(second.images[i], first.images[i]),
          isFalse,
          reason: 'slot $i uploaded',
        );
      }
      // The old textures are released after the swap; shared images survive.
      await Future<void>.delayed(Duration.zero);
      final u = RetouchUniforms.fromSettings(
        portraitOf({PortraitIds.skinSoftening: 80}),
        one.p.analysis,
      );
      final cpu = applyRetouch(one.p.image, pen, u);
      // Render with the cache's textures (half of them re-used).
      final source = await imageFromBuffer(one.p.image);
      final out = runRetouchPass(
        await ShaderLibrary.load(),
        source: source,
        textures: second,
        uniforms: u,
      )!;
      final gpu = await bufferFromImage(out);
      EngineImages.dispose(out);
      EngineImages.dispose(source);
      expect(diffStats(gpu, cpu).max, lessThanOrEqualTo(1));
      cache.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(EngineImages.live, 0);
    },
  );
}
