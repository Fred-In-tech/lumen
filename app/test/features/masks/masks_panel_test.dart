import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/masks/mask_kinds.dart';
import 'package:lumen/features/masks/masks_panel.dart';
import 'package:lumen/widgets/lumen_slider.dart';
import 'package:lumen_core/lumen_core.dart';

import 'masks_harness.dart';

Widget _panel() => const Align(
  alignment: Alignment.topLeft,
  child: SizedBox(
    width: 320,
    child: SingleChildScrollView(
      child: MasksPanel(assetId: kAsset, sourceSize: kSource),
    ),
  ),
);

Future<void> _addFromMenu(WidgetTester tester, String label) async {
  await tester.tap(find.text('Add mask'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// The track of the [label] slider (its CustomPaint).
Finder _track(String label) => find
    .descendant(
      of: find.widgetWithText(LumenSlider, label),
      matching: find.byType(CustomPaint),
    )
    .last;

class _FakeAiSource implements AiMaskSource {
  @override
  bool supports(MaskKind kind) => kind == MaskKind.subject;

  @override
  Future<AiShape> segment(String assetId, MaskKind kind) async => const AiShape(
    maskRef: 'masks/subject.png',
    model: 'fake',
    modelVersion: '1',
  );
}

void main() {
  testWidgets('the empty state explains masks in one line', (tester) async {
    final c = await openEditor();
    await pumpIn(tester, c, _panel());
    expect(find.text(MasksPanel.emptyHint), findsOneWidget);
    expect(find.text('0/8'), findsOneWidget);
  });

  testWidgets('adds each manual kind from the menu, one entry each', (
    tester,
  ) async {
    final c = await openEditor();
    await pumpIn(tester, c, _panel());
    await _addFromMenu(tester, 'Linear gradient');
    await _addFromMenu(tester, 'Radial gradient');
    await _addFromMenu(tester, 'Brush');
    final masks = masksOf(c);
    expect(masks.map((m) => m.kind), [
      MaskKind.linear,
      MaskKind.radial,
      MaskKind.brush,
    ]);
    expect(masks.map((m) => m.name), ['Linear 1', 'Radial 1', 'Brush 1']);
    expect(editor(c).history.entries.map((e) => e.label), [
      'Add Linear gradient',
      'Add Radial gradient',
      'Add Brush',
    ]);
    // The new mask is selected and shows its controls.
    expect(maskUi(c).selectedId, masks.last.id);
    expect(find.text('Editing: Brush 1'), findsOneWidget);
    expect(find.text('Paint'), findsOneWidget);
    // Gradients start inside the visible frame.
    final l = masks.first.linear;
    expect(l.y0, lessThan(l.y1));
    final r = masks[1].radial;
    expect(r.cx, closeTo(0.5, 1e-6));
    expect(r.cy, closeTo(0.5, 1e-6));
    await flushSave(tester);
  });

  testWidgets('renames a mask inline (double-click)', (tester) async {
    final c = await openEditor();
    cmds(c).add(MaskKind.linear, sourceSize: kSource);
    await pumpIn(tester, c, _panel());
    await tester.tap(find.text('Linear 1'));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('Linear 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Sky fade ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(masksOf(c).single.name, 'Sky fade');
    expect(editor(c).history.entries.last.label, 'Rename Linear 1');
    expect(find.text('Sky fade'), findsOneWidget);
    await flushSave(tester);
  });

  testWidgets('invert is one undoable step', (tester) async {
    final c = await openEditor();
    cmds(c).add(MaskKind.radial, sourceSize: kSource);
    await pumpIn(tester, c, _panel());
    await tester.tap(find.byTooltip('Invert'));
    await tester.pumpAndSettle();
    expect(masksOf(c).single.invert, isTrue);
    expect(historyLength(c), 2);
    c.read(editorProvider(kAsset).notifier).undo();
    expect(masksOf(c).single.invert, isFalse);
    await flushSave(tester);
  });

  testWidgets('dragging opacity is one history entry', (tester) async {
    final c = await openEditor();
    cmds(c).add(MaskKind.linear, sourceSize: kSource);
    await pumpIn(tester, c, _panel());
    await tester.drag(_track('Opacity'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    final opacity = masksOf(c).single.opacity;
    expect(opacity, lessThan(1));
    expect(historyLength(c), 2);
    expect(
      editor(c).history.entries.last.label,
      'Linear 1 · Opacity ${(opacity * 100).round()}%',
    );
    await flushSave(tester);
  });

  testWidgets('delete removes the mask and Undo brings it back', (
    tester,
  ) async {
    final c = await openEditor();
    final mask = cmds(c).add(MaskKind.linear, sourceSize: kSource)!;
    await pumpIn(tester, c, _panel());
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(masksOf(c), isEmpty);
    expect(maskUi(c).selectedId, isNull);
    expect(find.text('Deleted Linear 1.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(masksOf(c).single, mask);
    await flushSave(tester);
  });

  testWidgets('duplicate copies the mask after itself and selects it', (
    tester,
  ) async {
    final c = await openEditor();
    final m = cmds(c).add(MaskKind.radial, sourceSize: kSource)!;
    cmds(c).setAdjustment(m.id, P.exposure, 0.5);
    await pumpIn(tester, c, _panel());
    await tester.tap(find.byTooltip('Duplicate'));
    await tester.pumpAndSettle();
    final masks = masksOf(c);
    expect(masks.map((m) => m.name), ['Radial 1', 'Radial 1 copy']);
    expect(
      masks.last.adjustments,
      m.withAdjustment(P.exposure, 0.5).adjustments,
    );
    expect(masks.last.id, isNot(m.id));
    expect(maskUi(c).selectedId, masks.last.id);
    await flushSave(tester);
  });

  testWidgets('stops at 8 masks', (tester) async {
    final c = await openEditor();
    for (var i = 0; i < LocalMask.maxMasks; i++) {
      cmds(c).add(MaskKind.radial, sourceSize: kSource);
    }
    expect(cmds(c).add(MaskKind.linear, sourceSize: kSource), isNull);
    await pumpIn(tester, c, _panel());
    expect(find.text('8/8'), findsOneWidget);
    await tester.tap(find.text('Add mask'));
    await tester.pumpAndSettle();
    expect(find.text('Linear gradient'), findsNothing);
    expect(masksOf(c), hasLength(LocalMask.maxMasks));
    // Duplicate is disabled too.
    await tester.tap(find.byTooltip('Duplicate').first);
    await tester.pumpAndSettle();
    expect(masksOf(c), hasLength(LocalMask.maxMasks));
    await flushSave(tester);
  });

  testWidgets('AI entries stay disabled until the on-device model ships', (
    tester,
  ) async {
    final c = await openEditor();
    await pumpIn(tester, c, _panel());
    await tester.tap(find.text('Add mask'));
    await tester.pumpAndSettle();
    expect(
      find.text(kAiMaskUnavailableHint),
      findsNWidgets(kAiMaskKinds.length),
    );
    for (final k in kAiMaskKinds) {
      final item = tester.widget<PopupMenuItem<MaskKind>>(
        find.ancestor(
          of: find.text(k.menuLabel),
          matching: find.byType(PopupMenuItem<MaskKind>),
        ),
      );
      expect(item.enabled, isFalse, reason: k.name);
    }
    await tester.tap(find.text(MaskKind.subject.menuLabel), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(masksOf(c), isEmpty);
  });

  testWidgets('a supported AI kind adds a mask from the seam', (tester) async {
    final c = await openEditor(
      overrides: [aiMaskSourceProvider.overrideWithValue(_FakeAiSource())],
    );
    await pumpIn(tester, c, _panel());
    await _addFromMenu(tester, MaskKind.subject.menuLabel);
    final m = masksOf(c).single;
    expect(m.kind, MaskKind.subject);
    expect(m.ai.maskRef, 'masks/subject.png');
    await flushSave(tester);
  });

  testWidgets('a local slider drag is one entry on the mask only', (
    tester,
  ) async {
    final c = await openEditor();
    cmds(c).add(MaskKind.linear, sourceSize: kSource);
    await pumpIn(tester, c, _panel());
    final gesture = await tester.startGesture(
      tester.getCenter(_track('Exposure')),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final m = masksOf(c).single;
    expect(m.adjustments[P.exposure], greaterThan(0));
    expect(editor(c).settings.value(P.exposure), 0);
    expect(historyLength(c), 2);
    expect(
      editor(c).history.entries.last.label,
      startsWith('Linear 1 · Exposure +'),
    );
    // The per-mask reset clears it in one step.
    await tester.tap(find.byTooltip('Reset Adjustments'));
    await tester.pumpAndSettle();
    expect(masksOf(c).single.adjustments, isEmpty);
    expect(historyLength(c), 3);
    await flushSave(tester);
  });

  test('the local slider groups cover the 12 local params exactly', () {
    final ids = [for (final g in kLocalSliderGroups) ...g.ids];
    expect(ids.toSet(), kLocalParams.toSet());
    expect(ids, hasLength(kLocalParams.length));
  });
}
