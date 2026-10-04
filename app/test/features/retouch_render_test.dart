import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/portrait/retouch_inputs.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../../packages/lumen_core/test/retouch/support/synthetic_portrait.dart';

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

/// Renders [s] and waits for the new frame (not the previous one).
Future<RgbaBuffer> _frame(CpuPhotoRenderer r, DevelopSettings s) async {
  final previous = r.output.value;
  r.update(s);
  for (var i = 0; i < 400; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final out = r.output.value;
    if (out != null && !identical(out, previous)) return rgbaFromImage(out);
  }
  throw StateError('no frame');
}

void main() {
  testWidgets('the CPU renderer applies portrait retouch from pushed maps', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final portrait = renderSynthPortrait(320, 320, const [
        SynthFace(id: 'f', cx: 160, cy: 130, iod: 90),
      ]);
      final r = CpuPhotoRenderer(previewLongEdge: 320);
      addTearDown(r.dispose);
      await r.open(_png(portrait.image));
      final plain = await _frame(r, DevelopSettings.defaults);

      final maps = computeRetouchMaps(portrait.image, portrait.analysis);
      r.setRetouch(maps, portrait.analysis);
      final retouch = DevelopSettings.defaults.copyWith(
        portrait: PortraitSettings.empty
            .withGroupValue(FaceGroup.all, PortraitIds.skinSoftening, 100)
            .withGroupValue(FaceGroup.all, PortraitIds.acne, 100),
      );
      // Let the re-render triggered by setRetouch land first.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final out = await _frame(r, retouch);

      var changed = 0, outsideChanged = 0;
      for (var y = 0; y < 320; y++) {
        for (var x = 0; x < 320; x++) {
          final i = (y * 320 + x) * 4;
          final d =
              (out.data[i] - plain.data[i]).abs() +
              (out.data[i + 1] - plain.data[i + 1]).abs() +
              (out.data[i + 2] - plain.data[i + 2]).abs();
          if (d == 0) continue;
          // The synthetic face spans roughly ±1.7 IOD around its centre.
          final inFace = (x - 160).abs() < 160 && y > 10 && y < 320;
          if (inFace) {
            changed++;
          } else {
            outsideChanged++;
          }
        }
      }
      expect(changed, greaterThan(500));
      expect(outsideChanged, 0);

      // Clearing the maps turns retouch off again.
      r.setRetouch(null, null);
      final cleared = await _frame(r, retouch);
      expect(cleared.data, plain.data);
    });
  });

  test(
    'retouch inputs stay idle until there are edits or Portrait opens',
    () async {
      final repo = MemoryCatalogRepository();
      await repo.add(
        CatalogEntry(
          assetId: 'a',
          fileName: 'a.jpg',
          originalPath: 'originals/a.jpg',
          format: 'jpeg',
          width: 10,
          height: 10,
          bytes: 1,
          importedAt: DateTime.utc(2026),
        ),
        Uint8List(1),
      );
      var builds = 0;
      final c = ProviderContainer(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          retouchMapsBuildProvider('a').overrideWith((ref) async {
            builds++;
            return null;
          }),
        ],
      );
      addTearDown(c.dispose);
      await c.read(editorProvider('a').future);
      expect(
        c.read(retouchInputsProvider('a')),
        const AsyncData<RetouchInputs?>(null),
      );
      expect(builds, 0);
      c.read(editorModuleProvider('a').notifier).select(EditorModule.portrait);
      c.read(retouchInputsProvider('a'));
      await Future<void>.delayed(Duration.zero);
      expect(builds, 1);
    },
  );
}
