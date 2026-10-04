import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';
import 'package:path/path.dart' as p;

import 'package:lumen/ai/ondevice/cache_dirs_io.dart';
import 'package:lumen/ai/ondevice/disk_space_probe.dart';
import 'package:lumen/ai/ondevice/model_download_io.dart';
import 'package:lumen/ai/ondevice/model_store.dart';
import 'package:lumen/data/atomic_file_io_impl_io.dart';
import 'package:lumen/platform/platform_info.dart';

final _log = Logger('ModelStore');

/// [ModelStore] under `<root>/<id>/<version>/<file>` (root =
/// `<appSupport>/models`). Downloads land in `<file>.part`, are hashed
/// by streaming, then atomically renamed; a file is hashed again the first
/// time it is used in each session.
class FileModelStore implements ModelStore {
  FileModelStore({
    required this.root,
    required http.Client client,
    required DiskSpaceProbe diskProbe,
    required this.budgetBytes,
    BundledModelLoader? bundled,
    List<ModelSpec> manifest = ModelManifest.all,
    DateTime Function()? clock,
    this.stallTimeout = const Duration(seconds: 30),
    this.closeClientOnDispose = false,
    this.platform,
  }) : _http = client,
       _probe = diskProbe,
       _loadBundled = bundled,
       _bundledIds = {
         for (final s in manifest)
           if (s.bundled) s.id,
       },
       _clock = clock ?? DateTime.now;

  final String root;
  final int budgetBytes;
  final Duration stallTimeout;

  /// True when this store owns [client] (closed by [dispose]).
  final bool closeClientOnDispose;

  /// Platform for backup exclusion of [root] (null = the running platform).
  final PlatformInfo? platform;
  final http.Client _http;
  final DiskSpaceProbe _probe;
  final BundledModelLoader? _loadBundled;
  final Set<String> _bundledIds;
  final DateTime Function() _clock;
  final StreamController<ModelProgress> _progress =
      StreamController.broadcast();
  final Map<String, Future<ModelResult>> _inFlight = {};
  final Set<String> _verified = {};

  String pathFor(ModelSpec s) => p.join(root, s.id, s.version, s.fileName);

  @override
  Stream<ModelProgress> get progress => _progress.stream;

  @override
  Future<ModelResult> ensure(ModelSpec spec, {CancelToken? cancel}) {
    final key = spec.key;
    final running = _inFlight[key];
    if (running != null) return running;
    final op = _ensure(spec, cancel);
    _inFlight[key] = op;
    return op.whenComplete(() => _inFlight.remove(key));
  }

  @override
  Future<String?> readyPath(ModelSpec spec) async {
    try {
      spec.requireLoadable();
      return await _verifiedLocal(spec);
    } on ModelSpecException {
      return null;
    } on FileSystemException catch (e) {
      _log.warning('cannot read ${spec.key}: ${e.message}');
      return null;
    }
  }

  Future<ModelResult> _ensure(ModelSpec spec, CancelToken? cancel) async {
    try {
      spec.requireLoadable();
    } on ModelSpecException catch (e) {
      return _fail(spec, ModelRefused(e));
    }
    try {
      final local = await _verifiedLocal(spec);
      if (local != null) return await _ready(spec, local);
      final result = spec.bundled
          ? await _extractBundled(spec)
          : await _download(spec, cancel);
      return result;
    } on FileSystemException catch (e) {
      return _fail(spec, ModelStorageFailed(e.message));
    }
  }

  /// The final file if present, the right size and hashing to the pin.
  Future<String?> _verifiedLocal(ModelSpec spec) async {
    final path = pathFor(spec);
    final file = File(path);
    if (!await file.exists()) return null;
    if (await file.length() == spec.bytes) {
      if (_verified.contains(path)) return path;
      if (await _sha256(file) == spec.sha256) {
        _verified.add(path);
        return path;
      }
    }
    _log.warning('${spec.key} on disk failed verification; deleting');
    _verified.remove(path);
    await file.delete();
    return null;
  }

  Future<void> _ensureRoot() =>
      ensureBackupExcludedDir(root, platform: platform);

  Future<ModelResult> _extractBundled(ModelSpec spec) async {
    final bytes = await _loadBundled?.call(spec.bundledAssetKey);
    if (bytes == null) {
      return _fail(spec, BundledModelMissing(spec.bundledAssetKey));
    }
    final actual = sha256.convert(bytes).toString();
    if (actual != spec.sha256 || bytes.length != spec.bytes) {
      return _fail(
        spec,
        ModelChecksumMismatch(expected: spec.sha256!, actual: actual),
      );
    }
    final path = pathFor(spec);
    await _ensureRoot();
    await atomicWrite(path, bytes);
    _verified.add(path);
    return _ready(spec, path);
  }

  Future<ModelResult> _download(ModelSpec spec, CancelToken? cancel) async {
    _emit(spec, ModelPhase.checking);
    final need = requiredFreeBytes(spec.bytes);
    final free = await _probe.freeBytes(root);
    if (free == null) {
      _log.warning('free space unknown; downloading ${spec.key} anyway');
    } else if (free < need) {
      return _fail(
        spec,
        InsufficientDiskSpace(requiredBytes: need, availableBytes: free),
      );
    }
    await _ensureRoot();
    await _evict(incomingBytes: spec.bytes, keep: spec);
    final part = File('${pathFor(spec)}.part');
    final error = await downloadResumable(
      client: _http,
      url: Uri.parse(spec.url),
      part: part,
      expectedBytes: spec.bytes,
      cancel: cancel,
      stallTimeout: stallTimeout,
      onProgress: (n) => _emit(spec, ModelPhase.downloading, n),
    );
    if (error != null) return _fail(spec, error);
    _emit(spec, ModelPhase.verifying, spec.bytes);
    final actual = await _sha256(part);
    if (actual != spec.sha256) {
      await part.delete();
      return _fail(
        spec,
        ModelChecksumMismatch(expected: spec.sha256!, actual: actual),
      );
    }
    final path = pathFor(spec);
    if (await File(path).exists()) await File(path).delete();
    await part.rename(path);
    _verified.add(path);
    await _deleteOtherVersions(spec);
    return _ready(spec, path);
  }

  @override
  Future<void> evictToBudget() => _evict();

  /// Deletes least-recently-used downloads (never bundled models, never
  /// [keep]) until they plus [incomingBytes] fit [budgetBytes].
  Future<void> _evict({int incomingBytes = 0, ModelSpec? keep}) async {
    final dir = Directory(root);
    if (!await dir.exists()) return;
    final files = <({File file, int size, DateTime used})>[];
    await for (final idDir in dir.list()) {
      if (idDir is! Directory || _bundledIds.contains(p.basename(idDir.path))) {
        continue;
      }
      await for (final f in idDir.list(recursive: true)) {
        if (f is! File || f.path.endsWith('.part') || f.path.endsWith('.tmp')) {
          continue;
        }
        files.add((
          file: f,
          size: await f.length(),
          used: await f.lastModified(),
        ));
      }
    }
    var total = files.fold(0, (sum, f) => sum + f.size);
    files.sort((a, b) => a.used.compareTo(b.used));
    final keepPath = keep == null ? null : pathFor(keep);
    for (final f in files) {
      if (total + incomingBytes <= budgetBytes) break;
      if (f.file.path == keepPath) continue;
      _log.info('evicting ${f.file.path} (${f.size} B, used ${f.used})');
      await f.file.parent.delete(recursive: true);
      _verified.remove(f.file.path);
      total -= f.size;
    }
  }

  Future<void> _deleteOtherVersions(ModelSpec spec) async {
    final dir = Directory(p.join(root, spec.id));
    await for (final v in dir.list()) {
      if (v is Directory && p.basename(v.path) != spec.version) {
        await v.delete(recursive: true);
      }
    }
  }

  Future<ModelResult> _ready(ModelSpec spec, String path) async {
    if (!spec.bundled) await File(path).setLastModified(_clock());
    _emit(spec, ModelPhase.ready, spec.bytes);
    return ModelReady(spec, path);
  }

  ModelResult _fail(ModelSpec spec, ModelStoreError error) {
    _log.warning('${spec.key}: ${error.message}');
    _emit(spec, ModelPhase.failed);
    return ModelFailed(spec, error);
  }

  void _emit(ModelSpec spec, ModelPhase phase, [int received = 0]) {
    if (_progress.isClosed) return;
    _progress.add(
      ModelProgress(
        modelId: spec.id,
        phase: phase,
        receivedBytes: received,
        totalBytes: spec.bytes,
      ),
    );
  }

  static Future<String> _sha256(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();

  @override
  Future<void> dispose() async {
    if (closeClientOnDispose) _http.close();
    await _progress.close();
  }
}
