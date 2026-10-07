import 'dart:io';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/data/atomic_file_io_impl_io.dart';
import 'package:lumen/data/lut_repository.dart';

final _log = Logger('FileLutRepository');

/// LUTs under `<library>/luts/<hash>.lut` in `CubeLut.encode` form (16-bit
/// tables, a few hundred KB each), next to the presets that use them.
class FileLutRepository implements LutRepository {
  FileLutRepository(this.root);

  final String root;
  String get _dir => p.join(root, 'luts');

  String _path(String hash) => p.join(_dir, '$hash.lut');

  @override
  Future<void> save(CubeLut lut) async {
    final path = _path(lut.contentHash);
    if (await File(path).exists()) return;
    await atomicWrite(path, lut.encode());
  }

  @override
  Future<CubeLut?> load(String hash) async {
    if (!LutRef.isValidHash(hash)) return null;
    final f = File(_path(hash));
    if (!await f.exists()) return null;
    try {
      return CubeLut.decode(await f.readAsBytes());
    } on CubeFormatException catch (e) {
      _log.warning('Unreadable LUT $hash: $e');
      return null;
    }
  }

  @override
  Future<Set<String>> hashes() async {
    final dir = Directory(_dir);
    if (!await dir.exists()) return const {};
    return {
      await for (final f in dir.list())
        if (f is File && f.path.endsWith('.lut'))
          p.basenameWithoutExtension(f.path),
    };
  }
}
