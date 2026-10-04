import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/editor/compare_suppress.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/portrait/portrait_panel.dart';
import 'package:lumen/features/portrait/portrait_state.dart';
import 'package:lumen_core/lumen_core.dart';

void main() {
  test('withSuppressed turns develop and portrait params off', () {
    final s = DevelopSettings.defaults
        .withValue(P.exposure, 0.5)
        .withValue(P.contrast, 20)
        .copyWith(
          portrait: PortraitSettings.empty
              .withGroupValue(FaceGroup.all, PortraitIds.skinSoftening, 40)
              .withGroupValue(FaceGroup.all, PortraitIds.acne, 80),
        );
    final off = withSuppressed(s, {P.exposure, PortraitIds.skinSoftening});
    expect(off.value(P.exposure), 0);
    expect(off.value(P.contrast), 20);
    expect(
      off.portrait.valueFor(PortraitIds.skinSoftening, group: FaceGroup.all),
      0,
    );
    expect(off.portrait.valueFor(PortraitIds.acne, group: FaceGroup.all), 80);
    expect(identical(withSuppressed(s, const {}), s), isTrue);
  });

  testWidgets('holding a section eye suppresses only that section', (
    tester,
  ) async {
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
    final c = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        portraitFacesStatusProvider('a')
            .overrideWithValue(const AsyncData(null)),
      ],
    );
    addTearDown(c.dispose);
    await c.read(editorProvider('a').future);
    final s = c.read(editorProvider('a')).value!.settings;
    c
        .read(editorProvider('a').notifier)
        .commit(
          s.copyWith(portrait: PortraitPresets.autoRetouch(s.portrait)),
          label: 'Auto Retouch',
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildLumenTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: PortraitPanel(assetId: 'a')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final eye = find.bySemanticsLabel('Hold to compare without Skin');
    expect(eye, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(eye));
    // A press registers after the tap timeout (the header row also listens).
    await tester.pump(const Duration(milliseconds: 200));
    final skin = kPortraitSections.firstWhere((x) => x.title == 'Skin').ids;
    expect(c.read(compareSuppressProvider('a')), skin.toSet());
    await gesture.up();
    await tester.pump();
    expect(c.read(compareSuppressProvider('a')), isEmpty);
    await tester.pump(const Duration(seconds: 1));
  });
}
