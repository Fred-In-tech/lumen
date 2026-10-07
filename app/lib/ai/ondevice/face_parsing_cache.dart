import 'dart:typed_data';

import 'package:lumen/ai/ondevice/face_cache.dart';

/// File name of the per-photo face parsing inside `kAssetCacheDir`.
const kFaceParsingFile = 'parsing.bin';

/// Local, non-synced store for the face parsing of a photo (derived face
/// data like `face.json`: never in edit documents, excluded from backups,
/// deleted with the photo). The bytes are `wrapParsing` output.
abstract interface class FaceParsingCache {
  Future<Uint8List?> read(String assetId);
  Future<void> write(String assetId, Uint8List bytes);
  Future<void> delete(String assetId);
}

/// Web and tests.
class MemoryFaceParsingCache implements FaceParsingCache {
  final Map<String, Uint8List> _files = {};

  @override
  Future<Uint8List?> read(String assetId) async =>
      _files[checkAssetId(assetId)];

  @override
  Future<void> write(String assetId, Uint8List bytes) async =>
      _files[checkAssetId(assetId)] = bytes;

  @override
  Future<void> delete(String assetId) async =>
      _files.remove(checkAssetId(assetId));
}
