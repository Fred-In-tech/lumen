/// Creative LUTs for the renderers.
///
/// Public API:
/// * `CreativeLuts`: process-wide lookup of LUT data by content hash
///   (`configure(loader)` at startup with the LUT library, `remember(lut)`
///   after an import, `resolve(hash)`). Every renderer (preview graph,
///   export, CPU fallback, thumbnails, look previews) asks it, so an edit
///   renders the same everywhere; a hash it cannot find resolves to null and
///   the photo renders without the LUT (an edit opened on another machine).
/// * `CreativeLutCache`: one uploaded LUT atlas (owned by a graph or an
///   export); `obtain(settings.lut)` → `CreativeLutTexture?`.
library;

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';

final _log = Logger('CreativeLuts');

/// Loads stored LUT data by content hash (null when unknown).
typedef CreativeLutLoader = Future<CubeLut?> Function(String hash);

abstract final class CreativeLuts {
  static CreativeLutLoader? _loader;

  /// Recently used LUTs, most recent last (a few MB each at most).
  static final LinkedHashMap<String, CubeLut> _memory = LinkedHashMap();
  static const int _keep = 6;

  /// Sets where LUT data comes from (the LUT library on disk).
  static void configure(CreativeLutLoader? loader) => _loader = loader;

  /// Makes [lut] available at once (just imported, or a test fixture).
  static void remember(CubeLut lut) {
    _memory
      ..remove(lut.contentHash)
      ..[lut.contentHash] = lut;
    while (_memory.length > _keep) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// A LUT already in memory, without loading.
  static CubeLut? cached(String hash) => _memory[hash];

  /// The LUT with [hash], or null when it is not in the library.
  static Future<CubeLut?> resolve(String hash) async {
    final hit = _memory[hash];
    if (hit != null) {
      remember(hit);
      return hit;
    }
    final loader = _loader;
    if (loader == null) return null;
    try {
      final lut = await loader(hash);
      if (lut == null) return null;
      if (lut.contentHash != hash) {
        _log.warning('LUT $hash: stored data has another hash; ignored');
        return null;
      }
      remember(lut);
      return lut;
    } on Exception catch (e) {
      _log.warning('LUT $hash could not be loaded: $e');
      return null;
    }
  }

  /// The LUT [settings] use, when it is available (CPU renders).
  static Future<CubeLut?> forSettings(DevelopSettings settings) async {
    final ref = settings.lut;
    if (ref == null || ref.amount <= 0) return null;
    return resolve(ref.hash);
  }

  /// Forgets everything (tests).
  static void reset() {
    _memory.clear();
    _loader = null;
  }
}

/// An uploaded LUT atlas (2N × N², see `CubeLut.toAtlasRgba`).
class CreativeLutTexture {
  CreativeLutTexture._(this.image, this.lut);

  static Future<CreativeLutTexture> upload(CubeLut lut) async {
    final image = await uploadRgba(
      lut.toAtlasRgba(),
      lut.atlasWidth,
      lut.atlasHeight,
    );
    return CreativeLutTexture._(image, lut);
  }

  final ui.Image image;
  final CubeLut lut;

  String get hash => lut.contentHash;

  /// Grid size N (`DevelopContext.lutSize`).
  int get size => lut.size;

  void dispose() => EngineImages.dispose(image);
}

/// Keeps the atlas of the last LUT used (one per graph / export).
class CreativeLutCache {
  CreativeLutTexture? _current;
  bool _disposed = false;

  /// The texture for [ref], or null (no LUT, amount 0, LUT missing).
  Future<CreativeLutTexture?> obtain(LutRef? ref) async {
    if (ref == null || ref.amount <= 0) return null;
    final current = _current;
    if (current != null && current.hash == ref.hash) return current;
    final lut = await CreativeLuts.resolve(ref.hash);
    if (lut == null || _disposed) return null;
    final again = _current;
    if (again != null && again.hash == ref.hash) return again;
    final fresh = await CreativeLutTexture.upload(lut);
    if (_disposed) {
      fresh.dispose();
      return null;
    }
    // Frames already recorded keep the old texture alive in the engine.
    _current?.dispose();
    return _current = fresh;
  }

  void dispose() {
    _disposed = true;
    _current?.dispose();
    _current = null;
  }
}
