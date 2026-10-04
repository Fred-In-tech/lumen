import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/platform/platform_info_io.dart';

final _log = Logger('BackupExclusion');

const _channel = MethodChannel('lumen/backup');

/// Folder names under `assets/<id>/` that hold local-only derived data.
const kBackupExcludedAssetDirs = {'cache'};

/// Marks [path] (file or directory, recursively) as excluded from iCloud /
/// iTunes / Time Machine backups on Apple platforms. Android excludes the
/// same folders through its backup rules (AndroidManifest), Windows and
/// Linux have no app-level backup. Returns true when the flag was set.
Future<bool> excludeFromBackup(String path, {PlatformInfo? platform}) async {
  if (!(platform ?? PlatformInfo.current()).isApple) return false;
  try {
    return await _channel.invokeMethod<bool>('exclude', {'path': path}) ??
        false;
  } on PlatformException catch (e) {
    _log.warning('backup exclusion failed for $path: ${e.message}');
    return false;
  } on MissingPluginException {
    // Tests and embedders without the native handler.
    return false;
  }
}

/// Marks the model store and every `assets/<id>/cache` folder of the
/// library. Cheap (one directory listing); run at startup.
Future<int> sweepBackupExclusions(
  String supportRoot,
  String storageId, {
  PlatformInfo? platform,
}) async {
  final info = platform ?? PlatformInfo.current();
  if (!info.isApple) return 0;
  var marked = 0;
  final models = Directory(p.join(supportRoot, 'models'));
  if (await models.exists() &&
      await excludeFromBackup(models.path, platform: info)) {
    marked++;
  }
  final assets = Directory(p.join(supportRoot, storageId, 'assets'));
  if (!await assets.exists()) return marked;
  try {
    await for (final asset in assets.list(followLinks: false)) {
      if (asset is! Directory) continue;
      for (final name in kBackupExcludedAssetDirs) {
        final dir = Directory(p.join(asset.path, name));
        if (await dir.exists() &&
            await excludeFromBackup(dir.path, platform: info)) {
          marked++;
        }
      }
    }
  } on FileSystemException catch (e) {
    _log.warning('backup exclusion sweep stopped: ${e.message}');
  }
  return marked;
}
