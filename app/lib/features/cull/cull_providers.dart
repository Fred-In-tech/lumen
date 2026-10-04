import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ondevice/analysis_pixels.dart';
import 'package:lumen/ai/ondevice/ondevice_providers.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/features/cull/cull_service.dart';
import 'package:lumen/features/cull/cull_store.dart';
import 'package:lumen/features/cull/cull_store_platform.dart';

final _log = Logger('CullProviders');

final cullStoreProvider = FutureProvider<CullStore>(
  (ref) => openCullStore(),
  retry: noRetry,
);

final smartCullServiceProvider = FutureProvider<SmartCullService>((ref) async {
  final store = await ref.watch(cullStoreProvider.future);
  final catalog = ref.watch(catalogRepositoryProvider);
  return SmartCullService(
    store: store,
    catalog: catalog,
    pixels: (id) => loadAnalysisPixels(catalog, id),
    faces: (id, px) async {
      try {
        final service = await ref.read(faceAnalysisServiceProvider.future);
        return await service.analyze(
          id,
          pixels: () async => px.pixels,
          sourceWidth: px.sourceWidth,
          sourceHeight: px.sourceHeight,
        );
      } on Exception catch (e) {
        _log.info('no faces for culling $id: $e');
        return null;
      }
    },
    facesKey: kFaceModels.values.join('+'),
  );
}, retry: noRetry);

/// Cull cache records of the library photos (only photos with a record).
class CullRecordsNotifier extends AsyncNotifier<Map<String, CullRecord>> {
  @override
  Future<Map<String, CullRecord>> build() async {
    final ids = ref.watch(
      libraryProvider.select(
        (v) => (v.value ?? const <CatalogEntry>[])
            .map((e) => e.assetId)
            .join('\n'),
      ),
    );
    if (ids.isEmpty) return const {};
    final store = await ref.watch(cullStoreProvider.future);
    final out = <String, CullRecord>{};
    for (final id in ids.split('\n')) {
      final r = await store.read(id);
      if (r != null) out[id] = r;
    }
    return Map.unmodifiable(out);
  }

  Map<String, CullRecord> get _current => state.value ?? const {};

  /// Merges fresh records (after a run) into the state.
  void put(Map<String, CullRecord> records) =>
      state = AsyncData(Map.unmodifiable({..._current, ...records}));

  /// Sets the status of [ids]' suggestions and persists it.
  Future<void> setStatus(Iterable<String> ids, SuggestionStatus status) async {
    final store = await ref.read(cullStoreProvider.future);
    final next = {..._current};
    for (final id in ids) {
      final r = next[id];
      if (r == null || r.suggestion == null || r.status == status) continue;
      final updated = r.withStatus(status);
      await store.write(id, updated);
      next[id] = updated;
    }
    state = AsyncData(Map.unmodifiable(next));
  }
}

final cullRecordsProvider =
    AsyncNotifierProvider<CullRecordsNotifier, Map<String, CullRecord>>(
      CullRecordsNotifier.new,
      retry: noRetry,
    );

/// A running Smart Cull (null = idle).
class CullRun {
  const CullRun({required this.done, required this.total});
  final int done;
  final int total;
}

class SmartCullController extends Notifier<CullRun?> {
  bool _cancel = false;

  @override
  CullRun? build() => null;

  bool get running => state != null;

  /// Runs Smart Cull on [assetIds]; null when a run is already going.
  Future<SmartCullOutcome?> run(List<String> assetIds) async {
    if (state != null || assetIds.isEmpty) return null;
    _cancel = false;
    state = CullRun(done: 0, total: assetIds.length);
    try {
      final service = await ref.read(smartCullServiceProvider.future);
      final outcome = await service.run(
        assetIds,
        onProgress: (done, total) => state = CullRun(done: done, total: total),
        isCancelled: () => _cancel,
      );
      ref.read(cullRecordsProvider.notifier).put(outcome.records);
      return outcome;
    } finally {
      state = null;
    }
  }

  void cancel() => _cancel = true;
}

final smartCullProvider = NotifierProvider<SmartCullController, CullRun?>(
  SmartCullController.new,
);
