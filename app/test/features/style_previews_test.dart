import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/features/editor/editor_session.dart';
import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('style previews render every AI style on the photo', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repo = MemoryCatalogRepository();
      final s = SyntheticScenes.build(
        SceneId.goldenHourPortrait,
        longEdge: 400,
      ).image;
      final jpg = img.encodeJpg(
        img.Image.fromBytes(
          width: s.width,
          height: s.height,
          bytes: s.data.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        ).convert(numChannels: 3),
      );
      final r = await ImportService(repo)
          .importOne(ImportFile(name: 'a.jpg', bytes: Uint8List.fromList(jpg)));
      final id = (r as Imported).entry.assetId;
      final session = EditorSession(
        assetId: id,
        renderer: CpuPhotoRenderer(),
        repo: repo,
      );
      await session.open();
      final previews = await session.stylePreviews(
        const LocalAutoEditProvider(),
        DevelopSettings.defaults,
      );
      expect(previews.keys.toSet(), AiStyle.values.toSet());
      expect(
        previews.values.toSet().length,
        AiStyle.values.length,
        reason: 'each style looks different',
      );
      session.dispose();
    });
  });
}
