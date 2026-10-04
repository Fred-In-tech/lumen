import 'dart:async';

import 'package:lumen/platform/background.dart';

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/import/photo_decoder.dart';

/// Reference-pipeline renderer: correct everywhere, slower than the GPU path.
class CpuPhotoRenderer implements PhotoRenderer, MaskOverlayRenderer {
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
      final out = await runInBackground(() => renderReference(src, settings));
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
    final out = await runInBackground(() => renderReference(buf, settings));
    final img = await imageFromRgba(out);
    try {
      return await encodePng(img);
    } finally {
      img.dispose();
    }
  }

  /// CPU twin of the GPU overlay (`renderMaskOverlayReference`) at the
  /// interactive size. AI rasters are not loaded here, so AI masks show no
  /// tint on this fallback path; vector masks and brush strokes do.
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
    final out = await runInBackground(
      () => _overlay(w, h, settings, index, tint),
    );
    if (_disposed) return null;
    return imageFromRgba(out);
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
) => renderMaskOverlayReference(
  width,
  height,
  settings,
  MaskRasterizer.build(settings.masks, width, height),
  index,
  tint: tint,
);
