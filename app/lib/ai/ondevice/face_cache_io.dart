import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/ai/ondevice/cache_dirs_io.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/data/atomic_file_io_impl_io.dart';
import 'package:lumen/platform/platform_info.dart';

final _log = Logger('FaceCache');

/// `<root>/assets/<id>/cache/face.json`, where root is the catalog root.
/// Deleting a photo deletes `assets/<id>/` and with it this cache.
class FileFaceCache implements FaceCache {
  FileFaceCache(this.root, {this.platform});

  final String root;

  /// Platform for backup exclusion (null = the running platform).
  final PlatformInfo? platform;

  String pathFor(String assetId) => p.join(
    root,
    'assets',
    checkAssetId(assetId),
    kAssetCacheDir,
    kFaceCacheFile,
  );

  @override
  Future<FaceCacheEntry?> read(String assetId) async {
    final file = File(pathFor(assetId));
    if (!await file.exists()) return null;
    try {
      final entry = FaceCacheEntry.tryFromJson(
        jsonDecode(await file.readAsString()),
      );
      if (entry == null) _log.info('face cache for $assetId is outdated');
      return entry;
    } on FormatException catch (e) {
      _log.warning('face cache for $assetId unreadable, will rebuild: $e');
      return null;
    }
  }

  @override
  Future<void> write(String assetId, FaceCacheEntry entry) async {
    final path = pathFor(assetId);
    await ensureBackupExcludedDir(
      assetCacheDir(root, assetId),
      platform: platform,
    );
    await atomicWrite(
      path,
      Uint8List.fromList(utf8.encode(jsonEncode(entry.toJson()))),
    );
  }

  @override
  Future<void> delete(String assetId) async {
    final file = File(pathFor(assetId));
    if (await file.exists()) await file.delete();
  }
}
