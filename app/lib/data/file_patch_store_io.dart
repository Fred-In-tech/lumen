import 'dart:io';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/data/atomic_file_io_impl_io.dart';
import 'package:lumen/data/patch_store.dart';

final _log = Logger('FilePatchStore');

/// Patch PNGs at `<root>/assets/<id>/retouch/<name>.png`, where root is the
/// catalog root. Deleting a photo deletes `assets/<id>/` and its patches.
class FilePatchStore implements PatchStore {
  FilePatchStore(this.root);

  final String root;

  String _dir(String assetId) =>
      p.join(root, 'assets', checkPatchAssetId(assetId), kRetouchDir);

  /// Absolute path of [ref] for [assetId] (both validated).
  String pathFor(String assetId, String ref) =>
      p.join(_dir(assetId), checkPatchRef(ref).split('/').last);

  @override
  Future<void> save(String assetId, String ref, RgbaBuffer rgba) async {
    final path = pathFor(assetId, ref);
    await atomicWrite(path, await encodePatchPngInBackground(rgba));
  }

  @override
  Future<RgbaBuffer?> load(String assetId, String ref) async {
    if (!isStorablePatchRef(ref)) {
      _log.warning('ignoring unsafe patch ref for $assetId');
      return null;
    }
    final file = File(pathFor(assetId, ref));
    if (!await file.exists()) return null;
    final patch = await decodePatchPngInBackground(await file.readAsBytes());
    if (patch == null) _log.warning('patch $ref of $assetId is unreadable');
    return patch;
  }

  @override
  Future<Set<String>> list(String assetId) async {
    final dir = Directory(_dir(assetId));
    if (!await dir.exists()) return {};
    return {
      await for (final e in dir.list(followLinks: false))
        if (e is File) ...[
          if (isStorablePatchRef('$kRetouchDir/${p.basename(e.path)}'))
            '$kRetouchDir/${p.basename(e.path)}',
        ],
    };
  }

  @override
  Future<void> delete(String assetId, String ref) async {
    if (!isStorablePatchRef(ref)) return;
    final file = File(pathFor(assetId, ref));
    if (await file.exists()) await file.delete();
  }
}
