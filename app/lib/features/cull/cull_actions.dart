import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/cull/cull_providers.dart';
import 'package:lumen/features/cull/cull_store.dart';

/// Reads providers (a `WidgetRef.read` or `ProviderContainer.read`).
typedef CullReader = T Function<T>(ProviderListenable<T> provider);

/// Writes [flag] ([PhotoFlag]) to the catalog for [ids]. Returns how many
/// changed.
Future<int> setPhotoFlag(
  CatalogRepository repo,
  Iterable<String> ids,
  String flag,
) async {
  var n = 0;
  for (final id in ids) {
    final e = await repo.get(id);
    if (e == null || e.flag == flag) continue;
    await repo.update(e.copyWith(flag: flag));
    n++;
  }
  return n;
}

/// Writes a 0–5 star [rating] for [ids]. Returns how many changed.
Future<int> setPhotoRating(
  CatalogRepository repo,
  Iterable<String> ids,
  int rating,
) async {
  final r = rating.clamp(0, 5);
  var n = 0;
  for (final id in ids) {
    final e = await repo.get(id);
    if (e == null || e.rating == r) continue;
    await repo.update(e.copyWith(rating: r));
    n++;
  }
  return n;
}

/// Pending suggestions among [ids] (all photos when null).
Map<String, CullSuggestion> pendingSuggestions(
  Map<String, CullRecord> records, [
  Iterable<String>? ids,
]) => {for (final id in ids ?? records.keys) id: ?records[id]?.pending};

/// Accepts the pending suggestions of [ids] (all when null): picks and
/// rejects become catalog flags; the rest are just marked as reviewed.
/// Returns the number of flags written.
Future<int> acceptSuggestions(CullReader read, [Iterable<String>? ids]) async {
  final records = await read(cullRecordsProvider.future);
  final pending = pendingSuggestions(records, ids);
  final repo = read(catalogRepositoryProvider);
  var flags = 0;
  for (final s in pending.values) {
    final flag = s.decision.flag;
    if (flag != null) flags += await setPhotoFlag(repo, [s.assetId], flag);
  }
  await read(cullRecordsProvider.notifier)
      .setStatus(pending.keys, SuggestionStatus.accepted);
  return flags;
}

/// Dismisses the pending suggestions of [ids] (all when null).
Future<void> dismissSuggestions(
  CullReader read, [
  Iterable<String>? ids,
]) async {
  final records = await read(cullRecordsProvider.future);
  await read(cullRecordsProvider.notifier).setStatus(
    pendingSuggestions(records, ids).keys,
    SuggestionStatus.dismissed,
  );
}
