/// GPU side of the portrait retouch pass R (research 07 §3): map textures,
/// their cache, and the (tiled) pass itself.
///
/// Public API:
/// * `RetouchTextures.upload(RetouchMaps)`: the six map textures (B1, B2,
///   B3 at W×H; Bh, regionA, regionB at 2W×H); `maps`, `dispose()`.
/// * `RetouchMapsCache`: `obtain(maps)` uploads each `RetouchMaps` instance
///   once (identity-keyed) and returns null for null maps or maps without
///   faces. Replaced textures are released after the replacement is ready;
///   `dispose()` releases the current ones. The cache owns the textures.
/// * `runRetouchPass(shaders, source:, textures:, uniforms:, tileSize:)`:
///   pass R over the whole [source] in tiles (one pass when it fits),
///   returning a new source-size image (caller owns), or null when the
///   uniforms change no pixel (`RetouchPassUniforms.isActive`): the caller
///   keeps using the source, bit-exact.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';
import 'shader_library.dart';

class RetouchTextures {
  RetouchTextures._(this.maps, this.images);

  static Future<RetouchTextures> upload(RetouchMaps maps) async {
    final w = maps.width, h = maps.height;
    final images = <ui.Image>[];
    try {
      for (final (bytes, width) in [
        (maps.b1, w),
        (maps.b2, w),
        (maps.b3, w),
        (maps.bh, 2 * w),
        (maps.regionA, 2 * w),
        (maps.regionB, 2 * w),
      ]) {
        images.add(await uploadRgba(bytes, width, h));
      }
    } on Object {
      images.forEach(EngineImages.dispose);
      rethrow;
    }
    return RetouchTextures._(maps, List.unmodifiable(images));
  }

  final RetouchMaps maps;

  /// B1, B2, B3, Bh, regionA, regionB (sampler order of `retouch.frag`).
  final List<ui.Image> images;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    images.forEach(EngineImages.dispose);
  }
}

class RetouchMapsCache {
  RetouchMaps? _maps;
  Future<RetouchTextures?>? _current;
  RetouchTextures? _ready;
  bool _disposed = false;
  int _uploads = 0;

  /// Number of uploads so far (tests, diagnostics).
  int get uploads => _uploads;

  Future<RetouchTextures?> obtain(RetouchMaps? maps) {
    if (_disposed) throw StateError('RetouchMapsCache disposed');
    final current = _current;
    if (current != null && identical(maps, _maps)) return current;
    _maps = maps;
    _ready = null;
    final Future<RetouchTextures?> next;
    if (maps == null || !maps.hasFaces) {
      next = Future.value(null);
    } else {
      _uploads++;
      next = RetouchTextures.upload(maps);
    }
    _current = next;
    next.then((t) {
      if (identical(_current, next)) _ready = t;
    }).ignore();
    if (current != null) {
      next.whenComplete(() => current.then((t) => t?.dispose())).ignore();
    }
    return next;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final ready = _ready;
    if (ready != null) {
      ready.dispose();
    } else {
      _current?.then((t) => t?.dispose()).ignore();
    }
    _current = null;
    _ready = null;
  }
}

/// Runs pass R over [source]; see the library doc.
ui.Image? runRetouchPass(
  ShaderLibrary shaders, {
  required ui.Image source,
  required RetouchTextures textures,
  required RetouchUniforms uniforms,
  int tileSize = 4096,
}) {
  final maps = textures.maps;
  if (!RetouchPassUniforms.isActive(maps, uniforms)) return null;
  final w = source.width, h = source.height;
  ui.Image tile(int x0, int y0, int tw, int th) => runRetouch(
    shaders,
    floats: RetouchPassUniforms.pack(
      maps,
      uniforms,
      width: tw,
      height: th,
      tileX: x0.toDouble(),
      tileY: y0.toDouble(),
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
    ),
    source: source,
    maps: textures.images,
    width: tw,
    height: th,
  );
  if (w <= tileSize && h <= tileSize) return tile(0, 0, w, h);
  // Tiles are composed 1:1 into one source-size image (exact copies).
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  final parts = <ui.Image>[];
  for (var y0 = 0; y0 < h; y0 += tileSize) {
    for (var x0 = 0; x0 < w; x0 += tileSize) {
      final part = tile(
        x0,
        y0,
        math.min(tileSize, w - x0),
        math.min(tileSize, h - y0),
      );
      parts.add(part);
      canvas.drawImage(part, ui.Offset(x0.toDouble(), y0.toDouble()), paint);
    }
  }
  final picture = recorder.endRecording();
  final out = EngineImages.track(picture.toImageSync(w, h));
  picture.dispose();
  parts.forEach(EngineImages.dispose);
  return out;
}
