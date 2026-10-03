import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/memory_catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';

typedef Repositories = ({CatalogRepository catalog, PresetRepository presets, SettingsRepository settings});

/// Web demo: everything lives in memory for the session.
Future<Repositories> openRepositories() async => (
      catalog: MemoryCatalogRepository(),
      presets: MemoryPresetRepository(),
      settings: MemorySettingsRepository(),
    );

const bool kPersistentLibrary = false;
