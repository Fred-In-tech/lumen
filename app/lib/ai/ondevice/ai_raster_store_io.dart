import 'dart:io';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/ai/ondevice/ai_raster_store.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/data/atomic_file_io_impl_io.dart';
import 'package:lumen/platform/background.dart';

final _log = Logger('AiRasterStore');

/// `<root>/assets/<id>/cache/masks/<maskRef>.png` (root = catalog root).
/// PNG encode/decode runs off the UI isolate.
class FileAiRasterStore implements AiRasterStore {
  FileAiRasterStore(this.root);

  final String root;

  String pathFor(String assetId, String maskRef) => p.join(
    root,
    'assets',
    checkAssetId(assetId),
    kAssetCacheDir,
    kMaskCacheDir,
    '${checkMaskRef(maskRef)}.png',
  );

  @override
  Future<MaskRaster?> read(String assetId, String maskRef) async {
    final file = File(pathFor(assetId, maskRef));
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final raster = await runInBackground(() => decodeMaskPng(bytes));
    if (raster == null) _log.warning('$maskRef for $assetId is not a PNG');
    return raster;
  }

  @override
  Future<void> write(String assetId, String maskRef, MaskRaster raster) async {
    final path = pathFor(assetId, maskRef);
    final png = await runInBackground(() => encodeMaskPng(raster));
    await atomicWrite(path, png);
  }

  @override
  Future<bool> exists(String assetId, String maskRef) =>
      File(pathFor(assetId, maskRef)).exists();
}
