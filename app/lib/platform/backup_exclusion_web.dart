import 'package:lumen/platform/platform_info_web.dart';

/// Web: nothing is stored on disk, so there is nothing to exclude.
Future<bool> excludeFromBackup(String path, {PlatformInfo? platform}) async =>
    false;

/// Web: no-op.
Future<int> sweepBackupExclusions(
  String supportRoot,
  String storageId, {
  PlatformInfo? platform,
}) async => 0;
