import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:lumen/ai/ondevice/cache_dirs_io.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/ai/ondevice/face_parsing_cache.dart';
import 'package:lumen/data/atomic_file_io_impl_io.dart';
import 'package:lumen/platform/platform_info.dart';

/// `<root>/assets/<id>/cache/parsing.bin` (root = the catalog root), in
/// the same backup-excluded folder as the face cache.
class FileFaceParsingCache implements FaceParsingCache {
  FileFaceParsingCache(this.root, {this.platform});

  final String root;

  /// Platform for backup exclusion (null = the running platform).
  final PlatformInfo? platform;

  String pathFor(String assetId) => p.join(
    root,
    'assets',
    checkAssetId(assetId),
    kAssetCacheDir,
    kFaceParsingFile,
  );

  @override
  Future<Uint8List?> read(String assetId) async {
    final file = File(pathFor(assetId));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> write(String assetId, Uint8List bytes) async {
    await ensureBackupExcludedDir(
      assetCacheDir(root, assetId),
      platform: platform,
    );
    await atomicWrite(pathFor(assetId), bytes);
  }

  @override
  Future<void> delete(String assetId) async {
    final file = File(pathFor(assetId));
    if (await file.exists()) await file.delete();
  }
}
