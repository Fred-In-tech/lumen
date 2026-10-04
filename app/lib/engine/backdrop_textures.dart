/// GPU side of the backdrop changer / background blur (pass B).
///
/// Public API:
/// * `BackdropTextures.upload(BackdropAssets)`: matte, fill, plate A,
///   plate B images (sampler order of `backdrop.frag`); `dispose()`.
/// * `BackdropTexturesCache`: `obtain(assets)` uploads each `BackdropAssets`
///   instance once (identity-keyed), null for null; replaced textures are
///   released after the replacement is ready; `dispose()`.
/// * `runBackdropPass(shaders, source:, textures:, change:, tileSize:)`:
///   pass B over the whole source in tiles, a new source-size image (caller
///   owns), or null when [BackdropChange.isNone] (keep the source).
library;

import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';
import 'shader_library.dart';
import 'swap_cache.dart';

class BackdropTextures {
  BackdropTextures._(this.assets, this.images);

  static Future<BackdropTextures> upload(BackdropAssets a) async {
    final images = <ui.Image>[];
    try {
      for (final t in [a.matte, a.fill, a.plateA, a.plateB]) {
        images.add(await uploadRgba(t.rgba, t.width, t.height));
      }
    } on Object {
      images.forEach(EngineImages.dispose);
      rethrow;
    }
    return BackdropTextures._(a, List.unmodifiable(images));
  }

  final BackdropAssets assets;

  /// Matte, fill, plate A, plate B.
  final List<ui.Image> images;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    images.forEach(EngineImages.dispose);
  }
}

class BackdropTexturesCache {
  final SwapCache<BackdropAssets?, BackdropTextures> _cache = SwapCache(
    same: identical,
    release: (t) => t.dispose(),
  );

  int get uploads => _cache.builds;

  /// Textures of [assets] (uploaded once per instance), null for null.
  Future<BackdropTextures?> obtain(BackdropAssets? assets) => _cache.obtain(
    assets,
    () => assets == null ? Future.value(null) : BackdropTextures.upload(assets),
  );

  void dispose() => _cache.dispose();
}

ui.Image? runBackdropPass(
  ShaderLibrary shaders, {
  required ui.Image source,
  required BackdropTextures textures,
  required BackdropChange change,
  int tileSize = 4096,
}) {
  if (change.isNone) return null;
  final w = source.width, h = source.height;
  return renderTiled(
    w,
    h,
    tileSize,
    (x0, y0, tw, th) => runBackdrop(
      shaders,
      floats: BackdropUniforms.pack(
        textures.assets,
        change,
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
    ),
  );
}
