import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/patch_store.dart';
import 'package:lumen/features/remove/healed_source.dart';
import 'package:lumen/features/remove/remove_providers.dart';
import 'package:lumen/platform/background.dart';

final _log = Logger('ColorMatch');

/// Long edge of the analysis proxy a match is solved on (the editor's
/// `analysisProxy` size).
const kColorMatchProxyEdge = 512;

/// AI Color Match for library photos: the reference's look (as edited) and
/// the slider values that move a target toward it. All solving runs off
/// the UI isolate; only the managed colour/tone sliders change (portrait,
/// masks and the rest stay).
class ColorMatchService {
  ColorMatchService({required this.catalog, this.patches});

  final CatalogRepository catalog;
  final PatchStoreGetter? patches;

  /// History label of a match to [reference].
  static String labelFor(CatalogEntry? reference) =>
      'Color match · ${reference?.fileName ?? 'reference'}';

  /// The look of library photo [assetId] as the user edited it.
  Future<LookStats> lookOf(String assetId) async {
    final doc = await catalog.loadEdit(assetId);
    final proxy = await _proxy(assetId, doc.settings);
    return _lookInBackground(proxy, doc.settings);
  }

  /// The settings that move [proxy] (the target's unedited analysis proxy,
  /// currently developed with [current]) toward [reference].
  Future<ColorMatchResult> match(
    RgbaBuffer proxy,
    DevelopSettings current,
    LookStats reference, {
    Set<ParamId> locked = const {},
  }) => _matchInBackground(proxy, current, reference, locked);

  /// The AI record that powers Explain and AI Amount for a match.
  static AiRecord recordFor(DevelopSettings current, ColorMatchResult r) =>
      AiRecord(
        engine: 'local',
        style: 'color_match',
        preAi: current,
        postAi: r.settings,
        changes: [
          for (final c in r.changes)
            AiChange(param: c.param, from: c.from, to: c.to, reason: c.reason),
        ],
      );

  /// Matches stored photo [targetId] to [reference] (batch): one AI
  /// history entry. False when the photo could not be read.
  Future<bool> matchStored(
    String targetId,
    LookStats reference, {
    required String label,
  }) async {
    try {
      final doc = await catalog.loadEdit(targetId);
      final proxy = await _proxy(targetId, doc.settings);
      final r = await match(proxy, doc.settings, reference);
      final entry = HistoryEntry.tryDiff(
        label: label,
        kind: HistoryKind.ai,
        before: doc.settings,
        after: r.settings,
      );
      if (entry == null) return true;
      await catalog.saveEdit(
        doc.copyWith(
          settings: r.settings,
          history: doc.history.push(entry),
          ai: recordFor(doc.settings, r),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      final e = await catalog.get(targetId);
      if (e != null) {
        await catalog.update(
          e.copyWith(
            hasEdits: !r.settings.isDefault,
            editedAt: DateTime.now().toUtc(),
          ),
        );
      }
      return true;
    } on Exception catch (e) {
      _log.warning('color match of $targetId failed: $e');
      return false;
    }
  }

  /// The unedited analysis proxy, with heal ops drawn in (removed objects
  /// do not count toward the look).
  Future<RgbaBuffer> proxyOf(String assetId, DevelopSettings settings) =>
      _proxy(assetId, settings);

  Future<RgbaBuffer> _proxy(String assetId, DevelopSettings settings) async =>
      decodeHealedSource(
        await catalog.readOriginal(assetId),
        assetId: assetId,
        ops: settings.heal,
        patches: patches,
        maxLongEdge: kColorMatchProxyEdge,
      );
}

// Top-level so the isolate closures capture only their arguments.
Future<LookStats> _lookInBackground(
  RgbaBuffer proxy,
  DevelopSettings settings,
) => runInBackground(() => ColorMatch.lookOf(proxy, settings: settings));

Future<ColorMatchResult> _matchInBackground(
  RgbaBuffer proxy,
  DevelopSettings current,
  LookStats reference,
  Set<ParamId> locked,
) => runInBackground(
  () => ColorMatch.run(
    target: proxy,
    reference: reference,
    base: current,
    locked: locked,
  ),
);

final colorMatchServiceProvider = Provider<ColorMatchService>(
  (ref) => ColorMatchService(
    catalog: ref.watch(catalogRepositoryProvider),
    patches: () => ref.read(patchStoreProvider.future),
  ),
);

/// The most recently edited library photo other than [exclude] (null:
/// none edited yet).
CatalogEntry? lastEditedExcept(List<CatalogEntry> entries, String? exclude) {
  CatalogEntry? best;
  for (final e in entries) {
    if (e.assetId == exclude || !e.hasEdits) continue;
    final t = e.editedAt;
    if (t == null) continue;
    final bt = best?.editedAt;
    if (bt == null || t.isAfter(bt)) best = e;
  }
  return best;
}
