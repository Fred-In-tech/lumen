import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:lumen/platform/backup_exclusion.dart';
import 'package:lumen/platform/platform_info.dart';

/// Creates [dir] when missing and, on that first creation, marks it as
/// excluded from OS backups on [platform] (fire-and-forget; the startup
/// sweep catches anything this misses). Used for `assets/<id>/cache/` and
/// `models/`. A null [platform] (tests, tools) only creates the folder.
Future<void> ensureBackupExcludedDir(
  String dir, {
  PlatformInfo? platform,
}) async {
  final d = Directory(dir);
  if (await d.exists()) return;
  await d.create(recursive: true);
  if (platform != null) {
    unawaited(excludeFromBackup(d.path, platform: platform));
  }
}

/// `<root>/assets/<assetId>/cache`: the per-photo local-only folder.
String assetCacheDir(String root, String assetId) =>
    p.join(root, 'assets', assetId, 'cache');
