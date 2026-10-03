// DoD 30 (drag-and-drop, macOS): simulates the native desktop_drop messages
// (entered → updated → performOperation_macos) the way AppKit delivers them,
// for a single file and for a folder, and checks they land in the library.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';

Uint8List _jpeg(int seed) {
  final im = img.Image(width: 64, height: 48);
  for (var y = 0; y < 48; y++) {
    for (var x = 0; x < 64; x++) {
      im.setPixelRgb(x, y, (x * 4 + seed) % 256, y * 5 % 256, seed % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im));
}

Future<void> _native(String method, Object? args) async {
  final data = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, args),
  );
  ui.channelBuffers.push('desktop_drop', data, (_) {});
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dropping a file and a folder imports their photos', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('lumen_drop');
    final single = File('${dir.path}/single.jpg')..writeAsBytesSync(_jpeg(1));
    final folder = Directory('${dir.path}/shoot')..createSync();
    File('${folder.path}/a.jpg').writeAsBytesSync(_jpeg(2));
    File('${folder.path}/b.jpg').writeAsBytesSync(_jpeg(3));
    File('${folder.path}/notes.txt').writeAsStringSync('ignore me');
    Directory('${folder.path}/sub').createSync();
    File('${folder.path}/sub/c.jpg').writeAsBytesSync(_jpeg(4));

    final repo = MemoryCatalogRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repo),
          presetRepositoryProvider.overrideWithValue(MemoryPresetRepository()),
          settingsRepositoryProvider.overrideWithValue(
            MemorySettingsRepository(),
          ),
        ],
        child: const LumenApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LumenApp)),
    );

    Future<void> drop(List<Map<String, Object?>> items) async {
      await tester.runAsync(() async {
        await _native('entered', [400.0, 400.0]);
        await _native('updated', [410.0, 410.0]);
        await _native('performOperation_macos', items);
      });
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(end)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if ((container.read(libraryProvider).value?.length ?? 0) >=
            expectedCount) {
          break;
        }
      }
    }

    expectedCount = 1;
    await drop([
      {'path': single.path, 'isDirectory': false},
    ]);
    expect(container.read(libraryProvider).value!.map((e) => e.fileName), [
      'single.jpg',
    ]);

    expectedCount = 4;
    await drop([
      {'path': folder.path, 'isDirectory': true},
    ]);
    final names = container
        .read(libraryProvider)
        .value!
        .map((e) => e.fileName)
        .toSet();
    expect(names, {'single.jpg', 'a.jpg', 'b.jpg', 'c.jpg'});
    dir.deleteSync(recursive: true);
  });
}

int expectedCount = 0;
