import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/ai/auto_retouch.dart';
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
  AsyncValue<FaceAnalysis?>? status,
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
      portraitFacesStatusProvider('a')
          .overrideWithValue(status ?? AsyncData(faces)),
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

  testWidgets('Auto Retouch works again after Reset all, and after a slider '
      'is dragged back to 0 (a reset is not a hand edit)', (tester) async {
    final c = await _pump(tester);
    final ctl = c.read(editorProvider('a').notifier);
    await tester.tap(find.text('Auto Retouch'));
    await tester.pumpAndSettle();
    final auto = _portrait(c);
    expect(auto.hasFaceEdits, isTrue);
    // Hand edits (slider entries), then Reset all.
    final s = c.read(editorProvider('a')).value!.settings;
    ctl.commit(
      s.copyWith(
        portrait: auto
            .withGroupValue(FaceGroup.all, PortraitIds.skinSoftening, 80)
            .withGroupValue(FaceGroup.all, PortraitIds.skinShine, 0),
      ),
      label: 'by hand',
    );
    ctl.resetAll();
    expect(_portrait(c).isDefault, isTrue);
    await tester.tap(find.text('Auto Retouch'));
    await tester.pumpAndSettle();
    expect(_portrait(c), auto, reason: 'every value set again');
    expect(find.textContaining('Auto Retouch applied'), findsOneWidget);
    // Zero everything by hand (slider-kind entry): still not locked.
    ctl.commit(
      c
          .read(editorProvider('a'))
          .value!
          .settings
          .copyWith(portrait: PortraitSettings.empty),
      label: 'zeroed by hand',
    );
    await tester.tap(find.text('Auto Retouch'));
    await tester.pumpAndSettle();
    expect(
      _portrait(c).groupValue(FaceGroup.all, PortraitIds.skinSoftening),
      auto.groupValue(FaceGroup.all, PortraitIds.skinSoftening),
    );
    await _flushSave(tester);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Auto Retouch never looks dead: it says when it changes '
      'nothing, keeps hand-set values, or finds no faces', (tester) async {
    final c = await _pump(tester);
    final ctl = c.read(editorProvider('a').notifier);
    await tester.tap(find.text('Auto Retouch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto Retouch'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already applied'), findsOneWidget);
    expect(c.read(editorProvider('a')).value!.history.entries, hasLength(1));
    // A hand-set value stays, and the toast says so.
    final s = c.read(editorProvider('a')).value!.settings;
    ctl.commit(
      s.copyWith(
        portrait: s.portrait.withGroupValue(
          FaceGroup.all,
          PortraitIds.skinSoftening,
          77,
        ),
      ),
      label: 'Skin softening 77',
    );
    await tester.tap(find.text('Auto Retouch'));
    await tester.pumpAndSettle();
    expect(
      _portrait(c).groupValue(FaceGroup.all, PortraitIds.skinSoftening),
      77,
    );
    expect(find.textContaining('set by hand'), findsOneWidget);
    await _flushSave(tester);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Auto Retouch on a photo without faces says so', (tester) async {
    final c = await _pump(
      tester,
      faces: const FaceAnalysis(
        imageWidth: 10,
        imageHeight: 10,
        modelVersion: 't',
      ),
    );
    await tester.tap(find.text('Auto Retouch'));
    await tester.pumpAndSettle();
    expect(find.text(kNoFacesToRetouch), findsOneWidget);
    expect(_portrait(c).isDefault, isTrue);
    expect(c.read(editorProvider('a')).value!.history.entries, isEmpty);
    await tester.pump(const Duration(seconds: 5));
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
    await tester.tap(find.bySemanticsLabel('Face tools'));
    await tester.pumpAndSettle();
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

  testWidgets('face status reports detecting and unavailable honestly', (
    tester,
  ) async {
    await _pump(tester, status: const AsyncLoading());
    expect(find.text('Detecting faces…'), findsOneWidget);
    await _pump(
      tester,
      status: AsyncError(StateError('no runtime'), StackTrace.empty),
    );
    expect(find.textContaining('isn’t available here'), findsOneWidget);
  });

  testWidgets('the selected face shows a Tag as row with its group', (
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
    expect(find.text('Tag as'), findsNothing);
    c.read(portraitUiProvider('a').notifier).selectFace(_face);
    await tester.pumpAndSettle();
    expect(find.text('Tag as'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });
}
