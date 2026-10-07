import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/app/lumen_app.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/features/cull/cull_providers.dart';
import 'package:lumen/features/cull/cull_store.dart';
import 'package:lumen/features/library/library_actions.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_sources.dart';
import 'package:lumen_core/lumen_core.dart';

/// A photo entry for widget tests (no real pixels: thumbnails stay grey).
CatalogEntry photo(
  String id, {
  String? project,
  String flag = PhotoFlag.none,
  bool edited = false,
  DateTime? importedAt,
}) => CatalogEntry(
  assetId: id,
  fileName: '$id.jpg',
  originalPath: 'originals/$id.jpg',
  format: 'jpeg',
  width: 40,
  height: 30,
  bytes: 1,
  importedAt: importedAt ?? DateTime.utc(2026, 10, 1),
  projectId: project,
  flag: flag,
  hasEdits: edited,
  editedAt: edited ? DateTime.utc(2026, 10, 2) : null,
);

/// Picker that returns fixed files.
class FakeImportSource implements ImportSource {
  FakeImportSource(this.files);
  final List<ImportFile> files;

  @override
  Future<List<ImportFile>> pick({required bool mobile}) async => files;
}

/// A library with two projects ("Wedding": 3 photos, 2 picks, 1 edited;
/// "Family": 2 photos) and one Unsorted photo. Returns the repo and the
/// project ids.
Future<(MemoryCatalogRepository, String wedding, String family)>
twoProjectLibrary() async {
  final repo = MemoryCatalogRepository();
  final wedding = await repo.createProject(
    name: 'Wedding',
    shootDate: DateTime(2026, 9, 27),
  );
  final family = await repo.createProject(
    name: 'Family',
    shootDate: DateTime(2026, 10, 4),
  );
  for (final e in [
    photo('w1', project: wedding.id, flag: PhotoFlag.pick, edited: true),
    photo('w2', project: wedding.id, flag: PhotoFlag.pick),
    photo('w3', project: wedding.id, flag: PhotoFlag.reject),
    photo('f1', project: family.id),
    photo('f2', project: family.id),
    photo('u1'),
  ]) {
    await repo.add(e, Uint8List(1));
  }
  return (repo, wedding.id, family.id);
}

/// Overrides for the app with [repo] and in-memory preferences.
List<Override> appOverrides(
  MemoryCatalogRepository repo, {
  MemorySettingsRepository? settings,
  List<ImportFile> pick = const [],
}) => [
  catalogRepositoryProvider.overrideWithValue(repo),
  presetRepositoryProvider.overrideWithValue(MemoryPresetRepository()),
  settingsRepositoryProvider.overrideWithValue(
    settings ?? MemorySettingsRepository(),
  ),
  cullStoreProvider.overrideWith((ref) async => MemoryCullStore()),
  importSourceProvider.overrideWithValue(FakeImportSource(pick)),
];

/// Pumps the whole app at [size] (default desktop 1440×900).
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  MemoryCatalogRepository repo, {
  Size size = const Size(1440, 900),
  MemorySettingsRepository? settings,
  List<ImportFile> pick = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: appOverrides(repo, settings: settings, pick: pick),
      child: const LumenApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(LumenApp)));
}
