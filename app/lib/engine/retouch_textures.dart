/// GPU side of the portrait retouch pass R (research 07 §3): map textures,
/// their cache, and the (tiled) pass itself.
///
/// Public API:
/// * `RetouchTextures.upload(RetouchMaps)`: the seven map textures (low
///   at W×H; deltaA, deltaB, deltaC, regionA, regionB at 2W×H; the
///   backdrop atlas at 3W'×2H'); `maps`, `dispose()`.
/// * `RetouchMapsCache`: `obtain(maps)` uploads each `RetouchMaps` instance
///   once (identity-keyed) and returns null for null maps or maps with
///   no faces and no ready backdrop / clothes (`RetouchMaps.isUsable`).
///   Replaced textures are released after the replacement is ready;
///   `dispose()` releases the current ones. The cache owns the textures.
/// * `runRetouchPass(shaders, source:, textures:, uniforms:, tileSize:)`:
///   pass R over the whole [source] in tiles (one pass when it fits),
///   returning a new source-size image (caller owns), or null when the
///   uniforms change no pixel (`RetouchPassUniforms.isActive`): the caller
///   keeps using the source, bit-exact. `float: true` renders into a
///   float32 image (float sources); `window:` says [source] is a window of
///   the full source (float export): one pass over the window, maps sampled
///   at the full-source uv.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';
import 'shader_library.dart';

class RetouchTextures {
  RetouchTextures._(this.maps, this.images)
    : _given = List.filled(images.length, false);

  /// Uploads [maps]. Textures of [reuse] whose bytes are the very same
  /// arrays (e.g. after a Manual Tuning Pen edit, which only replaces the
  /// region atlases) move into the result instead of being uploaded again;
  /// [reuse] then no longer disposes them.
  static Future<RetouchTextures> upload(
    RetouchMaps maps, {
    RetouchTextures? reuse,
  }) async {
    final w = maps.width, h = maps.height;
    final slots = _slots(maps, w, h);
    final donor = reuse == null || reuse._disposed
        ? null
        : _slots(reuse.maps, reuse.maps.width, reuse.maps.height);
    // Claim reusable images up front, so the donor's disposal (after this
    // upload completes, or earlier) cannot release them.
    final taken = List<ui.Image?>.filled(slots.length, null);
    for (var i = 0; i < slots.length; i++) {
      if (donor != null && identical(donor[i].$1, slots[i].$1)) {
        taken[i] = reuse!.images[i];
        reuse._given[i] = true;
      }
    }
    final images = <ui.Image>[];
    try {
      for (var i = 0; i < slots.length; i++) {
        final (bytes, width, height) = slots[i];
        images.add(taken[i] ?? await uploadRgba(bytes, width, height));
      }
    } on Object {
      // Give claimed images back to the donor; drop what was uploaded.
      for (var i = 0; i < taken.length; i++) {
        if (taken[i] != null) reuse!._given[i] = false;
      }
      for (var i = 0; i < images.length; i++) {
        if (taken[i] == null) EngineImages.dispose(images[i]);
      }
      rethrow;
    }
    return RetouchTextures._(maps, List.unmodifiable(images));
  }

  static List<(Uint8List, int, int)> _slots(RetouchMaps m, int w, int h) => [
    (m.low, w, h),
    (m.deltaA, 2 * w, h),
    (m.deltaB, 2 * w, h),
    (m.deltaC, 2 * w, h),
    (m.regionA, 2 * w, h),
    (m.regionB, 2 * w, h),
    (
      m.backdrop.atlas,
      kImageAtlasColumns * m.backdrop.width,
      kImageAtlasRows * m.backdrop.height,
    ),
  ];

  final RetouchMaps maps;

  /// low, deltaA, deltaB, deltaC, regionA, regionB, backdrop (sampler order of
  /// `retouch.frag`).
  final List<ui.Image> images;

  /// Images handed on to newer textures (not disposed here).
  final List<bool> _given;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (var i = 0; i < images.length; i++) {
      if (!_given[i]) EngineImages.dispose(images[i]);
    }
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
    final donor = _ready;
    _ready = null;
    final Future<RetouchTextures?> next;
    if (maps == null || !maps.isUsable) {
      next = Future.value(null);
    } else {
      _uploads++;
      next = RetouchTextures.upload(maps, reuse: donor);
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
  bool float = false,
  SourceWindow? window,
}) {
  final maps = textures.maps;
  if (!RetouchPassUniforms.isActive(maps, uniforms)) return null;
  final w = source.width, h = source.height;
  if (window != null) {
    return runRetouch(
      shaders,
      floats: RetouchPassUniforms.pack(
        maps,
        uniforms,
        width: w,
        height: h,
        tileX: window.x.toDouble(),
        tileY: window.y.toDouble(),
        fullWidth: window.fullWidth.toDouble(),
        fullHeight: window.fullHeight.toDouble(),
        sourceIsWindow: true,
      ),
      source: source,
      maps: textures.images,
      width: w,
      height: h,
      float: float,
    );
  }
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
    float: float,
  );
  // Tiles are composed 1:1 into one source-size image (exact copies).
  return renderTiled(w, h, tileSize, tile, float: float);
}
