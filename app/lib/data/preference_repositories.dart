import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/app_settings.dart';

/// User presets (built-ins live in code: `kBuiltinPresets`).
abstract interface class PresetRepository {
  Future<List<Preset>> list();
  Future<void> save(Preset preset);
  Future<void> delete(String id);
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class MemoryPresetRepository implements PresetRepository {
  final Map<String, Preset> _presets = {};

  @override
  Future<List<Preset>> list() async => List.unmodifiable(
    _presets.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
  );

  @override
  Future<void> save(Preset preset) async => _presets[preset.id] = preset;

  @override
  Future<void> delete(String id) async => _presets.remove(id);
}

class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository([this._settings = const AppSettings()]);

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}
