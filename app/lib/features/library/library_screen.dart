import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/cull/cull_actions.dart';
import 'package:lumen/features/cull/cull_bar.dart';
import 'package:lumen/features/cull/cull_providers.dart';
import 'package:lumen/features/cull/library_filter.dart';
import 'package:lumen/features/editor/editor_screen.dart';
import 'package:lumen/features/library/batch_bar.dart';
import 'package:lumen/features/library/date_groups.dart';
import 'package:lumen/features/library/empty_library.dart';
import 'package:lumen/features/library/library_actions.dart';
import 'package:lumen/features/library/library_tile.dart';
import 'package:lumen/features/settings/settings_dialog.dart';
import 'package:lumen/import/import_sources.dart';
import 'package:lumen/widgets/buttons.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _dragging = false;

  void _open(List<CatalogEntry> all, CatalogEntry e) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Motion.of(context, Motion.panel),
        pageBuilder: (_, _, _) => EditorScreen(
          assetIds: [for (final x in all) x.assetId],
          initialAssetId: e.assetId,
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  /// P / X / U flag and 0–5 rate the selected photos (Lightroom keys).
  Map<ShortcutActivator, VoidCallback> _flagShortcuts() {
    final repo = ref.read(catalogRepositoryProvider);
    Iterable<String> ids() => ref.read(selectionProvider).ids;
    void flag(String f) => unawaited(setPhotoFlag(repo, ids(), f));
    void rate(int n) => unawaited(setPhotoRating(repo, ids(), n));
    const digits = [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
    ];
    return {
      const SingleActivator(LogicalKeyboardKey.keyP): () =>
          flag(PhotoFlag.pick),
      const SingleActivator(LogicalKeyboardKey.keyX): () =>
          flag(PhotoFlag.reject),
      const SingleActivator(LogicalKeyboardKey.keyU): () =>
          flag(PhotoFlag.none),
      for (var n = 0; n < digits.length; n++)
        SingleActivator(digits[n]): () => rate(n),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final platform = ref.watch(platformInfoProvider);
    final library = ref.watch(libraryProvider);
    final selection = ref.watch(selectionProvider);
    final progress = ref.watch(importProgressProvider);
    final entries = library.value ?? const <CatalogEntry>[];
    final filter = ref.watch(libraryFilterProvider);
    final records = ref.watch(cullRecordsProvider).value ?? const {};

    Widget body = library.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Center(
        child: Text('Couldn’t open your library: $e', style: LumenType.body()),
      ),
      data: (list) {
        if (list.isEmpty) {
          return EmptyLibrary(
            dragging: _dragging,
            onChoose: () => pickAndImport(context, ref),
          );
        }
        final shown = applyLibraryFilter(list, filter, records);
        if (shown.isEmpty) return _NoMatches(filter: filter);
        return _Grid(
          entries: shown,
          selection: selection,
          onOpen: (e) => _open(shown, e),
        );
      },
    );

    if (platform.supportsDragAndDrop) {
      body = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) async {
          setState(() => _dragging = false);
          final files = await readXFiles(details.files);
          if (context.mounted) await importFiles(context, ref, files);
        },
        child: body,
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            ref.read(selectionProvider.notifier).clear(),
        SingleActivator(
          LogicalKeyboardKey.keyA,
          meta: platform.isApple,
          control: !platform.isApple,
        ): () => ref
            .read(selectionProvider.notifier)
            .selectAll(entries.map((e) => e.assetId)),
        SingleActivator(
          LogicalKeyboardKey.keyI,
          meta: platform.isApple,
          control: !platform.isApple,
          shift: true,
        ): () =>
            pickAndImport(context, ref),
        ..._flagShortcuts(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: t.surface0,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(
                  count: entries.length,
                  onImport: () => pickAndImport(context, ref),
                ),
                if (entries.isNotEmpty) CullBar(entries: entries),
                if (progress != null)
                  LinearProgressIndicator(
                    value: progress.total == 0
                        ? null
                        : progress.done / progress.total,
                    minHeight: 2,
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: body),
                      if (_dragging && entries.isNotEmpty)
                        Positioned.fill(child: _DropOverlay()),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 24,
                        child: AnimatedSwitcher(
                          duration: Motion.of(context, Motion.base),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween(
                                begin: const Offset(0, 0.3),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: selection.isEmpty
                              ? const SizedBox.shrink()
                              : Center(
                                  key: const ValueKey('batch'),
                                  child: BatchBar(entries: entries),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.count, required this.onImport});

  final int count;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final platform = ref.watch(platformInfoProvider);
    return Container(
      height: Layout.topBar,
      padding: EdgeInsets.only(
        left: platform.isMacOS ? 78 : Sp.s4,
        right: Sp.s3,
      ),
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          Text(
            kBrand.name,
            style: LumenType.titleSerif().copyWith(
              fontSize: 22,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(width: Sp.s3),
          if (count > 0)
            Text(
              '$count ${count == 1 ? 'photo' : 'photos'}',
              style: LumenType.caption().copyWith(color: t.textTertiary),
            ),
          const Spacer(),
          LumenIconButton(
            icon: LucideIcons.settings,
            tooltip: 'Settings',
            onPressed: () => showSettingsDialog(context),
          ),
          const SizedBox(width: Sp.s2),
          LumenButton(
            label: 'Import',
            icon: const Icon(LucideIcons.imagePlus),
            kind: ButtonKind.primary,
            onPressed: onImport,
          ),
        ],
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(Sp.s4),
        decoration: BoxDecoration(
          color: t.accentTint,
          border: Border.all(color: t.accent, width: 2),
          borderRadius: BorderRadius.circular(Rad.md),
        ),
        alignment: Alignment.center,
        child: Text(
          'Drop to import',
          style: LumenType.display().copyWith(color: t.textPrimary),
        ),
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({
    required this.entries,
    required this.selection,
    required this.onOpen,
  });

  final List<CatalogEntry> entries;
  final LibrarySelection selection;
  final ValueChanged<CatalogEntry> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < Layout.phoneBreakpoint;
    final groups = groupByDay(entries, DateTime.now());
    final ordered = [for (final e in entries) e.assetId];
    final sel = ref.read(selectionProvider.notifier);
    final pad = phone ? Sp.s2 : Sp.s6;
    return CustomScrollView(
      slivers: [
        for (final g in groups) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              pad,
              phone ? Sp.s6 : Sp.s10,
              pad,
              Sp.s3,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    g.label,
                    style: LumenType.titleSerif(touch: phone)
                        .copyWith(color: t.textPrimary),
                  ),
                  const SizedBox(width: Sp.s2),
                  Text(
                    '${g.entries.length} ${g.entries.length == 1 ? 'photo' : 'photos'}',
                    style: LumenType.caption().copyWith(color: t.textTertiary),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            sliver: SliverGrid(
              gridDelegate: phone
                  ? const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                    )
                  : const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 240,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final e = g.entries[i];
                return LibraryTile(
                  key: ValueKey(e.assetId),
                  entry: e,
                  selected: selection.ids.contains(e.assetId),
                  selectionMode: !selection.isEmpty,
                  onOpen: () => onOpen(e),
                  onToggle: () => sel.toggle(e.assetId),
                  onRange: () => sel.extendTo(e.assetId, ordered),
                );
              }, childCount: g.entries.length),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _NoMatches extends ConsumerWidget {
  const _NoMatches({required this.filter});

  final LibraryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No photos in ${filter.label}.',
            style: LumenType.body().copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: Sp.s3),
          LumenButton(
            label: 'Show all',
            onPressed: () =>
                ref.read(libraryFilterProvider.notifier).set(LibraryFilter.all),
          ),
        ],
      ),
    );
  }
}
