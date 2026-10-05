import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/editor/canvas_mapping.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/liquify_canvas.dart';
import 'package:lumen/features/portrait/portrait_panel.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen/features/portrait/skin_pen_canvas.dart';
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

Future<void> _pump(WidgetTester tester, ProviderContainer c, Widget w) =>
    tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildLumenTheme(),
          home: Scaffold(body: w),
        ),
      ),
    );

final _mapping = CanvasMapping(
  geometry: Geometry.none,
  source: const Size(400, 300),
  view: const Size(400, 300),
);

DevelopSettings _settings(ProviderContainer c) =>
    c.read(editorProvider('a')).value!.settings;

void main() {
  testWidgets('a liquify drag is one Liquify history entry', (tester) async {
    final c = await _container();
    addTearDown(c.dispose);
    c
        .read(portraitUiProvider('a').notifier)
        .setLiquify(tool: LiquifyTool.bloat, radius: 0.1, strength: 0.7);
    await _pump(
      tester,
      c,
      Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: LiquifyCanvas(assetId: 'a', mapping: _mapping),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(LiquifyCanvas));
    await tester.dragFrom(
      origin + const Offset(200, 150),
      const Offset(80, 30),
    );
    await tester.pumpAndSettle();
    final s = _settings(c);
    expect(s.liquify, hasLength(1));
    final stroke = s.liquify.single;
    expect(stroke.tool, LiquifyTool.bloat);
    expect(stroke.radius, 0.1);
    expect(stroke.strength, 0.7);
    expect(stroke.points.length, greaterThan(1));
    final h = c.read(editorProvider('a')).value!.history;
    expect(h.entries.single.kind, HistoryKind.liquify);
    expect(h.entries.single.label, 'Liquify bloat');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('skin pen strokes record paint and erase', (tester) async {
    final c = await _container();
    addTearDown(c.dispose);
    await _pump(
      tester,
      c,
      Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: SkinPenCanvas(assetId: 'a', mapping: _mapping),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(SkinPenCanvas));
    await tester.dragFrom(origin + const Offset(100, 100), const Offset(60, 0));
    await tester.pumpAndSettle();
    c.read(portraitUiProvider('a').notifier).setPen(erase: true);
    await tester.pump();
    await tester.tapAt(origin + const Offset(300, 200));
    await tester.pumpAndSettle();
    final pen = _settings(c).portrait.skinPen;
    expect(pen, hasLength(2));
    expect(pen.first.erase, isFalse);
    expect(pen.first.points.length, greaterThan(1));
    expect(pen.last.erase, isTrue);
    expect(pen.last.points.single.$1, closeTo(300 / 400, 0.01));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('panel has shape/background sections; background reset works', (
    tester,
  ) async {
    final c = await _container();
    addTearDown(c.dispose);
    final s = _settings(c);
    c
        .read(editorProvider('a').notifier)
        .commit(
          s.copyWith(
            portrait: s.portrait.withImageValue(PortraitIds.bgClean, 60),
          ),
          label: 'Clean backdrop 60',
        );
    await _pump(
      tester,
      c,
      const SingleChildScrollView(child: PortraitPanel(assetId: 'a')),
    );
    await tester.pumpAndSettle();
    // Scene: the backdrop groups.
    await tester.tap(find.bySemanticsLabel('Scene tools'));
    await tester.pumpAndSettle();
    expect(find.text('Background'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Reset Background'));
    await tester.tap(find.byTooltip('Reset Background'));
    await tester.pumpAndSettle();
    expect(_settings(c).portrait.imageValue(PortraitIds.bgClean), 0);

    // Shape: face shape sliders and liquify.
    await tester.ensureVisible(find.bySemanticsLabel('Shape tools'));
    await tester.tap(find.bySemanticsLabel('Shape tools'));
    await tester.pumpAndSettle();
    expect(find.text('Face shape'), findsOneWidget);
    expect(find.text('Liquify'), findsOneWidget);

    // Tool toggles: the liquify button switches the canvas tool on and off.
    await tester.tap(find.text('Liquify'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Liquify brush'));
    await tester.tap(find.text('Liquify brush'));
    await tester.pump();
    expect(c.read(portraitUiProvider('a')).tool, PortraitCanvasTool.liquify);
    await tester.tap(find.text('Done').first);
    await tester.pump();
    expect(c.read(portraitUiProvider('a')).tool, PortraitCanvasTool.faces);
    await tester.pump(const Duration(seconds: 1));
  });
}
