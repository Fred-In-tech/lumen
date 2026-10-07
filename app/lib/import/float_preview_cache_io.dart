import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:lumen/ai/ondevice/cache_dirs_io.dart';
import 'package:lumen/import/float_decoder_types.dart';
import 'package:lumen/import/float_preview_cache_types.dart';
import 'package:lumen/platform/platform_info.dart';

final _log = Logger('FloatPreviewCache');

/// Temporary files of interrupted writes older than this are deleted.
const _staleTemp = Duration(minutes: 10);

/// The preview cache on Apple platforms: `<app caches>/float_previews/`,
/// outside the catalog and its originals, excluded from backups.
FloatPreviewCache platformFloatPreviewCache({PlatformInfo? platform}) {
  final info = platform ?? PlatformInfo.current();
  if (!info.isApple) return const NoFloatPreviewCache();
  return FileFloatPreviewCache(
    () async =>
        p.join((await getApplicationCacheDirectory()).path, 'float_previews'),
    platform: info,
  );
}

/// Float previews as files in one folder. Recency is the file's
/// modification time (set on every read), so eviction survives restarts
/// without an index file.
class FileFloatPreviewCache implements FloatPreviewCache {
  FileFloatPreviewCache(
    this._resolveDir, {
    this.maxBytes = kFloatPreviewCacheMaxBytes,
    this.platform,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<String> Function() _resolveDir;

  /// Size cap of the folder.
  final int maxBytes;

  /// For backup exclusion (null: only create the folder).
  final PlatformInfo? platform;
  final DateTime Function() _clock;

  Future<String?>? _dir;

  /// The folder, created (and excluded from backups) on first use; null
  /// when the platform has no caches directory.
  Future<String?> _folder() => _dir ??= () async {
    try {
      final dir = await _resolveDir();
      await ensureBackupExcludedDir(dir, platform: platform);
      return dir;
    } on Exception catch (e) {
      _log.info('no float preview cache: $e');
      return null;
    }
  }();

  @override
  Future<String?> pathFor(String assetId, int width, int height) async {
    final name = floatPreviewFileName(assetId, width, height);
    final dir = await _folder();
    if (name == null || dir == null) return null;
    return p.join(dir, name);
  }

  @override
  Future<bool> contains(String assetId, int width, int height) async {
    final path = await pathFor(assetId, width, height);
    return path != null && File(path).existsSync();
  }

  Future<List<File>> _entries() async {
    final dir = await _folder();
    if (dir == null) return const [];
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final out = <File>[];
    try {
      await for (final f in d.list(followLinks: false)) {
        if (f is File) out.add(f);
      }
    } on FileSystemException catch (e) {
      _log.warning('float preview cache listing failed: ${e.message}');
    }
    return out;
  }

  @override
  Future<FloatSourceInfo?> infoFor(String assetId) async {
    for (final f in await _entries()) {
      if (assetIdOfFloatPreview(p.basename(f.path)) != assetId) continue;
      final info = await _readHeader(f);
      if (info != null) return info;
    }
    return null;
  }

  Future<FloatSourceInfo?> _readHeader(File f) async {
    RandomAccessFile? raf;
    try {
      raf = await f.open();
      final head = await raf.read(kFloatPreviewHeaderBytes);
      return parseFloatPreviewHeader(Uint8List.fromList(head));
    } on FileSystemException {
      return null; // evicted meanwhile
    } finally {
      await raf?.close();
    }
  }

  @override
  Future<void> touch(String path) async {
    try {
      await File(path).setLastModified(_clock());
    } on FileSystemException {
      // Evicted or never written: nothing to mark.
    }
  }

  @override
  Future<int> sizeInBytes() async {
    var total = 0;
    for (final f in await _entries()) {
      if (p.extension(f.path) == '.lfp') total += _statSize(f);
    }
    return total;
  }

  static int _statSize(File f) {
    final s = f.statSync();
    return s.type == FileSystemEntityType.notFound ? 0 : s.size;
  }

  @override
  Future<int> trim({Set<String> keep = const {}}) async {
    final now = _clock();
    final live = <(File, FileStat)>[];
    var total = 0;
    for (final f in await _entries()) {
      final stat = f.statSync();
      if (stat.type == FileSystemEntityType.notFound) continue;
      final name = p.basename(f.path);
      if (name.startsWith('.tmp-')) {
        if (now.difference(stat.modified) > _staleTemp) _delete(f);
        continue;
      }
      if (assetIdOfFloatPreview(name) == null) {
        // Another version (or a stray file): never read again.
        _delete(f);
        continue;
      }
      live.add((f, stat));
      total += stat.size;
    }
    if (total <= maxBytes) return 0;
    live.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var freed = 0;
    for (final (f, stat) in live) {
      if (total - freed <= maxBytes) break;
      if (keep.contains(f.path)) continue;
      if (_delete(f)) freed += stat.size;
    }
    _log.info('float preview cache trimmed by ${freed ~/ (1 << 20)} MB');
    return freed;
  }

  static bool _delete(File f) {
    try {
      // A reader that already opened the file keeps reading it (unlink).
      f.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<void> remove(String assetId) async {
    for (final f in await _entries()) {
      if (assetIdOfFloatPreview(p.basename(f.path)) == assetId) _delete(f);
    }
  }
}
