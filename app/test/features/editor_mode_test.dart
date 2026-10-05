import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/develop/develop_panel.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_mode.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/editor/mode_switch.dart';
import 'package:lumen/features/portrait/portrait_panel.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/search/control_index.dart';
import 'package:lumen/features/search/open_control.dart';
import 'package:lumen_core/lumen_core.dart';

Future<ProviderContainer> _container() async {
  final repo = MemoryCatalogRepository();
  await repo.add(
    CatalogEntry(
      assetId: 'a',
      fileName: 'a.jpg',
      originalPath: 'originals/a.jpg',
      format: 'jpeg',
      width: 400,
      height: 300,
      bytes: 1,
      importedAt: DateTime.utc(2026),
    ),
    Uint8List(1),
  );
  final c = ProviderContainer(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(repo),
      portraitFacesStatusProvider('a').overrideWithValue(const AsyncData(null)),
    ],
  );
  await c.read(editorProvider('a').future);
  return c;
}

/// Pumps [child] with a [WidgetRef] handed to [onRef].
Future<void> _pump(
  WidgetTester tester,
  ProviderContainer c, {
  Widget? child,
  void Function(WidgetRef ref)? onRef,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: buildLumenTheme(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            followManualTools(ref, 'a');
            onRef?.call(ref);
            return child ?? const ModeSwitch(assetId: 'a');
          },
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the editor opens in Auto and the switch moves to Manual', (
    tester,
  ) async {
    final c = await _container();
    addTearDown(c.dispose);
    await _pump(tester, c);
    expect(c.read(editorModeProvider), EditorMode.auto);

    await tester.tap(find.bySemanticsLabel('Manual mode'));
    await tester.pump();
    expect(c.read(editorModeProvider), EditorMode.manual);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('going back to Auto puts the Manual tools away', (tester) async {
    final c = await _container();
    addTearDown(c.dispose);
    late WidgetRef ref;
    await _pump(tester, c, onRef: (r) => ref = r);
    selectManualTool(ref, 'a', ManualTool.masks);
    await tester.pump();
    // A canvas module is a Manual tool: the mode follows it.
    expect(c.read(editorModeProvider), EditorMode.manual);
    expect(c.read(manualToolProvider('a')), ManualTool.masks);

    selectManualTool(ref, 'a', ManualTool.crop);
    await tester.pump();
    expect(c.read(editorProvider('a')).value!.cropMode, isTrue);
    expect(c.read(manualToolProvider('a')), ManualTool.crop);

    selectManualTool(ref, 'a', ManualTool.presets);
    await tester.pump();
    expect(c.read(editorProvider('a')).value!.cropMode, isFalse);
    expect(c.read(manualToolProvider('a')), ManualTool.presets);

    await tester.tap(find.bySemanticsLabel('Auto mode'));
    await tester.pump();
    expect(c.read(editorModeProvider), EditorMode.auto);
    expect(c.read(editorModuleProvider('a')), EditorModule.adjust);
    expect(c.read(presetsOpenProvider('a')), isFalse);
    expect(c.read(manualToolProvider('a')), ManualTool.adjust);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('crop (the R key) moves the editor to Manual', (tester) async {
    final c = await _container();
    addTearDown(c.dispose);
    await _pump(tester, c);
    c.read(editorProvider('a').notifier).setCropMode(true);
    await tester.pump();
    expect(c.read(editorModeProvider), EditorMode.manual);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the tool tabs select every Manual tool', (tester) async {
    final c = await _container();
    addTearDown(c.dispose);
    await _pump(
      tester,
      c,
      child: const SizedBox(width: 320, child: ModuleTabs(assetId: 'a')),
    );
    for (final tool in ManualTool.values.reversed) {
      await tester.tap(find.text(tool.label));
      await tester.pump();
      expect(c.read(manualToolProvider('a')), tool);
    }
    await tester.pump(const Duration(seconds: 1));
  });

  test(
    'search opens Auto edit in Auto and everything else in Manual',
    () async {
      final c = await _container();
      addTearDown(c.dispose);
      final index = buildControlIndex();

      openControl(
        c.read,
        'a',
        index.firstWhere((e) => e.id == PortraitIds.teethBrightness),
      );
      expect(c.read(editorModeProvider), EditorMode.manual);
      expect(c.read(editorModuleProvider('a')), EditorModule.portrait);
      expect(c.read(portraitUiProvider('a')).category, PortraitCategory.face);

      openControl(c.read, 'a', index.firstWhere((e) => e.id == 'editSpots'));
      expect(c.read(portraitUiProvider('a')).category, PortraitCategory.skin);

      var ran = false;
      openControl(
        c.read,
        'a',
        index.firstWhere((e) => e.id == 'auto'),
        runAuto: () => ran = true,
      );
      expect(ran, isTrue);
      expect(c.read(editorModeProvider), EditorMode.auto);
    },
  );

  test('every portrait slider belongs to one part of the panel', () {
    for (final s in kPortraitSections) {
      for (final id in s.ids) {
        expect(categoryOfControl(id), s.category, reason: id);
      }
    }
    expect(categoryOfControl('autoRetouch'), isNull);
    // Each part shows at least one group.
    expect({
      for (final s in kPortraitSections) s.category,
    }, PortraitCategory.values.toSet());
  });
}
