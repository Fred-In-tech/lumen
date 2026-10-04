import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/ai/auto_retouch.dart';

final _log = Logger('RemeasureSync');

/// "Re-measure per photo" for a portrait sync: after the clipboard's
/// portrait values were pasted onto [targets] (one "Paste settings" entry
/// each), each target's retouch is moved by what its own faces need
/// compared with the source photo's ([PortraitPresets.rebase]): the
/// source's hand adjustments survive as offsets, the need-scaling is per
/// photo. The paste entry is amended in place, so it stays ONE history
/// entry per photo. Targets whose faces cannot be measured keep the pasted
/// values (counted in the result).
Future<({int remeasured, int skipped})> remeasureSyncedRetouch({
  required CatalogRepository repo,
  required AutoRetouchPlanner planner,
  required String sourceAssetId,
  required DevelopSettings sourceSettings,
  required Iterable<String> targets,
}) async {
  final from = await planner.measure(sourceAssetId, sourceSettings);
  final fromNeeds = from.needs;
  if (fromNeeds == null || fromNeeds.isEmpty) {
    return (remeasured: 0, skipped: targets.length);
  }
  final fromAuto = PortraitPresets.autoRetouchFor(
    PortraitSettings.empty,
    fromNeeds,
  );
  var remeasured = 0, skipped = 0;
  for (final id in targets) {
    if (id == sourceAssetId) continue;
    final doc = await repo.loadEdit(id);
    final h = doc.history;
    final last = h.cursor == 0 ? null : h.entries[h.cursor - 1];
    if (last == null ||
        last.kind != HistoryKind.paste ||
        !last.ops.any((o) => o.path == 'portrait')) {
      continue;
    }
    final to = await planner.measure(id, doc.settings);
    final toNeeds = to.needs;
    if (toNeeds == null || toNeeds.isEmpty) {
      skipped++;
      continue;
    }
    final before = last.applyBackward(doc.settings);
    final next = doc.settings.copyWith(
      portrait: PortraitPresets.rebase(
        doc.settings.portrait,
        fromAuto: fromAuto,
        toAuto: PortraitPresets.autoRetouchFor(PortraitSettings.empty, toNeeds),
        locked: manualPortraitLocks(HistoryStack(h.entries, h.cursor - 1)),
      ),
    );
    final amended = HistoryEntry.tryDiff(
      label: last.label,
      kind: HistoryKind.paste,
      before: before,
      after: next,
    );
    final entries = [...h.entries.take(h.cursor - 1), ?amended];
    await repo.saveEdit(
      doc.copyWith(
        settings: next,
        history: HistoryStack(List.unmodifiable(entries), entries.length),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    remeasured++;
  }
  _log.fine('re-measured $remeasured photos, skipped $skipped');
  return (remeasured: remeasured, skipped: skipped);
}
