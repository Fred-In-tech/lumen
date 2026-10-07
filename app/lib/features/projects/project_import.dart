import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/library/library_actions.dart';
import 'package:lumen/features/projects/import_destination.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/import/exif_reader.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/widgets/toast.dart';

final _log = Logger('ProjectImport');

/// The capture time of the first photo in [files], when its EXIF has one.
Future<DateTime?> firstCaptureDate(List<ImportFile> files) async {
  if (files.isEmpty) return null;
  try {
    return (await readExifSummary(files.first.bytes)).capturedAt;
  } on Exception catch (e) {
    _log.fine('no capture date in ${files.first.name}: $e');
    return null;
  }
}

/// Asks where [files] go (new project, existing project, Unsorted), opens
/// that place and imports there. [context] and [ref] must outlive the
/// import (the app shell's): the page that started it may close.
Future<void> importWithDestination(
  BuildContext context,
  WidgetRef ref,
  List<ImportFile> files,
) async {
  if (files.isEmpty) return;
  final captured = await firstCaptureDate(files);
  if (!context.mounted) return;
  final projects =
      ref.read(projectsProvider).value ??
      await ref.read(catalogRepositoryProvider).listProjects();
  if (!context.mounted) return;
  final dest = await showImportDestinationDialog(
    context,
    count: files.length,
    suggestedName: suggestProjectName(
      now: DateTime.now(),
      capturedAt: captured,
      firstFileName: files.first.name,
    ),
    projects: projects,
  );
  if (dest == null || !context.mounted) return;
  final String? projectId;
  try {
    projectId = switch (dest) {
      NewProjectDestination(:final name) =>
        (await ref
                .read(catalogRepositoryProvider)
                .createProject(name: name, shootDate: captured))
            .id,
      ExistingProjectDestination(:final projectId) => projectId,
      UnsortedDestination() => null,
    };
  } on CatalogException catch (e) {
    if (context.mounted) showToast(context, e.message, kind: ToastKind.error);
    return;
  }
  if (!context.mounted) return;
  ref.read(shellLocationProvider.notifier).go(ProjectLocation(projectId));
  await importFiles(context, ref, files, projectId: projectId);
}

/// Opens the picker, then asks where the photos go.
Future<void> pickAndImport(BuildContext context, WidgetRef ref) async {
  final files = await pickImportFiles(ref);
  if (!context.mounted) return;
  await importWithDestination(context, ref, files);
}

/// Imports straight into [projectId] (null: Unsorted): the picker when
/// [files] is null, else the dropped files.
Future<void> importInto(
  BuildContext context,
  WidgetRef ref,
  String? projectId, {
  List<ImportFile>? files,
}) async {
  final chosen = files ?? await pickImportFiles(ref);
  if (!context.mounted || chosen.isEmpty) return;
  await importFiles(context, ref, chosen, projectId: projectId);
}
