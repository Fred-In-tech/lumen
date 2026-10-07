import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/engine/creative_lut_cache.dart';
import 'package:lumen/features/home/looks.dart';
import 'package:lumen/features/home/looks_page.dart';
import 'package:lumen/features/looks/look_details.dart';
import 'package:lumen/features/looks/look_import_flow.dart';
import 'package:lumen/features/looks/look_import_service.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen_core/lumen_core.dart';

import '../../support/look_files.dart';
import '../../support/project_fixtures.dart';

class _FakeLookSource implements LookImportSource {
  _FakeLookSource(this.files);
  final List<LookImportFile> files;
  int picks = 0;

  @override
  Future<List<LookImportFile>> pick() async {
    picks++;
    return files;
  }
}

Preset _imported(String id, String name, String group) => Preset(
  id: id,
  name: name,
  group: group,
  values: const {P.exposure: 0.3},
  source: PresetSource.lightroom,
  importReport: const PresetImportReport(
    fileName: 'pack.zip › x.xmp',
    applied: ['Exposure'],
    skipped: ['Calibration'],
  ),
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<Preset> presets = const [],
  _FakeLookSource? source,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = MemoryPresetRepository();
  for (final p in presets) {
    await repo.save(p);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...appOverrides(MemoryCatalogRepository(), presets: repo),
        lookImportSourceProvider.overrideWithValue(
          source ?? _FakeLookSource(const []),
        ),
      ],
      child: const LumenApp(),
    ),
  );
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(LumenApp)));
  c.read(shellLocationProvider.notifier).go(const LooksLocation());
  await tester.pumpAndSettle();
  return c;
}

void main() {
  tearDown(CreativeLuts.reset);

  testWidgets('Looks page: groups from zip folders, badges and sources', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(1440, 2400),
      presets: [
        _imported('a', 'Soft', 'Portraits'),
        _imported('b', 'Grain', 'Film'),
        Preset(
          id: 'c',
          name: 'Kodak 2383',
          group: 'LUTs',
          values: const {},
          lut: const LutRef(hash: '0123456789abcdef', name: 'Kodak 2383'),
          source: PresetSource.lut,
        ),
      ],
    );
    expect(find.byType(LooksPage), findsOneWidget);
    for (final g in ['Portraits', 'Film', 'LUTs', 'AI styles']) {
      expect(find.text(g), findsWidgets, reason: g);
    }
    expect(find.text('LUT: Kodak 2383'), findsOneWidget);
    expect(find.text('Imported LUT'), findsOneWidget);
    expect(find.text('Imported from Lightroom'), findsNWidgets(2));
    expect(find.text('LUT'), findsWidgets);
    expect(find.text('Preset'), findsWidgets);
    expect(find.text('Look'), findsWidgets);
    expect(find.text('Import presets & LUTs'), findsWidgets);
  });

  testWidgets('rename, details and delete an imported preset', (tester) async {
    final c = await _pump(tester, presets: [_imported('a', 'Soft', 'Pack')]);
    final card = find.ancestor(
      of: find.text('Soft'),
      matching: find.byType(LookCard),
    );
    await tester.tap(
      find.descendant(
        of: card,
        matching: find.bySemanticsLabel('More for Soft'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byType(LookDetails), findsOneWidget);
    expect(find.text('Calibration'), findsOneWidget);
    expect(find.text('pack.zip › x.xmp'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: card,
        matching: find.bySemanticsLabel('More for Soft'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Soft Skin');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    expect(find.text('Soft Skin'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('More for Soft Skin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Soft Skin'), findsNothing);
    expect(await c.read(userPresetsProvider.future), isEmpty);
  });

  testWidgets('import from the picker shows the summary', (tester) async {
    final source = _FakeLookSource(sampleLookFiles());
    final c = await _pump(tester, source: source);
    await tester.tap(find.text('Import presets & LUTs').first);
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (c.read(lastLookImportProvider) != null) break;
      }
    });
    await tester.pumpAndSettle();
    expect(source.picks, 1);
    expect(find.byType(LookImportSummary), findsOneWidget);
    expect(
      find.text('2 presets imported · 1 LUT imported · 1 file not imported'),
      findsOneWidget,
    );
    expect(
      find.textContaining('“Airy Wedding” have no equivalent'),
      findsOneWidget,
    );
    expect(find.textContaining('White balance (Kelvin'), findsOneWidget);
    expect(find.textContaining('notes.cube:'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Airy Wedding'), findsOneWidget);
    expect(find.text('LUT: Teal & Orange'), findsOneWidget);
    expect(find.text('Last import'), findsOneWidget);
  });
}
