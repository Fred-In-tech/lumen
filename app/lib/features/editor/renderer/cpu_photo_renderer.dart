import 'dart:async';

import 'package:lumen/platform/background.dart';

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/import/photo_decoder.dart';

/// Reference-pipeline renderer: correct everywhere, slower than the GPU path.
class CpuPhotoRenderer
    implements
        PhotoRenderer,
        MaskOverlayRenderer,
        MaskRasterSink,
        RetouchSink,
        HealSink {
  CpuPhotoRenderer({
    this.previewLongEdge = 1280,
    this.interactiveLongEdge = 640,
  });

  final int previewLongEdge;
  final int interactiveLongEdge;
  final ValueNotifier<ui.Image?> _output = ValueNotifier(null);
  ui.Image? _before;
  RgbaBuffer? _preview;
  RgbaBuffer? _small;
  RgbaBuffer? _proxy;
  DevelopSettings? _pending;
  bool _pendingInteractive = false;
  bool _busy = false;
  bool _disposed = false;
  Timer? _settle;
  Map<String, MaskRaster> _rasters = const {};
  RetouchMaps? _retouchMaps;
  FaceAnalysis? _faces;
  HealedSourceCache? _healer;
  DevelopSettings? _last;

  @override
  ValueListenable<ui.Image?> get output => _output;

  @override
  ui.Image? get before => _before;

  @override
  RgbaBuffer? get analysisProxy => _proxy;

  @override
  Future<void> open(Uint8List original) async {
    final img = await decodePhoto(original, maxLongEdge: previewLongEdge);
    _before = img;
    _preview = await rgbaFromImage(img);
    final small = await resizeImage(img, interactiveLongEdge);
    _small = await rgbaFromImage(small);
    small.dispose();
    final proxy = await resizeImage(img, 512);
    _proxy = await rgbaFromImage(proxy);
    proxy.dispose();
  }

  @override
  void update(DevelopSettings settings, {bool interactive = false}) {
    _last = settings;
    _pending = settings;
    _pendingInteractive = interactive;
    _settle?.cancel();
    if (interactive) {
      _settle = Timer(
        const Duration(milliseconds: 150),
        () => update(settings),
      );
    }
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_busy || _disposed) return;
    final settings = _pending;
    final src = _pendingInteractive ? _small : _preview;
    if (settings == null || src == null) return;
    _pending = null;
    _busy = true;
    try {
      final healed = await _healed(src, settings.heal);
      if (_disposed) return;
      final out = await _renderInBackground(
        healed,
        settings,
        _rasters,
        _retouchMaps,
        _faces,
      );
      if (_disposed) return;
      final img = await imageFromRgba(out);
      final old = _output.value;
      _output.value = img;
      if (!identical(old, _before)) old?.dispose();
    } finally {
      _busy = false;
    }
    if (_pending != null) unawaited(_pump());
  }

  @override
  Future<Uint8List> renderThumbnail(
    DevelopSettings settings, {
    int longEdge = 384,
  }) async {
    final before = _before;
    if (before == null) throw StateError('open() first');
    final small = await resizeImage(before, longEdge);
    final buf = await rgbaFromImage(small);
    small.dispose();
    final out = await _renderInBackground(
      await _healed(buf, settings.heal, once: true),
      settings,
      _rasters,
      _retouchMaps,
      _faces,
    );
    final img = await imageFromRgba(out);
    try {
      return await encodePng(img);
    } finally {
      img.dispose();
    }
  }

  /// CPU twin of the GPU overlay (`renderMaskOverlayReference`) at the
  /// interactive size, AI masks included (see [setMaskRasters]).
  @override
  Future<ui.Image?> renderMaskOverlay(
    DevelopSettings settings,
    int index, {
    MaskTint tint = kDefaultMaskTint,
  }) async {
    final src = _small ?? _preview;
    if (src == null || index < 0 || index >= settings.masks.length) {
      return null;
    }
    final w = src.width, h = src.height;
    final rasters = _rasters;
    final out = await runInBackground(
      () => _overlay(w, h, settings, index, tint, rasters),
    );
    if (_disposed) return null;
    return imageFromRgba(out);
  }

  @override
  void setMaskRasters(Map<String, MaskRaster> rasters) {
    _rasters = Map.unmodifiable(rasters);
    final last = _last;
    if (last != null) update(last);
  }

  @override
  void setRetouch(RetouchMaps? maps, FaceAnalysis? faces) {
    _retouchMaps = maps;
    _faces = faces;
    final last = _last;
    if (last != null) update(last);
  }

  @override
  void setHealer(HealedSourceCache? healer) {
    _healer = healer;
    final last = _last;
    if (last != null) update(last);
  }

  /// [src] with [ops] drawn in ([once]: a one-off buffer, not cached).
  Future<RgbaBuffer> _healed(
    RgbaBuffer src,
    List<HealOp> ops, {
    bool once = false,
  }) async {
    final healer = _healer;
    if (healer == null || ops.isEmpty) return src;
    final hit = healer.peek(src, ops);
    if (hit != null) return hit.buffer;
    final h = once
        ? await healer.composeOnce(src, ops)
        : await healer.compose(src, ops);
    return h.buffer;
  }

  @override
  void dispose() {
    _disposed = true;
    _settle?.cancel();
    final out = _output.value;
    if (!identical(out, _before)) out?.dispose();
    _before?.dispose();
    _output.dispose();
  }
}

RgbaBuffer _overlay(
  int width,
  int height,
  DevelopSettings settings,
  int index,
  MaskTint tint,
  Map<String, MaskRaster> rasters,
) => renderMaskOverlayReference(
  width,
  height,
  settings,
  MaskRasterizer.build(settings.masks, width, height, rasters: rasters),
  index,
  tint: tint,
);

/// Retouch + develop off the UI isolate. Top-level so the closure only
/// captures plain data.
Future<RgbaBuffer> _renderInBackground(
  RgbaBuffer src,
  DevelopSettings settings,
  Map<String, MaskRaster> rasters,
  RetouchMaps? maps,
  FaceAnalysis? faces,
) => runInBackground(
  () => renderReference(
    retouchedSource(src, settings, maps, faces),
    settings,
    maskRasters: rasters,
  ),
);
