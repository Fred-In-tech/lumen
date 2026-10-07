import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/data/lut_repository.dart';

typedef Repositories = ({
  CatalogRepository catalog,
  PresetRepository presets,
  SettingsRepository settings,
  LutRepository luts,
});

/// Web demo: everything lives in memory for the session.
Future<Repositories> openRepositories() async => (
  catalog: MemoryCatalogRepository(),
  presets: MemoryPresetRepository(),
  settings: MemorySettingsRepository(),
  luts: MemoryLutRepository(),
);

const bool kPersistentLibrary = false;
