import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/masks/canvas/mask_canvas.dart';
import 'package:lumen/features/masks/canvas/mask_painter.dart';
import 'package:lumen/features/masks/canvas/mask_tint_layer.dart';
import 'package:lumen/features/masks/mask_ui_state.dart';
import 'package:lumen_core/lumen_core.dart';

import 'masks_harness.dart';

/// The canvas laid out over a [kSource]-sized frame (view = source pixels).
Widget _canvas({
  Geometry geometry = Geometry.none,
  MaskOverlayRenderer? overlay,
}) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox.fromSize(
    size: kSource,
    child: MaskCanvas(
      assetId: kAsset,
      mapping: CanvasMapping(
        geometry: geometry,
        source: kSource,
        view: kSource,
      ),
      overlayRenderer: overlay,
    ),
  ),
);

/// Global position of view point [p] on the canvas.
Offset _at(WidgetTester tester, Offset p) =>
    tester.getTopLeft(find.byType(MaskCanvas)) + p;

/// Records overlay requests (the tint itself is the engine's job).
class _RecordingOverlay implements MaskOverlayRenderer {
  final calls = <(int, MaskTint)>[];

  @override
  Future<ui.Image?> renderMaskOverlay(
    DevelopSettings settings,
    int index, {
    MaskTint tint = kDefaultMaskTint,
  }) async {
    calls.add((index, tint));
    return null;
  }
}

void main() {
  testWidgets('the tint follows the overlay toggle, hover and coverage', (
    tester,
  ) async {
    final c = await openEditor();
    final a = cmds(c).add(MaskKind.radial, sourceSize: kSource)!;
    final b = cmds(c).add(MaskKind.linear, sourceSize: kSource)!;
    final overlay = _RecordingOverlay();
    await pumpIn(tester, c, _canvas(overlay: overlay));
    // A new mask shows its overlay in the design's rose tint.
    expect(overlay.calls.single, (1, CanvasInk.maskTint));
    // Adjustments are uniforms: no re-render of the coverage.
    cmds(c).setAdjustment(b.id, P.exposure, 0.4);
    await tester.pumpAndSettle();
    expect(overlay.calls, hasLength(1));
    // A coverage change re-renders.
    cmds(c).setInvert(b.id, true);
    await tester.pumpAndSettle();
    expect(overlay.calls, hasLength(2));
    // O / the eye hides it …
    final notifier = c.read(maskUiProvider(kAsset).notifier);
    notifier.setShowOverlay(false);
    await tester.pumpAndSettle();
    expect(find.byType(MaskTintLayer), findsNothing);
    // … and hovering a row shows that mask's tint.
    notifier.setHover(a.id);
    await tester.pumpAndSettle();
    expect(find.byType(MaskTintLayer), findsOneWidget);
    expect(overlay.calls.last.$1, 0);
    await flushSave(tester);
  });

  testWidgets('dragging a linear endpoint reshapes it as one entry', (
    tester,
  ) async {
    final c = await openEditor();
    final m = cmds(c).add(MaskKind.linear, sourceSize: kSource)!;
    await pumpIn(tester, c, _canvas());
    final start = m.linear;
    final before = historyLength(c);
    final a = Offset(start.x0 * kSource.width, start.y0 * kSource.height);
    await tester.dragFrom(_at(tester, a), const Offset(40, 24));
    await tester.pumpAndSettle();
    final l = masksOf(c).single.linear;
    expect(l.x0, closeTo(start.x0 + 40 / kSource.width, 1e-6));
    expect(l.y0, closeTo(start.y0 + 24 / kSource.height, 1e-6));
    expect(l.x1, start.x1);
    expect(l.y1, start.y1);
    expect(historyLength(c), before + 1);
    expect(editor(c).history.entries.last.label, 'Shape Linear 1');
    await flushSave(tester);
  });

  testWidgets('dragging the linear centre pin moves the whole gradient', (
    tester,
  ) async {
    final c = await openEditor();
    final m = cmds(c).add(MaskKind.linear, sourceSize: kSource)!;
    await pumpIn(tester, c, _canvas());
    final s = m.linear;
    final mid = Offset(
      (s.x0 + s.x1) / 2 * kSource.width,
      (s.y0 + s.y1) / 2 * kSource.height,
    );
    await tester.dragFrom(_at(tester, mid), const Offset(-60, 30));
    await tester.pumpAndSettle();
    final l = masksOf(c).single.linear;
    expect(l.x0 - s.x0, closeTo(-60 / kSource.width, 1e-6));
    expect(l.x1 - s.x1, closeTo(-60 / kSource.width, 1e-6));
    expect(l.y1 - s.y1, closeTo(30 / kSource.height, 1e-6));
    expect(editor(c).history.entries.last.label, 'Move Linear 1');
    await flushSave(tester);
  });

  testWidgets('dragging the radial centre moves it as one entry', (
    tester,
  ) async {
    final c = await openEditor();
    cmds(c).add(MaskKind.radial, sourceSize: kSource);
    await pumpIn(tester, c, _canvas());
    final before = historyLength(c);
    await tester.dragFrom(
      _at(tester, const Offset(200, 150)),
      const Offset(-50, 30),
    );
    await tester.pumpAndSettle();
    final r = masksOf(c).single.radial;
    expect(r.cx, closeTo(0.5 - 50 / kSource.width, 1e-6));
    expect(r.cy, closeTo(0.5 + 30 / kSource.height, 1e-6));
    expect(historyLength(c), before + 1);
    expect(editor(c).history.entries.last.label, 'Move Radial 1');
    await flushSave(tester);
  });

  testWidgets('handles follow the geometry (rotated + flipped frame)', (
    tester,
  ) async {
    const g = Geometry(rotate90: 2, flipH: true);
    final c = await openEditor();
    final m = cmds(c).add(MaskKind.radial, sourceSize: kSource)!;
    // Move the centre in source space so it is off-centre on screen.
    cmds(c).update(
      m.id,
      (m) => m.copyWith(shape: {...m.shape, 'cx': 0.25, 'cy': 0.25}),
      label: 'setup',
    );
    await pumpIn(tester, c, _canvas(geometry: g));
    // Half turn + horizontal flip = vertical flip: (0.25, 0.25) → (0.25, 0.75).
    await tester.dragFrom(
      _at(tester, const Offset(100, 225)),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    final r = masksOf(c).single.radial;
    expect(r.cx, closeTo(0.25 + 40 / kSource.width, 1e-6));
    expect(r.cy, closeTo(0.25, 1e-6));
    await flushSave(tester);
  });

  testWidgets('a brush drag appends exactly one stroke', (tester) async {
    final c = await openEditor();
    final m = cmds(c).add(MaskKind.brush, sourceSize: kSource)!;
    await pumpIn(tester, c, _canvas());
    final before = historyLength(c);
    final g = await tester.startGesture(_at(tester, const Offset(80, 80)));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(12, 4));
      await tester.pump();
    }
    // The live stroke is vector only: nothing is committed mid-drag.
    expect(masksOf(c).single.strokes, isEmpty);
    await g.up();
    await tester.pumpAndSettle();
    final strokes = masksOf(c).single.strokes;
    expect(strokes, hasLength(1));
    expect(strokes.single.points.length, greaterThan(2));
    expect(strokes.single.radius, closeTo(maskUi(c).brush.radius, 1e-9));
    expect(strokes.single.erase, isFalse);
    expect(strokes.single.points.first.$1, closeTo(80 / kSource.width, 1e-6));
    expect(historyLength(c), before + 1);
    expect(editor(c).history.entries.last.label, 'Brush · ${m.name}');
    await flushSave(tester);
  });

  testWidgets('erase mode records an erase stroke', (tester) async {
    final c = await openEditor();
    cmds(c).add(MaskKind.brush, sourceSize: kSource);
    final notifier = c.read(maskUiProvider(kAsset).notifier);
    notifier.setBrush(maskUi(c).brush.copyWith(erase: true, size: 40));
    await pumpIn(tester, c, _canvas());
    await tester.dragFrom(
      _at(tester, const Offset(150, 150)),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    final s = masksOf(c).single.strokes.single;
    expect(s.erase, isTrue);
    expect(s.radius, closeTo(0.1, 1e-9));
    expect(editor(c).history.entries.last.label, startsWith('Erase'));
    await flushSave(tester);
  });

  testWidgets('tapping another mask pin selects it', (tester) async {
    final c = await openEditor();
    final linear = cmds(c).add(MaskKind.linear, sourceSize: kSource)!;
    // Park the gradient low on the left, clear of the radial's handles.
    const shape = LinearShape(x0: 0.2, y0: 0.8, x1: 0.2, y1: 0.95);
    cmds(c).update(
      linear.id,
      (m) => m.copyWith(shape: shape.toJson()),
      label: 'setup',
    );
    final radial = cmds(c).add(MaskKind.radial, sourceSize: kSource)!;
    expect(maskUi(c).selectedId, radial.id);
    await pumpIn(tester, c, _canvas());
    final pin = Offset(0.2 * kSource.width, 0.875 * kSource.height);
    await tester.tapAt(_at(tester, pin));
    await tester.pumpAndSettle();
    expect(maskUi(c).selectedId, linear.id);
    await flushSave(tester);
  });

  testWidgets('no edits without a selected mask', (tester) async {
    final c = await openEditor();
    final m = cmds(c).add(MaskKind.radial, sourceSize: kSource)!;
    c.read(maskUiProvider(kAsset).notifier).select(null);
    await pumpIn(tester, c, _canvas());
    final before = historyLength(c);
    // The radial's pin (its centre) only selects it.
    await tester.dragFrom(
      _at(tester, const Offset(10, 10)),
      const Offset(50, 50),
    );
    await tester.pumpAndSettle();
    expect(historyLength(c), before);
    expect(masksOf(c).single, m);
    await flushSave(tester);
  });
}
