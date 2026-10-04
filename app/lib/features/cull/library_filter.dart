import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/features/cull/cull_store.dart';

/// Library filter chips (Smart Cull and flags).
enum LibraryFilter {
  all('All'),
  picks('Picks'),
  rejects('Rejects'),
  eyesClosed('Eyes closed'),
  blurry('Blurry'),
  clusters('Clusters');

  const LibraryFilter(this.label);
  final String label;
}

bool _flagged(CatalogEntry e, CullRecord? r, String flag, CullDecision d) =>
    e.flag == flag || r?.pending?.decision == d;

bool _hasReason(CullRecord? r, Set<CullReason> reasons) =>
    r?.suggestion?.reasons.any(reasons.contains) ?? false;

/// True when [e] passes [filter]. Picks/Rejects include pending
/// suggestions (so they can be reviewed before accepting); the signal
/// filters read the latest Smart Cull reasons.
bool matchesLibraryFilter(
  CatalogEntry e,
  LibraryFilter filter,
  CullRecord? r,
) => switch (filter) {
  LibraryFilter.all => true,
  LibraryFilter.picks => _flagged(e, r, PhotoFlag.pick, CullDecision.pick),
  LibraryFilter.rejects => _flagged(
    e,
    r,
    PhotoFlag.reject,
    CullDecision.reject,
  ),
  LibraryFilter.eyesClosed => _hasReason(r, {CullReason.eyesClosed}),
  LibraryFilter.blurry => _hasReason(r, {
    CullReason.blurryFace,
    CullReason.blurry,
  }),
  LibraryFilter.clusters => r?.suggestion?.inCluster ?? false,
};

/// [entries] that pass [filter], in their original order.
List<CatalogEntry> applyLibraryFilter(
  List<CatalogEntry> entries,
  LibraryFilter filter,
  Map<String, CullRecord> records,
) => filter == LibraryFilter.all
    ? entries
    : List.unmodifiable(
        entries.where(
          (e) => matchesLibraryFilter(e, filter, records[e.assetId]),
        ),
      );

/// Count per filter (chip badges).
Map<LibraryFilter, int> libraryFilterCounts(
  List<CatalogEntry> entries,
  Map<String, CullRecord> records,
) => {
  for (final f in LibraryFilter.values)
    f: f == LibraryFilter.all
        ? entries.length
        : entries
              .where((e) => matchesLibraryFilter(e, f, records[e.assetId]))
              .length,
};

class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => LibraryFilter.all;

  void set(LibraryFilter f) => state = f;
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilter>(
      LibraryFilterNotifier.new,
    );
