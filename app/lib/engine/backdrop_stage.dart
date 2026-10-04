/// Pass B (backdrop composite) in the render graph and the export.
///
/// Public API:
/// * `BackdropStage(shaders)`: `assets` (settable) are the photo's current
///   `BackdropAssets` (from `BackdropService`), null = off.
///   - `prepare(settings)` → `BackdropFrame?`: uploads the textures and,
///     when develop uses spatial maps (`needsAuxMaps`), builds the aux
///     textures of the composite (off the UI isolate). Null when the pass is
///     off or the assets cannot stand in for the change yet.
///   - `composite(change, upstream, frame)` → the source for develop: pass
///     B over [upstream], cached by change + textures + upstream identity;
///     [upstream] itself when [frame] is null.
///   - `runs`, `textures.uploads`, `auxBuilds`; `release()` drops the
///     cached output; `dispose()`.
/// * `exportBackdrop(shaders, source:, settings:, assets:, tileSize:)`:
///   full-resolution pass B in tiles plus the composite's aux textures when
///   needed; null when off. The caller owns both results.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:lumen_core/lumen_core.dart';

import 'aux_cache.dart';
import 'backdrop_textures.dart';
import 'gpu_pass.dart';
import 'shader_library.dart';
import 'swap_cache.dart';

typedef BackdropFrame = ({BackdropTextures textures, AuxTextures? aux});

AuxMaps _auxMaps((BackdropAssets, BackdropChange) r) =>
    backdropAuxMaps(r.$1, r.$2);

/// Aux textures of the composite of [b] (built in an isolate).
Future<AuxTextures> backdropAuxTextures(
  BackdropAssets a,
  BackdropChange b,
) async => AuxTextures.fromMaps(await compute(_auxMaps, (a, b)));

class BackdropStage {
  BackdropStage(this.shaders);

  final ShaderLibrary shaders;

  /// Uploaded textures of [assets] (owned).
  final BackdropTexturesCache textures = BackdropTexturesCache();
  final SwapCache<(BackdropAssets, BackdropChange), AuxTextures> _aux =
      SwapCache(
        same: (x, y) => identical(x.$1, y.$1) && x.$2 == y.$2,
        release: (t) => t.dispose(),
      );

  BackdropAssets? assets;
  ui.Image? _out;
  ui.Image? _upstream;
  BackdropTextures? _textures;
  BackdropChange? _change;
  int _runs = 0;

  /// Number of times pass B actually ran (cache diagnostics, tests).
  int get runs => _runs;

  /// Number of composite aux builds.
  int get auxBuilds => _aux.builds;

  Future<BackdropFrame?> prepare(DevelopSettings s) async {
    final a = assets, b = s.backdrop;
    if (a == null || !a.canRender(b)) return null;
    final t = await textures.obtain(a);
    if (t == null) return null;
    final aux = needsAuxMaps(s)
        ? await _aux.obtain((a, b), () => backdropAuxTextures(a, b))
        : null;
    return (textures: t, aux: aux);
  }

  ui.Image composite(
    BackdropChange b,
    ui.Image upstream,
    BackdropFrame? frame,
  ) {
    if (frame == null) {
      release();
      return upstream;
    }
    final cached = _out;
    if (cached != null &&
        identical(upstream, _upstream) &&
        identical(frame.textures, _textures) &&
        b == _change) {
      return cached;
    }
    // Frames already recorded keep the previous output alive.
    release();
    final out = runBackdropPass(
      shaders,
      source: upstream,
      textures: frame.textures,
      change: b,
    );
    if (out == null) return upstream;
    _runs++;
    _upstream = upstream;
    _textures = frame.textures;
    _change = b;
    return _out = out;
  }

  void release() {
    EngineImages.dispose(_out);
    _out = null;
    _upstream = null;
    _textures = null;
    _change = null;
  }

  void dispose() {
    release();
    textures.dispose();
    _aux.dispose();
  }
}

Future<({ui.Image image, AuxTextures? aux})?> exportBackdrop(
  ShaderLibrary shaders, {
  required ui.Image source,
  required DevelopSettings settings,
  required BackdropAssets? assets,
  int tileSize = 2048,
}) async {
  final b = settings.backdrop;
  if (assets == null || !assets.canRender(b)) return null;
  final t = await BackdropTextures.upload(assets);
  final ui.Image? out;
  try {
    out = runBackdropPass(
      shaders,
      source: source,
      textures: t,
      change: b,
      tileSize: tileSize,
    );
  } finally {
    t.dispose();
  }
  if (out == null) return null;
  try {
    final aux = needsAuxMaps(settings)
        ? await backdropAuxTextures(assets, b)
        : null;
    return (image: out, aux: aux);
  } on Object {
    EngineImages.dispose(out);
    rethrow;
  }
}
