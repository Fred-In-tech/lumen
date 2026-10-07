import 'dart:async';
import 'dart:collection';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/engine/float_source.dart';
import 'package:lumen/import/float_decoder_types.dart';
import 'package:lumen/import/float_preview_cache_types.dart';

final _log = Logger('FloatPreviewStore');

/// A [FloatSource] that can hand out its editor preview without decoding
/// the original when it was decoded before (docs/HIGH_BIT_DEPTH.md,
/// "Preview cache"). The renderer checks for it to decide between opening
/// on the float preview at once and the progressive open.
abstract interface class PreviewCacheAware {
  /// The whole photo at [width]×[height] when it is in memory or in the
  /// preview cache, else null. Never decodes the original.
  Future<FloatPixels?> cachedPreview(int width, int height);
}

/// Float previews of the editor, in memory and on disk:
///
/// * memory: the last [memoryEntries] previews (the open photo and its two
///   filmstrip neighbours; 70 MB each at 1708 × 2560);
/// * disk: [FloatPreviewCache], written by the native decoder.
///
/// [load] serves memory, then disk, then decodes (and the decode writes
/// the disk entry). [prefetch] and [warm] fill memory / disk in the
/// background, one decode at a time, newest request first.
class FloatPreviewStore {
  FloatPreviewStore({
    required this.decoder,
    required this.cache,
    this.memoryEntries = 3,
  });

  final FloatDecoder decoder;
  final FloatPreviewCache cache;
  final int memoryEntries;

  final LinkedHashMap<String, FloatPixels> _memory = LinkedHashMap();

  /// Cache file of each preview in memory (never evicted from disk).
  final Map<String, String> _pathOf = {};
  final Map<String, Future<FloatPixels?>> _reads = {};
  final Map<String, Future<FloatPixels>> _decodes = {};

  /// Background builds running now, by key: a [load] of the same preview
  /// waits for it instead of decoding the original a second time.
  final Map<String, Future<void>> _builds = {};

  /// Pending background jobs: prefetches first (newest set only), then
  /// warm-ups in request order.
  final List<_Job> _prefetchJobs = [];
  final List<_Job> _warmJobs = [];
  bool _running = false;
  Timer? _trimTimer;
  bool _disposed = false;

  /// Number of decodes of the original this store started (tests,
  /// diagnostics), and of background cache builds.
  int decodes = 0;
  int builds = 0;

  static String _key(String assetId, int w, int h) => '$assetId@${w}x$h';

  /// Previews held in memory, oldest first (tests).
  List<String> get memoryKeys => _memory.keys.toList();

  FloatPixels? _memoryHit(String key) {
    final hit = _memory.remove(key);
    if (hit != null) _memory[key] = hit; // most recently used
    return hit;
  }

  void _remember(String key, FloatPixels px, String? path) {
    _memory.remove(key);
    _memory[key] = px;
    if (path != null) _pathOf[key] = path;
    while (_memory.length > memoryEntries) {
      final old = _memory.keys.first;
      _memory.remove(old);
      _pathOf.remove(old);
    }
  }

  /// The preview from memory or the disk cache, else null. Never decodes.
  Future<FloatPixels?> cached(String assetId, int width, int height) async {
    final key = _key(assetId, width, height);
    final hit = _memoryHit(key);
    if (hit != null) return hit;
    return _reads[key] ??= _readDisk(assetId, width, height, key).whenComplete(
      () {
        // A block body: returning the removed future would make it wait on
        // itself.
        _reads.remove(key);
      },
    );
  }

  Future<FloatPixels?> _readDisk(
    String assetId,
    int width,
    int height,
    String key,
  ) async {
    final path = await cache.pathFor(assetId, width, height);
    if (path == null || !await cache.contains(assetId, width, height)) {
      return null;
    }
    final read = await decoder.readPreview(path, width: width, height: height);
    if (read == null) return null;
    unawaited(cache.touch(path));
    if (!_disposed) _remember(key, read.pixels, path);
    return read.pixels;
  }

  /// The preview of [source] (the file of [assetId]): memory, disk cache,
  /// else a decode that also writes the cache entry. Throws
  /// [FloatSourceException] when the decode fails.
  Future<FloatPixels> load(
    String assetId,
    DecodedFloatSource source,
    int width,
    int height,
  ) async {
    final key = _key(assetId, width, height);
    final building = _builds[key];
    if (building != null) await building;
    final hit = await cached(assetId, width, height);
    if (hit != null) return hit;
    return _decodes[key] ??= _decode(assetId, source, width, height, key)
        .whenComplete(() {
          _decodes.remove(key);
        });
  }

  Future<FloatPixels> _decode(
    String assetId,
    DecodedFloatSource source,
    int width,
    int height,
    String key,
  ) async {
    final path = await cache.pathFor(assetId, width, height);
    decodes++;
    final px = path == null
        ? await source.render(fullWidth: width, fullHeight: height)
        : await source.renderCaching(
            fullWidth: width,
            fullHeight: height,
            cachePath: path,
          );
    if (!_disposed) _remember(key, px, path);
    _scheduleTrim();
    return px;
  }

  /// Fills memory with the previews of [targets] (the filmstrip
  /// neighbours), building missing cache entries first. Replaces the
  /// prefetches still pending from an earlier call.
  void prefetch(List<FloatPreviewTarget> targets) {
    _prefetchJobs
      ..clear()
      ..addAll(targets.take(memoryEntries - 1).map((t) => _Job(t, true)));
    _pump();
  }

  /// Builds missing cache entries of [targets] in the background (after an
  /// import, in idle time). Memory is untouched.
  void warm(List<FloatPreviewTarget> targets) {
    for (final t in targets) {
      if (_warmJobs.any((j) => j.target.key == t.key)) continue;
      _warmJobs.add(_Job(t, false));
    }
    _pump();
  }

  /// Completes when no background job is pending or running (tests,
  /// measurements).
  Future<void> idle() async {
    while (_running || _prefetchJobs.isNotEmpty || _warmJobs.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void _pump() {
    if (_running || _disposed) return;
    final job = _prefetchJobs.isNotEmpty
        ? _prefetchJobs.removeAt(0)
        : (_warmJobs.isNotEmpty ? _warmJobs.removeAt(0) : null);
    if (job == null) return;
    _running = true;
    unawaited(
      _runJob(job).whenComplete(() {
        _running = false;
        _pump();
      }),
    );
  }

  Future<void> _runJob(_Job job) async {
    final t = job.target;
    try {
      final key = _key(t.assetId, t.width, t.height);
      if (job.inMemory && _memory.containsKey(key)) return;
      final path = await cache.pathFor(t.assetId, t.width, t.height);
      if (path == null) return;
      if (!await cache.contains(t.assetId, t.width, t.height)) {
        builds++;
        final build = decoder.buildPreview(
          t.path,
          cachePath: path,
          fullWidth: t.width,
          fullHeight: t.height,
        );
        _builds[t.key] = build;
        final int? bytes;
        try {
          bytes = await build;
        } finally {
          _builds.removeWhere((k, _) => k == t.key);
        }
        if (bytes == null) return;
        _scheduleTrim();
      }
      if (job.inMemory && !_disposed) {
        await cached(t.assetId, t.width, t.height);
      }
    } on Exception catch (e) {
      _log.info('float preview of ${t.assetId} not prepared: $e');
    }
  }

  /// Keeps the folder under its cap a moment after writes settle; the
  /// previews in memory are never evicted.
  void _scheduleTrim() {
    _trimTimer?.cancel();
    _trimTimer = Timer(trimDelay, () {
      if (_disposed) return;
      unawaited(cache.trim(keep: _pathOf.values.toSet()));
    });
  }

  /// Delay between the last write and the size check of the folder.
  static const trimDelay = Duration(seconds: 2);

  /// Drops the previews held in memory.
  void clearMemory() {
    _memory.clear();
    _pathOf.clear();
  }

  void dispose() {
    _disposed = true;
    _trimTimer?.cancel();
    _prefetchJobs.clear();
    _warmJobs.clear();
    clearMemory();
  }
}

/// One photo whose preview should be ready: its asset id, the original's
/// path and the preview size the editor will ask for.
class FloatPreviewTarget {
  const FloatPreviewTarget({
    required this.assetId,
    required this.path,
    required this.width,
    required this.height,
  });

  final String assetId;
  final String path;
  final int width;
  final int height;

  String get key => '$assetId@${width}x$height';
}

class _Job {
  _Job(this.target, this.inMemory);
  final FloatPreviewTarget target;
  final bool inMemory;
}

/// The float source of one catalog photo with the preview store in front:
/// whole-photo renders (the editor preview) come from memory or the disk
/// cache when they can, windows (the export) always from the decoder.
class CachingFloatSource implements FloatSource, PreviewCacheAware {
  CachingFloatSource({
    required this.assetId,
    required this.inner,
    required this.store,
  });

  final String assetId;
  final DecodedFloatSource inner;
  final FloatPreviewStore store;

  @override
  int get width => inner.width;

  @override
  int get height => inner.height;

  @override
  HbdProfile get profile => inner.profile;

  @override
  Future<FloatPixels?> cachedPreview(int width, int height) =>
      store.cached(assetId, width, height);

  @override
  Future<FloatPixels> render({
    required int fullWidth,
    required int fullHeight,
    int x = 0,
    int y = 0,
    int? width,
    int? height,
  }) {
    final whole =
        x == 0 &&
        y == 0 &&
        (width ?? fullWidth) == fullWidth &&
        (height ?? fullHeight) == fullHeight;
    if (whole) return store.load(assetId, inner, fullWidth, fullHeight);
    return inner.render(
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  @override
  Future<void> release() => inner.release();
}
