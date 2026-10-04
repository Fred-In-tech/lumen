import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/gpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/retouch/support/synthetic_portrait.dart';
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
  late SynthPortrait p;
  setUpAll(() {
    p = renderSynthPortrait(320, 320, const [
      SynthFace(id: 'f', cx: 160, cy: 130, iod: 90),
    ]);
  });

  final reshape = DevelopSettings.defaults.copyWith(
    portrait: PortraitSettings.empty
        .withGroupValue(FaceGroup.all, PortraitIds.faceWidth, -80)
        .withGroupValue(FaceGroup.all, PortraitIds.eyeSize, 70),
    liquify: const [
      LiquifyStroke(
        tool: LiquifyTool.push,
        points: [(0.2, 0.85), (0.3, 0.85)],
        radius: 0.06,
        strength: 1,
      ),
    ],
  );

  Future<void> check(PhotoRenderer r, {required int tol}) async {
    await r.open(_png(p.image));
    expect(r is WarpSink, isTrue);
    (r as WarpSink).setWarpFaces(p.analysis);
    final plain = await _frame(r, DevelopSettings.defaults);
    // Shape sliders rebuild after the debounce; wait for that frame.
    await _frame(r, reshape);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final out = await _frame(r, reshape.withValue(P.exposure, 0.01));
    final cpu = renderReference(
      p.image,
      reshape.withValue(P.exposure, 0.01),
      faces: p.analysis,
    );
    final d = diffStats(out, cpu);
    expect(d.max, lessThanOrEqualTo(tol));
    expect(diffStats(out, plain).max, greaterThan(20));
    // Far corner: untouched.
    for (var c = 0; c < 3; c++) {
      expect((out.data[c] - plain.data[c]).abs(), lessThanOrEqualTo(1));
    }
  }

  testWidgets('CPU renderer warps with pushed faces and liquify', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final r = CpuPhotoRenderer(
        previewLongEdge: 320,
        interactiveLongEdge: 320,
      );
      addTearDown(r.dispose);
      await check(r, tol: 0);
    });
  });

  testWidgets('GPU renderer warps with pushed faces and liquify', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final r = GpuPhotoRenderer(assetId: 'w', previewLongEdge: 320);
      addTearDown(r.dispose);
      await check(r, tol: 3);
      expect(r.usingFallback, isFalse);
    });
  });
}
