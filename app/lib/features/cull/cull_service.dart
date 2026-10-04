import 'dart:async';

import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/analysis_pixels.dart';
import 'package:lumen/ai/ondevice/face_analyzer.dart';
import 'package:lumen/ai/ondevice/face_cache.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/cull/cull_store.dart';
import 'package:lumen/platform/background.dart';

final _log = Logger('SmartCull');

/// Faces for a photo (the face cache, analyzing when needed); null when
/// face analysis cannot run (signals are then measured without faces).
typedef CullFaceLoader = Future<FaceCacheEntry?> Function(
  String assetId,
  AnalysisPixels pixels,
);

/// What a Smart Cull run produced.
class SmartCullOutcome {
  const SmartCullOutcome({
    required this.records,
    required this.result,
    required this.failed,
    required this.cancelled,
  });

  final Map<String, CullRecord> records;
  final SmartCullResult result;

  /// Photos that could not be measured (left out of the run).
  final List<String> failed;
  final bool cancelled;
}

/// Measures photos (cached per photo in `cache/cull.json`) and runs
/// [smartCull] over them. Suggestions are stored as pending; the catalog
/// only changes when the user accepts them.
class SmartCullService {
  SmartCullService({
    required this.store,
    required this.catalog,
    required this.pixels,
    required this.faces,
    required this.facesKey,
    this.config = const CullConfig(),
    BackgroundRunner? runner,
  }) : _run = runner ?? runInBackground;

  final CullStore store;
  final CatalogRepository catalog;
  final Future<AnalysisPixels> Function(String assetId) pixels;
  final CullFaceLoader faces;

  /// Face model keys the signals depend on.
  final String facesKey;
  final CullConfig config;
  final BackgroundRunner _run;

  String get signalsKey => 'cull${CullSignals.version}+$facesKey';

  /// Cached signals when current, else measured and cached.
  Future<CullSignals?> signalsFor(String assetId) async {
    final cached = await store.read(assetId);
    if (cached != null && cached.signalsKey == signalsKey) {
      return cached.signals;
    }
    final entry = await catalog.get(assetId);
    if (entry == null) return null;
    final px = await pixels(assetId);
    final f = await faces(assetId, px);
    final measured = await _measure(
      _run,
      px.pixels,
      f?.analysis.faces ?? const [],
      f?.rejected ?? const [],
      entry.exif.capturedAt,
    );
    await store.write(
      assetId,
      CullRecord(
        signalsKey: signalsKey,
        signals: measured,
        suggestion: cached?.suggestion,
        status: cached?.status ?? SuggestionStatus.pending,
      ),
    );
    return measured;
  }

  /// Measures [assetIds] (in library order) and suggests picks/rejects.
  Future<SmartCullOutcome> run(
    List<String> assetIds, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final items = <CullItem>[];
    final failed = <String>[];
    var cancelled = false;
    for (var i = 0; i < assetIds.length; i++) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      final id = assetIds[i];
      try {
        final s = await signalsFor(id);
        s == null ? failed.add(id) : items.add(CullItem(id, s));
      } on Exception catch (e) {
        _log.warning('could not measure $id: $e');
        failed.add(id);
      }
      onProgress?.call(i + 1, assetIds.length);
    }
    final result = smartCull(items, config: config);
    final records = <String, CullRecord>{};
    for (final item in items) {
      final record = CullRecord(
        signalsKey: signalsKey,
        signals: item.signals,
        suggestion: result.suggestions[item.assetId],
      );
      await store.write(item.assetId, record);
      records[item.assetId] = record;
    }
    return SmartCullOutcome(
      records: Map.unmodifiable(records),
      result: result,
      failed: List.unmodifiable(failed),
      cancelled: cancelled,
    );
  }
}

// Top-level so the isolate closure captures only its arguments.
Future<CullSignals> _measure(
  BackgroundRunner run,
  RgbaBuffer pixels,
  List<DetectedFace> faces,
  List<RejectedFace> rejected,
  DateTime? capturedAt,
) => run(
  () => computeCullSignals(
    pixels,
    faces: faces,
    rejected: rejected,
    capturedAt: capturedAt,
  ),
);
