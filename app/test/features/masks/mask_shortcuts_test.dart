import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
import 'package:lumen/features/masks/mask_shortcuts.dart';
import 'package:lumen_core/lumen_core.dart';

import 'masks_harness.dart';

void main() {
  test('M opens the Masks module and leaves crop mode', () async {
    final c = await openEditor();
    c.read(editorProvider(kAsset).notifier).setCropMode(true);
    final r = handleMaskShortcut(c.read, kAsset, LogicalKeyboardKey.keyM);
    expect(r, KeyEventResult.handled);
    expect(c.read(editorModuleProvider(kAsset)), EditorModule.masks);
    expect(editor(c).cropMode, isFalse);
  });

  test('O toggles the overlay only in the Masks module', () async {
    final c = await openEditor();
    expect(
      handleMaskShortcut(c.read, kAsset, LogicalKeyboardKey.keyO),
      KeyEventResult.ignored,
    );
    c.read(editorModuleProvider(kAsset).notifier).select(EditorModule.masks);
    final before = maskUi(c).showOverlay;
    handleMaskShortcut(c.read, kAsset, LogicalKeyboardKey.keyO);
    expect(maskUi(c).showOverlay, !before);
  });

  test('Delete removes the selected mask as one undoable step', () async {
    final c = await openEditor();
    c.read(editorModuleProvider(kAsset).notifier).select(EditorModule.masks);
    final a = cmds(c).add(MaskKind.linear, sourceSize: kSource)!;
    final b = cmds(c).add(MaskKind.radial, sourceSize: kSource)!;
    final r = handleMaskShortcut(c.read, kAsset, LogicalKeyboardKey.delete);
    expect(r, KeyEventResult.handled);
    expect(masksOf(c).map((m) => m.id), [a.id]);
    // The selection moves to the neighbour.
    expect(maskUi(c).selectedId, a.id);
    c.read(editorProvider(kAsset).notifier).undo();
    expect(masksOf(c).map((m) => m.id), [a.id, b.id]);
  });

  test('Delete with nothing selected falls through', () async {
    final c = await openEditor();
    c.read(editorModuleProvider(kAsset).notifier).select(EditorModule.masks);
    expect(
      handleMaskShortcut(c.read, kAsset, LogicalKeyboardKey.backspace),
      KeyEventResult.ignored,
    );
  });
}
