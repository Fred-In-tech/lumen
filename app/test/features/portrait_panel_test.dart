import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_panel.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen_core/lumen_core.dart';

const _face = DetectedFace(
  id: 'f1',
  box: FaceBox(0.4, 0.2, 0.2, 0.3),
  group: FaceGroup.female,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  FaceAnalysis? faces,
}) async {
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
  final container = ProviderContainer(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(repo),
      portraitFacesProvider('a').overrideWithValue(faces),
    ],
  );
  addTearDown(container.dispose);
  await container.read(editorProvider('a').future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLumenTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(child: PortraitPanel(assetId: 'a')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Lets the editor's debounced auto-save run so no timer outlives the test.
Future<void> _flushSave(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 1));

PortraitSettings _portrait(ProviderContainer c) =>
    c.read(editorProvider('a')).value!.settings.portrait;

void main() {
  testWidgets('shows group tabs and the face status', (tester) async {
    await _pump(
      tester,
      faces: const FaceAnalysis(
        imageWidth: 10,
        imageHeight: 10,
        modelVersion: 't',
        faces: [_face],
      ),
    );
    for (final g in FaceGroup.values) {
      expect(find.text(g.label), findsOneWidget);
    }
    expect(find.textContaining('1 face'), findsOneWidget);
    expect(find.text('Individual'), findsNothing);
  });

  testWidgets('Auto Retouch is one undoable step for every face', (
    tester,
  ) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Auto Retouch'));
    await tester.pumpAndSettle();
    final p = _portrait(c);
    expect(p.valueFor(PortraitIds.skinSoftening, group: FaceGroup.male), 40);
    expect(p.valueFor(PortraitIds.skinSoftening, group: FaceGroup.child), 15);
    final state = c.read(editorProvider('a')).value!;
    expect(state.history.entries.single.label, 'Auto Retouch');
    c.read(editorProvider('a').notifier).undo();
    expect(_portrait(c).isDefault, isTrue);
    await _flushSave(tester);
  });

  testWidgets('a group tab edits that group only', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Female'));
    await tester.pumpAndSettle();
    expect(
      c.read(portraitUiProvider('a')).target,
      const PortraitTarget.group(FaceGroup.female),
    );
    // Commit a value through the controller path the slider uses.
    final s = c.read(editorProvider('a')).value!.settings;
    c
        .read(editorProvider('a').notifier)
        .commit(
          s.copyWith(
            portrait: withPortraitValue(
              s.portrait,
              PortraitIds.skinSoftening,
              c.read(portraitUiProvider('a')).target,
              55,
            ),
          ),
          label: 'Skin softening 55 · Female',
        );
    await tester.pumpAndSettle();
    final p = _portrait(c);
    expect(p.valueFor(PortraitIds.skinSoftening, group: FaceGroup.female), 55);
    expect(p.valueFor(PortraitIds.skinSoftening, group: FaceGroup.male), 0);
    // The Skin section shows the modified dot + reset; reset re-inherits All.
    await tester.tap(find.byTooltip('Reset Skin'));
    await tester.pumpAndSettle();
    expect(
      _portrait(c).groupOverrides(FaceGroup.female, PortraitIds.skinSoftening),
      isFalse,
    );
    await _flushSave(tester);
  });

  testWidgets('lower-lid protection appears only with under-eye work', (
    tester,
  ) async {
    final c = await _pump(tester);
    await tester.tap(find.text('Eyes'));
    await tester.pumpAndSettle();
    expect(find.text('Lower-lid protection'), findsNothing);
    final s = c.read(editorProvider('a')).value!.settings;
    c
        .read(editorProvider('a').notifier)
        .commit(
          s.copyWith(
            portrait: s.portrait.withGroupValue(
              FaceGroup.all,
              PortraitIds.eyeBags,
              30,
            ),
          ),
          label: 'Eye bags 30',
        );
    await tester.pumpAndSettle();
    expect(find.text('Lower-lid protection'), findsOneWidget);
    await _flushSave(tester);
  });

  testWidgets('selecting a face opens the Individual tab for that person', (
    tester,
  ) async {
    final c = await _pump(
      tester,
      faces: const FaceAnalysis(
        imageWidth: 10,
        imageHeight: 10,
        modelVersion: 't',
        faces: [_face],
      ),
    );
    c.read(portraitUiProvider('a').notifier).selectFace(_face);
    await tester.pumpAndSettle();
    expect(find.text('Individual'), findsOneWidget);
    final target = c.read(portraitUiProvider('a')).target;
    expect(target.isPerson, isTrue);
    expect(target.group, FaceGroup.female);
  });
}
