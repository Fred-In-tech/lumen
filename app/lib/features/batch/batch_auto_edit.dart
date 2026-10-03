import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/ai/ai_providers.dart';
import 'package:lumen/ai/auto_edit_service.dart';
import 'package:lumen/ai/preview_encoder.dart';
import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/editor/renderer/image_bridge.dart';
import 'package:lumen/features/library/library_tile.dart';
import 'package:lumen/import/photo_decoder.dart';

final _log = Logger('BatchAutoEdit');

/// Progress of the running batch job (null = idle).
class BatchProgress {
  const BatchProgress({required this.label, required this.done, required this.total, this.cancelled = false});
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
    if (s != null) state = BatchProgress(label: s.label, done: s.done + 1, total: s.total, cancelled: _cancel);
  }

  void cancel() => _cancel = true;

  void finish() => state = null;
}

final batchProvider = NotifierProvider<BatchNotifier, BatchProgress?>(BatchNotifier.new);

/// Auto-edits one stored photo without opening the editor. Returns false on failure.
Future<bool> autoEditStoredAsset({
  required CatalogRepository repo,
  required AutoEditService service,
  required String assetId,
  AiStyle style = AiStyle.natural,
}) async {
  try {
    final entry = await repo.get(assetId);
    if (entry == null) return false;
    final original = await repo.readOriginal(assetId);
    final doc = await repo.loadEdit(assetId);
    final proxyImg = await decodePhoto(original, maxLongEdge: 512);
    final proxy = await rgbaFromImage(proxyImg);
    proxyImg.dispose();
    final result = await service.autoEdit(
      AiPhotoContext(
        proxy: proxy,
        current: doc.settings,
        exif: entry.exif,
        visionJpeg: () async {
          final img = await decodePhoto(original, maxLongEdge: 1024);
          final buf = await rgbaFromImage(img);
          img.dispose();
          return encodeJpegNoMetadata(buf);
        },
      ),
      style: style,
    );
    final next = result.outcome.settings;
    final hist = HistoryEntry.tryDiff(label: result.label, kind: HistoryKind.ai, before: doc.settings, after: next);
    await repo.saveEdit(doc.copyWith(
      settings: next,
      history: hist == null ? doc.history : doc.history.push(hist),
      ai: result.record,
      updatedAt: DateTime.now().toUtc(),
    ));
    final thumbImg = await decodePhoto(original, maxLongEdge: 384);
    final thumbSrc = await rgbaFromImage(thumbImg);
    thumbImg.dispose();
    final rendered = await Isolate.run(() => renderReference(thumbSrc, next));
    final out = await imageFromRgba(rendered);
    final png = await encodePng(out);
    out.dispose();
    await repo.writeThumb(assetId, png);
    final fresh = await repo.get(assetId);
    if (fresh != null) {
      await repo.update(fresh.copyWith(
        hasEdits: !next.isDefault,
        editedAt: DateTime.now().toUtc(),
        aiEngine: result.record.engine,
        aiStyle: result.record.style,
        thumbVersion: fresh.thumbVersion + 1,
      ));
    }
    return true;
  } on Exception catch (e) {
    _log.warning('auto-edit $assetId failed: $e');
    return false;
  }
}

/// Auto-edits [assetIds] with bounded concurrency; returns (ok, failed).
Future<(int, int)> batchAutoEdit(WidgetRef ref, List<String> assetIds, {AiStyle style = AiStyle.natural, int concurrency = 2}) async {
  if (assetIds.isEmpty) return (0, 0);
  final repo = ref.read(catalogRepositoryProvider);
  final service = ref.read(autoEditServiceProvider);
  final batch = ref.read(batchProvider.notifier)..start('Auto-editing', assetIds.length);
  final busy = ref.read(busyAssetsProvider.notifier)..add(assetIds);
  var ok = 0, failed = 0, next = 0;
  Future<void> worker() async {
    while (next < assetIds.length && !batch.cancelRequested) {
      final id = assetIds[next++];
      final success = await autoEditStoredAsset(repo: repo, service: service, assetId: id, style: style);
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
Future<int> applyPresetToAssets(WidgetRef ref, Preset preset, List<String> assetIds) async {
  final repo = ref.read(catalogRepositoryProvider);
  var n = 0;
  for (final id in assetIds) {
    final doc = await repo.loadEdit(id);
    final next = preset.apply(doc.settings);
    final h = HistoryEntry.tryDiff(label: 'Preset · ${preset.name}', kind: HistoryKind.preset, before: doc.settings, after: next);
    if (h == null) continue;
    await repo.saveEdit(doc.copyWith(settings: next, history: doc.history.push(h), updatedAt: DateTime.now().toUtc()));
    await refreshThumbnail(repo, id, next);
    n++;
  }
  return n;
}

/// Re-renders a stored photo's thumbnail with [settings] (CPU reference pipeline).
Future<void> refreshThumbnail(CatalogRepository repo, String assetId, DevelopSettings settings) async {
  try {
    final original = await repo.readOriginal(assetId);
    final img = await decodePhoto(original, maxLongEdge: 384);
    final src = await rgbaFromImage(img);
    img.dispose();
    final rendered = await Isolate.run(() => renderReference(src, settings));
    final out = await imageFromRgba(rendered);
    final png = await encodePng(out);
    out.dispose();
    await repo.writeThumb(assetId, png);
    final e = await repo.get(assetId);
    if (e != null) {
      await repo.update(e.copyWith(hasEdits: !settings.isDefault, editedAt: DateTime.now().toUtc(), thumbVersion: e.thumbVersion + 1));
    }
  } on Exception catch (e) {
    _log.warning('thumbnail $assetId failed: $e');
  }
}
