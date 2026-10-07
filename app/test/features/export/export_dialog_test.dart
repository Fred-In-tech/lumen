import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen_core/lumen_core.dart';

Future<(MemorySettingsRepository, String)> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = MemoryCatalogRepository();
  final settings = MemorySettingsRepository();
  final im = img.Image(width: 16, height: 12);
  final r = await tester.runAsync(
    () => ImportService(repo).importOne(
      ImportFile(
        name: 'IMG_7.jpg',
        bytes: Uint8List.fromList(img.encodeJpg(im)),
      ),
    ),
  );
  final id = (r! as Imported).entry.assetId;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        presetRepositoryProvider.overrideWithValue(MemoryPresetRepository()),
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
      child: MaterialApp(
        theme: buildLumenTheme(),
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => showExportDialog(context, ref, [id]),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (settings, id);
}

void main() {
  testWidgets('presets, 16-bit hint for an 8-bit photo, save a preset', (
    tester,
  ) async {
    final (settings, _) = await _pump(tester);
    expect(find.text('Export photo'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);

    // Pick the print preset: TIFF 16-bit with the 8-bit note.
    await tester.tap(find.byKey(const ValueKey('export-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print TIFF 16-bit full size').last);
    await tester.pumpAndSettle();
    expect(
      find.text('This photo is 8-bit; 16-bit adds no detail.'),
      findsOneWidget,
    );
    expect(find.text('IMG_7_edit.tif', findRichText: true), findsNothing);
    expect(
      find.textContaining('IMG_7_edit.tif'),
      findsOneWidget,
      reason: 'name preview',
    );

    // Editing turns it into Custom; watermark on shows its controls.
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('export-naming')),
      '{date}_{name}',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long edge'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('export-size-value')),
      '3000',
    );
    await tester.tap(find.text('Megapixels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print, low'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top left'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('export-watermark-text')),
      '© Studio',
    );
    await tester.pumpAndSettle();

    // Save as a preset.
    await tester.tap(find.byTooltip('Save as preset'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('export-preset-name')),
      'Client',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = (await settings.load()).exportPresets.single;
    expect(saved.name, 'Client');
    expect(saved.format, ExportFileFormat.tiff16);
    expect(saved.naming, '{date}_{name}');
    expect(
      saved.size,
      const ExportSizeLimit.megapixels(3000 > 200 ? 200 : 3000),
    );
    expect(saved.sharpen, OutputSharpen.printLow);
    expect(saved.watermark!.text, '© Studio');
    expect(saved.watermark!.position, WatermarkPosition.topLeft);
    expect((await settings.load()).exportPresetId, saved.id);

    // Delete it again.
    await tester.tap(find.byTooltip('Delete preset'));
    await tester.pumpAndSettle();
    expect((await settings.load()).exportPresets, isEmpty);
    expect(find.text('Custom'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
