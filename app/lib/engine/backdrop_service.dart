/// Keeps the backdrop textures of the open photo in step with its settings.
///
/// Public API:
/// * `BackdropService({preview, onAssets, debounce, buildBase, buildAssets})`
///   - `preview()` reads the preview pixels the matte is refined against
///     (called once, when a backdrop is first needed).
///   - `onAssets(BackdropAssets?)` receives every new value (set it on the
///     `RenderGraph` and re-render). Null = pass off.
/// * `setInputs({people, hair, image})`: the subject rasters (AI person and
///   hair planes, any resolution) and the decoded backdrop image (image
///   mode). New rasters rebuild the matte (per photo, in an isolate; the
///   old textures stay published meanwhile); a new image rebuilds
///   image-mode textures. Without rasters the pass is off.
/// * `update(BackdropChange)`: call on every settings change.
///   - Off (or no rasters): publishes null at once.
///   - Colours, gradient, fit, spill and match are uniforms: nothing to do.
///   - Edge shift/feather and blur amount rebuild the textures off the UI
///     isolate, throttled to one build per [debounce] (80 ms) while a
///     slider moves; the previous textures stay published meanwhile. A mode
///     the published textures cannot draw (blur, image) builds at once.
/// * `assets`: the last published value; `assetsFor(change)`: exact
///   textures for any change (export), null when off.
/// * `baseBuilds`, `assetBuilds` (diagnostics); `dispose()`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:lumen_core/lumen_core.dart';

typedef BackdropBaseRequest = ({
  RgbaBuffer source,
  MaskRaster? people,
  MaskRaster? hair,
});
typedef BackdropAssetsRequest = ({
  BackdropBase base,
  BackdropChange change,
  RgbaBuffer? image,
});
typedef BackdropBaseBuild = Future<BackdropBase> Function(
  BackdropBaseRequest r,
);
typedef BackdropAssetsBuild = Future<BackdropAssets> Function(
  BackdropAssetsRequest r,
);

BackdropBase _buildBaseSync(BackdropBaseRequest r) =>
    BackdropBase.build(r.source, people: r.people, hair: r.hair);

BackdropAssets _buildAssetsSync(BackdropAssetsRequest r) =>
    BackdropAssets.build(r.base, r.change, image: r.image);

class BackdropService {
  BackdropService({
    required this.preview,
    required this.onAssets,
    this.debounce = const Duration(milliseconds: 80),
    BackdropBaseBuild? buildBase,
    BackdropAssetsBuild? buildAssets,
  }) : _buildBase = buildBase ?? ((r) => compute(_buildBaseSync, r)),
       _buildAssets = buildAssets ?? ((r) => compute(_buildAssetsSync, r));

  final Future<RgbaBuffer> Function() preview;
  final void Function(BackdropAssets? assets) onAssets;
  final Duration debounce;
  final BackdropBaseBuild _buildBase;
  final BackdropAssetsBuild _buildAssets;

  MaskRaster? _people;
  MaskRaster? _hair;
  RgbaBuffer? _image;
  Future<RgbaBuffer>? _preview;
  Future<BackdropBase>? _base;
  BackdropBase? _baseValue;
  BackdropAssets? _published;
  BackdropChange? _last;
  Timer? _timer;
  int _gen = 0;
  int _baseBuilds = 0;
  int _assetBuilds = 0;
  bool _disposed = false;

  BackdropAssets? get assets => _published;
  int get baseBuilds => _baseBuilds;
  int get assetBuilds => _assetBuilds;
  bool get _hasRasters => _people != null || _hair != null;

  void setInputs({MaskRaster? people, MaskRaster? hair, RgbaBuffer? image}) {
    if (!identical(people, _people) || !identical(hair, _hair)) {
      _people = people;
      _hair = hair;
      _base = null;
      _baseValue = null;
      _cancel();
    }
    if (!identical(image, _image)) _image = image;
    final last = _last;
    if (last != null) update(last);
  }

  void update(BackdropChange b) {
    if (_disposed) return;
    _last = b;
    if (b.isNone || !_hasRasters) {
      _cancel();
      _publish(null);
      return;
    }
    final current = _published;
    final sameMatte = current != null && identical(current.base, _baseValue);
    if (sameMatte && current.fits(b, _image)) {
      _cancel();
      return;
    }
    if (_timer != null) return; // a build is coming; it re-checks _last
    _schedule(sameMatte && current.canRender(b) ? debounce : Duration.zero);
  }

  /// Exact textures for [b] (export); null when off or without rasters.
  Future<BackdropAssets?> assetsFor(BackdropChange b) async {
    if (b.isNone || !_hasRasters) return null;
    final current = _published;
    if (current != null &&
        identical(current.base, _baseValue) &&
        current.fits(b, _image)) {
      return current;
    }
    return _build(b);
  }

  Future<BackdropAssets> _build(BackdropChange b) async {
    final image = _image;
    final pending = _base ??= _newBase();
    final BackdropBase base;
    try {
      base = await pending;
    } on Object {
      if (identical(_base, pending)) _base = null; // retry next time
      rethrow;
    }
    if (identical(_base, pending)) _baseValue = base;
    _assetBuilds++;
    return _buildAssets((base: base, change: b, image: image));
  }

  Future<BackdropBase> _newBase() async {
    final people = _people, hair = _hair;
    final pending = _preview ??= preview();
    final RgbaBuffer src;
    try {
      src = await pending;
    } on Object {
      if (identical(_preview, pending)) _preview = null;
      rethrow;
    }
    _baseBuilds++;
    return _buildBase((source: src, people: people, hair: hair));
  }

  void _schedule(Duration delay) {
    _cancel();
    final gen = ++_gen;
    _timer = Timer(delay, () => unawaited(_rebuild(gen)));
  }

  Future<void> _rebuild(int gen) async {
    final b = _last;
    if (b == null) return;
    final BackdropAssets a;
    try {
      a = await _build(b);
    } finally {
      if (gen == _gen) _timer = null;
    }
    if (_disposed || gen != _gen) return;
    _publish(a);
    final last = _last;
    if (last != null && last != b) update(last);
  }

  void _publish(BackdropAssets? a) {
    if (identical(a, _published)) return;
    _published = a;
    onAssets(a);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _gen++;
  }

  void dispose() {
    _disposed = true;
    _cancel();
  }
}
