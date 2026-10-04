/// GPU side of the warp field (face reshape + liquify).
///
/// Public API:
/// * `WarpTexture.upload(WarpField)`: the `(2w)×h` packed atlas sampled by
///   `develop.frag` and `mask_overlay.frag` (`FilterQuality.none`, manual
///   bilinear); `field`, `image`, `dispose()`.
/// * `WarpFieldCache`: `obtain(field)` uploads each `WarpField` instance
///   once (identity-keyed) and returns null for null or identity fields
///   (the warp is then skipped, bit-exact). Replaced textures are released
///   after the replacement is ready; `dispose()` releases the current one.
library;

import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';

class WarpTexture {
  WarpTexture._(this.field, this.image);

  static Future<WarpTexture> upload(WarpField field) async => WarpTexture._(
    field,
    await uploadRgba(field.packRgba(), 2 * field.width, field.height),
  );

  final WarpField field;
  final ui.Image image;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    EngineImages.dispose(image);
  }
}

class WarpFieldCache {
  WarpField? _field;
  Future<WarpTexture?>? _current;
  WarpTexture? _ready;
  bool _disposed = false;
  int _uploads = 0;

  /// Number of uploads so far (tests, diagnostics).
  int get uploads => _uploads;

  Future<WarpTexture?> obtain(WarpField? field) {
    if (_disposed) throw StateError('WarpFieldCache disposed');
    final current = _current;
    if (current != null && identical(field, _field)) return current;
    _field = field;
    _ready = null;
    final Future<WarpTexture?> next;
    if (field == null || field.isIdentity) {
      next = Future.value(null);
    } else {
      _uploads++;
      next = WarpTexture.upload(field);
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
