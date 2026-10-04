import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/backdrop/support/backdrop_scene.dart';
import '../support/test_images.dart';

Uint8List _png(RgbaBuffer b) => Uint8List.fromList(
  img.encodePng(
    img.Image.fromBytes(
      width: b.width,
      height: b.height,
      bytes: b.data.buffer,
      numChannels: 4,
    ),
  ),
);

/// Renders [s] and waits for a frame other than the previous one.
Future<RgbaBuffer> _frame(PhotoRenderer r, DevelopSettings s) async {
  final previous = r.output.value;
  r.update(s);
  for (var i = 0; i < 500; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final out = r.output.value;
    if (out != null && !identical(out, previous)) return rgbaFromImage(out);
  }
  throw StateError('no frame');
}

void main() {
  final scene = SwapScene.make();
  const blue = BackdropChange(mode: BackdropMode.color, color: 0xFF2050C0);
  final swapped = DevelopSettings.defaults
      .withValues({P.exposure: 0.2})
      .copyWith(backdrop: blue);

  Future<void> check(PhotoRenderer r, {required int tol}) async {
    await r.open(_png(scene.image));
    expect(r is BackdropSink, isTrue);
    // Without a subject raster the backdrop stays off.
    final noSubject = await _frame(r, swapped);
    final plain = renderReference(scene.image, swapped);
    expect(diffStats(noSubject, plain).max, lessThanOrEqualTo(tol));
    (r as BackdropSink).setBackdropInputs(people: scene.people);
    // The matte builds off the UI isolate; wait, then take a fresh frame.
    await _frame(r, swapped.withValue(P.exposure, 0.21));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final out = await _frame(r, swapped);
    final cpu = renderReference(
      backdroppedSource(scene.image, blue, people: scene.people),
      swapped,
    );
    expect(diffStats(out, cpu).max, lessThanOrEqualTo(tol));
    // The far background is the new colour, the subject centre is kept.
    final bg = (out.r(4, 4), out.g(4, 4), out.b(4, 4));
    expect(bg.$3, greaterThan(bg.$2));
    final c = (scene.cx.floor(), scene.cy.floor());
    expect(
      (out.r(c.$1, c.$2) - plain.r(c.$1, c.$2)).abs(),
      lessThanOrEqualTo(tol),
    );
  }

  testWidgets('CPU renderer composites the backdrop', (tester) async {
    await tester.runAsync(() async {
      final r = CpuPhotoRenderer(
        previewLongEdge: 320,
        interactiveLongEdge: 320,
      );
      addTearDown(r.dispose);
      await check(r, tol: 0);
    });
  });

  testWidgets('GPU renderer composites the backdrop', (tester) async {
    await tester.runAsync(() async {
      final r = GpuPhotoRenderer(assetId: 'b', previewLongEdge: 320);
      addTearDown(r.dispose);
      await check(r, tol: 3);
      expect(r.usingFallback, isFalse);
      final exact = await r.backdropAssetsFor(blue.copyWith(feather: 10));
      expect(exact!.fits(blue.copyWith(feather: 10), null), isTrue);
    });
  });
}
