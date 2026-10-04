import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/design/theme.dart';
import 'package:lumen/features/cull/cull_providers.dart';
import 'package:lumen/features/cull/cull_store.dart';
import 'package:lumen/features/cull/library_filter.dart';
import 'package:lumen/features/library/library_screen.dart';
import 'package:lumen_core/lumen_core.dart';

CatalogEntry _entry(String id, {String flag = 'none', int minute = 0}) =>
    CatalogEntry(
      assetId: id,
      fileName: '$id.jpg',
      originalPath: 'originals/$id.jpg',
      format: 'jpeg',
      width: 40,
      height: 30,
      bytes: 1,
      importedAt: DateTime.utc(2026, 10, 3, 12, minute),
      flag: flag,
    );

CullRecord _record(
  String id,
  CullDecision d, {
  Set<CullReason> reasons = const {},
  int clusterSize = 1,
}) => CullRecord(
  signalsKey: 'k',
  signals: CullSignals(
    sharpness: 0.3,
    highlightClip: 0,
    shadowClip: 0,
    meanLuma: 0.5,
    dHash: '0000000000000000',
  ),
  suggestion: CullSuggestion(
    assetId: id,
    decision: d,
    score: 0.5,
    reasons: reasons,
    clusterId: clusterSize > 1 ? 'c:x' : null,
    clusterSize: clusterSize,
  ),
);

/// Library: a (picked), b (pending pick, cluster), c (pending reject:
/// eyes closed, cluster), d (pending reject: blurry), e (nothing).
Future<(ProviderContainer, MemoryCatalogRepository)> _pump(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = MemoryCatalogRepository();
  for (final (i, e) in [
    _entry('a', flag: 'pick'),
    _entry('b'),
    _entry('c'),
    _entry('d'),
    _entry('e'),
  ].indexed) {
    await repo.add(
      CatalogEntry.fromJson({
        ...e.toJson(),
        'importedAt': e.importedAt.add(Duration(minutes: i)).toIso8601String(),
      }),
      Uint8List(1),
    );
  }
  final store = MemoryCullStore();
  await store.write('b', _record('b', CullDecision.pick, clusterSize: 2));
  await store.write(
    'c',
    _record(
      'c',
      CullDecision.reject,
      reasons: {CullReason.eyesClosed},
      clusterSize: 2,
    ),
  );
  await store.write(
    'd',
    _record('d', CullDecision.reject, reasons: {CullReason.blurryFace}),
  );
  final c = ProviderContainer(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(repo),
      presetRepositoryProvider.overrideWithValue(MemoryPresetRepository()),
      settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()),
      cullStoreProvider.overrideWith((ref) async => store),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildLumenTheme(), home: const LibraryScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (c, repo);
}

Set<String> _shown(WidgetTester tester) => {
  for (final id in ['a', 'b', 'c', 'd', 'e'])
    if (find.byKey(ValueKey(id)).evaluate().isNotEmpty) id,
};

Future<void> _chip(WidgetTester tester, String label) async {
  final chip = find.textContaining(RegExp('^$label  '));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('filter chips show counts and narrow the grid', (tester) async {
    final (c, _) = await _pump(tester);
    expect(find.text('All  5'), findsOneWidget);
    expect(find.text('Picks  2'), findsOneWidget);
    expect(find.text('Rejects  2'), findsOneWidget);
    expect(find.text('Eyes closed  1'), findsOneWidget);
    expect(find.text('Blurry  1'), findsOneWidget);
    expect(find.text('Clusters  2'), findsOneWidget);
    expect(_shown(tester), {'a', 'b', 'c', 'd', 'e'});

    await _chip(tester, 'Picks');
    expect(_shown(tester), {'a', 'b'});
    await _chip(tester, 'Rejects');
    expect(_shown(tester), {'c', 'd'});
    await _chip(tester, 'Eyes closed');
    expect(_shown(tester), {'c'});
    await _chip(tester, 'Blurry');
    expect(_shown(tester), {'d'});
    await _chip(tester, 'Clusters');
    expect(_shown(tester), {'b', 'c'});
    expect(c.read(libraryFilterProvider), LibraryFilter.clusters);
    await _chip(tester, 'All');
    expect(_shown(tester), hasLength(5));
  });

  testWidgets('tiles badge flags and pending suggestions', (tester) async {
    await _pump(tester);
    expect(find.byIcon(LucideIcons.flag), findsOneWidget); // a: picked
    expect(find.byIcon(LucideIcons.thumbsUp), findsOneWidget); // b
    expect(find.byIcon(LucideIcons.thumbsDown), findsNWidgets(2)); // c, d
    expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
    expect(find.byIcon(LucideIcons.focus), findsOneWidget);
    expect(find.byIcon(LucideIcons.layers), findsNWidgets(2));
    expect(find.text('1 pick · 2 rejects suggested'), findsOneWidget);
  });

  testWidgets('Accept writes picks and rejects to the catalog', (tester) async {
    final (c, repo) = await _pump(tester);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect((await repo.get('b'))!.flag, PhotoFlag.pick);
    expect((await repo.get('c'))!.flag, PhotoFlag.reject);
    expect((await repo.get('d'))!.flag, PhotoFlag.reject);
    expect((await repo.get('e'))!.flag, PhotoFlag.none);
    final records = c.read(cullRecordsProvider).value!;
    expect(records['b']!.status, SuggestionStatus.accepted);
    expect(find.textContaining('suggested'), findsNothing);
    expect(find.byIcon(LucideIcons.thumbsDown), findsNothing);
    expect(find.byIcon(LucideIcons.circleX), findsNWidgets(2));
  });

  testWidgets('Dismiss leaves the catalog alone', (tester) async {
    final (_, repo) = await _pump(tester);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect((await repo.get('c'))!.flag, PhotoFlag.none);
    expect(find.text('Rejects  0'), findsOneWidget);
  });

  testWidgets('P / X / U flag and 0–5 rate the selection', (tester) async {
    final (_, repo) = await _pump(tester);
    await tester.longPress(find.byKey(const ValueKey('e')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect((await repo.get('e'))!.flag, PhotoFlag.pick);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pumpAndSettle();
    expect((await repo.get('e'))!.flag, PhotoFlag.reject);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.pumpAndSettle();
    expect((await repo.get('e'))!.flag, PhotoFlag.none);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.pumpAndSettle();
    expect((await repo.get('e'))!.rating, 4);
    expect(find.text('★★★★'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    expect((await repo.get('e'))!.rating, 0);
    // Nothing selected elsewhere was touched.
    expect((await repo.get('a'))!.flag, PhotoFlag.pick);
  });
}
