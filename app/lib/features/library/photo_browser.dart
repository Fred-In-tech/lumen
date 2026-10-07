import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen_core/lumen_core.dart';

import 'package:lumen/app/providers.dart';
import 'package:lumen/design/tokens.dart';
import 'package:lumen/design/type.dart';
import 'package:lumen/features/cull/cull_actions.dart';
import 'package:lumen/features/cull/cull_bar.dart';
import 'package:lumen/features/cull/cull_providers.dart';
import 'package:lumen/features/cull/library_filter.dart';
import 'package:lumen/features/editor/open_editor.dart';
import 'package:lumen/features/library/batch_bar.dart';
import 'package:lumen/features/library/date_groups.dart';
import 'package:lumen/features/library/library_tile.dart';
import 'package:lumen/import/import_file.dart';
import 'package:lumen/import/import_sources.dart';
import 'package:lumen/widgets/buttons.dart';

/// A photo grid over [entries] (All photos, or one project): the cull
/// strip, day-grouped tiles, the floating batch bar, selection shortcuts
/// and drag-and-drop. The editor opened from it walks only the photos
/// shown.
class PhotoBrowser extends ConsumerStatefulWidget {
  const PhotoBrowser({
    super.key,
    required this.entries,
    required this.onDropFiles,
    required this.empty,
  });

  /// Every photo in scope (unfiltered), library order.
  final List<CatalogEntry> entries;

  /// Files dropped on the grid.
  final Future<void> Function(List<ImportFile> files) onDropFiles;

  /// Shown when [entries] is empty; gets whether files are dragged over.
  final Widget Function(bool dragging) empty;

  @override
  ConsumerState<PhotoBrowser> createState() => _PhotoBrowserState();
}

class _PhotoBrowserState extends ConsumerState<PhotoBrowser> {
  bool _dragging = false;

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
    final platform = ref.watch(platformInfoProvider);
    final selection = ref.watch(selectionProvider);
    final entries = widget.entries;
    final filter = ref.watch(libraryFilterProvider);
    final records = ref.watch(cullRecordsProvider).value ?? const {};

    Widget body;
    if (entries.isEmpty) {
      body = widget.empty(_dragging);
    } else {
      final shown = applyLibraryFilter(entries, filter, records);
      body = shown.isEmpty
          ? _NoMatches(filter: filter)
          : _Grid(
              entries: shown,
              selection: selection,
              onOpen: (e) => openEditor(context, [
                for (final x in shown) x.assetId,
              ], e.assetId),
            );
    }

    if (platform.supportsDragAndDrop) {
      body = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) async {
          setState(() => _dragging = false);
          final files = await readXFiles(details.files);
          if (mounted) await widget.onDropFiles(files);
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
        ..._flagShortcuts(),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            if (entries.isNotEmpty)
              CullBar(
                entries: entries,
                flat: true,
                inset: MediaQuery.sizeOf(context).width < Layout.phoneBreakpoint
                    ? Sp.s2
                    : Sp.s8,
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: body),
                  if (_dragging && entries.isNotEmpty)
                    const Positioned.fill(child: _DropOverlay()),
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
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Sp.s3,
                                ),
                                child: BatchBar(entries: entries),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

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
    final pad = phone ? Sp.s2 : Sp.s8;
    return CustomScrollView(
      slivers: [
        for (final (i, g) in groups.indexed) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              pad,
              i == 0 ? Sp.s3 : (phone ? Sp.s6 : Sp.s10),
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
