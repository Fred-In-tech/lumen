import 'dart:typed_data';

import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/patch_store.dart';

/// Session-only patch store (web, tests). Keeps the encoded PNG bytes, so
/// a round trip exercises the same codec as the file store.
class MemoryPatchStore implements PatchStore {
  final Map<String, Map<String, Uint8List>> _png = {};

  @override
  Future<void> save(String assetId, String ref, RgbaBuffer rgba) async {
    checkPatchAssetId(assetId);
    checkPatchRef(ref);
    final bytes = await encodePatchPngInBackground(rgba);
    (_png[assetId] ??= {})[ref] = bytes;
  }

  @override
  Future<RgbaBuffer?> load(String assetId, String ref) async {
    if (!isStorablePatchRef(ref)) return null;
    final bytes = _png[checkPatchAssetId(assetId)]?[ref];
    return bytes == null ? null : decodePatchPngInBackground(bytes);
  }

  @override
  Future<Set<String>> list(String assetId) async => {
    ...?_png[checkPatchAssetId(assetId)]?.keys,
  };

  @override
  Future<void> delete(String assetId, String ref) async {
    if (!isStorablePatchRef(ref)) return;
    _png[checkPatchAssetId(assetId)]?.remove(ref);
  }

  /// Drops every patch of [assetId] (the memory catalog's photo delete
  /// does not reach this store).
  void deleteAsset(String assetId) => _png.remove(assetId);
}
