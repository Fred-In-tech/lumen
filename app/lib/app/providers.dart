import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/data/app_settings.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/data/preference_repositories.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen/platform/platform_info.dart';

/// Overridden at startup (`main.dart`) and in tests.
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => throw UnimplementedError('override'),
);
final presetRepositoryProvider = Provider<PresetRepository>(
  (ref) => throw UnimplementedError('override'),
);
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('override'),
);
final platformInfoProvider = Provider<PlatformInfo>(
  (ref) => PlatformInfo.current(),
);

/// All catalog entries, newest first.
final libraryProvider = StreamProvider<List<CatalogEntry>>(
  (ref) => ref.watch(catalogRepositoryProvider).watch(),
);

final importServiceProvider = Provider<ImportService>(
  (ref) => ImportService(ref.watch(catalogRepositoryProvider)),
);

/// App preferences, persisted on change.
class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> change(AppSettings Function(AppSettings) edit) async {
    final current = state.value ?? await future;
    final next = edit(current);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// User presets + built-ins.
class PresetsNotifier extends AsyncNotifier<List<Preset>> {
  @override
  Future<List<Preset>> build() => ref.watch(presetRepositoryProvider).list();

  Future<void> save(Preset preset) async {
    await ref.read(presetRepositoryProvider).save(preset);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(presetRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }
}

final userPresetsProvider =
    AsyncNotifierProvider<PresetsNotifier, List<Preset>>(PresetsNotifier.new);

/// Library multi-selection (asset ids) plus the anchor for shift-range select.
class LibrarySelection {
  const LibrarySelection({this.ids = const {}, this.anchor});

  final Set<String> ids;
  final String? anchor;

  bool get isEmpty => ids.isEmpty;
  int get count => ids.length;
}

class SelectionNotifier extends Notifier<LibrarySelection> {
  @override
  LibrarySelection build() => const LibrarySelection();

  void toggle(String id) {
    final next = {...state.ids};
    if (!next.remove(id)) next.add(id);
    state = LibrarySelection(ids: Set.unmodifiable(next), anchor: id);
  }

  /// Selects every id between the anchor and [id] in [ordered] (inclusive).
  void extendTo(String id, List<String> ordered) {
    final anchor = state.anchor;
    final a = anchor == null ? -1 : ordered.indexOf(anchor);
    final b = ordered.indexOf(id);
    if (a < 0 || b < 0) return toggle(id);
    final (lo, hi) = a <= b ? (a, b) : (b, a);
    state = LibrarySelection(
      ids: Set.unmodifiable({...state.ids, ...ordered.sublist(lo, hi + 1)}),
      anchor: anchor,
    );
  }

  void selectAll(Iterable<String> ids) =>
      state = LibrarySelection(ids: Set.unmodifiable(ids.toSet()));

  void clear() => state = const LibrarySelection();
}

final selectionProvider = NotifierProvider<SelectionNotifier, LibrarySelection>(
  SelectionNotifier.new,
);
