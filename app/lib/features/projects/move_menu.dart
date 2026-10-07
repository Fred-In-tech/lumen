import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/data/catalog_repository.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/projects/project_dialogs.dart';
import 'package:lumen/features/projects/project_providers.dart';
import 'package:lumen/widgets/toast.dart';

const _unsorted = '\u0000unsorted';
const _create = '\u0000new';

/// Batch bar menu: move the selection to a project, Unsorted, or a new
/// project.
class MoveToProjectMenu extends ConsumerWidget {
  const MoveToProjectMenu({super.key, required this.ids});

  final List<String> ids;

  Future<void> _move(BuildContext context, WidgetRef ref, String choice) async {
    final repo = ref.read(catalogRepositoryProvider);
    String? target;
    String name;
    try {
      if (choice == _create) {
        final n = await showProjectNameDialog(
          context,
          title: 'New project',
          action: 'Create and move',
        );
        if (n == null || !context.mounted) return;
        final p = await repo.createProject(name: n);
        (target, name) = (p.id, p.name);
      } else if (choice == _unsorted) {
        (target, name) = (null, 'Unsorted');
      } else {
        final projects = ref.read(projectsProvider).value ?? const [];
        target = choice;
        name = projects.firstWhere((p) => p.id == choice).name;
      }
      await repo.movePhotos(ids, target);
    } on CatalogException catch (e) {
      if (context.mounted) showToast(context, e.message, kind: ToastKind.error);
      return;
    }
    ref.read(selectionProvider.notifier).clear();
    if (context.mounted) {
      showToast(
        context,
        '${ids.length} ${ids.length == 1 ? 'photo' : 'photos'} moved to '
        '$name.',
        kind: ToastKind.success,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final projects = ref.watch(projectsProvider).value ?? const [];
    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          height: 36,
          child: Row(
            children: [
              Icon(icon, size: 16, color: t.textSecondary),
              const SizedBox(width: Sp.s2),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: LumenType.body().copyWith(color: t.textPrimary),
                ),
              ),
            ],
          ),
        );
    return PopupMenuButton<String>(
      tooltip: 'Move the selection to a project',
      color: t.surface1,
      onSelected: (v) => _move(context, ref, v),
      itemBuilder: (_) => [
        for (final p in projects) item(p.id, LucideIcons.folder, p.name),
        item(_unsorted, LucideIcons.inbox, 'Unsorted'),
        const PopupMenuDivider(height: 8),
        item(_create, LucideIcons.folderPlus, 'New project…'),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.s3, vertical: Sp.s2),
        child: Text(
          'Move to…',
          style: LumenType.button().copyWith(color: t.textSecondary),
        ),
      ),
    );
  }
}
