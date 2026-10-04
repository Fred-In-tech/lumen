import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/export_renderer.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/render_scheduler.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/import/photo_decoder.dart';

final _log = Logger('GpuPhotoRenderer');

/// Fragment-shader renderer (interactive). Falls back to [CpuPhotoRenderer]
/// when shaders cannot load on this device.
class GpuPhotoRenderer
    implements PhotoRenderer, MaskOverlayRenderer, MaskRasterSink, RetouchSink {
  GpuPhotoRenderer({required this.assetId, this.previewLongEdge = 2560});

  final String assetId;
  final int previewLongEdge;
  final ValueNotifier<ui.Image?> _output = ValueNotifier(null);
  ui.Image? _source;
  AuxTextures? _aux;
  RenderGraph? _graph;
  RenderScheduler? _scheduler;
  RgbaBuffer? _proxy;
  CpuPhotoRenderer? _fallback;
  Map<String, MaskRaster> _rasters = const {};
  RetouchMaps? _retouchMaps;
  FaceAnalysis? _faces;
  DevelopSettings? _last;

  /// True when the CPU fallback is in use.
  bool get usingFallback => _fallback != null;

  @override
  ValueListenable<ui.Image?> get output => _fallback?.output ?? _output;

  @override
  ui.Image? get before => _fallback?.before ?? _source;

  @override
  RgbaBuffer? get analysisProxy => _fallback?.analysisProxy ?? _proxy;

  @override
  Future<void> open(Uint8List original) async {
    final ShaderLibrary shaders;
    try {
      shaders = await ShaderLibrary.load();
    } on ShaderLoadException catch (e) {
      _log.warning('Shaders unavailable, using CPU renderer: $e');
      final cpu = _fallback = CpuPhotoRenderer()
        ..setMaskRasters(_rasters)
        ..setRetouch(_retouchMaps, _faces);
      await cpu.open(original);
      return;
    }
    final size = await probeSize(original);
    final source = _source = await decodePhoto(
      original,
      maxLongEdge: previewLongEdge,
    );
    final aux = _aux = await AuxTextures.build(source);
    final graph = _graph =
        RenderGraph(
            shaders: shaders,
            source: source,
            aux: aux,
            assetId: assetId,
            originalSize: (width: size.width, height: size.height),
          )
          ..maskRasters = _rasters
          ..retouchMaps = _retouchMaps
          ..faceAnalysis = _faces;
    final scheduler = _scheduler = RenderScheduler(graph);
    scheduler.frame.addListener(() => _output.value = scheduler.frame.value);
    scheduler.errors.listen((e) => _log.warning('render failed: $e'));
    final proxyImg = await resizeImage(source, 512);
    _proxy = await rgbaFromImage(proxyImg);
    proxyImg.dispose();
  }

  @override
  void update(DevelopSettings settings, {bool interactive = false}) {
    _last = settings;
    final fb = _fallback;
    if (fb != null) return fb.update(settings, interactive: interactive);
    _scheduler?.update(settings, interactive: interactive);
  }

  @override
  void setMaskRasters(Map<String, MaskRaster> rasters) {
    _rasters = Map.unmodifiable(rasters);
    final fb = _fallback;
    if (fb != null) return fb.setMaskRasters(_rasters);
    _graph?.maskRasters = _rasters;
    final last = _last;
    if (last != null) _scheduler?.update(last);
  }

  @override
  void setRetouch(RetouchMaps? maps, FaceAnalysis? faces) {
    _retouchMaps = maps;
    _faces = faces;
    final fb = _fallback;
    if (fb != null) return fb.setRetouch(maps, faces);
    _graph
      ?..retouchMaps = maps
      ..faceAnalysis = faces;
    final last = _last;
    if (last != null) _scheduler?.update(last);
  }

  @override
  Future<Uint8List> renderThumbnail(
    DevelopSettings settings, {
    int longEdge = 384,
  }) async {
    final fb = _fallback;
    if (fb != null) return fb.renderThumbnail(settings, longEdge: longEdge);
    final graph = _graph;
    final source = _source;
    if (graph == null || source == null) throw StateError('open() first');
    final full = graph.outputSize(settings, 1);
    final scale = math.min(1.0, longEdge / math.max(full.width, full.height));
    final img = await graph.render(settings, scale: scale);
    try {
      return await encodePng(img);
    } finally {
      EngineImages.dispose(img);
    }
  }

  /// Long edge of the mask overlay tint (it is stretched over the frame).
  static const int _overlayLongEdge = 1024;

  @override
  Future<ui.Image?> renderMaskOverlay(
    DevelopSettings settings,
    int index, {
    MaskTint tint = kDefaultMaskTint,
  }) async {
    final fb = _fallback;
    if (fb != null) return fb.renderMaskOverlay(settings, index, tint: tint);
    final graph = _graph;
    if (graph == null || index < 0 || index >= settings.masks.length) {
      return null;
    }
    final full = graph.outputSize(settings, 1);
    final scale = math.min(
      1.0,
      _overlayLongEdge / math.max(full.width, full.height),
    );
    return graph.renderMaskOverlay(settings, index, scale: scale, tint: tint);
  }

  @override
  void dispose() {
    _fallback?.dispose();
    _scheduler?.dispose();
    _aux?.dispose();
    EngineImages.dispose(_source);
    _output.dispose();
  }
}

/// GPU full-resolution export render (tiled). Falls back to the CPU path.
Future<RgbaBuffer> gpuFullResRender(
  Uint8List original,
  DevelopSettings settings,
  int? longEdge,
) async {
  final ShaderLibrary shaders;
  try {
    shaders = await ShaderLibrary.load();
  } on ShaderLoadException {
    final decoded = await decodePhoto(original, maxLongEdge: longEdge);
    final src = await rgbaFromImage(decoded);
    decoded.dispose();
    return renderReference(src, settings);
  }
  final source = await ExportRenderer.decodeOriginal(original);
  final aux = await AuxTextures.build(source);
  try {
    final px = await ExportRenderer(
      shaders,
    ).render(source: source, aux: aux, settings: settings, longEdge: longEdge);
    return RgbaBuffer(px.width, px.height, px.rgba);
  } finally {
    aux.dispose();
    EngineImages.dispose(source);
  }
}
