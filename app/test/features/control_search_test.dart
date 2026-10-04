import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/develop/sections.dart';
import 'package:lumen/features/editor/editor_controller.dart';
import 'package:lumen/features/editor/editor_module.dart';
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
      portraitFacesStatusProvider('a').overrideWithValue(const AsyncData(null)),
    ],
  );
  await c.read(editorProvider('a').future);
  return c;
}

void main() {
  final index = buildControlIndex();
  String top(String q) => searchControls(index, q).first.id;

  test('index has every develop and shown portrait param once', () {
    final ids = [for (final e in index) '${e.kind.name}:${e.id}'];
    expect(ids.toSet().length, ids.length);
    for (final spec in ParamRegistry.all) {
      expect(ids, contains('developParam:${spec.id}'));
    }
    for (final s in kPortraitSections) {
      for (final id in s.ids) {
        expect(ids, contains('portraitParam:$id'));
      }
    }
  });

  test('photographer words find the right control', () {
    expect(top('pimple'), PortraitIds.acne);
    expect(top('puffy'), PortraitIds.eyeBags);
    expect(top('whiten'), startsWith('teeth.'));
    expect(top('warmer'), P.temp);
    expect(top('exp'), P.exposure);
    expect(top('eye bags'), PortraitIds.eyeBags);
    expect(top('clone'), 'clone');
    expect(top('radial'), 'radial');
    expect(searchControls(index, 'zzqx'), isEmpty);
    expect(searchControls(index, '  '), isEmpty);
  });

  testWidgets('revealing a slider opens its closed develop section', (
    tester,
  ) async {
    final c = await _container();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildLumenTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: DevelopSections(assetId: 'a')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final label = ParamRegistry.byId(P.sharpenAmount).label;
    expect(find.text(label), findsNothing);
    final e = index.firstWhere((x) => x.id == P.sharpenAmount);
    openControl(c.read, 'a', e);
    await tester.pumpAndSettle();
    expect(find.text(label), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('revealing a portrait slider switches module and opens it', (
    tester,
  ) async {
    final c = await _container();
    addTearDown(c.dispose);
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
    final label = PortraitRegistry.byId(PortraitIds.teethBrightness).label;
    expect(find.text(label), findsNothing);
    final e = index.firstWhere((x) => x.id == PortraitIds.teethBrightness);
    openControl(c.read, 'a', e);
    await tester.pumpAndSettle();
    expect(c.read(editorModuleProvider('a')), EditorModule.portrait);
    expect(find.text(label), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
