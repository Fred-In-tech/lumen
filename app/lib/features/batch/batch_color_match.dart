import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/features/ai/color_match_service.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/features/library/library_tile.dart';
import 'package:lumen/features/masks/ai_mask_source.dart';
import 'package:lumen/features/portrait/retouch_build.dart';
import 'package:lumen/features/remove/remove_providers.dart';

/// Matches every photo of [assetIds] (except the reference itself) to
/// [reference]'s look, one AI history entry each, with progress and Stop.
/// Returns (matched, failed).
Future<(int, int)> batchColorMatch(
  WidgetRef ref,
  List<String> assetIds,
  CatalogEntry reference,
) async {
  final targets = [
    for (final id in assetIds)
      if (id != reference.assetId) id,
  ];
  if (targets.isEmpty) return (0, 0);
  final repo = ref.read(catalogRepositoryProvider);
  final service = ref.read(colorMatchServiceProvider);
  final batch = ref.read(batchProvider.notifier)
    ..start('Matching look', targets.length);
  final busy = ref.read(busyAssetsProvider.notifier)..add(targets);
  var ok = 0, failed = 0;
  try {
    final look = await service.lookOf(reference.assetId);
    final label = ColorMatchService.labelFor(reference);
    for (final id in targets) {
      if (batch.cancelRequested) break;
      final done = await service.matchStored(id, look, label: label);
      if (done) {
        ok++;
        final doc = await repo.loadEdit(id);
        await refreshThumbnail(
          repo,
          id,
          doc.settings,
          patches: () => ref.read(patchStoreProvider.future),
          maskLoader: ref.read(aiMaskRasterLoaderProvider),
          retouch: ref.read(storedRetouchLoaderProvider).load,
        );
      } else {
        failed++;
      }
      busy.remove(id);
      batch.step();
    }
  } finally {
    for (final id in targets) {
      busy.remove(id);
    }
    batch.finish();
  }
  return (ok, failed);
}
