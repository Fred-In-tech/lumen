import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/engine/aux_cache.dart';
import 'package:lumen/engine/backdrop_service.dart';
import 'package:lumen/engine/float_source.dart';
import 'package:lumen/engine/gpu_pass.dart';
import 'package:lumen/engine/hbd_capability.dart';
import 'package:lumen/engine/render_graph.dart';
import 'package:lumen/engine/render_scheduler.dart';
import 'package:lumen/engine/shader_library.dart';
import 'package:lumen/engine/warp_service.dart';
import 'package:lumen/features/editor/renderer/cpu_photo_renderer.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/editor/renderer/photo_renderer.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/import/photo_decoder.dart';

export 'gpu_source_renderer.dart';

final _log = Logger('GpuPhotoRenderer');

/// Fragment-shader renderer (interactive). Falls back to [CpuPhotoRenderer]
/// when shaders cannot load on this device.
///
/// Float path (docs/HIGH_BIT_DEPTH.md): when [floatSource] finds a float
/// source for the photo (camera RAW, 16-bit PNG, 10-bit HEIC) and the
/// device passes the float probe, the render graph develops a float32
/// preview of it, so exposure, white balance, highlights and shadows work
/// on real headroom and precision. The 8-bit decode stays for [before],
/// the analysis proxy, heal patches and backdrop mattes. Any failure on
/// the way keeps the 8-bit path.
class GpuPhotoRenderer
    implements
        PhotoRenderer,
        MaskOverlayRenderer,
        MaskRasterSink,
        RetouchSink,
        HealSink,
        WarpSink,
        BackdropSink {
  GpuPhotoRenderer({
    required this.assetId,
    this.previewLongEdge = 2560,
    this.floatSource,
  });

  final String assetId;
  final int previewLongEdge;

  /// Finds the photo's float source (null: always the 8-bit path).
  final FloatSourceLoader? floatSource;
  FloatSource? _float;
  ui.Image? _floatImage;

  /// True when the open photo is edited on the float path.
  bool get usingFloat => _floatImage != null;

  /// The graph's unhealed source: the float preview, else the 8-bit one.
  ui.Image? get _base => _floatImage ?? _source;
  final ValueNotifier<ui.Image?> _output = ValueNotifier(null);
  ui.Image? _source;
  AuxTextures? _aux;
  RenderGraph? _graph;
  RenderScheduler? _scheduler;
  RgbaBuffer? _proxy;
  CpuPhotoRenderer? _fallback;
  Map<String, MaskRaster> _rasters = const {};
  RetouchMaps? _retouchMaps;
  FaceAnalysis? _warpFaces;
  WarpFieldService? _warp;
  BackdropService? _swap;
  BackdropInputs _swapInputs = kNoBackdropInputs;
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
        ..setHealer(_healer)
        ..setWarpFaces(_warpFaces)
        ..setBackdropInputs(
          people: _swapInputs.people,
          hair: _swapInputs.hair,
          image: _swapInputs.image,
        );
      await cpu.open(original);
      return;
    }
    final size = await probeSize(original);
    final source = _source = await decodePhoto(
      original,
      maxLongEdge: previewLongEdge,
    );
    final float = await _openFloat(shaders, source.width, source.height);
    _float = float?.source;
    _floatImage = float?.image;
    final base = float?.image ?? source;
    final aux = _aux = await AuxTextures.build(base, float: float != null);
    final graph = _graph =
        RenderGraph(
            shaders: shaders,
            source: base,
            aux: aux,
            assetId: assetId,
            originalSize: (width: size.width, height: size.height),
            float: float != null,
            profile: float?.source.profile ?? HbdProfile.none,
          )
          ..maskRasters = _rasters
          ..retouchMaps = _retouchMaps
          ..faceAnalysis = _faces;
    _warp = WarpFieldService(
      sourceWidth: source.width,
      sourceHeight: source.height,
      onField: (field) {
        if (_disposed) return;
        graph.warpField = field;
        final last = _last;
        if (last != null) _scheduler?.update(last);
      },
    )..faces = _warpFaces ?? _faces;
    _swap =
        BackdropService(
          preview: () async => _sourceRgba ??= await rgbaFromImage(source),
          onAssets: (assets) {
            if (_disposed) return;
            graph.backdropAssets = assets;
            final last = _last;
            if (last != null) _scheduler?.update(last);
          },
        )..setInputs(
          people: _swapInputs.people,
          hair: _swapInputs.hair,
          image: _swapInputs.image,
        );
    final scheduler = _scheduler = RenderScheduler(graph);
    scheduler.frame.addListener(() => _output.value = scheduler.frame.value);
    scheduler.errors.listen((e) => _log.warning('render failed: $e'));
    final proxyImg = await resizeImage(source, 512);
    _proxy = await rgbaFromImage(proxyImg);
    proxyImg.dispose();
  }

  /// The float preview of this photo at exactly [width]×[height] (the size
  /// of the 8-bit preview, so heals, masks and maps line up), or null when
  /// the photo has no float source, the device fails the float probe or
  /// the decode fails.
  Future<({ui.Image image, FloatSource source})?> _openFloat(
    ShaderLibrary shaders,
    int width,
    int height,
  ) async {
    final loader = floatSource;
    if (loader == null) return null;
    try {
      if (!await HbdCapability.probe(shaders)) return null;
      final source = await loader(assetId);
      if (source == null) return null;
      // Both decodes must be the same upright picture.
      final skew = (source.width * height - source.height * width).abs();
      if (skew > source.width + source.height) {
        _log.warning(
          'float source is ${source.width}x${source.height}, preview '
          '${width}x$height: keeping the 8-bit path',
        );
        return null;
      }
      final px = await source.render(fullWidth: width, fullHeight: height);
      final image = await uploadFloat(px.rgba, width, height);
      _log.info('float path on for $assetId (${width}x$height)');
      return (image: image, source: source);
    } on Exception catch (e) {
      _log.warning('float source unavailable, using the 8-bit path: $e');
      return null;
    }
  }

  @override
  void update(DevelopSettings settings, {bool interactive = false}) {
    _last = settings;
    final fb = _fallback;
    if (fb != null) return fb.update(settings, interactive: interactive);
    _requestHeals(settings.heal);
    _warp?.update(settings);
    _swap?.update(settings.backdrop);
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
    final base = _base, floatBase = _floatImage;
    if (graph == null || source == null || baseAux == null || base == null) {
      return;
    }
    final healer = _healer;
    final visible = ops.any((o) => !o.hidden && o.isRenderable);
    HealedSource? h;
    if (healer != null && visible) {
      final rgba = _sourceRgba ??= await rgbaFromImage(source);
      h = await healer.compose(rgba, ops);
    }
    if (_disposed || gen != _healGen) return;
    if (h == null || !h.healed) {
      graph.replaceSource(base, aux: baseAux);
      _releaseHealed();
    } else if (!identical(h.buffer, _healedBuffer)) {
      final ui.Image img;
      if (floatBase != null) {
        // The float source keeps its values; the 8-bit patches replace
        // what they cover.
        final overlay = await healer!.overlay(source.width, source.height, ops);
        if (_disposed || gen != _healGen || overlay == null) return;
        final patches = await imageFromRgba(overlay);
        img = compositeOverlay(floatBase, patches);
        patches.dispose();
      } else {
        img = await imageFromRgba(h.buffer);
      }
      final aux = h.needsAuxRecompute
          ? await AuxTextures.build(img, float: floatBase != null)
          : null;
      if (_disposed || gen != _healGen) {
        EngineImages.dispose(img);
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
    EngineImages.dispose(_healedImage);
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
    _warp?.faces = _warpFaces ?? faces;
    final last = _last;
    if (last != null) _scheduler?.update(last);
  }

  @override
  void setWarpFaces(FaceAnalysis? faces) {
    _warpFaces = faces;
    final fb = _fallback;
    if (fb != null) return fb.setWarpFaces(faces);
    _warp?.faces = faces ?? _faces;
  }

  @override
  void setBackdropInputs({
    MaskRaster? people,
    MaskRaster? hair,
    RgbaBuffer? image,
  }) {
    _swapInputs = (people: people, hair: hair, image: image);
    final fb = _fallback;
    if (fb != null) {
      return fb.setBackdropInputs(people: people, hair: hair, image: image);
    }
    _swap?.setInputs(people: people, hair: hair, image: image);
  }

  /// Exact backdrop textures for [b] (export), null when off.
  Future<BackdropAssets?> backdropAssetsFor(BackdropChange b) async =>
      _swap?.assetsFor(b);

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
    final warp = await _warp?.fieldFor(settings);
    final img = await graph.render(settings, scale: scale, warp: warp);
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
    _warp?.dispose();
    _swap?.dispose();
    _scheduler?.dispose();
    _releaseHealed();
    _aux?.dispose();
    EngineImages.dispose(_source);
    EngineImages.dispose(_floatImage);
    _floatImage = null;
    // The native decoder keeps the RAW decode cached while the photo is open.
    unawaited(_float?.release());
    _float = null;
    _output.dispose();
  }
}
