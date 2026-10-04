import 'dart:async';

import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/file_catalog_repository_io.dart';
import 'package:lumen/data/file_preference_repositories_io.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/platform/backup_exclusion_io.dart';

/// The repositories bundle for the current platform.
typedef Repositories = ({
  CatalogRepository catalog,
  PresetRepository presets,
  SettingsRepository settings,
});

/// Opens the on-disk library under the app-support directory.
Future<Repositories> openRepositories() async {
  final support = await getApplicationSupportDirectory();
  final root = p.join(support.path, kBrand.storageId);
  // Face geometry, AI rasters and models are local-only: keep them out of
  // iCloud / Time Machine (Android: backup rules in the manifest).
  unawaited(sweepBackupExclusions(support.path, kBrand.storageId));
  return (
    catalog: FileCatalogRepository(root),
    presets: FilePresetRepository(root),
    settings: FileSettingsRepository(root),
  );
}

/// True when photos persist across app restarts.
const bool kPersistentLibrary = true;
