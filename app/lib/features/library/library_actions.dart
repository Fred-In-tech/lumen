import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/features/batch/batch_auto_edit.dart';
import 'package:lumen/import/float_sources.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_service.dart';
import 'package:lumen/import/import_sources.dart';
import 'package:lumen/widgets/toast.dart';

/// Import source used by the library (overridden in tests).
final importSourceProvider = Provider<ImportSource>(
  (ref) => const PickerImportSource(),
);

/// Progress of the running import, or null when idle.
class ImportProgressNotifier extends Notifier<({int done, int total})?> {
  @override
  ({int done, int total})? build() => null;

  void set(({int done, int total})? v) => state = v;
}

final importProgressProvider =
    NotifierProvider<ImportProgressNotifier, ({int done, int total})?>(
      ImportProgressNotifier.new,
    );

/// Imports [files] into [projectId] (null: Unsorted), reports a toast, and
/// triggers auto-edit-on-import. Photos already in the library stay where
/// they are, except Unsorted ones, which join [projectId].
Future<List<ImportResult>> importFiles(
  BuildContext context,
  WidgetRef ref,
  List<ImportFile> files, {
  String? projectId,
}) async {
  if (files.isEmpty) return const [];
  final progress = ref.read(importProgressProvider.notifier)
    ..set((done: 0, total: files.length));
  final List<ImportResult> results;
  try {
    results = await ref
        .read(importServiceProvider)
        .importAll(
          files,
          projectId: projectId,
          onProgress: (done, total) => progress.set((done: done, total: total)),
        );
  } finally {
    progress.set(null);
  }
  final imported = results
      .whereType<Imported>()
      .map((r) => r.entry.assetId)
      .toList();
  final duplicates = results.whereType<Duplicate>().toList();
  final dupes = duplicates.length;
  final adopt = [
    for (final d in duplicates)
      if (d.entry.projectId == null) d.entry.assetId,
  ];
  if (projectId != null && adopt.isNotEmpty) {
    await ref.read(catalogRepositoryProvider).movePhotos(adopt, projectId);
  }
  final failed = results.whereType<ImportFailed>().toList();
  if (context.mounted) {
    final parts = [
      if (imported.isNotEmpty)
        '${imported.length} ${imported.length == 1 ? 'photo' : 'photos'} imported',
      if (dupes > 0)
        projectId != null && adopt.isNotEmpty
            ? '$dupes already in your library (Unsorted ones moved here)'
            : '$dupes already in your library',
      if (failed.isNotEmpty) '${failed.length} couldn’t be opened',
    ];
    showToast(
      context,
      '${parts.join(' · ')}.',
      kind: failed.isNotEmpty && imported.isEmpty
          ? ToastKind.error
          : ToastKind.success,
    );
  }
  if (imported.isNotEmpty) {
    // Float previews of imported RAWs, built in the background one at a
    // time: their first open in the editor is then instant.
    unawaited(
      ref
          .read(floatSourcesProvider)
          .warm(imported, previewLongEdge: ref.read(previewLongEdgeProvider)),
    );
  }
  final settings = ref.read(settingsProvider).value;
  if (imported.isNotEmpty && (settings?.autoEditOnImport ?? true)) {
    final style =
        AiStyle.fromId(settings?.defaultStyle ?? 'natural') ?? AiStyle.natural;
    await batchAutoEdit(ref, imported, style: style);
  }
  return results;
}

/// Opens the picker; the chosen files (empty when cancelled).
Future<List<ImportFile>> pickImportFiles(WidgetRef ref) {
  final mobile = ref.read(platformInfoProvider).isMobile;
  return ref.read(importSourceProvider).pick(mobile: mobile);
}

/// Removes the selected photos from the library.
Future<void> deleteSelected(BuildContext context, WidgetRef ref) async {
  final ids = ref.read(selectionProvider).ids.toList();
  final repo = ref.read(catalogRepositoryProvider);
  for (final id in ids) {
    await repo.delete(id);
  }
  ref.read(selectionProvider.notifier).clear();
  if (context.mounted) {
    showToast(context, '${ids.length} removed from library.');
  }
}
