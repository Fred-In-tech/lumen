import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/features/cull/cull_bar.dart';
import 'package:lumen/features/editor/editor_mode.dart';
import 'package:lumen/features/editor/open_editor.dart';
import 'package:lumen/features/export/export_dialog.dart';
import 'package:lumen/features/projects/project_dialogs.dart';
import 'package:lumen/features/projects/project_import.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/features/shell/shell_scope.dart';
import 'package:lumen/widgets/toast.dart';

/// Runs [op], turning a [CatalogException] into an error toast.
Future<bool> _guard(BuildContext context, Future<void> Function() op) async {
  try {
    await op();
    return true;
  } on CatalogException catch (e) {
    if (context.mounted) showToast(context, e.message, kind: ToastKind.error);
    return false;
  }
}

/// Asks for a name and opens the new, empty project.
Future<void> createProjectFlow(BuildContext context, WidgetRef ref) async {
  final name = await showProjectNameDialog(
    context,
    title: 'New project',
    action: 'Create project',
    initial: suggestProjectName(now: DateTime.now()),
  );
  if (name == null || !context.mounted) return;
  Project? created;
  final ok = await _guard(context, () async {
    created = await ref
        .read(catalogRepositoryProvider)
        .createProject(name: name);
  });
  if (!ok || created == null) return;
  ref.read(shellLocationProvider.notifier).go(ProjectLocation(created!.id));
}

Future<void> renameProjectFlow(
  BuildContext context,
  WidgetRef ref,
  Project project,
) async {
  final name = await showProjectNameDialog(
    context,
    title: 'Rename project',
    action: 'Rename',
    initial: project.name,
  );
  if (name == null || name == project.name || !context.mounted) return;
  await _guard(
    context,
    () => ref
        .read(catalogRepositoryProvider)
        .updateProject(project.copyWith(name: name)),
  );
}

Future<void> setCoverFlow(
  BuildContext context,
  WidgetRef ref,
  ProjectSummary summary,
) async {
  final project = summary.project;
  if (project == null) return;
  if (summary.photos.isEmpty) {
    showToast(context, 'Add photos first, then pick one as the cover.');
    return;
  }
  final id = await showCoverPicker(
    context,
    summary.photos,
    current: summary.cover?.assetId,
  );
  if (id == null || !context.mounted) return;
  final ok = await _guard(
    context,
    () => ref
        .read(catalogRepositoryProvider)
        .updateProject(project.copyWith(coverAssetId: id)),
  );
  if (ok && context.mounted) showToast(context, 'Cover updated.');
}

/// Confirms (naming the photo count) and deletes; leaves the project page
/// when it was open.
Future<void> deleteProjectFlow(
  BuildContext context,
  WidgetRef ref,
  ProjectSummary summary,
) async {
  final project = summary.project;
  if (project == null) return;
  final deletePhotos = await showDeleteProjectDialog(context, summary);
  if (deletePhotos == null || !context.mounted) return;
  final (shell, shellRef) = ShellScope.of(context, ref);
  if (shellRef.read(shellLocationProvider) == ProjectLocation(project.id)) {
    shellRef.read(shellLocationProvider.notifier).go(const ProjectsLocation());
  }
  final ok = await _guard(
    shell,
    () => shellRef
        .read(catalogRepositoryProvider)
        .deleteProject(project.id, deletePhotos: deletePhotos),
  );
  if (!ok || !shell.mounted) return;
  final n = summary.count;
  showToast(
    shell,
    deletePhotos
        ? '“${project.name}” and $n ${n == 1 ? 'photo' : 'photos'} deleted.'
        : '“${project.name}” deleted. '
              '${n == 0 ? '' : '$n ${n == 1 ? 'photo is' : 'photos are'} in Unsorted.'}',
  );
}

/// Exports the photos a client gets: picks, else every photo not rejected.
Future<void> exportDeliverables(
  BuildContext context,
  WidgetRef ref,
  ProjectSummary summary,
) async {
  final ids = summary.deliverable;
  if (ids.isEmpty) {
    showToast(context, 'Nothing to export yet.');
    return;
  }
  await showExportDialog(context, ref, ids);
}

/// Does the project's next step: import, Smart Cull, open the editor on
/// the photos still to edit or retouch, or export the rest.
Future<void> runNextStep(
  BuildContext context,
  WidgetRef ref,
  ProjectSummary summary,
) async {
  final (shell, shellRef) = ShellScope.of(context, ref);
  final next = summary.progress.next;
  final id = summary.project?.id;
  final nav = shellRef.read(shellLocationProvider.notifier);
  switch (next.step) {
    case null:
      nav.go(ProjectLocation(id));
    case ProjectStep.import:
      nav.go(ProjectLocation(id));
      await importInto(shell, shellRef, id);
    case ProjectStep.cull:
      nav.go(ProjectLocation(id));
      await runSmartCull(shell, shellRef, summary.photos);
    case ProjectStep.edit || ProjectStep.retouch:
      if (next.assetIds.isEmpty) return;
      await openEditor(
        context,
        next.assetIds,
        next.assetIds.first,
        ref: ref,
        mode: EditorMode.auto,
      );
    case ProjectStep.export:
      await showExportDialog(context, ref, next.assetIds);
  }
}

/// Opens the project page.
void openProject(WidgetRef ref, String? projectId) =>
    ref.read(shellLocationProvider.notifier).go(ProjectLocation(projectId));

/// The newest photo of any project, for actions that need "a photo".
CatalogEntry? latestPhoto(WidgetRef ref, {bool editedFirst = false}) {
  final all = ref.read(libraryProvider).value ?? const <CatalogEntry>[];
  if (all.isEmpty) return null;
  if (editedFirst) {
    final edited = [
      for (final e in all)
        if (e.hasEdits && e.editedAt != null) e,
    ]..sort((a, b) => b.editedAt!.compareTo(a.editedAt!));
    if (edited.isNotEmpty) return edited.first;
  }
  return all.first;
}
