import 'dart:async';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/ai_raster_store.dart';
import 'package:lumen/ai/ondevice/mask_segmenter.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';

final _log = Logger('AiMaskSource');

enum AiMaskPhase { loadingModel, segmenting, ready, failed }

/// What the AI mask pipeline is doing (bind a progress chip to it; model
/// download bytes come from `modelProgressProvider`).
class AiMaskStatus {
  const AiMaskStatus(this.assetId, this.phase, {this.message, this.timings});

  final String assetId;
  final AiMaskPhase phase;
  final String? message;
  final MaskSegmentationTimings? timings;
}

/// Thrown for kinds no on-device model makes (sky).
class AiMaskUnsupported implements Exception {
  const AiMaskUnsupported(this.kind);
  final MaskKind kind;

  @override
  String toString() => 'AiMaskUnsupported: ${kind.name} has no on-device model';
}

/// [AiMaskSource] on Selfie Multiclass: one segmentation per photo writes
/// every raster (people, background, face skin, hair, clothes); masks then
/// reference them by `maskRef`. Rasters are a local cache, regenerated on
/// demand with the same model.
class OnDeviceAiMaskSource implements AiMaskSource, AiMaskRasterLoader {
  OnDeviceAiMaskSource({
    required this.spec,
    required Future<MaskSegmenter> Function() segmenter,
    required Future<AiRasterStore> Function() store,
    required Future<RgbaBuffer> Function(String assetId) pixels,
    required Future<List<FaceBox>> Function(String assetId) faces,
  }) : _loadSegmenter = segmenter,
       _openStore = store,
       _loadPixels = pixels,
       _loadFaces = faces;

  /// The segmentation model (its key is part of every `maskRef`).
  final ModelSpec spec;
  final Future<MaskSegmenter> Function() _loadSegmenter;
  final Future<AiRasterStore> Function() _openStore;
  final Future<RgbaBuffer> Function(String assetId) _loadPixels;
  final Future<List<FaceBox>> Function(String assetId) _loadFaces;
  final StreamController<AiMaskStatus> _status = StreamController.broadcast();
  final Map<String, Future<void>> _inFlight = {};
  final Map<String, MaskRaster> _decoded = {};

  Stream<AiMaskStatus> get status => _status.stream;

  String maskRefFor(AiRaster raster) => aiMaskRef(raster, spec.key);

  @override
  bool supports(MaskKind kind) =>
      spec.enabled && AiRaster.forKind(kind) != null;

  @override
  Future<AiShape> segment(String assetId, MaskKind kind) async {
    final raster = AiRaster.forKind(kind);
    if (raster == null || !spec.enabled) throw AiMaskUnsupported(kind);
    await ensureRasters(assetId);
    return AiShape(
      maskRef: maskRefFor(raster),
      model: spec.id,
      modelVersion: spec.version,
    );
  }

  @override
  Future<MaskRaster?> load(String assetId, String maskRef) async {
    final parsed = parseAiMaskRef(maskRef);
    if (parsed == null) return null;
    final key = '$assetId/$maskRef';
    final hit = _decoded[key];
    if (hit != null) return hit;
    final store = await _openStore();
    var raster = await store.read(assetId, maskRef);
    if (raster == null && maskRef == maskRefFor(parsed.raster)) {
      await ensureRasters(assetId);
      raster = await store.read(assetId, maskRef);
    } else if (raster == null) {
      _log.info('$maskRef was made by another model version; not available');
    }
    if (raster != null) _remember(key, raster);
    return raster;
  }

  /// Segments [assetId] once and writes every raster, unless all exist.
  Future<void> ensureRasters(String assetId) {
    final running = _inFlight[assetId];
    if (running != null) return running;
    final op = _ensure(assetId);
    _inFlight[assetId] = op;
    return op.whenComplete(() => _inFlight.remove(assetId));
  }

  Future<void> _ensure(String assetId) async {
    final store = await _openStore();
    final refs = {for (final r in AiRaster.values) r: maskRefFor(r)};
    var missing = false;
    for (final ref in refs.values) {
      if (!await store.exists(assetId, ref)) missing = true;
    }
    if (!missing) return;
    _emit(AiMaskStatus(assetId, AiMaskPhase.loadingModel));
    try {
      final segmenter = await _loadSegmenter();
      _emit(AiMaskStatus(assetId, AiMaskPhase.segmenting));
      final result = await segmenter.segment(
        await _loadPixels(assetId),
        faces: await _loadFaces(assetId),
      );
      for (final MapEntry(key: raster, value: ref) in refs.entries) {
        final r = result.planes.raster(raster);
        await store.write(assetId, ref, r);
        _remember('$assetId/$ref', r);
      }
      _log.info('AI masks for $assetId: ${result.timings}');
      _emit(AiMaskStatus(assetId, AiMaskPhase.ready, timings: result.timings));
    } on Exception catch (e) {
      _emit(AiMaskStatus(assetId, AiMaskPhase.failed, message: '$e'));
      rethrow;
    }
  }

  /// Keeps the last few decoded rasters (one photo's worth).
  void _remember(String key, MaskRaster r) {
    _decoded.remove(key);
    _decoded[key] = r;
    while (_decoded.length > AiRaster.values.length * 2) {
      _decoded.remove(_decoded.keys.first);
    }
  }

  void _emit(AiMaskStatus s) {
    if (!_status.isClosed) _status.add(s);
  }

  Future<void> dispose() => _status.close();
}
