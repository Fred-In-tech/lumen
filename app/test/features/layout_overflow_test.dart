import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/export/export_dialog.dart';

List<Override> _overrides() => [
  catalogRepositoryProvider.overrideWithValue(MemoryCatalogRepository()),
  presetRepositoryProvider.overrideWithValue(MemoryPresetRepository()),
  settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()),
];

void main() {
  for (final size in const [Size(375, 812), Size(768, 1024), Size(1440, 900)]) {
    testWidgets(
      'no overflow at ${size.width.toInt()}×${size.height.toInt()}: library + export dialog',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(overrides: _overrides(), child: const LumenApp()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          ProviderScope(
            overrides: _overrides(),
            child: MaterialApp(
              theme: buildLumenTheme(),
              home: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () =>
                          showExportDialog(context, ref, ['a', 'b']),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Export 2 photos'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
