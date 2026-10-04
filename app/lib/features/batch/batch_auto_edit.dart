import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/ai/auto_edit_service.dart';
import 'package:lumen/ai/preview_encoder.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/export/export_service.dart'
    show loadAiMaskRasters;
import 'package:lumen/features/export/source_render.dart';
import 'package:lumen/features/library/library_tile.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/import/photo_decoder.dart';

final _log = Logger('BatchAutoEdit');

/// Progress of the running batch job (null = idle).
class BatchProgress {
  const BatchProgress({
    required this.label,
    required this.done,
    required this.total,
    this.cancelled = false,
  });
  final String label;
  final int done;
  final int total;
  final bool cancelled;
}

class BatchNotifier extends Notifier<BatchProgress?> {
  bool _cancel = false;

  @override
  BatchProgress? build() => null;

  bool get cancelRequested => _cancel;

  void start(String label, int total) {
    _cancel = false;
    state = BatchProgress(label: label, done: 0, total: total);
  }

  void step() {
    final s = state;
    if (s != null) {
      state = BatchProgress(
        label: s.label,
        done: s.done + 1,
        total: s.total,
        cancelled: _cancel,
      );
    }
  }

  void cancel() => _cancel = true;

  void finish() => state = null;
}

final batchProvider = NotifierProvider<BatchNotifier, BatchProgress?>(
  BatchNotifier.new,
);

/// Auto-edits one stored photo without opening the editor. Returns false on failure.
///
/// Heal ops are drawn into the analysis proxy and the thumbnail (from
/// [patches]), so removed objects neither steer the edit nor reappear.
Future<bool> autoEditStoredAsset({
  required CatalogRepository repo,
  required AutoEditService service,
  required String assetId,
  AiStyle style = AiStyle.natural,
  PatchStoreGetter? patches,
  AiMaskRasterLoader? maskLoader,
  RetouchLoader? retouch,
}) async {
  try {
    final entry = await repo.get(assetId);
    if (entry == null) return false;
    final original = await repo.readOriginal(assetId);
    final doc = await repo.loadEdit(assetId);
    Future<RgbaBuffer> source(int longEdge) => decodeHealedSource(
      original,
      assetId: assetId,
      ops: doc.settings.heal,
      patches: patches,
      maxLongEdge: longEdge,
    );
    final proxy = await source(512);
    final result = await service.autoEdit(
      AiPhotoContext(
        proxy: proxy,
        current: doc.settings,
        exif: entry.exif,
        visionJpeg: () async => encodeJpegNoMetadata(await source(1024)),
      ),
      style: style,
    );
    final next = result.outcome.settings;
    final hist = HistoryEntry.tryDiff(
      label: result.label,
      kind: HistoryKind.ai,
      before: doc.settings,
      after: next,
    );
    await repo.saveEdit(
      doc.copyWith(
        settings: next,
        history: hist == null ? doc.history : doc.history.push(hist),
        ai: result.record,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    final thumbSrc = await source(384);
    final faces = await (retouch?.call(assetId, next) ?? kNoRetouchFuture);
    final rendered = await developInBackground(
      thumbSrc,
      next,
      await loadAiMaskRasters(maskLoader, assetId, next.masks),
      faces.maps,
      faces.faces,
    );
    final out = await imageFromRgba(rendered);
    final png = await encodePng(out);
    out.dispose();
    await repo.writeThumb(assetId, png);
    final fresh = await repo.get(assetId);
    if (fresh != null) {
      await repo.update(
        fresh.copyWith(
          hasEdits: !next.isDefault,
          editedAt: DateTime.now().toUtc(),
          aiEngine: result.record.engine,
          aiStyle: result.record.style,
          thumbVersion: fresh.thumbVersion + 1,
        ),
      );
    }
    return true;
  } on Exception catch (e) {
    _log.warning('auto-edit $assetId failed: $e');
    return false;
  }
}

/// Auto-edits [assetIds] with bounded concurrency; returns (ok, failed).
Future<(int, int)> batchAutoEdit(
  WidgetRef ref,
  List<String> assetIds, {
  AiStyle style = AiStyle.natural,
  int concurrency = 2,
}) async {
  if (assetIds.isEmpty) return (0, 0);
  final repo = ref.read(catalogRepositoryProvider);
  final service = ref.read(autoEditServiceProvider);
  Future<PatchStore> patches() => ref.read(patchStoreProvider.future);
  final maskLoader = ref.read(aiMaskRasterLoaderProvider);
  final retouch = ref.read(storedRetouchLoaderProvider).load;
  final batch = ref.read(batchProvider.notifier)
    ..start('Auto-editing', assetIds.length);
  final busy = ref.read(busyAssetsProvider.notifier)..add(assetIds);
  var ok = 0, failed = 0, next = 0;
  Future<void> worker() async {
    while (next < assetIds.length && !batch.cancelRequested) {
      final id = assetIds[next++];
      final success = await autoEditStoredAsset(
        repo: repo,
        service: service,
        assetId: id,
        style: style,
        patches: patches,
        maskLoader: maskLoader,
        retouch: retouch,
      );
      success ? ok++ : failed++;
      busy.remove(id);
      batch.step();
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  for (final id in assetIds) {
    busy.remove(id);
  }
  batch.finish();
  return (ok, failed);
}

/// Applies [preset] to each asset as one history entry.
Future<int> applyPresetToAssets(
  WidgetRef ref,
  Preset preset,
  List<String> assetIds,
) async {
  final repo = ref.read(catalogRepositoryProvider);
  var n = 0;
  for (final id in assetIds) {
    final doc = await repo.loadEdit(id);
    final next = preset.apply(doc.settings);
    final h = HistoryEntry.tryDiff(
      label: 'Preset · ${preset.name}',
      kind: HistoryKind.preset,
      before: doc.settings,
      after: next,
    );
    if (h == null) continue;
    await repo.saveEdit(
      doc.copyWith(
        settings: next,
        history: doc.history.push(h),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await refreshThumbnail(
      repo,
      id,
      next,
      patches: () => ref.read(patchStoreProvider.future),
      maskLoader: ref.read(aiMaskRasterLoaderProvider),
      retouch: ref.read(storedRetouchLoaderProvider).load,
    );
    n++;
  }
  return n;
}

/// Re-renders a stored photo's thumbnail with [settings] (CPU reference pipeline).
Future<void> refreshThumbnail(
  CatalogRepository repo,
  String assetId,
  DevelopSettings settings, {
  PatchStoreGetter? patches,
  AiMaskRasterLoader? maskLoader,
  RetouchLoader? retouch,
}) async {
  try {
    final original = await repo.readOriginal(assetId);
    final src = await decodeHealedSource(
      original,
      assetId: assetId,
      ops: settings.heal,
      patches: patches,
      maxLongEdge: 384,
    );
    final faces = await (retouch?.call(assetId, settings) ?? kNoRetouchFuture);
    final rendered = await developInBackground(
      src,
      settings,
      await loadAiMaskRasters(maskLoader, assetId, settings.masks),
      faces.maps,
      faces.faces,
    );
    final out = await imageFromRgba(rendered);
    final png = await encodePng(out);
    out.dispose();
    await repo.writeThumb(assetId, png);
    final e = await repo.get(assetId);
    if (e != null) {
      await repo.update(
        e.copyWith(
          hasEdits: !settings.isDefault,
          editedAt: DateTime.now().toUtc(),
          thumbVersion: e.thumbVersion + 1,
        ),
      );
    }
  } on Exception catch (e) {
    _log.warning('thumbnail $assetId failed: $e');
  }
}
