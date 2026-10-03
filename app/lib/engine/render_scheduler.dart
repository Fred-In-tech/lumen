/// Latest-wins render coalescing for the editor canvas.
///
/// Public API (consumed by the editor notifier / canvas):
/// * `RenderScheduler(FrameRenderer renderer, {settleDelay, dragScale})`
/// * `ValueListenable<ui.Image?> frame`: the latest rendered frame. The
///   scheduler owns every frame image and disposes the previous one when a
///   new frame is published. A consumer that keeps an image beyond the next
///   frame (e.g. `RawImage`, which disposes what it is given) must pass
///   `image.clone()` and dispose the clone itself.
/// * `int generation`: id of the published frame (increments per frame).
/// * `DevelopSettings? settings`: settings of the published frame.
/// * `void update(DevelopSettings s, {bool interactive = false})`: queue a
///   render. Bursts coalesce into one render (latest wins); at most one
///   render is in flight. `interactive: true` (slider drag) renders at
///   [dragScale] and re-renders at full scale [settleDelay] after the last
///   change.
/// * `set showClipping(bool)`: toggles the clipping overlay and re-renders.
/// * `Future<void> idle()`: completes when nothing is pending or in flight.
/// * `Stream<Object> errors`: render failures (the last good frame stays).
/// * `void dispose()`: disposes the current frame and the renderer.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';
import 'render_graph.dart';

class RenderScheduler {
  RenderScheduler(
    this.renderer, {
    this.settleDelay = const Duration(milliseconds: 120),
    this.dragScale = 0.5,
  });

  final FrameRenderer renderer;
  final Duration settleDelay;
  final double dragScale;

  final ValueNotifier<ui.Image?> _frame = ValueNotifier<ui.Image?>(null);
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  DevelopSettings? _latest;
  DevelopSettings? _publishedSettings;
  double _publishedScale = 1;
  bool _pending = false;
  bool _pendingInteractive = false;
  bool _inFlight = false;
  bool _flushScheduled = false;
  bool _showClipping = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _settle;
  final List<Completer<void>> _idleWaiters = [];

  ValueListenable<ui.Image?> get frame => _frame;
  int get generation => _generation;
  DevelopSettings? get settings => _publishedSettings;
  Stream<Object> get errors => _errors.stream;
  bool get showClipping => _showClipping;

  set showClipping(bool value) {
    if (value == _showClipping) return;
    _showClipping = value;
    final s = _latest;
    if (s != null) update(s);
  }

  void update(DevelopSettings s, {bool interactive = false}) {
    if (_disposed) return;
    _latest = s;
    _pending = true;
    _pendingInteractive = interactive;
    _settle?.cancel();
    _settle = null;
    _scheduleFlush();
  }

  Future<void> idle() {
    if (_isIdle) return Future.value();
    final c = Completer<void>();
    _idleWaiters.add(c);
    return c.future;
  }

  bool get _isIdle =>
      !_pending && !_inFlight && !_flushScheduled && _settle == null;

  void _scheduleFlush() {
    if (_flushScheduled || _inFlight) return;
    _flushScheduled = true;
    Timer.run(_flush);
  }

  Future<void> _flush() async {
    _flushScheduled = false;
    final s = _latest;
    if (_disposed || !_pending || s == null) return _notifyIdle();
    final interactive = _pendingInteractive;
    final scale = interactive ? dragScale : 1.0;
    _pending = false;
    _inFlight = true;
    try {
      final image = await renderer.render(
        s,
        scale: scale,
        showClipping: _showClipping,
      );
      _publish(image, s, scale);
    } on Object catch (e) {
      if (!_disposed) _errors.add(e);
    } finally {
      _inFlight = false;
    }
    if (_disposed) return;
    if (_pending) {
      _scheduleFlush();
    } else if (interactive) {
      _settle = Timer(settleDelay, _onSettled);
    } else {
      _notifyIdle();
    }
  }

  void _onSettled() {
    _settle = null;
    final s = _latest;
    if (_disposed || s == null) return;
    if (_publishedScale != 1 || _publishedSettings != s) {
      update(s);
    } else {
      _notifyIdle();
    }
  }

  void _publish(ui.Image image, DevelopSettings s, double scale) {
    if (_disposed) {
      EngineImages.dispose(image);
      return;
    }
    final old = _frame.value;
    _generation++;
    _publishedSettings = s;
    _publishedScale = scale;
    _frame.value = image;
    EngineImages.dispose(old);
  }

  void _notifyIdle() {
    if (!_isIdle) return;
    for (final c in _idleWaiters) {
      c.complete();
    }
    _idleWaiters.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _settle?.cancel();
    _settle = null;
    final img = _frame.value;
    _frame.value = null;
    EngineImages.dispose(img);
    _frame.dispose();
    renderer.dispose();
    unawaited(_errors.close());
    for (final c in _idleWaiters) {
      c.complete();
    }
    _idleWaiters.clear();
  }
}
