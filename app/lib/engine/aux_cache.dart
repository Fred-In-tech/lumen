/// Per-photo spatial analysis textures (clarity base, guided-filter
/// coefficients, dark channel) for `develop.frag`.
///
/// Computed once per photo, on the CPU (`lumen_core` `AuxMaps`), from a
/// ≤ 512-px GPU downscale of the unedited source, then uploaded as two packed
/// RGBA8888 textures. They live in source-uv space, so geometry edits and
/// export tiles reuse them unchanged (resolution independent).
///
/// Public API:
/// * `AuxTextures.build(source, {float})` / `AuxTextures.fromMaps(maps)`.
///   With `float: true` the proxy is read back in float and the maps come
///   from `AuxMaps.computeFloat`, so highlights above white are in the
///   guided base and the clarity base (float sources).
/// * `AuxTextures.auxA`, `auxB`, `maps`, `dispose()`.
/// * `AuxCache.obtain(assetId, source)` → cached `AuxTextures` per
///   (assetId, source size); `evict(assetId)`, `dispose()`. The cache owns
///   the textures: never dispose an `AuxTextures` obtained from it.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';

class AuxTextures {
  AuxTextures._(this.maps, this.auxA, this.auxB);

  static Future<AuxTextures> fromMaps(AuxMaps maps) async {
    final a = await uploadRgba(maps.auxA, maps.width, maps.height);
    final b = await uploadRgba(maps.auxB, maps.width, maps.height);
    return AuxTextures._(maps, a, b);
  }

  /// Downscales [source] on the GPU and computes the maps off the UI isolate.
  /// [float]: [source] is a float image; the maps keep its extended range.
  static Future<AuxTextures> build(
    ui.Image source, {
    bool float = false,
  }) async {
    if (float) {
      final proxy = await _floatProxy(source);
      return fromMaps(await compute(_computeFloatMaps, proxy));
    }
    final proxy = await _proxy(source);
    final maps = await compute(_computeMaps, proxy);
    return fromMaps(maps);
  }

  /// The maps of float pixels that already are analysis-size (the native
  /// decoder renders the proxy of an export directly).
  static Future<AuxTextures> fromFloatProxy(FloatBuffer proxy) async =>
      fromMaps(await compute(_computeFloatMaps, proxy));

  final AuxMaps maps;
  final ui.Image auxA;
  final ui.Image auxB;

  int get width => maps.width;
  int get height => maps.height;

  void dispose() {
    EngineImages.dispose(auxA);
    EngineImages.dispose(auxB);
  }
}

AuxMaps _computeMaps(RgbaBuffer proxy) => AuxMaps.compute(proxy);

AuxMaps _computeFloatMaps(FloatBuffer proxy) =>
    AuxMaps.computeFloat(AuxMaps.proxyFloat(proxy));

({int width, int height}) _proxySize(ui.Image source) {
  final le = math.max(source.width, source.height);
  final scale = math.min(1.0, kAnalysisLongEdge / le);
  return (
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
  );
}

Future<FloatBuffer> _floatProxy(ui.Image source) async {
  final size = _proxySize(source);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, size.width.toDouble(), size.height.toDouble()),
    ui.Paint()
      ..blendMode = ui.BlendMode.src
      ..filterQuality = ui.FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final img = picture.toImageSync(
    size.width,
    size.height,
    targetFormat: kFloatTarget,
  );
  picture.dispose();
  try {
    return FloatBuffer(size.width, size.height, await readFloat(img));
  } finally {
    img.dispose();
  }
}

Future<RgbaBuffer> _proxy(ui.Image source) async {
  final le = math.max(source.width, source.height);
  final scale = math.min(1.0, kAnalysisLongEdge / le);
  final w = math.max(1, (source.width * scale).round());
  final h = math.max(1, (source.height * scale).round());
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final img = await picture.toImage(w, h);
  picture.dispose();
  try {
    return RgbaBuffer(w, h, await readRgba(img));
  } finally {
    img.dispose();
  }
}

class AuxCache {
  final Map<String, (int, int, Future<AuxTextures>)> _entries = {};

  /// Aux textures for [assetId] built from [source]; rebuilt if the source
  /// size changed. Concurrent calls share one build.
  Future<AuxTextures> obtain(String assetId, ui.Image source) {
    final e = _entries[assetId];
    if (e != null && e.$1 == source.width && e.$2 == source.height) {
      return e.$3;
    }
    evict(assetId);
    final future = AuxTextures.build(source);
    _entries[assetId] = (source.width, source.height, future);
    return future;
  }

  bool contains(String assetId) => _entries.containsKey(assetId);

  void evict(String assetId) {
    final e = _entries.remove(assetId);
    if (e != null) _disposeLater(e.$3);
  }

  void dispose() {
    for (final e in _entries.values) {
      _disposeLater(e.$3);
    }
    _entries.clear();
  }

  static void _disposeLater(Future<AuxTextures> f) {
    f.then((t) => t.dispose(), onError: (Object _) {}).ignore();
  }
}
