import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/library/empty_library.dart';
import 'package:lumen/features/library/photo_browser.dart';
import 'package:lumen/features/projects/project_import.dart';
import 'package:lumen/features/shell/page_header.dart';
import 'package:lumen/features/shell/shell_location.dart';
import 'package:lumen/features/shell/shell_scope.dart';
import 'package:lumen/widgets/buttons.dart';

/// Every photo in the library, whatever project it is in (the library
/// grid from before projects).
class AllPhotosPage extends ConsumerWidget {
  const AllPhotosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final library = ref.watch(libraryProvider);
    final entries = library.value ?? const <CatalogEntry>[];
    final unsorted = entries.where((e) => e.projectId == null).length;
    final (shell, shellRef) = ShellScope.of(context, ref);
    final n = entries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'All photos',
          breadcrumb: [
            (
              label: 'Home',
              onTap: () => ref
                  .read(shellLocationProvider.notifier)
                  .go(const HomeLocation()),
            ),
            (label: 'All photos', onTap: null),
          ],
          subtitle: n == 0
              ? null
              : '$n ${n == 1 ? 'photo' : 'photos'}'
                    '${unsorted == 0 ? '' : '  ·  $unsorted unsorted'}',
          actions: [
            LumenButton(
              label: 'Import',
              icon: const Icon(LucideIcons.imagePlus),
              kind: ButtonKind.primary,
              onPressed: () => pickAndImport(shell, shellRef),
            ),
          ],
        ),
        Expanded(
          child: library.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Center(
              child: Text(
                'Couldn’t open your library: $e',
                style: LumenType.body().copyWith(color: t.textSecondary),
              ),
            ),
            data: (list) => PhotoBrowser(
              entries: list,
              onDropFiles: (files) =>
                  importWithDestination(shell, shellRef, files),
              empty: (dragging) => EmptyLibrary(
                dragging: dragging,
                onChoose: () => pickAndImport(shell, shellRef),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
