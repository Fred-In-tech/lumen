/// Histogram of the rendered frame, throttled (default 10 Hz).
///
/// Public API:
/// * `HistogramService({Duration interval, measure})`
/// * `void submit(ui.Image frame)`: the service clones [frame] (the caller
///   keeps ownership of its own handle). Leading-edge measurement, then at
///   most one per `interval`; the latest submitted frame always wins.
/// * `Stream<Histogram> histograms` (broadcast), `Histogram? latest`.
/// * `static Future<Histogram> measure(ui.Image, {int width = 256})`:
///   draws the frame into a ≤ 256-px-wide picture (`FilterQuality.medium`),
///   reads it back and bins it with `lumen_core` `Histogram.compute`.
/// * `void dispose()`.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:lumen_core/lumen_core.dart';

import 'gpu_pass.dart';

typedef HistogramMeasure = Future<Histogram> Function(ui.Image frame);

class HistogramService {
  HistogramService({
    this.interval = const Duration(milliseconds: 100),
    HistogramMeasure? measure,
  }) : _measure = measure ?? HistogramService.measure;

  final Duration interval;
  final HistogramMeasure _measure;
  final StreamController<Histogram> _out =
      StreamController<Histogram>.broadcast();

  ui.Image? _queued;
  bool _busy = false;
  bool _cooling = false;
  bool _disposed = false;
  Timer? _cooldown;
  Histogram? _latest;

  Stream<Histogram> get histograms => _out.stream;
  Histogram? get latest => _latest;

  void submit(ui.Image frame) {
    if (_disposed) return;
    _queued?.dispose();
    _queued = frame.clone();
    _pump();
  }

  void _pump() {
    final img = _queued;
    if (_disposed || _busy || _cooling || img == null) return;
    _queued = null;
    _busy = true;
    _cooling = true;
    _cooldown = Timer(interval, () {
      _cooling = false;
      _pump();
    });
    _measure(img)
        .then(
          (h) {
            if (_disposed) return;
            _latest = h;
            _out.add(h);
          },
          onError: (Object e, StackTrace st) {
            if (!_disposed) _out.addError(e, st);
          },
        )
        .whenComplete(() {
          img.dispose();
          _busy = false;
          _pump();
        })
        .ignore();
  }

  static Future<Histogram> measure(ui.Image frame, {int width = 256}) async {
    final w = math.min(width, frame.width);
    final h = math.max(1, (frame.height * w / frame.width).round());
    if (w == frame.width && h == frame.height) {
      return Histogram.compute(RgbaBuffer(w, h, await readRgba(frame)));
    }
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      frame,
      ui.Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final small = await picture.toImage(w, h);
    picture.dispose();
    try {
      return Histogram.compute(RgbaBuffer(w, h, await readRgba(small)));
    } finally {
      small.dispose();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cooldown?.cancel();
    _queued?.dispose();
    _queued = null;
    unawaited(_out.close());
  }
}
