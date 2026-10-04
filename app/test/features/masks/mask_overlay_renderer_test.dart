import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/masks/canvas/mask_painter.dart';
import 'package:lumen_core/lumen_core.dart';

Uint8List _jpeg(int w, int h) => Uint8List.fromList(
  img.encodeJpg(
    img.Image(width: w, height: h)..clear(img.ColorRgb8(90, 90, 90)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the CPU fallback renders the overlay tint in frame geometry', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final r = CpuPhotoRenderer();
      expect(r, isA<MaskOverlayRenderer>());
      final circle = LocalMask(
        id: 'm',
        name: 'Radial 1',
        kind: MaskKind.radial,
        shape: const RadialShape(rx: 0.2, ry: 0.3, feather: 0).toJson(),
      );
      final settings = DevelopSettings.defaults.copyWith(
        masks: [circle],
        geometry: const Geometry(rotate90: 1),
      );
      expect(
        await r.renderMaskOverlay(settings, 0),
        isNull,
        reason: 'not open',
      );
      await r.open(_jpeg(300, 200));
      final image = (await r.renderMaskOverlay(
        settings,
        0,
        tint: CanvasInk.maskTint,
      ))!;
      // A quarter turn swaps the frame's axes.
      expect((image.width, image.height), (200, 300));
      final px = await rgbaFromImage(image);
      int alpha(int x, int y) => px.data[px.offset(x, y) + 3];
      expect(alpha(100, 150), closeTo(CanvasInk.maskOverlayAlpha * 255, 2));
      expect(alpha(2, 2), 0);
      expect(await r.renderMaskOverlay(settings, 3), isNull);
      image.dispose();
      r.dispose();
    });
  });
}
