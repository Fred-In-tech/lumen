/// Mask coverage atlases on the GPU, rebuilt only when coverage changes.
///
/// Public API:
/// * `MaskAtlasTextures.upload(MaskAtlases)`, `MaskAtlasTextures.empty()`:
///   `atlas0` (masks 0–3), `atlas1` (masks 4–7), `atlases` (CPU data, for
///   the CPU reference and overlays), `dispose()`. Unused atlases are the
///   shared 1×1 `emptyMaskAtlas`.
/// * `MaskAtlasCache({sourceWidth, sourceHeight})`: `obtain(masks)` returns
///   the atlases for the first 8 masks, rasterizing (on the CPU, at ≤ 1024
///   px) only when a mask's coverage changes (shape, strokes, invert,
///   opacity, kind) or its AI raster changes; adjustment-only edits reuse the
///   cached textures (adjustments are uniforms). `rasters` maps `maskRef` →
///   decoded AI coverage; assign a new map to update them. The cache owns
///   the textures: never dispose what `obtain` returns. Replaced textures
///   are released asynchronously once their replacement is ready (a render
///   that already obtained them may still be drawing).
library;

import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';

class MaskAtlasTextures {
  MaskAtlasTextures._(this.atlases, this.atlas0, this.atlas1, this._owned);

  factory MaskAtlasTextures.empty() => MaskAtlasTextures._(
    MaskAtlases.empty(),
    emptyMaskAtlas,
    emptyMaskAtlas,
    const [],
  );

  static Future<MaskAtlasTextures> upload(MaskAtlases a) async {
    if (a.count == 0) return MaskAtlasTextures.empty();
    final w = 2 * a.width;
    final i0 = await uploadRgba(a.atlasRgba(0), w, a.height);
    if (a.count <= 4) return MaskAtlasTextures._(a, i0, emptyMaskAtlas, [i0]);
    final i1 = await uploadRgba(a.atlasRgba(1), w, a.height);
    return MaskAtlasTextures._(a, i0, i1, [i0, i1]);
  }

  final MaskAtlases atlases;
  final ui.Image atlas0;
  final ui.Image atlas1;
  final List<ui.Image> _owned;
  bool _disposed = false;

  int get width => atlases.width;
  int get height => atlases.height;
  int get count => atlases.count;

  /// The atlas image holding mask [index].
  ui.Image atlasFor(int index) => index < 4 ? atlas0 : atlas1;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _owned.forEach(EngineImages.dispose);
  }
}

class MaskAtlasCache {
  MaskAtlasCache({
    required this.sourceWidth,
    required this.sourceHeight,
    this.longEdge = kMaskLongEdge,
  });

  final int sourceWidth;
  final int sourceHeight;
  final int longEdge;

  Map<String, MaskRaster> _rasters = const {};
  List<int>? _key;
  Future<MaskAtlasTextures>? _current;
  MaskAtlasTextures? _ready; // resolved value of [_current]
  int _builds = 0;
  bool _disposed = false;

  /// Number of rasterizations so far (for tests and diagnostics).
  int get builds => _builds;

  Map<String, MaskRaster> get rasters => _rasters;

  set rasters(Map<String, MaskRaster> value) =>
      _rasters = Map.unmodifiable(value);

  Future<MaskAtlasTextures> obtain(List<LocalMask> masks) {
    if (_disposed) throw StateError('MaskAtlasCache disposed');
    final used = masks.take(kMaxRenderedMasks).toList(growable: false);
    final key = [
      for (final m in used) ...[
        m.coverageKey,
        if (m.kind.isAi) identityHashCode(_rasters[m.ai.maskRef]),
      ],
    ];
    final current = _current;
    if (current != null && const ListEquality<int>().equals(key, _key)) {
      return current;
    }
    _key = key;
    final rasters = _rasters;
    final next = used.isEmpty
        ? Future.value(MaskAtlasTextures.empty())
        : _build(used, rasters);
    _current = next;
    _ready = null;
    next.then((t) {
      if (identical(_current, next)) _ready = t;
    }).ignore();
    if (current != null) {
      next.whenComplete(() => current.then((t) => t.dispose())).ignore();
    }
    return next;
  }

  Future<MaskAtlasTextures> _build(
    List<LocalMask> masks,
    Map<String, MaskRaster> rasters,
  ) {
    _builds++;
    final atlases = MaskRasterizer.build(
      masks,
      sourceWidth,
      sourceHeight,
      rasters: rasters,
      longEdge: longEdge,
    );
    return MaskAtlasTextures.upload(atlases);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final ready = _ready;
    if (ready != null) {
      ready.dispose(); // synchronous when already built
    } else {
      _current?.then((t) => t.dispose()).ignore();
    }
    _current = null;
    _ready = null;
  }
}
