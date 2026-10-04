import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
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
import 'package:lumen/features/export/source_render.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/import/photo_decoder.dart';

final _log = Logger('GpuPhotoRenderer');

/// Fragment-shader renderer (interactive). Falls back to [CpuPhotoRenderer]
/// when shaders cannot load on this device.
class GpuPhotoRenderer
    implements
        PhotoRenderer,
        MaskOverlayRenderer,
        MaskRasterSink,
        RetouchSink,
        HealSink {
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

  // Heals: the graph develops [_healedImage] (with [_healedAux] when the
  // healed area is large) instead of [_source]; [before] stays [_source].
  HealedSourceCache? _healer;
  RgbaBuffer? _sourceRgba;
  ui.Image? _healedImage;
  RgbaBuffer? _healedBuffer;
  AuxTextures? _healedAux;
  List<HealOp> _appliedHeal = const [];
  List<HealOp>? _requestedHeal;
  Future<void>? _healing;
  int _healGen = 0;
  bool _disposed = false;

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
        ..setRetouch(_retouchMaps, _faces)
        ..setHealer(_healer);
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
    _requestHeals(settings.heal);
    _scheduler?.update(settings, interactive: interactive);
  }

  @override
  void setHealer(HealedSourceCache? healer) {
    _healer = healer;
    final fb = _fallback;
    if (fb != null) return fb.setHealer(healer);
    _appliedHeal = const [];
    _requestedHeal = null;
    final last = _last;
    if (last != null) update(last);
  }

  static bool _sameOps(List<HealOp> a, List<HealOp> b) =>
      identical(a, b) || const ListEquality<HealOp>().equals(a, b);

  /// Starts swapping the graph's source when [ops] differ from what it
  /// shows. Frames keep rendering the previous source meanwhile; the new
  /// one re-renders the last settings when it lands.
  void _requestHeals(List<HealOp> ops) {
    if (_graph == null) return;
    final requested = _requestedHeal;
    if (requested != null && _sameOps(requested, ops)) return;
    if (requested == null && _sameOps(_appliedHeal, ops)) return;
    _requestedHeal = ops;
    _healing = _applyHeals(ops, ++_healGen);
  }

  Future<void> _applyHeals(List<HealOp> ops, int gen) async {
    try {
      await _swapSource(ops, gen);
    } on Exception catch (e) {
      _log.warning('heals could not be applied: $e');
    } finally {
      if (gen == _healGen) _requestedHeal = null;
    }
  }

  Future<void> _swapSource(List<HealOp> ops, int gen) async {
    final graph = _graph, source = _source, baseAux = _aux;
    if (graph == null || source == null || baseAux == null) return;
    final healer = _healer;
    final visible = ops.any((o) => !o.hidden && o.isRenderable);
    HealedSource? h;
    if (healer != null && visible) {
      final rgba = _sourceRgba ??= await rgbaFromImage(source);
      h = await healer.compose(rgba, ops);
    }
    if (_disposed || gen != _healGen) return;
    if (h == null || !h.healed) {
      graph.replaceSource(source, aux: baseAux);
      _releaseHealed();
    } else if (!identical(h.buffer, _healedBuffer)) {
      final img = await imageFromRgba(h.buffer);
      final aux = h.needsAuxRecompute ? await AuxTextures.build(img) : null;
      if (_disposed || gen != _healGen) {
        img.dispose();
        aux?.dispose();
        return;
      }
      graph.replaceSource(img, aux: aux ?? baseAux);
      _releaseHealed();
      _healedImage = img;
      _healedBuffer = h.buffer;
      _healedAux = aux;
    }
    _appliedHeal = ops;
    final last = _last;
    if (last != null) _scheduler?.update(last);
  }

  void _releaseHealed() {
    // Frames already recorded keep their images alive in the engine.
    _healedImage?.dispose();
    _healedAux?.dispose();
    _healedImage = null;
    _healedBuffer = null;
    _healedAux = null;
  }

  /// Applies [ops] now (thumbnails must show the heals they are asked for).
  Future<void> _ensureHeals(List<HealOp> ops) async {
    _requestHeals(ops);
    Future<void>? waited;
    while (!_disposed &&
        _requestedHeal != null &&
        !identical(_healing, waited)) {
      waited = _healing;
      await waited;
    }
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
    await _ensureHeals(settings.heal);
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
    _disposed = true;
    _fallback?.dispose();
    _scheduler?.dispose();
    _releaseHealed();
    _aux?.dispose();
    EngineImages.dispose(_source);
    _output.dispose();
  }
}

/// GPU full-resolution export render (tiled). Falls back to the CPU path.
Future<RgbaBuffer> gpuFullResRender(
  Uint8List original,
  DevelopSettings settings,
  int? longEdge, {
  String assetId = '',
}) async {
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
    final px = await ExportRenderer(shaders).render(
      source: source,
      aux: aux,
      settings: settings,
      assetId: assetId,
      longEdge: longEdge,
    );
    return RgbaBuffer(px.width, px.height, px.rgba);
  } finally {
    aux.dispose();
    EngineImages.dispose(source);
  }
}

/// GPU export of decoded (healed) source pixels: portrait retouch (pass R),
/// AI masks and the develop/finish passes, tiled, with aux maps built from
/// the source it is given. Falls back to [CpuSourceRenderer] when shaders
/// cannot load.
class GpuSourceRenderer implements SourceRenderer {
  const GpuSourceRenderer();

  @override
  int? decodeLongEdge(int? longEdge) => kMaxExportEdge;

  @override
  Future<RgbaBuffer> render(
    RgbaBuffer source,
    DevelopSettings settings,
    SourceInputs inputs, {
    int? longEdge,
  }) async {
    final ShaderLibrary shaders;
    try {
      shaders = await ShaderLibrary.load();
    } on ShaderLoadException {
      return const CpuSourceRenderer().render(
        source,
        settings,
        inputs,
        longEdge: longEdge,
      );
    }
    final img = await imageFromRgba(source);
    final aux = await AuxTextures.build(img);
    try {
      final px = await ExportRenderer(shaders).render(
        source: img,
        aux: aux,
        settings: settings,
        assetId: inputs.assetId,
        longEdge: longEdge,
        maskRasters: inputs.maskRasters,
        faceAnalysis: inputs.faces,
        retouchMaps: inputs.retouchMaps,
      );
      return RgbaBuffer(px.width, px.height, px.rgba);
    } finally {
      aux.dispose();
      img.dispose();
    }
  }
}
