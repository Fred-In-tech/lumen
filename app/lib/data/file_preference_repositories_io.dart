import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/data/app_settings.dart';
import 'package:lumen/data/atomic_file_io_impl_io.dart';
import 'package:lumen/data/preference_repositories.dart';

final _log = Logger('FilePreferences');

Uint8List _encode(Object? json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

class FilePresetRepository implements PresetRepository {
  FilePresetRepository(this.root);

  final String root;
  String get _dir => p.join(root, 'presets');

  @override
  Future<List<Preset>> list() async {
    final dir = Directory(_dir);
    if (!await dir.exists()) return const [];
    final out = <Preset>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await f.readAsString());
        if (json is Map) out.add(Preset.fromJson(json.cast()));
      } on FormatException catch (e) {
        _log.warning('Skipping unreadable preset ${f.path}: $e');
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(out);
  }

  String _safeName(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  @override
  Future<void> save(Preset preset) => atomicWrite(p.join(_dir, '${_safeName(preset.id)}.json'), _encode(preset.toJson()));

  @override
  Future<void> delete(String id) async {
    final f = File(p.join(_dir, '${_safeName(id)}.json'));
    if (await f.exists()) await f.delete();
  }
}

class FileSettingsRepository implements SettingsRepository {
  FileSettingsRepository(this.root);

  final String root;
  String get _path => p.join(root, 'settings.json');

  @override
  Future<AppSettings> load() async {
    final f = File(_path);
    if (!await f.exists()) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(await f.readAsString()));
    } on FormatException catch (e) {
      _log.warning('settings.json unreadable, using defaults: $e');
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) => atomicWrite(_path, _encode(settings.toJson()));
}
