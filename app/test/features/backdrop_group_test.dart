import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_tools.dart';
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
    overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
  );
  await c.read(editorProvider('a').future);
  return c;
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildLumenTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(child: BackgroundSwapGroup(assetId: 'a')),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Background swap')); // open the group
  await tester.pumpAndSettle();
}

BackdropChange _backdrop(ProviderContainer c) =>
    c.read(editorProvider('a')).value!.settings.backdrop;

void main() {
  testWidgets('mode, colour and reset are backdrop history entries', (
    tester,
  ) async {
    final c = await _container();
    addTearDown(c.dispose);
    await _pump(tester, c);
    expect(find.text('Image'), findsNothing); // no stored image yet
    await tester.tap(find.text('Colour'));
    await tester.pumpAndSettle();
    expect(_backdrop(c).mode, BackdropMode.color);
    await tester.tap(find.bySemanticsLabel('#2050c0'));
    await tester.pumpAndSettle();
    expect(_backdrop(c).color, 0xFF2050C0);
    expect(find.text('Remove spill'), findsOneWidget);
    await tester.tap(find.text('Gradient'));
    await tester.pumpAndSettle();
    expect(find.text('Angle'), findsOneWidget);
    final h = c.read(editorProvider('a')).value!.history.entries;
    expect(h.map((e) => e.kind).toSet(), {HistoryKind.backdrop});
    expect(h.first.label, 'Background Colour');
    await tester.tap(find.byTooltip('Reset Background swap'));
    await tester.pumpAndSettle();
    expect(_backdrop(c), BackdropChange.none);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('image mode is offered once an image is stored', (tester) async {
    final c = await _container();
    addTearDown(c.dispose);
    final s = c.read(editorProvider('a')).value!.settings;
    c
        .read(editorProvider('a').notifier)
        .commit(
          s.copyWith(
            backdrop: const BackdropChange(
              mode: BackdropMode.image,
              imageRef: 'retouch/bg.png',
            ),
          ),
          label: 'Background image',
          kind: HistoryKind.backdrop,
        );
    await _pump(tester, c);
    expect(find.text('Image'), findsOneWidget);
    await tester.tap(find.text('Fit'));
    await tester.pumpAndSettle();
    expect(_backdrop(c).fit, BackdropFit.fit);
    expect(find.bySemanticsLabel('#ffffff'), findsOneWidget); // letterbox
    await tester.pump(const Duration(seconds: 1));
  });
}
