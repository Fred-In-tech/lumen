import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/cache_dirs_io.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/data/atomic_file_io_impl_io.dart';
import 'package:lumen/features/cull/cull_store.dart';
import 'package:lumen/platform/platform_info.dart';

final _log = Logger('CullStore');

/// `<root>/assets/<id>/cache/cull.json` (root = catalog root). Excluded
/// from backups when its cache folder is first created.
class FileCullStore implements CullStore {
  FileCullStore(this.root, {this.platform});

  final String root;
  final PlatformInfo? platform;

  String pathFor(String assetId) =>
      p.join(assetCacheDir(root, checkAssetId(assetId)), kCullCacheFile);

  @override
  Future<CullRecord?> read(String assetId) async {
    final file = File(pathFor(assetId));
    if (!await file.exists()) return null;
    try {
      return CullRecord.tryFromJson(jsonDecode(await file.readAsString()));
    } on FormatException catch (e) {
      _log.warning('cull cache for $assetId unreadable, will rebuild: $e');
      return null;
    }
  }

  @override
  Future<void> write(String assetId, CullRecord record) async {
    final path = pathFor(assetId);
    await ensureBackupExcludedDir(
      assetCacheDir(root, assetId),
      platform: platform,
    );
    await atomicWrite(
      path,
      Uint8List.fromList(utf8.encode(jsonEncode(record.toJson()))),
    );
  }
}

/// The cull cache next to the catalog.
Future<CullStore> openCullStore() async {
  final support = await getApplicationSupportDirectory();
  return FileCullStore(
    p.join(support.path, kBrand.storageId),
    platform: PlatformInfo.current(),
  );
}
